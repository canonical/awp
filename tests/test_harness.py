"""tests/lib/harness.sh: the input-prompt regex and K1 (tests.md 5.5).

Claude Code 2.1.3xx draws its prompt as "❯" followed by a no-break space
(U+00A0). A regex with a plain space there makes harness_start time out with
Claude Code ready, so every campaign fails its first check (G.1, S.1). The
character is easy to lose in an edit, hence this test.
"""
import os
import subprocess
import unittest
import json
import tempfile
import time
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)


def prompt_re(harness):
    script = (
        '. tests/lib/lxc.sh >/dev/null 2>&1; HARNESS=%s; '
        '. tests/lib/harness.sh >/dev/null 2>&1; printf %%s "$HARNESS_PROMPT_RE"'
        % harness
    )
    env = {k: v for k, v in os.environ.items() if k != "HARNESS_PROMPT_RE"}
    return subprocess.run(["bash", "-c", script], cwd=REPO, env=env,
                          capture_output=True, text=True, check=True).stdout


def grep(regex, line):
    r = subprocess.run(["grep", "-qE", regex], input=line + "\n", text=True,
                       env=dict(os.environ, LC_ALL="C.UTF-8"))
    return r.returncode == 0


class ClaudePrompt(unittest.TestCase):
    def setUp(self):
        self.re = prompt_re("claude")

    def test_no_break_space(self):
        self.assertTrue(grep(self.re, '❯ Try "how does <filepath> work?"'))

    def test_plain_space(self):
        self.assertTrue(grep(self.re, "> hello"))
        self.assertTrue(grep(self.re, "│ ❯ "))

    def test_shortcuts_hint(self):
        self.assertTrue(grep(self.re, "  ? for shortcuts"))

    def test_rejects_text(self):
        self.assertFalse(grep(self.re, "Running unlzw baseline WP"))


