#!/usr/bin/env python3
"""Project-local OpenCode heartbeat. Run from the project root."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import select
import signal
import subprocess
import sys
import time

PIDFILE = Path(".time-loop-watchdog.pid")
STOPFILE = Path(".time-loop-watchdog.stop")
LOGFILE = Path(".time-loop-watchdog.log")
ALERTFILE = Path(".time-loop-watchdog.alert")

# 2026-11-25: fail loudly. 55 h of a 96 h budget produced nothing because every
# `opencode run` died in seconds with `Error: Free usage limit reached` (no default
# model was configured, so it fell back to a cloud free tier) while this watchdog
# kept re-firing every 8 minutes and told nobody.
ANSI = re.compile(rb"\x1b\[[0-9;]*[A-Za-z]")
BANNER = re.compile(rb"build\s+\xc2\xb7\s+(\S+)")   # "build · <model>"
TOOL_FAILURE = b"\xe2\x9c\x97"                      # the "✗ <tool> failed" marker


def identity(pid):
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return None if fields[0] == "Z" else fields[19]
    except (OSError, IndexError):
        return None


def running():
    try:
        record = json.loads(PIDFILE.read_text())
        pid = record["pid"]
        if pid > 1 and identity(pid) == record["start"]:
            return pid
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return None


def stop():
    STOPFILE.touch()
    pid = running()
    if pid is None:
        return
    # The worker is a session leader; its agent and tool children share this
    # process group. Never signal an unverified pid from a stale pidfile.
    try:
        if os.getpgid(pid) != pid:
            raise RuntimeError("watchdog is not its process-group leader")
        os.killpg(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(50):
        if running() is None:
            break
        time.sleep(0.1)
    try:
        os.killpg(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def alert(reasons):
    """Record a loud, durable alert and echo it into the run log."""
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    body = ["", "=" * 72,
            f"WATCHDOG ALERT {stamp}: re-firing STOPPED, the campaign is NOT advancing."]
    body += [f"  - {r}" for r in reasons]
    body += [f"  Log: {LOGFILE}    Alert: {ALERTFILE}",
             "  Fix the cause, then restart the watchdog (`time-loop-watchdog.py start ...`).",
             "=" * 72, ""]
    text = "\n".join(body)
    print(text, flush=True)
    try:
        with ALERTFILE.open("a", encoding="utf-8") as fh:
            fh.write(text + "\n")
    except OSError:
        pass


class RunMonitor:
    """Tees a run's output to the log while watching for failure signatures.

    Classification of `Error:` lines is empirical: in the 2026-11-24 log, all 316
    session-fatal errors stand alone, while all 9 benign ones (a failed `Read`,
    say) are immediately preceded by a `✗ <tool> failed` line. Treating every
    `Error:` as fatal would halt the campaign on a missing file.
    """

    def __init__(self, expect_model):
        self.expect_model = expect_model
        self.partial = b""
        self.prev = b""
        self.models = []
        self.fatal_errors = []
        self.tool_errors = 0

    def feed(self, chunk):
        data = self.partial + chunk
        *lines, self.partial = data.split(b"\n")
        for raw in lines:
            self._line(ANSI.sub(b"", raw).strip())

    def finish(self):
        if self.partial:
            self._line(ANSI.sub(b"", self.partial).strip())
            self.partial = b""

    def _line(self, line):
        if not line:
            return
        found = BANNER.search(line)
        if found:
            model = found.group(1).decode("utf-8", "replace")
            if model not in self.models:
                self.models.append(model)
        elif line.startswith(b"Error:"):
            if self.prev.startswith(TOOL_FAILURE):
                self.tool_errors += 1          # a tool failed; the run continues
            else:
                text = line.decode("utf-8", "replace")
                if len(self.fatal_errors) < 3:
                    self.fatal_errors.append(text[:200])
        self.prev = line

    def verdict(self, elapsed, rc, min_runtime):
        """Reasons to stop re-firing; empty means the run looked healthy."""
        reasons = []
        if elapsed < min_runtime:
            reasons.append(f"run exited after {elapsed:.1f}s, under the {min_runtime:g}s "
                           f"floor (exit={rc}) — it is not doing any work")
        for text in self.fatal_errors:
            reasons.append(f"session error in run output: {text}")
        wrong = [m for m in self.models if m != self.expect_model]
        if wrong:
            reasons.append(f"banner model is {', '.join(wrong)}, expected "
                           f"{self.expect_model} — `opencode run` picked the wrong model")
        return reasons

    def summary(self):
        bits = [f"models={','.join(self.models) if self.models else 'NONE-SEEN'}"]
        if self.tool_errors:
            bits.append(f"tool_errors={self.tool_errors}")
        if self.fatal_errors:
            bits.append(f"session_errors={len(self.fatal_errors)}")
        return " ".join(bits)


def work(args):
    signal.signal(signal.SIGTERM, lambda *_: STOPFILE.touch())
    sink = getattr(sys.stdout, "buffer", None)
    with os.fdopen(args.lock_fd, "w") as lock:
        lock.write(json.dumps({"pid": os.getpid(), "start": identity(os.getpid())}))
        lock.flush()
        child = None
        try:
            while not STOPFILE.exists() and time.time() < args.deadline:
                time.sleep(min(args.interval, max(0, args.deadline - time.time())))
                if STOPFILE.exists() or time.time() >= args.deadline:
                    break
                try:
                    idle = time.time() - Path(args.state).stat().st_mtime
                except FileNotFoundError:
                    continue
                if idle < args.idle:
                    continue
                monitor = RunMonitor(args.expect_model)
                started = time.time()
                child = subprocess.Popen(["opencode", "run", args.prompt],
                                         stdout=subprocess.PIPE,
                                         stderr=subprocess.STDOUT)
                pipe = child.stdout
                eof = False
                while child.poll() is None:
                    if STOPFILE.exists() or time.time() >= args.deadline:
                        # TERM reaches both the agent and its tool processes.
                        os.killpg(os.getpgrp(), signal.SIGTERM)
                        try:
                            child.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            pass
                        # The agent may exit before a TERM-resistant tool.
                        # End the entire owned group, including this worker.
                        os.killpg(os.getpgrp(), signal.SIGKILL)
                    if eof:
                        time.sleep(0.1)
                        continue
                    # Drain the pipe as we wait, so a chatty run cannot block on a
                    # full pipe buffer, and tee it to the log exactly as before.
                    try:
                        ready, _, _ = select.select([pipe], [], [], 0.1)
                    except (OSError, ValueError):
                        eof = True
                        continue
                    if not ready:
                        continue
                    chunk = pipe.read1(65536) if hasattr(pipe, "read1") else pipe.read(65536)
                    if not chunk:
                        eof = True
                        continue
                    if sink is not None:
                        sink.write(chunk)
                        sink.flush()
                    monitor.feed(chunk)
                rest = b""
                try:
                    rest = pipe.read() or b""
                except (OSError, ValueError):
                    pass
                if rest:
                    if sink is not None:
                        sink.write(rest)
                        sink.flush()
                    monitor.feed(rest)
                monitor.finish()
                try:
                    pipe.close()
                except OSError:
                    pass
                rc = child.wait()
                elapsed = time.time() - started
                child = None
                print(f"wake exit={rc}", flush=True)
                print(f"wake took={elapsed:.1f}s {monitor.summary()}", flush=True)
                if not monitor.models:
                    print("wake WARNING: no 'build · <model>' banner in this run's output",
                          flush=True)
                reasons = monitor.verdict(elapsed, rc, args.min_runtime)
                if reasons and args.fail_fast:
                    alert(reasons)
                    break
                if reasons:
                    print("wake WARNING (--no-fail-fast): " + "; ".join(reasons), flush=True)
        finally:
            STOPFILE.touch()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["start", "run", "stop", "status"])
    parser.add_argument("state", nargs="?")
    parser.add_argument("deadline", type=int, nargs="?")
    parser.add_argument("prompt", nargs="?")
    parser.add_argument("--interval", type=float, default=480)
    parser.add_argument("--idle", type=float, default=600)
    parser.add_argument("--min-runtime", type=float, default=60,
                        help="a run that exits sooner than this is a failure (seconds)")
    parser.add_argument("--expect-model", default="qwen3.8:27b-mlx",
                        help="model the `build · <model>` banner must name")
    parser.add_argument("--no-fail-fast", dest="fail_fast", action="store_false",
                        help="warn instead of stopping when a run looks broken")
    parser.add_argument("--lock-fd", type=int)
    args = parser.parse_args()
    if args.action == "stop":
        stop()
        return 0
    if args.action == "status":
        pid = running()
        print(f"watchdog alive: {pid}" if pid else "watchdog stopped")
        if ALERTFILE.exists():
            print(f"ALERT PENDING -- read {ALERTFILE}")
        return 0 if pid else 1
    if not args.state or not args.deadline or not args.prompt:
        parser.error("start/run needs state, deadline epoch and resume prompt")
    if args.interval <= 0 or args.idle < 0:
        parser.error("interval must be positive and idle nonnegative")
    if args.min_runtime < 0:
        parser.error("min-runtime must be nonnegative")
    if args.action == "run":
        work(args)
        return 0
    with PIDFILE.open("a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("watchdog already running")
            return 0
        if args.deadline <= time.time():
            STOPFILE.touch()
            parser.error("deadline already passed; not re-arming")
        STOPFILE.unlink(missing_ok=True)
        lock.seek(0)
        lock.truncate()
        argv = [sys.executable, str(Path(__file__).resolve()), "run", args.state,
                str(args.deadline), args.prompt, "--lock-fd", str(lock.fileno()),
                "--interval", str(args.interval), "--idle", str(args.idle),
                "--min-runtime", str(args.min_runtime),
                "--expect-model", args.expect_model]
        if not args.fail_fast:
            argv.append("--no-fail-fast")
        with LOGFILE.open("ab") as log:
            child = subprocess.Popen(
                argv, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                start_new_session=True, pass_fds=(lock.fileno(),))
        for _ in range(50):
            if running() == child.pid:
                return 0
            if child.poll() is not None:
                break
            time.sleep(0.1)
        child.terminate()
        child.wait(timeout=10)
        raise RuntimeError(f"watchdog failed to start; read {LOGFILE}")


if __name__ == "__main__":
    sys.exit(main())
