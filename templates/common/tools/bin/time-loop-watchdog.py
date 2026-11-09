#!/usr/bin/env python3
"""Project-local OpenCode heartbeat. Run from the project root."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

PIDFILE = Path(".time-loop-watchdog.pid")
STOPFILE = Path(".time-loop-watchdog.stop")
LOGFILE = Path(".time-loop-watchdog.log")


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


def work(args):
    signal.signal(signal.SIGTERM, lambda *_: STOPFILE.touch())
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
                child = subprocess.Popen(["opencode", "run", args.prompt])
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
                    time.sleep(0.1)
                print(f"wake exit={child.wait()}", flush=True)
                child = None
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
    parser.add_argument("--lock-fd", type=int)
    args = parser.parse_args()
    if args.action == "stop":
        stop()
        return 0
    if args.action == "status":
        pid = running()
        print(f"watchdog alive: {pid}" if pid else "watchdog stopped")
        return 0 if pid else 1
    if not args.state or not args.deadline or not args.prompt:
        parser.error("start/run needs state, deadline epoch and resume prompt")
    if args.interval <= 0 or args.idle < 0:
        parser.error("interval must be positive and idle nonnegative")
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
        with LOGFILE.open("ab") as log:
            child = subprocess.Popen(
                [sys.executable, str(Path(__file__).resolve()), "run", args.state,
                 str(args.deadline), args.prompt, "--lock-fd", str(lock.fileno()),
                 "--interval", str(args.interval), "--idle", str(args.idle)],
                stdin=subprocess.DEVNULL, stdout=log, stderr=log,
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