class HarnessSelection(unittest.TestCase):
    def test_unknown_values_fail_before_side_effects(self):
        for library in ("harness", "secret", "workshop"):
            for value in ("none", "copilot", "typo"):
                with self.subTest(library=library, value=value):
                    result = subprocess.run(
                        ["bash", "-c", f". tests/lib/{library}.sh; echo UNREACHABLE"],
                        cwd=REPO, env=dict(os.environ, HARNESS=value),
                        text=True, capture_output=True)
                    self.assertEqual(result.returncode, 2)
                    self.assertIn(f"HARNESS={value}: unknown harness", result.stderr)
                    self.assertNotIn("UNREACHABLE", result.stdout)

    def test_credential_modes_fail_closed(self):
        for mode in ("persisted", "typo"):
            result = subprocess.run(["bash", "-c", ". tests/lib/secret.sh"],
                                    cwd=REPO, env=dict(os.environ, HARNESS="opencode",
                                                     HARNESS_CREDENTIAL=mode),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)

    def test_opencode_prompt(self):
        regex = prompt_re("opencode")
        for text in ("Ask anything…", "  shift+tab agents"):
            self.assertTrue(grep(regex, text))
        self.assertFalse(grep(regex, "Running unlzw baseline WP"))

    def test_key_variable_is_not_shell_code(self):
        result = subprocess.run(["bash", "-c", ". tests/lib/harness.sh"],
                                cwd=REPO, env=dict(os.environ, HARNESS="opencode",
                                                 AUTOWP_OPENCODE_KEY_ENV="BAD; echo unsafe"),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)

    def test_manifest_mismatch_prevents_launch(self):
        with tempfile.TemporaryDirectory() as d:
            config = Path(d) / "config"
            config.mkdir()
            (config / "auto-wp.json").write_text('{"harness":"claude"}')
            script = """
                . tests/lib/lxc.sh
                . tests/lib/harness.sh
                autowp_exec_user_argv() { shift; "$@"; }
                harness_write_launcher() { echo UNREACHABLE; }
                harness_start local "$1" '/time-loop test 1'
            """
            result = subprocess.run(["bash", "-c", script, "_", d], cwd=REPO,
                                    env=dict(os.environ, HARNESS="opencode"),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("harness mismatch", result.stderr)
            self.assertNotIn("UNREACHABLE", result.stdout)

    def test_opencode_trust_writes_separate_json_files(self):
        with tempfile.TemporaryDirectory() as d:
            script = """
                . tests/lib/lxc.sh
                . tests/lib/harness.sh
                autowp_exec_user() { shift; bash -c "$*"; }
                opencode() { printf '%s\\n' "$*" > "$HOME/service-call"; }
                export -f opencode
                harness_trust local /project
            """
            result = subprocess.run(["bash", "-c", script], cwd=REPO,
                                    env=dict(os.environ, HOME=d, HARNESS="opencode"),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            root = Path(d) / ".config/opencode"
            self.assertIn("permissions", json.loads((root / "opencode.json").read_text()))
            self.assertEqual(json.loads((root / "cli.json").read_text()), {"highlights": False})
            self.assertEqual((Path(d) / "service-call").read_text().strip(),
                             "service set disabled true")

    def test_wal_at_custom_path_and_skill_not_only_prompt(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            db = root / "custom channel/opencode.db"
            db.parent.mkdir()
            db.write_bytes(b"old")
            (root / ".autowp-harness-start").touch()
            os.utime(root / ".autowp-harness-start", (time.time() - 10,) * 2)
            wal = Path(str(db) + "-wal")
            script = """
                . tests/lib/lxc.sh
                . tests/lib/harness.sh
                autowp_exec_user() { shift; bash -c "$*"; }
                autowp_exec_user_argv() { shift; "$@"; }
                opencode() { printf 'db         %s\\n' "$TEST_DB"; }
                sleep() { :; }
                export -f opencode
                harness_confirm local time-loop 1
            """
            for content, expected in ((b"/time-loop test 1", 1),
                                      (b'\x00{"tool":"skill","name":"time-loop"}', 0)):
                wal.write_bytes(content)
                result = subprocess.run(["bash", "-c", script], cwd=REPO,
                                        env=dict(os.environ, HOME=d, HARNESS="opencode",
                                                 TEST_DB=str(db)),
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)


class Watchdog(unittest.TestCase):
    def test_deadline_stops_an_active_wake(self):
        watchdog = Path(REPO) / "templates/common/tools/bin/time-loop-watchdog.py"
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            fake = root / "opencode"
            fake.write_text(
                "#!/usr/bin/env python3\nimport os,subprocess,time\n"
                "from pathlib import Path\n"
                "Path('wake.pid').write_text(str(os.getpid()))\n"
                "subprocess.Popen(['python3','-c',"
                "'import os,signal,time; from pathlib import Path; "
                "signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                "Path(\"tool.pid\").write_text(str(os.getpid())); time.sleep(300)'])\n"
                "time.sleep(300)\n")
            fake.chmod(0o755)
            (root / "state").touch()
            env = dict(os.environ, PATH=d + ":" + os.environ["PATH"])

            def run(*args):
                return subprocess.run(["python3", str(watchdog), *map(str, args)],
                                      cwd=d, env=env, capture_output=True, text=True,
                                      timeout=15)
            try:
                result = run("start", "state", int(time.time()) + 3, "resume",
                             "--interval", .05, "--idle", 0)
                self.assertEqual(result.returncode, 0, result.stderr)
                end = time.time() + 8
                while run("status").returncode == 0 and time.time() < end:
                    time.sleep(.1)
                self.assertEqual(run("status").returncode, 1)
                self.assertTrue((root / ".time-loop-watchdog.stop").exists())
                pid = int((root / "wake.pid").read_text())
                self.assertFalse(Path(f"/proc/{pid}").exists())
                tool_pid = int((root / "tool.pid").read_text())
                stat = Path(f"/proc/{tool_pid}/stat")
                if stat.exists():
                    self.assertEqual(stat.read_text().rsplit(")", 1)[1].split()[0], "Z")
            finally:
                run("stop")

    def test_lifecycle_and_inherited_credentials(self):
        watchdog = Path(REPO) / "templates/common/tools/bin/time-loop-watchdog.py"
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            fake = root / "opencode"
            fake.write_text(
                "#!/usr/bin/env python3\nimport os,time,subprocess\n"
                "from pathlib import Path\n"
                "Path('credential').write_text(os.environ['TEST_PROVIDER_KEY'])\n"
                "child=subprocess.Popen(['sleep','300'])\n"
                "Path('child.pid').write_text(str(child.pid))\n"
                "time.sleep(300)\n")
            fake.chmod(0o755)
            state = root / "state"
            state.touch()
            env = dict(os.environ, PATH=d + ":" + os.environ["PATH"],
                       TEST_PROVIDER_KEY="dummy-test-key")

            def run(*args):
                return subprocess.run(
                    ["python3", str(watchdog), *map(str, args)], cwd=d, env=env,
                    capture_output=True, text=True, timeout=15)

            deadline = int(time.time()) + 60
            try:
                first = run("start", "state", deadline, "resume", "--interval", .05, "--idle", 0)
                self.assertEqual(first.returncode, 0, first.stderr)
                original = (root / ".time-loop-watchdog.pid").read_text()
                second = run("start", "state", deadline, "resume")
                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertEqual((root / ".time-loop-watchdog.pid").read_text(), original)
                end = time.time() + 5
                while not (root / "child.pid").exists() and time.time() < end:
                    time.sleep(.05)
                self.assertEqual((root / "credential").read_text(), "dummy-test-key")
                child = int((root / "child.pid").read_text())
                self.assertEqual(run("status").returncode, 0)
                self.assertEqual(run("stop").returncode, 0)
                self.assertEqual(run("status").returncode, 1)
                stat = Path(f"/proc/{child}/stat")
                if stat.exists():
                    self.assertEqual(stat.read_text().rsplit(")", 1)[1].split()[0], "Z")
                self.assertTrue((root / ".time-loop-watchdog.stop").exists())
                self.assertNotEqual(run("start", "state", 1, "resume").returncode, 0)
            finally:
                run("stop")

    def test_stale_pidfile_does_not_signal_other_process(self):
        watchdog = Path(REPO) / "templates/common/tools/bin/time-loop-watchdog.py"
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / ".time-loop-watchdog.pid").write_text(
                json.dumps({"pid": os.getpid(), "start": "stale"}))
            result = subprocess.run(["python3", str(watchdog), "stop"], cwd=d,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


LOCK = '# This file is automatically @generated by Cargo.\nversion = 4\n\n[[package]]\nname = "glob"\nversion = "0.3.2"\n'
PATCH_UNUSED = '\n[[patch.unused]]\nname = "creusot-std"\nversion = "0.15.0-dev"\n'


def put(path, text, mode="w"):
    with open(path, mode) as f:
        f.write(text)


class K1(unittest.TestCase):
    """k1 (K1, S.2): the crate under study is unchanged. A Cargo.lock that only
    gained [[patch.unused]] entries (a global cargo [patch], as the creusot
    SDK sets) passes with an INFO line; any other change fails."""

    def run_k1(self, mutate):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            g = lambda *a: subprocess.run(["git", "-C", d, *a], check=True, capture_output=True)
            g("init", "-q")
            put(os.path.join(d, "Cargo.lock"), mode="w", text=LOCK)
            put(os.path.join(d, "lib.rs"), mode="w", text="fn f() {}\n")
            g("add", ".")
            g("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
            head = subprocess.run(["git", "-C", d, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
            mutate(d)
            script = (
                '. tests/lib/lxc.sh >/dev/null 2>&1; . tests/lib/harness.sh >/dev/null 2>&1; '
                'autowp_exec_user() { shift; bash -c "$*"; }; '
                'k1 local "$1" "$2" S.2'
            )
            r = subprocess.run(["bash", "-c", script, "_", d, head], cwd=REPO,
                               capture_output=True, text=True)
            return r.stdout + r.stderr

    def test_unchanged(self):
        self.assertIn("PASS: S.2", self.run_k1(lambda d: None))

    def test_patch_unused_only(self):
        out = self.run_k1(lambda d: put(os.path.join(d, "Cargo.lock"), mode="a", text=PATCH_UNUSED))
        self.assertIn("PASS: S.2", out)
        self.assertIn("patch.unused", out)

    def test_other_lock_change(self):
        def m(d):
            p = os.path.join(d, "Cargo.lock")
            put(p, mode="w", text=LOCK.replace("0.3.2", "0.3.3"))
        self.assertIn("FAIL: S.2", self.run_k1(m))

    def test_new_package_in_lock(self):
        out = self.run_k1(lambda d: put(os.path.join(d, "Cargo.lock"), mode="a", text=
            '\n[[package]]\nname = "evil"\nversion = "1.0.0"\n'))
        self.assertIn("FAIL: S.2", out)

    def test_source_change(self):
        def m(d):
            put(os.path.join(d, "Cargo.lock"), mode="a", text=PATCH_UNUSED)
            put(os.path.join(d, "lib.rs"), mode="a", text="fn g() {}\n")
        self.assertIn("FAIL: S.2", self.run_k1(m))


def embedded_python(path, start_pattern, arg_dir, *args):
    """Run the Python heredoc that follows start_pattern in a shell file."""
    import re
    with open(os.path.join(REPO, path)) as f:
        lines = f.read().split("\n")
    i = next(n for n, l in enumerate(lines) if re.search(start_pattern, l))
    j = next(n for n in range(i, len(lines)) if re.search(r"<<'PY'$", lines[n]))
    k = next(n for n in range(j + 1, len(lines)) if lines[n] == "PY")
    code = "\n".join(lines[j + 1:k])
    r = subprocess.run(["python3", "-I", "-", *args], input=code, text=True,
                       capture_output=True, cwd=arg_dir, check=True)
    return r.stdout


class StateFile(unittest.TestCase):
    """state_json (G.4-G.7): the pinned lines of time-loop/SKILL.md §4."""

    def parse(self, text):
        import json, tempfile
        with tempfile.TemporaryDirectory() as d:
            put(os.path.join(d, "s"), text)
            return json.loads(embedded_python("tests/lib/harness.sh", r"^state_json\(\)", d,
                                              os.path.join(d, "s")))

    def test_pinned(self):
        s = self.parse("start=1793967699\ndeadline=1793971299\nwake=1793967700\n"
                       "cycle 1: x\nwake=1793968900\ncycle 2: y (deadline 1793971299)\n")
        self.assertEqual(s["deadline"], 1793971299)
        self.assertEqual(s["wakes"], [1793967700, 1793968900])
        self.assertEqual(s["cycles"], [1, 2])

    def test_deadline_on_cycle_line_is_not_a_wake(self):
        s = self.parse("start=1793967699\ndeadline=1793971299\n"
                       "cycle2 plan: inflate; ~18min budget (deadline 1793971299).\n")
        self.assertEqual(s["wakes"], [])
        self.assertEqual(s["cycles"], [2])

    def test_gate_t(self):
        self.assertTrue(self.parse("Gate T: six items PASS\n")["gate_t_pass"])
        self.assertFalse(self.parse("Gate T not run; deadline already passed\n")["gate_t_pass"])
        self.assertFalse(self.parse("PAUSE. Gate T not run; items 1-4 expected FAIL. PASS later\n")["gate_t_pass"])


class Verdicts(unittest.TestCase):
    """g11 (G.11): verdicts.tsv as time-loop/SKILL.md §5 pins it, and older words."""

    def counts(self, tsv):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "gzip-1.9-analysis-acsl"))
            put(os.path.join(d, "gzip-1.9-analysis-acsl", "verdicts.tsv"), tsv)
            out = embedded_python("tests/c/gzip-test.sh", r"^g11\(\)", d, "gzip-1.9")
            return [int(x) for x in out.split()]

    def test_pinned_schema(self):
        units, proved, goals, _ = self.counts(
            "unit\tSA#\tfunction\tverdict\tgoals\tnotes\n"
            "unlzh\tSA2\tinit_getbits\tVERIFIED\t7/7\t\n"
            "unzip\tSA1\t-\tRESIDUE(C)\t131/136\t5 open\n"
            "unlzw\t-\t-\tRESIDUE(A)\t\tnon-natural loop\n")
        self.assertEqual((units, proved, goals), (3, 2, 138))

    def test_nothing_proved(self):
        _, proved, _, _ = self.counts(
            "unit\tSA#\tfunction\tverdict\tgoals\tnotes\n"
            "unlzw\t-\t-\tRESIDUE(A)\t0/0\tWP aborts\n")
        self.assertEqual(proved, 0)

    def test_old_words_without_header(self):
        _, proved, _, _ = self.counts("inflate\tValid\n")
        self.assertEqual(proved, 1)


if __name__ == "__main__":
    unittest.main()
