"""Level 1 program tests for auto-wp.py (auto-wp.md section 5, tests 1-22).

Run from the repository root:

    python3 -m unittest discover -s tests -v

Every test runs auto-wp.py as a subprocess in a fresh working directory.
Git discovery is bounded so TMPDIR may also point inside the checkout.

Known pending skill: `creusot-launch` is roadmap step 1 (auto-wp.md 4.3.7,
"Until a step is done, its files are absent"). The expected Rust skill set is
the list of auto-wp.md 4.3.2 minus the pending skills whose template is
absent; every check that needs such a skill is reported as a skip, never as a
silent pass.
"""

import errno
import hashlib
import itertools
import json
import os
import pty
import re
import select
import http.server
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import termios
import time
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "auto-wp.py"
TEMPLATES = REPO / "templates"

# --- what the specification says (auto-wp.md 4.1, 4.2, 4.3.2) -------------

COMMON_SKILLS = [
    "directory-structure", "ebios-risk-manager", "ebios-sl", "fips-sl", "lean",
    "polish-skill", "rmf-sl", "rocq", "sl-auditor", "sl-builder",
    "sl-internal", "sl-monitoring-sl", "stride", "workshop",
]
C_LAYER_SKILLS = [
    "frama-c", "frama-c-api", "frama-c-internals", "frama-c-launch",
    "frama-c-monitoring", "framac-sl", "linux-api", "ocaml", "time-loop",
]
C_COMMANDS = ["ebios", "rmf", "time-loop"]
RUST_LAYER_SKILLS = [
    "creusot", "creusot-launch", "creusot-monitoring", "creusot-sl",
    "sl-auditor", "sl-builder", "sl-internal", "sl-monitoring-sl", "time-loop",
]
RUST_COMMANDS = ["time-loop"]

C_SKILLS = sorted(set(COMMON_SKILLS) | set(C_LAYER_SKILLS))            # 23
RUST_SPEC_SKILLS = sorted(set(COMMON_SKILLS) | set(RUST_LAYER_SKILLS))  # 19

# Rust-layer skills the roadmap has not delivered yet (auto-wp.md 4.3.7).
PENDING_RUST = {"creusot-launch": "roadmap step 1 (auto-wp.md 4.3.7)"}
RUST_ABSENT_PENDING = sorted(
    s for s in PENDING_RUST if not (TEMPLATES / "rust" / "skills" / s).is_dir())
RUST_SKILLS = sorted(set(RUST_SPEC_SKILLS) - set(RUST_ABSENT_PENDING))


def pending_note(skills):
    return ", ".join(f"{s} not written yet: {PENDING_RUST[s]}" for s in skills)


# --- helpers ---------------------------------------------------------------

def snapshot(root):
    """A comparable description of everything under root (and root itself)."""
    root = Path(root)
    result = {}
    if not os.path.lexists(root):
        return None
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames.sort()
        for name in [""] + sorted(dirnames) + sorted(filenames):
            p = Path(dirpath) / name if name else Path(dirpath)
            rel = os.path.relpath(p, root)
            if rel in result:
                continue
            st = os.lstat(p)
            if stat.S_ISLNK(st.st_mode):
                result[rel] = ("link", os.readlink(p))
            elif stat.S_ISDIR(st.st_mode):
                result[rel] = ("dir", stat.S_IMODE(st.st_mode))
            else:
                h = hashlib.sha256(p.read_bytes()).hexdigest()
                result[rel] = ("file", stat.S_IMODE(st.st_mode), h, st.st_mtime_ns)
        # symlinks to directories appear in dirnames but are not descended
    return result


def skill_dirs(project):
    d = Path(project) / "config" / "skills"
    return sorted(p.name for p in d.iterdir() if p.is_dir())


def command_names(project):
    d = Path(project) / "config" / "commands"
    return sorted(p.stem for p in d.iterdir() if p.is_file() and p.suffix == ".md")


def parse_definition(text):
    """Minimal reader for .workshop/autowp.yaml (no YAML module in the stdlib).

    Returns (top-level scalars, [(sdk name, channel or None), ...]).
    """
    top, sdks, in_sdks = {}, [], False
    for raw in text.splitlines():
        line = re.sub(r"\s+#.*$", "", raw).rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            in_sdks = line == "sdks:"
            if not in_sdks and ":" in line:
                k, v = line.split(":", 1)
                top[k.strip()] = v.strip()
            continue
        if in_sdks:
            m = re.match(r"\s*-\s*name:\s*(\S+)$", line)
            if m:
                sdks.append([m.group(1), None])
                continue
            m = re.match(r"\s+channel:\s*(\S+)$", line)
            if m and sdks:
                sdks[-1][1] = m.group(1).strip('"')
    return top, [tuple(x) for x in sdks]


class AutoWpTestCase(unittest.TestCase):
    """Base: an isolated working directory, also when TMPDIR is in the repo."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="autowp-test-")).resolve()
        self.addCleanup(self._cleanup)
        git_env = mock.patch.dict(os.environ, {
            "GIT_CEILING_DIRECTORIES": str(self.tmp.parent),
        })
        git_env.start()
        self.addCleanup(git_env.stop)

    def _cleanup(self):
        for dirpath, dirnames, filenames in os.walk(self.tmp):
            for n in dirnames + filenames:
                p = os.path.join(dirpath, n)
                if not os.path.islink(p):
                    try:
                        os.chmod(p, 0o700)
                    except OSError:
                        pass
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_auto_wp(self, *args, cwd=None, env=None, script=SCRIPT):
        """Run the program; return CompletedProcess (text)."""
        e = dict(os.environ)
        e.pop("GIT_DIR", None)
        e.pop("GIT_WORK_TREE", None)
        if env:
            e.update(env)
        return subprocess.run(
            [sys.executable, str(script), *args],
            cwd=str(cwd or self.tmp), env=e, capture_output=True, text=True,
            stdin=subprocess.DEVNULL, timeout=120)

    def assertOk(self, r):
        self.assertEqual(r.returncode, 0,
                         f"exit {r.returncode}\nstdout:\n{r.stdout}\nstderr:\n{r.stderr}")

    def _copy_program(self):
        """A private copy of auto-wp.py + templates whose templates we may break."""
        prog = self.tmp / "prog"
        prog.mkdir()
        shutil.copy2(SCRIPT, prog / "auto-wp.py")
        shutil.copytree(TEMPLATES, prog / "templates", symlinks=True)
        # The corpus index only: the local PDFs/text are not in git (specs/README.md).
        (prog / "specs").mkdir()
        shutil.copy2(SCRIPT.parent / "specs/MANIFEST.tsv", prog / "specs/MANIFEST.tsv")
        return prog


class TestAutoWp(AutoWpTestCase):

    # 1 ----------------------------------------------------------------------
    def test_01_c_layout(self):
        r = self.run_auto_wp("--c", "--harness", "claude", "foo")
        self.assertOk(r)
        foo = self.tmp / "foo"
        for rel in ["config/skills/frama-c/SKILL.md", "config/commands/rmf.md",
                    "config/skills/sl-internal/SKILL.md"]:
            self.assertTrue((foo / rel).is_file(), f"missing {rel}")
        skills = skill_dirs(foo)
        self.assertEqual(len(skills), 23, skills)
        self.assertEqual(skills, C_SKILLS)
        self.assertEqual(command_names(foo), C_COMMANDS)
        self.assertEqual([s for s in skills if s.startswith("creusot")], [])
        self.assertFalse(os.path.lexists(foo / "config/skills/creusot-launch"))

    # 2 ----------------------------------------------------------------------
    def test_02_rust_layout(self):
        r = self.run_auto_wp("--rust", "--harness", "claude", "foo")
        self.assertOk(r)
        foo = self.tmp / "foo"
        for s in ["creusot", "creusot-launch", "creusot-monitoring", "creusot-sl"]:
            if s in RUST_ABSENT_PENDING:
                continue  # reported by test_02b
            self.assertTrue((foo / "config/skills" / s / "SKILL.md").is_file(),
                            f"missing config/skills/{s}/SKILL.md")
        skills = skill_dirs(foo)
        self.assertEqual(skills, RUST_SKILLS,
                         f"expected the 19 skills of auto-wp.md 4.3.2 minus "
                         f"{RUST_ABSENT_PENDING or 'nothing'}")
        self.assertEqual(len(skills), 19 - len(RUST_ABSENT_PENDING))
        self.assertEqual(command_names(foo), RUST_COMMANDS)
        self.assertEqual([s for s in skills if s.startswith("frama-c")], [])
        self.assertEqual(
            (foo / "config/skills/sl-builder/SKILL.md").read_bytes(),
            (TEMPLATES / "rust/skills/sl-builder/SKILL.md").read_bytes())
        self.assertFalse(os.path.lexists(
            foo / "config/skills/sl-internal/scripts/no_ceiling_gate.py"))

    def test_02b_rust_creusot_launch_installed(self):
        """The part of test 2 that needs creusot-launch (spec count: 19)."""
        if RUST_ABSENT_PENDING:
            self.skipTest(pending_note(RUST_ABSENT_PENDING) +
                          "; --rust installs %d skills instead of 19" % len(RUST_SKILLS))
        r = self.run_auto_wp("--rust", "--harness", "claude", "foo")
        self.assertOk(r)
        self.assertTrue((self.tmp / "foo/config/skills/creusot-launch/SKILL.md").is_file())
        self.assertEqual(len(skill_dirs(self.tmp / "foo")), 19)

    def test_02c_rust_only_pending_skills_absent(self):
        """Every Rust-layer skill of 4.3.2 that is not pending has a template."""
        missing = [s for s in RUST_LAYER_SKILLS
                   if not (TEMPLATES / "rust/skills" / s).is_dir() and s not in PENDING_RUST]
        self.assertEqual(missing, [])

    # 3 ----------------------------------------------------------------------
    def test_03_missing_choices_nonterminal(self):
        cases = [
            ((), "--c/--rust, --harness, <directory-name>"),
            (("foo",), "--c/--rust, --harness"),
            (("--rust",), "--harness, <directory-name>"),
            (("--c", "--harness", "claude"), "<directory-name>"),
        ]
        for args, missing in cases:
            with self.subTest(args=args):
                r = self.run_auto_wp(*args)
                self.assertEqual(r.returncode, 2, r.stderr)
                self.assertIn("usage:", r.stderr)
                self.assertEqual(r.stderr.splitlines()[-1],
                                 f"auto-wp.py: error: missing {missing} "
                                 "(not prompting: stdin or stderr is not a terminal)")
                self.assertEqual(r.stdout, "")
                self.assertEqual(os.listdir(self.tmp), [])

    # 4 ----------------------------------------------------------------------
    def test_04_both_flags_usage_error(self):
        r = self.run_auto_wp("--c", "--rust", "foo")
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertNotEqual(r.stderr.strip(), "")
        self.assertFalse(os.path.lexists(self.tmp / "foo"))
        self.assertEqual(os.listdir(self.tmp), [])

    def test_04b_other_usage_errors(self):
        """auto-wp.md 3.6: unknown option or extra positional -> exit 2."""
        for args in [("a", "b"), ("--bogus", "foo")]:
            with self.subTest(args=args):
                r = self.run_auto_wp("--c", "--harness", "claude", *args)
                self.assertEqual(r.returncode, 2, r.stderr)
                self.assertNotEqual(r.stderr.strip(), "")
                self.assertEqual(os.listdir(self.tmp), [])

    def test_04c_driver_usage_errors(self):
        """fips-skill-spec.md 2: the --driver/--level dependency, both option orders."""
        cases = [
            (("--driver", "fips", "foo"), "--driver fips needs --level"),
            (("--level", "3", "foo"), "--level is only valid with --driver fips"),
            (("--driver", "fips", "--level", "5", "foo"), "invalid choice"),
            (("--driver", "ebios", "foo"), "invalid choice"),
            (("--level", "3", "--driver", "fips", "drv-ok1"), None),   # order-free: accepted
            (("--driver", "fips", "--level", "3", "drv-ok2"), None),
        ]
        for args, err in cases:
            with self.subTest(args=args):
                r = self.run_auto_wp("--c", "--harness", "claude", *args)
                if err is None:
                    self.assertOk(r)
                else:
                    self.assertEqual(r.returncode, 2, r.stderr)
                    self.assertIn(err, r.stderr)
                    self.assertEqual(os.listdir(self.tmp), [])

    # 5 ----------------------------------------------------------------------
    def test_05_help(self):
        for flag in ("--help", "-h"):
            with self.subTest(flag=flag):
                r = self.run_auto_wp(flag)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertIn("usage", r.stdout.lower())
                self.assertIn("--rust", r.stdout)
                help_text = " ".join(r.stdout.split())
                # --c/--rust, --harness and --local-inference: none of the
                # three claims a default, all three are asked for instead.
                self.assertEqual(help_text.count(
                    "asked interactively when omitted and stdin is a terminal"), 3)
                self.assertIn("[<directory-name>]", help_text)
                self.assertIn("--local-inference", help_text)
                self.assertIn("--no-local-inference", help_text)
                self.assertNotIn("default: claude", help_text)
                self.assertEqual(r.stderr, "")
                self.assertEqual(os.listdir(self.tmp), [])

    # 6 ----------------------------------------------------------------------
    def test_06_second_run_fails_unchanged(self):
        for lang in ("--c", "--rust"):
            with self.subTest(lang=lang):
                name = "foo" + lang.strip("-")
                self.assertOk(self.run_auto_wp(lang, "--harness", "claude", name))
                before = snapshot(self.tmp / name)
                r = self.run_auto_wp(lang, "--harness", "claude", name)
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                self.assertIn("auto-wp: error:", r.stderr)
                self.assertEqual(snapshot(self.tmp / name), before)

    # 7 ----------------------------------------------------------------------
    def test_07_existing_file_preserved(self):
        foo = self.tmp / "foo"
        (foo / "src").mkdir(parents=True)
        (foo / "src/main.c").write_text("int main(void) { return 0; }\n")
        (foo / "notes.txt").write_text("keep me\n")
        before = snapshot(foo)
        self.assertOk(self.run_auto_wp("--c", "--harness", "claude", "foo"))
        after = snapshot(foo)
        for k, v in before.items():
            if k == ".":
                continue
            self.assertEqual(after.get(k), v, k)

    # 8 ----------------------------------------------------------------------
    def test_08_existing_harness_dirs(self):
        for dot in (".claude", ".opencode"):
            with self.subTest(dir=dot):
                foo = self.tmp / ("foo" + dot.strip("."))
                (foo / dot).mkdir(parents=True)
                (foo / dot / "settings.json").write_text('{"x": 1}\n')
                before = snapshot(foo / dot / "settings.json")
                r = self.run_auto_wp("--c", "--harness", "claude", foo.name)
                self.assertOk(r)
                self.assertEqual(snapshot(foo / dot / "settings.json"), before)
                self.assertTrue((foo / dot / "skills").is_symlink())

    def test_08b_reserved_paths_refused(self):
        cases = {
            "claude-skills": lambda d: ((d / ".claude").mkdir(),
                                        (d / ".claude/skills").mkdir()),
            "claude-commands-file": lambda d: ((d / ".claude").mkdir(),
                                               (d / ".claude/commands").write_text("x")),
            "opencode-skills": lambda d: ((d / ".opencode").mkdir(),
                                          (d / ".opencode/skills").mkdir()),
            "opencode-commands-file": lambda d: ((d / ".opencode").mkdir(),
                                                 (d / ".opencode/commands").write_text("x")),
            "config-dir": lambda d: (d / "config").mkdir(),
            "config-file": lambda d: (d / "config").write_text("x"),
            "agents-link": lambda d: (d / ".agents").symlink_to("nowhere"),
            "claude-is-file": lambda d: (d / ".claude").write_text("x"),
            "opencode-is-file": lambda d: (d / ".opencode").write_text("x"),
        }
        for name, make in cases.items():
            with self.subTest(case=name):
                d = self.tmp / name
                d.mkdir()
                (d / "keep.txt").write_text("keep\n")
                make(d)
                before = snapshot(d)
                r = self.run_auto_wp("--c", "--harness", "claude", name)
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                self.assertIn("auto-wp: error:", r.stderr)
                self.assertEqual(snapshot(d), before)

    def test_08c_target_is_a_file(self):
        (self.tmp / "foo").write_text("plain file\n")
        before = snapshot(self.tmp)
        r = self.run_auto_wp("--c", "--harness", "claude", "foo")
        self.assertEqual(r.returncode, 1)
        self.assertIn("auto-wp: error:", r.stderr)
        self.assertEqual(snapshot(self.tmp), before)

    def test_08d_target_symlink_to_dir(self):
        """auto-wp.md 3.1 item 1: a symlink to a directory is used as the directory."""
        (self.tmp / "real").mkdir()
        (self.tmp / "foo").symlink_to("real")
        self.assertOk(self.run_auto_wp("--c", "--harness", "claude", "foo"))
        self.assertTrue((self.tmp / "foo").is_symlink())
        self.assertTrue((self.tmp / "real/config/skills/frama-c/SKILL.md").is_file())

    # 9 ----------------------------------------------------------------------
    def test_09_relative_symlinks(self):
        for lang in ("--c", "--rust"):
            with self.subTest(lang=lang):
                foo = self.tmp / ("foo" + lang.strip("-"))
                self.assertOk(self.run_auto_wp(lang, "--harness", "claude", foo.name))
                for rel, target, resolved in [
                        (".claude/skills", "../config/skills", "config/skills"),
                        (".claude/commands", "../config/commands", "config/commands"),
                        (".opencode/skills", "../config/skills", "config/skills"),
                        (".opencode/commands", "../config/commands", "config/commands"),
                        (".agents", "config", "config")]:
                    p = foo / rel
                    self.assertTrue(p.is_symlink(), rel)
                    self.assertEqual(os.readlink(p), target)
                    self.assertFalse(os.path.isabs(os.readlink(p)))
                    self.assertEqual(p.resolve(), (foo / resolved).resolve())
                # still valid after moving the project
                moved = self.tmp / ("moved-" + foo.name)
                foo.rename(moved)
                self.assertTrue((moved / ".claude/skills/sl-builder/SKILL.md").is_file())
                self.assertTrue((moved / ".opencode/skills/sl-builder/SKILL.md").is_file())
                if lang == "--c":
                    self.assertTrue((moved / ".opencode/commands/time-loop.md").is_file())

    # 10 ---------------------------------------------------------------------
    def test_10_exec_bits(self):
        for lang in ("c", "rust"):
            with self.subTest(lang=lang):
                foo = self.tmp / ("foo" + lang)
                self.assertOk(self.run_auto_wp("--" + lang, "--harness", "claude", foo.name))
                layers = [TEMPLATES / "common/skills", TEMPLATES / lang / "skills"]
                skills_root = foo / "config/skills"
                checked = executable = 0
                for dirpath, _, filenames in os.walk(skills_root):
                    for fn in filenames:
                        p = Path(dirpath) / fn
                        rel = p.relative_to(skills_root)
                        skill = rel.parts[0]
                        src = next(l / rel for l in reversed(layers)
                                   if (l / skill).is_dir())
                        self.assertTrue(os.path.lexists(src), f"no template for {rel}")
                        if p.is_symlink():
                            self.assertTrue(src.is_symlink(), rel)
                            continue
                        mine = bool(os.stat(p).st_mode & stat.S_IXUSR)
                        theirs = bool(os.stat(src).st_mode & stat.S_IXUSR)
                        self.assertEqual(mine, theirs, f"exec bit of {rel}")
                        self.assertEqual(p.read_bytes(), src.read_bytes(), rel)
                        checked += 1
                        executable += mine
                self.assertGreater(checked, 0)
                self.assertGreater(executable, 0, "expected executable scripts")
                if lang == "c":
                    self.assertTrue(os.access(
                        skills_root / "sl-internal/scripts/no_ceiling_gate.py", os.X_OK))
                    self.assertTrue(os.access(
                        skills_root / "frama-c-monitoring/canaries/macsl-contexts-sync.sh",
                        os.X_OK))

    # 11 ---------------------------------------------------------------------
    def test_11_manifest(self):
        for lang in ("c", "rust"):
            with self.subTest(lang=lang):
                foo = self.tmp / ("foo" + lang)
                self.assertOk(self.run_auto_wp("--" + lang, "--harness", "claude", foo.name))
                m = json.loads((foo / "config/auto-wp.json").read_text())
                self.assertEqual(m["language"], lang)
                self.assertEqual(m["auto_wp_version"], "0.9.0")
                self.assertEqual(m["driver"], "rmf")
                self.assertNotIn("fips_level", m)
                self.assertRegex(m["created"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
                self.assertEqual(m["skills"], sorted(m["skills"]))
                self.assertEqual(m["commands"], sorted(m["commands"]))
                self.assertEqual(m["skills"], skill_dirs(foo))
                self.assertEqual(m["commands"], command_names(foo))
                self.assertEqual(sorted(os.listdir(foo / "config/commands")),
                                 [c + ".md" for c in m["commands"]])

    # 12 ---------------------------------------------------------------------
    def test_12_other_cwd(self):
        elsewhere = self.tmp / "elsewhere"
        elsewhere.mkdir()
        r = self.run_auto_wp("--c", "--harness", "claude", "foo", cwd=elsewhere)
        self.assertOk(r)
        self.assertEqual(len(skill_dirs(elsewhere / "foo")), 23)
        # absolute target path as well
        r = self.run_auto_wp("--rust", "--harness", "claude", str(self.tmp / "abs"), cwd=elsewhere)
        self.assertOk(r)
        self.assertEqual(skill_dirs(self.tmp / "abs"), RUST_SKILLS)

    # 13 ---------------------------------------------------------------------
    def test_13_c_readme(self):
        self.assertOk(self.run_auto_wp("--c", "--harness", "claude", "foobar"))
        text = (self.tmp / "foobar/README.md").read_text()
        self.assertIn("git clone https://gitlab.freedesktop.org/gnu-grub/grub.git", text)
        self.assertIn("/time-loop grub 72", text)
        self.assertIn("bin/fetch-sources.sh", text)
        # The /time-loop explanation is shared (3.4 item 2D): one code block.
        blocks = re.findall(r"```\n(.*?)```", text, re.S)
        self.assertEqual(sum("/time-loop grub 72" in b for b in blocks), 1, blocks)
        # Three quick starts, in order: Workshop, Multipass, LXD.
        self.assertLess(text.index("workshop launch"), text.index("multipass launch"))
        self.assertLess(text.index("multipass launch"), text.index("bin/launch_lxc.sh"))
        for needle in ("/project", "workshop shell", "workshop remove", "caffeinate",
                       "multipass transfer"):
            self.assertIn(needle, text, needle)
        # Stand-alone: no host checkout such as ~/git/use-frama-c is needed.
        self.assertNotIn("~/git/", text)
        self.assertNotIn("UFC", text)
        self.assertNotIn("{{", text)
        self.assertTrue(text.startswith(
            "# foobar — automated verification of C (Frama-C/WP) code"), text[:80])

    def test_13b_c_tools_stand_alone(self):
        self.assertOk(self.run_auto_wp("--c", "--harness", "claude", "foobar"))
        d = self.tmp / "foobar"
        for rel in ("bin/rmf-lint.sh", "bin/fips-lint.sh", "bin/ebios-lint.sh",
                    "bin/ledger-ratchet.sh",
                    "bin/crosswalk-gen.sh", "bin/fetch-sources.sh", "no-ceiling.md", ".gitignore",
                    "frama-c-patches/apply.sh", "framac-gold"):
            self.assertTrue(os.path.lexists(d / rel), rel)
            self.assertFalse((d / rel).is_symlink(), rel)
        # bin/ merges the common layer (rmf-lint.sh) and the C layer (22): 4.1, 4.2.1.
        self.assertEqual(len(list(d.glob("bin/*.sh"))), 23)
        self.assertEqual((d / "bin/rmf-lint.sh").read_bytes(),
                         (TEMPLATES / "common/tools/bin/rmf-lint.sh").read_bytes())
        self.assertEqual((d / "bin/fips-lint.sh").read_bytes(),
                         (TEMPLATES / "c/tools/bin/fips-lint.sh").read_bytes())
        # The FIPS corpus is a fips-driver install (test_21_fips_specs); no PDF at the root.
        self.assertFalse(os.path.lexists(d / "specs"))
        self.assertEqual(list(d.glob("*.pdf")), [])
        self.assertEqual(list(d.glob("*.sh")), [], "scripts belong in bin/, not the root")
        for s in d.glob("bin/*.sh"):
            self.assertTrue(os.access(s, os.X_OK), s.name)
        self.assertIn("/framac-src/", (d / ".gitignore").read_text())
        self.assertIn("/.workshop.lock", (d / ".gitignore").read_text())

    def test_13c_rust_has_only_common_tools(self):
        """--rust gets the common linter and watchdog, but no C-only tools."""
        self.assertOk(self.run_auto_wp("--rust", "--harness", "claude", "foobar"))
        d = self.tmp / "foobar"
        self.assertEqual(sorted(p.name for p in (d / "bin").iterdir()),
                         ["check-delivery", "heavy", "ledger", "mem-watchdog",
                          "rmf-lint.sh", "time-loop-watchdog.py"])
        # The R6 resource guard (2026-11-15 OOM crash) ships from the common layer, executable.
        for name in ("heavy", "mem-watchdog"):
            g = d / "bin" / name
            self.assertTrue(g.is_file() and not g.is_symlink(), name)
            self.assertTrue(os.access(g, os.X_OK), f"{name} not executable")
        lint = d / "bin/rmf-lint.sh"
        self.assertTrue(lint.is_file() and not lint.is_symlink())
        self.assertTrue(os.access(lint, os.X_OK))
        self.assertEqual(lint.read_bytes(),
                         (TEMPLATES / "common/tools/bin/rmf-lint.sh").read_bytes())
        for rel in ("frama-c-patches", "framac-gold", "no-ceiling.md", "specs"):
            self.assertFalse(os.path.lexists(d / rel), rel)
        gi = self.tmp / "foobar/.gitignore"
        self.assertTrue(gi.is_file() and not gi.is_symlink())
        self.assertIn("/.workshop.lock", gi.read_text())

    def test_13d_existing_tool_kept(self):
        foo = self.tmp / "foo"
        foo.mkdir()
        (foo / ".gitignore").write_text("mine\n")
        r = self.run_auto_wp("--c", "--harness", "claude", "foo")
        self.assertOk(r)
        self.assertEqual((foo / ".gitignore").read_text(), "mine\n")
        self.assertIn("kept    foo/.gitignore (already exists)", r.stdout.splitlines())
        self.assertNotIn("copied  foo/.gitignore", r.stdout.splitlines())
        self.assertIn("copied  foo/bin", r.stdout.splitlines())

    # 14 ---------------------------------------------------------------------
    def test_14_rust_readme(self):
        self.assertOk(self.run_auto_wp("--rust", "--harness", "claude", "foobar"))
        text = (self.tmp / "foobar/README.md").read_text()
        self.assertIn("creusot-launch", text)
        for needle in ("workshop launch", "multipass launch", "cargo creusot"):
            self.assertIn(needle, text, needle)
        self.assertNotIn("bin/fetch-sources.sh", text)
        self.assertNotIn("{{", text)
        has_cmd = (TEMPLATES / "rust/commands/time-loop.md").exists()
        self.assertEqual("/time-loop mycrate 72" in text, has_cmd)
        self.assertTrue(text.startswith(
            "# foobar — automated verification of Rust (Creusot) code"), text[:80])

    # 15 ---------------------------------------------------------------------
    def test_15_dot_in_bar(self):
        bar = self.tmp / "bar"
        bar.mkdir()
        r = self.run_auto_wp("--c", "--harness", "claude", ".", cwd=bar)
        self.assertOk(r)
        title = (bar / "README.md").read_text().splitlines()[0]
        self.assertTrue(title.startswith("# bar"), title)
        for spelled in ("baz/", "./qux"):
            with self.subTest(spelled=spelled):
                self.assertOk(self.run_auto_wp("--c", "--harness", "claude", spelled))
                name = spelled.strip("./")
                title = (self.tmp / name / "README.md").read_text().splitlines()[0]
                self.assertTrue(title.startswith(f"# {name} "), title)

    # 16 ---------------------------------------------------------------------
    def test_16_existing_readme_kept(self):
        foo = self.tmp / "foo"
        foo.mkdir()
        (foo / "README.md").write_text("my own readme\n")
        before = snapshot(foo / "README.md")
        r = self.run_auto_wp("--c", "--harness", "claude", "foo")
        self.assertOk(r)
        self.assertEqual(snapshot(foo / "README.md"), before)
        self.assertIn("kept    foo/README.md (already exists)", r.stdout.splitlines())

    # 17 ---------------------------------------------------------------------
    def test_17_git(self):
        if shutil.which("git") is None:
            self.skipTest("git not installed")
        probe = subprocess.run(["git", "-C", str(self.tmp), "rev-parse",
                                "--is-inside-work-tree"], capture_output=True, text=True,
                               timeout=15)
        if probe.returncode == 0:
            self.fail(f"temporary directory {self.tmp} is already inside a git work tree")
        r = self.run_auto_wp("--c", "--harness", "claude", "foo")
        self.assertOk(r)
        self.assertIn("git     initialized foo", r.stdout.splitlines())
        out = subprocess.run(["git", "-C", str(self.tmp / "foo"), "rev-parse",
                              "--show-toplevel"], capture_output=True, text=True, timeout=15)
        self.assertEqual(out.returncode, 0)
        self.assertEqual(Path(out.stdout.strip()).resolve(), (self.tmp / "foo").resolve())
        branch = subprocess.run(["git", "-C", str(self.tmp / "foo"), "symbolic-ref",
                                 "--short", "HEAD"], capture_output=True, text=True, timeout=15)
        self.assertEqual(branch.stdout.strip(), "main",
                         "auto-wp.py must init on branch main")
        # One commit, the generated baseline, and a clean tree after it: a
        # project that starts with "No commits yet on main" has no baseline to
        # diff the campaign's own work against.
        log = subprocess.run(["git", "-C", str(self.tmp / "foo"), "rev-list", "--count", "HEAD"],
                             capture_output=True, text=True, timeout=15)
        self.assertEqual(log.stdout.strip(), "1", "auto-wp.py must make one commit")
        status = subprocess.run(["git", "-C", str(self.tmp / "foo"), "status", "--porcelain"],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(status.stdout, "", "the generated tree must be fully committed")
        remotes = subprocess.run(["git", "-C", str(self.tmp / "foo"), "remote"],
                                 capture_output=True, text=True, timeout=15)
        self.assertEqual(remotes.stdout.strip(), "", "auto-wp.py must not add a remote")
        # Inside an existing work tree the project still gets a repository of
        # its own: the campaign's checkpoints belong in the project's history,
        # not in whatever repository happens to contain it.
        outer = self.tmp / "outer"
        outer.mkdir()
        subprocess.run(["git", "init", "-q", str(outer)], check=True, timeout=15)
        r = self.run_auto_wp("--c", "--harness", "claude", "outer/foo")
        self.assertOk(r)
        self.assertTrue((outer / "foo/.git").is_dir(),
                        "every generated project gets its own .git")
        self.assertIn("git     initialized outer/foo", r.stdout.splitlines())
        top = subprocess.run(["git", "-C", str(outer / "foo"), "rev-parse",
                              "--show-toplevel"], capture_output=True, text=True,
                             timeout=15)
        self.assertEqual(Path(top.stdout.strip()).resolve(),
                         (outer / "foo").resolve(),
                         "the nested repository must be the project itself")

    # 18 ---------------------------------------------------------------------
    def test_18_no_git(self):
        empty_bin = self.tmp / "emptybin"
        empty_bin.mkdir()
        r = self.run_auto_wp("--c", "--harness", "claude", "foo", env={"PATH": str(empty_bin)})
        self.assertOk(r)
        self.assertIn("warning: git not found; run 'git init -b main' in foo before /time-loop",
                      r.stderr)
        self.assertFalse(os.path.lexists(self.tmp / "foo/.git"))
        self.assertEqual(len(skill_dirs(self.tmp / "foo")), 23)

    # 19 ---------------------------------------------------------------------
    def test_19_rollback(self):
        if os.geteuid() == 0:
            self.skipTest("running as root: an unreadable file is still readable")
        prog = self._copy_program()
        # A file late in the copy order (sorted skill names), so a lot is
        # already created when the error happens.
        victim = prog / "templates/c/skills/time-loop/SKILL.md"
        victim.chmod(0)
        work = self.tmp / "work"
        work.mkdir()
        script = prog / "auto-wp.py"

        with self.subTest(case="target created by the run"):
            r = self.run_auto_wp("--c", "--harness", "claude", "foo", cwd=work, script=script)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("auto-wp: error:", r.stderr)
            self.assertEqual(r.stdout, "")
            self.assertFalse(os.path.lexists(work / "foo"))
            self.assertEqual(os.listdir(work), [])

        with self.subTest(case="missing parents created by the run"):
            r = self.run_auto_wp("--c", "--harness", "claude", "a/b/foo", cwd=work, script=script)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertEqual(os.listdir(work), [])

        with self.subTest(case="existing target with content and .claude/"):
            foo = work / "existing"
            (foo / ".claude").mkdir(parents=True)
            (foo / ".claude/settings.json").write_text("{}\n")
            (foo / "src.c").write_text("int x;\n")
            before = snapshot(foo)
            r = self.run_auto_wp("--c", "--harness", "claude", "existing", cwd=work, script=script)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertEqual(snapshot(foo), before)

        with self.subTest(case="re-run after fixing starts from the same state"):
            victim.chmod(0o644)
            r = self.run_auto_wp("--c", "--harness", "claude", "foo", cwd=work, script=script)
            self.assertOk(r)
            self.assertEqual(len(skill_dirs(work / "foo")), 23)

    def test_19b_rollback_missing_template_dir(self):
        """Missing template directory: run-time error, exit 1, nothing created."""
        prog = self._copy_program()
        shutil.rmtree(prog / "templates/rust")
        r = self.run_auto_wp("--rust", "--harness", "claude", "foo", script=prog / "auto-wp.py")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("auto-wp: error:", r.stderr)
        self.assertFalse(os.path.lexists(self.tmp / "foo"))

    def test_19c_rollback_git_init_fails(self):
        """git init failing (auto-wp.md 3.6) is rolled back, .git included."""
        fakebin = self.tmp / "fakebin"
        fakebin.mkdir()
        fake = fakebin / "git"
        fake.write_text("#!/bin/sh\n"
                        "case \"$*\" in *rev-parse*) exit 128;; esac\n"
                        "echo 'fatal: simulated failure' >&2\nexit 1\n")
        fake.chmod(0o755)
        r = self.run_auto_wp("--c", "--harness", "claude", "foo", env={"PATH": f"{fakebin}"})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("auto-wp: error:", r.stderr)
        self.assertFalse(os.path.lexists(self.tmp / "foo"))


    # 20 ---------------------------------------------------------------------
    def test_20_workshop_definition(self):
        expected = {
            "c": ["frama-c-sdk", "rocq", "lean", "project-autowp-packages"],
            "rust": ["creusot", "rocq", "lean", "project-autowp-packages"],
        }
        for lang in ("c", "rust"):
            with self.subTest(lang=lang):
                foo = self.tmp / ("foo" + lang)
                r = self.run_auto_wp("--" + lang, "--harness", "claude", foo.name)
                self.assertOk(r)
                self.assertIn(f"copied  {foo.name}/.workshop (workshop: autowp)",
                              r.stdout.splitlines())
                ws = foo / ".workshop"
                for rel in ("autowp.yaml", "autowp-packages/sdk.yaml"):
                    p = ws / rel
                    self.assertTrue(p.is_file() and not p.is_symlink(), rel)
                    self.assertEqual(p.read_bytes(),
                                     (TEMPLATES / lang / "workshop" / rel).read_bytes(), rel)
                    text = p.read_text()
                    for bad in ("{{", "~/git/", "sdks/"):
                        self.assertNotIn(bad, text, f"{rel} contains {bad!r}")
                self.assertTrue(os.access(ws / "autowp-packages/hooks/setup-base", os.X_OK))
                self.assertFalse(os.access(ws / "autowp.yaml", os.X_OK))
                top, sdks = parse_definition((ws / "autowp.yaml").read_text())
                self.assertEqual(top.get("name"), "autowp")
                self.assertEqual(top.get("base"), "ubuntu@24.04")
                self.assertEqual([n for n, _ in sdks], expected[lang])
                for name, channel in sdks:
                    if name.startswith("project-"):
                        self.assertIsNone(channel, name)
                    else:
                        self.assertEqual(channel, "latest/edge", name)
                    self.assertFalse(name.startswith("try-"), name)
                hook = (ws / "autowp-packages/hooks/setup-base").read_text()
                self.assertTrue(hook.startswith("#!/bin/bash\n"))
                self.assertIn("apt-get install", hook)
                self.assertEqual("libfuse3-dev" in hook, lang == "c")
                sdk = (ws / "autowp-packages/sdk.yaml").read_text()
                self.assertRegex(sdk, r"(?m)^name: autowp-packages$")

    def test_20b_byobu_default_and_opt_out(self):
        """Byobu is configured by default; --no-byobu strips the hook and the package."""
        hooks = ".workshop/autowp-packages/hooks"
        for lang in ("c", "rust"):
            with self.subTest(lang=lang):
                # default: setup-project hook present, byobu in setup-base's apt line
                r = self.run_auto_wp("--" + lang, "--harness", "none", "with" + lang)
                self.assertOk(r)
                proj = self.tmp / ("with" + lang)
                self.assertTrue((proj / hooks / "setup-project").is_file())
                self.assertIn("byobu tmux", (proj / hooks / "setup-base").read_text())
                # --no-byobu: hook removed, byobu dropped from the apt line, tmux kept
                r = self.run_auto_wp("--" + lang, "--harness", "none", "--no-byobu",
                                     "no" + lang)
                self.assertOk(r)
                proj = self.tmp / ("no" + lang)
                self.assertFalse(os.path.lexists(proj / hooks / "setup-project"))
                base = (proj / hooks / "setup-base").read_text()
                self.assertNotIn("byobu", base)
                self.assertIn("tmux curl", base)

    # 21 ---------------------------------------------------------------------
    def test_21_workshop_reserved_paths(self):
        cases = {
            "yaml-exists": lambda d: ((d / ".workshop").mkdir(),
                                      (d / ".workshop/autowp.yaml").write_text("x")),
            "packages-dir-exists": lambda d: (d / ".workshop/autowp-packages").mkdir(parents=True),
            "workshop-is-file": lambda d: (d / ".workshop").write_text("x"),
        }
        for name, make in cases.items():
            with self.subTest(case=name):
                d = self.tmp / name
                d.mkdir()
                (d / "keep.txt").write_text("keep\n")
                make(d)
                before = snapshot(d)
                r = self.run_auto_wp("--c", "--harness", "claude", name)
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                self.assertIn("auto-wp: error:", r.stderr)
                self.assertEqual(snapshot(d), before)
                self.assertFalse(os.path.lexists(d / "config"))
        with self.subTest(case="other definition preserved"):
            d = self.tmp / "other"
            (d / ".workshop").mkdir(parents=True)
            (d / ".workshop/other.yaml").write_text("name: other\n")
            before = snapshot(d / ".workshop/other.yaml")
            r = self.run_auto_wp("--c", "--harness", "claude", "other")
            self.assertOk(r)
            self.assertEqual(snapshot(d / ".workshop/other.yaml"), before)
            self.assertTrue((d / ".workshop/autowp.yaml").is_file())

    # 22 ---------------------------------------------------------------------
    def test_22_workshop_rollback(self):
        if os.geteuid() == 0:
            self.skipTest("running as root: an unreadable file is still readable")
        prog = self._copy_program()
        # The README is written after .workshop/ (3.6), so an unreadable
        # README template fails the run once .workshop/ exists.
        victim = prog / "templates/c/README.md"
        victim.chmod(0)
        script = prog / "auto-wp.py"
        work = self.tmp / "work"
        work.mkdir()
        with self.subTest(case=".workshop created by the run"):
            r = self.run_auto_wp("--c", "--harness", "claude", "foo", cwd=work, script=script)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertFalse(os.path.lexists(work / "foo"))
        with self.subTest(case="pre-existing .workshop/other.yaml kept"):
            foo = work / "existing"
            (foo / ".workshop").mkdir(parents=True)
            (foo / ".workshop/other.yaml").write_text("name: other\n")
            before = snapshot(foo)
            r = self.run_auto_wp("--c", "--harness", "claude", "existing", cwd=work, script=script)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertEqual(snapshot(foo), before)
            self.assertEqual(os.listdir(foo / ".workshop"), ["other.yaml"])


class TerminalProcess:
    """Canonical terminal input/stderr, separately drained stdout, bounded waits."""

    def __init__(self, test, *args, cwd=None, env=None):
        self.master, slave = pty.openpty()
        self.process = None
        test.addCleanup(self.close)
        try:
            attrs = termios.tcgetattr(slave)
            attrs[3] |= termios.ICANON
            attrs[3] &= ~termios.ECHO
            termios.tcsetattr(slave, termios.TCSANOW, attrs)
            self.veof = attrs[6][termios.VEOF]
            e = dict(os.environ)
            e.pop("GIT_DIR", None)
            e.pop("GIT_WORK_TREE", None)
            if env:
                e.update(env)
            self.process = subprocess.Popen(
                [sys.executable, str(SCRIPT), *args], cwd=cwd or test.tmp,
                env=e, stdin=slave, stderr=slave, stdout=subprocess.PIPE)
        finally:
            os.close(slave)
        self.streams = {self.master: "stderr", self.process.stdout.fileno(): "stdout"}
        self.output = {"stdout": b"", "stderr": b""}

    def close(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.kill()
            self.process.wait(timeout=5)
            self.process.stdout.close()
        os.close(self.master)

    def read(self, deadline):
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not self.streams:
            raise AssertionError(f"terminal wait failed: {self.output!r}")
        ready, _, _ = select.select(list(self.streams), [], [], remaining)
        if not ready:
            raise AssertionError(f"terminal timed out: {self.output!r}")
        for fd in ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError as e:
                if fd != self.master or e.errno != errno.EIO:
                    raise
                chunk = b""  # Linux signals the closed slave with EIO.
            if chunk:
                self.output[self.streams[fd]] += chunk
            else:
                del self.streams[fd]

    def wait_for(self, text):
        deadline = time.monotonic() + 15
        while text.encode() not in self.output["stderr"]:
            self.read(deadline)

    def send(self, data):
        os.write(self.master, data)

    def finish(self):
        deadline = time.monotonic() + 30
        while self.streams:
            self.read(deadline)
        code = self.process.wait(timeout=max(0.1, deadline - time.monotonic()))
        return subprocess.CompletedProcess(
            self.process.args, code,
            self.output["stdout"].decode("utf-8", errors="replace"),
            self.output["stderr"].decode("utf-8", errors="replace").replace("\r\n", "\n"))


class TestInteractiveCompletion(AutoWpTestCase):
    PROMPTS = ("Choose the language:", "Choose the agent harness:", "Project directory:")
    QUESTIONS = ("Type 1 or 2: ", "Type 1, 2, 3 or 4: ", "Project directory: ")
    # Asked only under --harness opencode, so it is not one of PROMPTS.
    LOCAL_QUESTION = "Use a local inference server for OpenCode?"

    def assertPrompts(self, result, expected):
        prompts = re.findall("|".join(map(re.escape, self.PROMPTS)), result.stderr)
        self.assertEqual(prompts, expected, result.stderr)
        for prompt in self.PROMPTS:
            self.assertNotIn(prompt, result.stdout)

    def comparable_tree(self, root):
        tree = snapshot(root)
        for rel in list(tree):
            if rel == ".git" or rel.startswith(".git/"):
                del tree[rel]
            elif tree[rel][0] == "file":
                tree[rel] = tree[rel][:3]  # Ignore timestamps, not content or modes.
        manifest = json.loads((root / "config/auto-wp.json").read_text())
        del manifest["created"]
        tree["config/auto-wp.json"] = manifest
        tree["README.md"] = (root / "README.md").read_text().replace(root.name, "PROJECT")
        return tree

    def test_t2_all_missing_combinations(self):
        for explicit in itertools.product((False, True), repeat=3):
            with self.subTest(explicit=explicit):
                name = "project-" + "".join(str(int(x)) for x in explicit)
                choices = [("--rust",), ("--harness", "none"), (name,)]
                args = [arg for supplied, choice in zip(explicit, choices)
                        if supplied for arg in choice]
                p = TerminalProcess(self, *args)
                for supplied, question, answer in zip(
                        explicit, self.QUESTIONS, (b"2\n", b"4\n", name.encode() + b"\n")):
                    if not supplied:
                        p.wait_for(question)
                        self.assertTrue(p.output["stderr"].endswith(question.encode()))
                        self.assertFalse((self.tmp / name).exists())
                        p.send(answer)
                r = p.finish()
                self.assertOk(r)
                self.assertPrompts(r, [prompt for supplied, prompt in zip(explicit, self.PROMPTS)
                                       if not supplied])
                m = json.loads((self.tmp / name / "config/auto-wp.json").read_text())
                self.assertEqual((m["language"], m["harness"]), ("rust", "none"))
                self.assertIn("harness:  none", r.stdout)

    def test_answering_yes_names_the_address_file(self):
        """The question gives no hint that a file is required; the answer does.

        Answered yes, nothing is generated yet and the user can still act, so
        this is the moment to say where the address goes. Answered no, there
        is nothing to say.
        """
        for answer, expected in (("2", True), ("1", False)):
            with self.subTest(answer=answer):
                name = f"ip-note-{answer}"
                p = TerminalProcess(self)
                p.wait_for(self.QUESTIONS[0])
                p.send(f"1\n2\n{answer}\n{name}\n".encode())
                r = p.finish()
                self.assertOk(r)
                said = ".local-llm-machine-ip.txt" in r.stderr
                self.assertEqual(said, expected, r.stderr)
                if expected:
                    # Both locations, and what happens without the file.
                    self.assertIn("project", r.stderr)
                    self.assertIn("workshop refresh", r.stderr)
                    self.assertIn("current provider", r.stderr)
                    # On stderr with the prompts, never in the result output.
                    self.assertNotIn(".local-llm-machine-ip.txt", r.stdout)

    def test_t2_interactive_matches_explicit_tree(self):
        for language, number in (("c", "1"), ("rust", "2")):
            for harness, selection in (("claude", "1"), ("opencode", "2"),
                                       ("copilot", "3"), ("none", "4")):
                with self.subTest(language=language, harness=harness):
                    name = f"prompted-{language}-{harness}"
                    other = f"explicit-{language}-{harness}"
                    # OpenCode is asked one more question, between the harness
                    # and the directory; "1" is the cloud provider, which is
                    # what the explicit command below selects.
                    extra = "1\n" if harness == "opencode" else ""
                    flags = (("--no-local-inference",) if harness == "opencode"
                             else ())
                    p = TerminalProcess(self)
                    p.wait_for(self.QUESTIONS[0])
                    p.send(f"{number}\n{selection}\n{extra}{name}\n".encode())
                    r = p.finish()
                    self.assertOk(r)
                    explicit = self.run_auto_wp("--" + language, "--harness", harness,
                                                *flags, other)
                    self.assertOk(explicit)
                    self.assertEqual(self.comparable_tree(self.tmp / name),
                                     self.comparable_tree(self.tmp / other))
                    self.assertEqual(r.stdout.replace(name, "PROJECT"),
                                     explicit.stdout.replace(other, "PROJECT"))
                    self.assertPrompts(r, list(self.PROMPTS))
                    self.assertEqual(self.LOCAL_QUESTION in r.stderr,
                                     harness == "opencode", r.stderr)

    def test_t3_open_pipe_never_read(self):
        for args, code in ((("--rust", "--harness", "none", "foo"), 0), ((), 2)):
            with self.subTest(args=args):
                read_fd, write_fd = os.pipe()
                try:
                    r = subprocess.run(
                        [sys.executable, str(SCRIPT), *args], cwd=self.tmp,
                        stdin=read_fd, capture_output=True, text=True, timeout=15)
                    self.assertEqual(r.returncode, code, r.stderr)
                    # The writer stayed open and empty for the entire invocation.
                    self.assertNotIn("Choose the", r.stderr)
                finally:
                    os.close(read_fd)
                    os.close(write_fd)

    def test_t3_pipe_contents_not_consumed(self):
        for args, code in (((), 2), (("--c", "--harness", "none", "foo"), 0)):
            with self.subTest(args=args):
                read_fd, write_fd = os.pipe()
                try:
                    data = b"2\n4\nunwanted\n"
                    os.write(write_fd, data)
                    r = subprocess.run(
                        [sys.executable, str(SCRIPT), *args], cwd=self.tmp,
                        stdin=read_fd, capture_output=True, text=True, timeout=15)
                    self.assertEqual(r.returncode, code, r.stderr)
                    os.set_blocking(read_fd, False)
                    self.assertEqual(os.read(read_fd, len(data)), data)
                    self.assertFalse((self.tmp / "unwanted").exists())
                    if code == 2:
                        self.assertEqual(os.listdir(self.tmp), [])
                finally:
                    os.close(read_fd)
                    os.close(write_fd)

    def test_t3_terminal_stdin_redirected_stderr(self):
        master, slave = pty.openpty()
        try:
            with (self.tmp / "stderr.log").open("w+") as log:
                r = subprocess.run(
                    [sys.executable, str(SCRIPT)], cwd=self.tmp, stdin=slave,
                    stderr=log, stdout=subprocess.PIPE, text=True, timeout=15)
                self.assertEqual(r.returncode, 2)
                log.seek(0)
                self.assertIn("missing --c/--rust, --harness, <directory-name> "
                              "(not prompting: stdin or stderr is not a terminal)", log.read())
                self.assertEqual(r.stdout, "")
                self.assertEqual(os.listdir(self.tmp), ["stderr.log"])
        finally:
            os.close(master)
            os.close(slave)

    def test_t4_invalid_lines_recover_without_losing_buffered_answers(self):
        p = TerminalProcess(self, env={"PYTHONIOENCODING": "latin-1"})
        p.wait_for(self.QUESTIONS[0])
        p.send(b"\n3 \nx\n\xff\n 1 \n\n0\nx\n\xff\n 4 \n  \n\xff\n  my dir  \n")
        r = p.finish()
        self.assertOk(r)
        self.assertPrompts(r, [self.PROMPTS[0]] * 5 + [self.PROMPTS[1]] * 5 +
                           [self.PROMPTS[2]] * 3)
        self.assertEqual(r.stderr.count("Type 1 or 2.\n"), 3)
        self.assertEqual(r.stderr.count("Type 1, 2, 3 or 4.\n"), 3)
        self.assertEqual(r.stderr.count("Input must be valid UTF-8.\n"), 3)
        self.assertEqual(r.stderr.count("Enter a project directory.\n"), 1)
        self.assertTrue((self.tmp / "my dir/config/auto-wp.json").is_file())
        self.assertNotIn("Traceback", r.stderr)

    def test_t4_literal_directory_and_target_validation(self):
        answers = ("-", "~/$NOT_EXPANDED;echo nope", ".", str(self.tmp / "absolute"))
        for i, answer in enumerate(answers):
            with self.subTest(answer=answer):
                work = self.tmp / str(i)
                work.mkdir()
                p = TerminalProcess(self, "--c", "--harness", "none", cwd=work)
                p.wait_for(self.QUESTIONS[2])
                p.send((answer + "\n").encode())
                r = p.finish()
                self.assertOk(r)
                self.assertTrue((work / answer / "config/auto-wp.json").is_file())
        (self.tmp / "file").write_text("keep")
        before = snapshot(self.tmp)
        p = TerminalProcess(self, "--c", "--harness", "none")
        p.wait_for(self.QUESTIONS[2])
        p.send(b"file\n")
        r = p.finish()
        self.assertEqual(r.returncode, 1)
        self.assertIn("exists and is not a directory", r.stderr)
        self.assertPrompts(r, [self.PROMPTS[2]])
        self.assertEqual(snapshot(self.tmp), before)

    def test_t5_copilot_selection_asks_for_directory(self):
        p = TerminalProcess(self)
        p.wait_for(self.QUESTIONS[0])
        p.send(b"1\n3\n")
        p.wait_for(self.QUESTIONS[2])
        self.assertEqual(os.listdir(self.tmp), [])
        p.send(b"copilot-project\n")
        r = p.finish()
        self.assertOk(r)
        self.assertPrompts(r, list(self.PROMPTS))
        self.assertNotIn("not implemented yet", r.stderr)
        manifest = json.loads((self.tmp / "copilot-project/config/auto-wp.json").read_text())
        self.assertEqual(manifest["harness"], "copilot")

    def test_t6_prompt_eof_and_sigint(self):
        for cancel in ("eof", "sigint"):
            with self.subTest(cancel=cancel):
                p = TerminalProcess(self)
                p.wait_for(self.QUESTIONS[0])
                p.send(b"1\n")
                p.wait_for(self.QUESTIONS[1])
                self.assertEqual(os.listdir(self.tmp), [])
                if cancel == "eof":
                    p.send(p.veof)
                    code, message = 1, "auto-wp: error: input ended before all required choices were provided"
                else:
                    p.process.send_signal(signal.SIGINT)
                    code, message = 130, "auto-wp: cancelled"
                r = p.finish()
                self.assertEqual(r.returncode, code, r.stderr)
                self.assertIn(message, r.stderr)
                self.assertNotIn("Traceback", r.stderr)
                self.assertEqual(r.stdout, "")
                self.assertEqual(os.listdir(self.tmp), [])

    def test_t6_generation_interrupt_rolls_back(self):
        # Execute the real entry point, injecting SIGINT after a partial copy or
        # completed generation step. No scheduling race or model session needed.
        injection = """
import os, runpy, signal, sys
from unittest.mock import patch
from pathlib import Path
app = runpy.run_path(sys.argv[1])
Run = app['Run']
stage = sys.argv[2]
if stage == 'copy':
    original = app['shutil'].copy2
    def interrupt(src, dst, *args, **kwargs):
        if Path(dst).name == 'autowp.yaml':
            Path(dst).write_text('partial copy')
            os.kill(os.getpid(), signal.SIGINT)
        return original(src, dst, *args, **kwargs)
    owner, method = app['shutil'], 'copy2'
else:
    original = getattr(Run, stage)
    def interrupt(self):
        original(self)
        assert self.created
        os.kill(os.getpid(), signal.SIGINT)
    owner, method = Run, stage
with patch.object(owner, method, interrupt):
    sys.exit(app['main'](['--c', '--harness', 'none', sys.argv[3]]))
"""
        for stage in ("install_config", "copy", "init_git"):
            for existing in (False, True):
                with self.subTest(stage=stage, existing=existing):
                    work = self.tmp / f"{stage}-{existing}"
                    work.mkdir()
                    target = work / "parent/project"
                    if existing:
                        for directory in (".claude", ".opencode", ".workshop", "bin"):
                            (target / directory).mkdir(parents=True, exist_ok=True)
                            (target / directory / "keep").write_text("unchanged\n")
                        (target / "README.md").write_text("original readme\n")
                        subprocess.run(["git", "init", "-q", str(target)],
                                       check=True, timeout=15)
                    before = snapshot(work)
                    r = subprocess.run(
                        [sys.executable, "-c", injection, str(SCRIPT), stage, str(target)],
                        cwd=work, stdin=subprocess.DEVNULL, capture_output=True,
                        text=True, timeout=30)
                    self.assertEqual(r.returncode, 130, r.stderr)
                    self.assertEqual(r.stderr, "auto-wp: cancelled\n")
                    self.assertEqual(r.stdout, "")
                    self.assertEqual(snapshot(work), before)

    def test_t7_help_and_explicit_errors_before_prompts(self):
        cases = [
            (("--help",), None),
            (("--bogus",), "unrecognized arguments"),
            (("--c", "--rust"), "not allowed with argument"),
            (("a", "b"), "unrecognized arguments"),
            (("--harness", "typo"), "invalid choice"),
            (("--driver", "fips"), "--driver fips needs --level"),
            (("--level", "3"), "--level is only valid with --driver fips"),
            (("--driver", "typo"), "invalid choice"),
            (("--driver", "fips", "--level", "5"), "invalid choice"),
        ]
        for args, error in cases:
            with self.subTest(args=args):
                r = TerminalProcess(self, *args).finish()
                self.assertEqual(r.returncode, 0 if error is None else 2, r.stderr)
                self.assertPrompts(r, [])
                if error is not None:
                    self.assertIn("usage:", r.stderr)
                    self.assertIn(error, r.stderr)
                self.assertEqual(os.listdir(self.tmp), [])

    def test_t8_automated_generation_is_explicit(self):
        calls = []
        for path in sorted((REPO / "tests").rglob("*.sh")):
            for line in path.read_text().replace("\\\n", " ").splitlines():
                if line.lstrip().startswith("#"):
                    continue
                call = re.search(r"""\bpython3\s+[^\s]*auto-wp\.py["']?(.*)""", line)
                if call and "--help" not in call[1]:
                    calls.append((path, call[1]))
                forwarded = re.search(r"\bws_generate\s+(\S+)", line)
                if forwarded:
                    self.assertIn(forwarded[1], ("c", "rust"), f"{path}: {line}")
        doc = REPO / "spec/tests.md"
        doc_calls = re.findall(
            r"`[^`\n]*auto-wp\.py\s+([^`\n]+)`|^python3\s+\S*auto-wp\.py\s+(.+)$",
            doc.read_text(), re.M)
        self.assertTrue(calls)
        self.assertTrue(doc_calls)
        calls.extend((doc, inline or block) for inline, block in doc_calls)
        for path, args in calls:
            with self.subTest(path=path, args=args):
                if path == REPO / "tests/lib/workshop.sh":
                    self.assertIn('"--$lang"', args)
                else:
                    self.assertRegex(args, r"--(?:c|rust)\b")
                self.assertIn("--harness", args)


class TestHarnessSelection(AutoWpTestCase):
    def test_selected_harness_in_both_languages(self):
        for language in ("c", "rust"):
            for harness in ("claude", "opencode", "copilot", "none"):
                with self.subTest(language=language, harness=harness):
                    target = f"{language}-{harness}"
                    result = self.run_auto_wp("--" + language, "--harness", harness, target)
                    self.assertOk(result)
                    project = self.tmp / target
                    manifest = json.loads((project / "config/auto-wp.json").read_text())
                    self.assertEqual(manifest["harness"], harness)
                    readme = (project / "README.md").read_text()
                    self.assertNotIn("{{", readme)
                    hook = (project / ".workshop/autowp-packages/hooks/setup-base").read_text()
                    base = (TEMPLATES / language / "workshop/autowp-packages/hooks/setup-base").read_text()
                    for rel in (".agents", ".claude/skills", ".claude/commands",
                                ".opencode/skills", ".opencode/commands"):
                        self.assertTrue((project / rel).is_symlink())
                    if harness == "none":
                        self.assertEqual(hook, base)
                        self.assertIn("No agent harness is installed", readme)
                        self.assertIn("workshop shell", readme)
                        self.assertNotIn("https://claude.ai", readme)
                        self.assertNotIn("https://opencode.ai", readme)
                        self.assertNotIn("https://gh.io/copilot-install", readme)
                        self.assertNotIn("--dangerously-skip-permissions", readme)
                    else:
                        snippet = (TEMPLATES / "common/harness" / f"{harness}.sh").read_text()
                        self.assertEqual(hook, base + "\n" + snippet)
                        if harness == "copilot":
                            self.assertIn("PREFIX=/usr/local", hook)
                            self.assertIn("https://gh.io/copilot-install", readme)
                            self.assertIn("copilot login --device-code", readme)
                            self.assertIn("copilot --disable-builtin-mcps --sync-session=off", readme)
                            self.assertIn("**Copilot: manual use only.**", readme)
                            self.assertIn("No Copilot watchdog is installed", readme)
                            skill = "frama-c" if language == "c" else "creusot"
                            self.assertIn(f"Load the {skill} skill", readme)
                            self.assertNotIn("COPILOT_ALLOW_ALL", readme)
                        else:
                            self.assertIn(f"/usr/local/bin/{harness}", hook)
                        subprocess.run(["bash", "-n"], input=hook, text=True,
                                       check=True, timeout=15)
                        for other, url in (("claude", "claude.ai"),
                                           ("opencode", "opencode.ai"),
                                           ("copilot", "gh.io/copilot-install")):
                            if other != harness:
                                self.assertNotIn(url, readme)
                        self.assertIn(f"  harness:  {harness}", result.stdout)
                    self.assertFalse((project / ".github/hooks").exists())

    def test_rejected_harness_creates_nothing(self):
        for harness in ("openrouter", "typo"):
            with self.subTest(harness=harness):
                result = self.run_auto_wp("--harness", harness, "project")
                self.assertEqual(result.returncode, 2)
                self.assertFalse((self.tmp / "project").exists())

    def test_missing_installer_rolls_back(self):
        prog = self._copy_program()
        (prog / "templates/common/harness/opencode.sh").unlink()
        project = self.tmp / "existing"
        project.mkdir()
        (project / "keep").write_text("unchanged")
        before = snapshot(project)
        result = self.run_auto_wp("--c", "--harness", "opencode", str(project),
                                  script=prog / "auto-wp.py")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(snapshot(project), before)


class TestOutputAndConstraints(AutoWpTestCase):
    """auto-wp.md 2 and 3.6 (exact output), not numbered in 5."""

    def test_c_output_exact(self):
        r = self.run_auto_wp("--c", "--harness", "claude", "foobar")
        self.assertOk(r)
        self.assertEqual(r.stdout, (
            "created foobar/config (language: c)\n"
            "  driver:   rmf\n"
            "  harness:  claude\n"
            "  skills:   23\n"
            "  commands: 3\n"
            "copied  foobar/.gitignore\n"
            "copied  foobar/bin\n"
            "copied  foobar/frama-c-patches\n"
            "copied  foobar/framac-gold\n"
            "copied  foobar/no-ceiling.md\n"
            "copied  foobar/.workshop (workshop: autowp)\n"
            "linked  foobar/.agents            -> config\n"
            "linked  foobar/.claude/skills     -> ../config/skills\n"
            "linked  foobar/.claude/commands   -> ../config/commands\n"
            "linked  foobar/.opencode/skills   -> ../config/skills\n"
            "linked  foobar/.opencode/commands -> ../config/commands\n"
            "wrote   foobar/README.md\n"
            "git     initialized foobar\n"
            # The file count is the only part that is not fixed, so the exact
            # comparison stops here and the last line is matched by shape.
            + r.stdout.splitlines(keepends=True)[-1]))
        self.assertRegex(r.stdout.splitlines()[-1],
                         r"^git     committed foobar \(\d+ files\) on main$")

    def test_rust_output_counts(self):
        r = self.run_auto_wp("--rust", "--harness", "claude", "foobar")
        self.assertOk(r)
        lines = r.stdout.splitlines()
        self.assertEqual(lines[0], "created foobar/config (language: rust)")
        self.assertEqual(lines[1], "  driver:   rmf")
        self.assertEqual(lines[2], "  harness:  claude")
        self.assertEqual(lines[3], f"  skills:   {len(RUST_SKILLS)}")
        self.assertEqual(lines[4], f"  commands: {len(RUST_COMMANDS)}")
        self.assertEqual(lines[5:8], ["copied  foobar/.gitignore",
                                      "copied  foobar/bin",
                                      "copied  foobar/.workshop (workshop: autowp)"])

    def test_rust_output_spec_count_19(self):
        if RUST_ABSENT_PENDING:
            self.skipTest(pending_note(RUST_ABSENT_PENDING) +
                          f"; prints 'skills:   {len(RUST_SKILLS)}', spec says 19")
        r = self.run_auto_wp("--rust", "--harness", "claude", "foobar")
        self.assertIn("  skills:   19", r.stdout.splitlines())

    def test_script_header_and_mode(self):
        self.assertTrue(SCRIPT.read_text().startswith("#!/usr/bin/env python3\n"))
        # The mode that ships is the index's (spec §5: 0755). The working
        # tree may carry extra group-write bits from the checkout's umask
        # (a group-shared clone with umask 002 yields 0775), so compare the
        # index entry and require the exec bit locally.
        index = subprocess.run(
            ["git", "-C", str(REPO), "ls-files", "-s", "--", "auto-wp.py"],
            capture_output=True, text=True, check=True, timeout=15).stdout.split()
        self.assertEqual(index[0], "100755")
        self.assertTrue(os.access(SCRIPT, os.X_OK))

    def test_stdlib_only(self):
        allowed = {"argparse", "pathlib", "shutil", "json", "datetime", "subprocess",
                   "os", "sys", "stat", "re"}
        mods = set()
        for line in SCRIPT.read_text().splitlines():
            m = re.match(r"\s*(?:from\s+(\w+)|import\s+([\w, ]+))", line)
            if m:
                if m.group(1):
                    mods.add(m.group(1))
                else:
                    mods.update(x.strip().split(".")[0] for x in m.group(2).split(","))
        self.assertLessEqual(mods - allowed, set(), "non-stdlib or unexpected imports")
        text = SCRIPT.read_text()
        self.assertNotIn("../use-frama-c", text)
        self.assertNotIn("../use-creusot", text)


class TestFipsDriver(AutoWpTestCase):
    """fips-skill-spec.md 2, 3, 6 and 7.3: the --driver/--level options."""

    FIPS_COMMANDS = ["ebios", "fips", "time-loop"]

    def test_fips_generation(self):
        r = self.run_auto_wp("--c", "--harness", "claude", "--driver", "fips", "--level", "3", "foobar")
        self.assertOk(r)
        self.assertIn("  driver:   fips (FIPS 140-3 level 3)", r.stdout.splitlines())
        d = self.tmp / "foobar"
        m = json.loads((d / "config/auto-wp.json").read_text())
        self.assertEqual(m["driver"], "fips")
        self.assertEqual(m["fips_level"], 3)
        self.assertEqual(m["commands"], self.FIPS_COMMANDS)
        self.assertEqual(command_names(d), self.FIPS_COMMANDS)
        # Only the driver's command: fips.md in, rmf.md out (spec 6, option B).
        self.assertTrue((d / "config/commands/fips.md").is_file())
        self.assertFalse(os.path.lexists(d / "config/commands/rmf.md"))
        # Everything else is installed whatever the driver: both skills, both
        # linters, the same links and the workshop definition; the fips driver
        # adds the corpus, specs/.
        self.assertIn("fips-sl", m["skills"])
        self.assertIn("rmf-sl", m["skills"])
        self.assertTrue((d / "bin/fips-lint.sh").is_file())
        self.assertTrue((d / "bin/rmf-lint.sh").is_file())
        self.assertTrue((d / "specs/MANIFEST.tsv").is_file())
        self.assertTrue((d / ".workshop/autowp.yaml").is_file())
        self.assertTrue((d / ".opencode/skills").is_symlink())

    def test_default_generation_has_rmf_only(self):
        r = self.run_auto_wp("--c", "--harness", "claude", "foobar")
        self.assertOk(r)
        d = self.tmp / "foobar"
        self.assertTrue((d / "config/commands/rmf.md").is_file())
        self.assertFalse(os.path.lexists(d / "config/commands/fips.md"))

    def test_fips_readme(self):
        self.run_auto_wp("--c", "--harness", "claude", "--driver", "fips", "--level", "2", "foobar")
        text = (self.tmp / "foobar/README.md").read_text()
        self.assertIn("Requirement study: FIPS 140-3, security level 2 (fips-sl).", text)
        self.assertIn("/fips <dir> <dir>-analysis", text)
        self.assertIn("bin/fips-lint.sh grub-analysis-fips-report.md", text)
        self.assertIn("--dir=grub-core/lib/libgcrypt", text)
        self.assertNotIn("{{", text)
        self.assertNotIn("/rmf <dir>", text)
        # The default driver's README keeps its line and has no fips note.
        self.run_auto_wp("--c", "--harness", "claude", "rmfbar")
        text = (self.tmp / "rmfbar/README.md").read_text()
        self.assertIn("Risk study: NIST RMF (rmf-sl).", text)
        self.assertNotIn("libgcrypt", text)
        self.assertNotIn("{{", text)

    def test_fips_rust(self):
        r = self.run_auto_wp("--harness", "claude", "--driver", "fips", "--level", "4", "--rust", "foobar")
        self.assertOk(r)
        d = self.tmp / "foobar"
        m = json.loads((d / "config/auto-wp.json").read_text())
        self.assertEqual(m["driver"], "fips")
        self.assertEqual(m["fips_level"], 4)
        self.assertEqual(m["commands"], RUST_COMMANDS)  # time-loop only: no /rmf or /fips for Rust yet
        self.assertTrue((d / "specs/MANIFEST.tsv").is_file())
        text = (d / "README.md").read_text()
        self.assertIn("Requirement study: FIPS 140-3, security level 4 (fips-sl).", text)
        self.assertNotIn("{{", text)

    def test_fips_specs(self):
        """--driver fips copies specs/ and warns about documents not imported."""
        prog = self._copy_program()
        manifest = (prog / "specs/MANIFEST.tsv").read_text()
        ids = [l.split("\t", 1)[0] for l in manifest.splitlines() if l and not l.startswith("#")][1:]
        (prog / "specs/pdf").mkdir()
        (prog / "specs/pdf/FIPS140-3.pdf").write_bytes(b"%PDF stub")
        (prog / "specs/notes~").write_text("editor backup")
        r = self.run_auto_wp("--c", "--harness", "claude", "--driver", "fips", "--level", "1",
                             "foobar", script=prog / "auto-wp.py")
        self.assertOk(r)
        self.assertIn(f"copied  foobar/specs (corpus: 1 of {len(ids)} documents)", r.stdout.splitlines())
        self.assertIn(f"{len(ids) - 1} of {len(ids)} FIPS corpus documents", r.stderr)
        d = self.tmp / "foobar/specs"
        self.assertEqual((d / "MANIFEST.tsv").read_text(), manifest)
        self.assertTrue((d / "pdf/FIPS140-3.pdf").is_file())
        self.assertFalse(os.path.lexists(d / "notes~"))
        self.assertIn("FIPS140-3", ids)
        self.assertIn("IG", ids)

    def test_fips_specs_missing_manifest(self):
        prog = self._copy_program()
        (prog / "specs/MANIFEST.tsv").unlink()
        r = self.run_auto_wp("--c", "--harness", "claude", "--driver", "fips", "--level", "1",
                             "foobar", script=prog / "auto-wp.py")
        self.assertEqual(r.returncode, 1)
        self.assertIn("MANIFEST.tsv", r.stderr)
        self.assertFalse(os.path.lexists(self.tmp / "foobar"))

    def test_fips_rollback(self):
        if os.geteuid() == 0:
            self.skipTest("running as root: an unreadable file is still readable")
        prog = self._copy_program()
        victim = prog / "templates/c/skills/time-loop/SKILL.md"
        victim.chmod(0)
        work = self.tmp / "work"
        work.mkdir()
        r = self.run_auto_wp("--c", "--harness", "claude", "--driver", "fips", "--level", "2", "foo",
                             cwd=work, script=prog / "auto-wp.py")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertEqual(r.stdout, "")
        self.assertFalse(os.path.lexists(work / "foo"))
        self.assertEqual(os.listdir(work), [])


class TestCampaignTools(AutoWpTestCase):
    """The common-layer campaign tools: bin/ledger, bin/check-delivery,
    bin/heavy and bin/time-loop-watchdog.py (auto-wp.md 4.1).

    They live in the common layer, so both languages install them; `ledger`
    and `check-delivery` discover the campaign directory instead of naming
    one, which is what lets a single copy serve `XXX-analysis-acsl/` (C) and
    `XXX-creusot/` (Rust).
    """

    NEW_TOOLS = ("ledger", "check-delivery")

    def generate(self, language="c", name=None):
        name = name or f"tools-{language}"
        self.assertOk(self.run_auto_wp("--" + language, "--harness", "claude", name))
        return self.tmp / name

    def assertCompiles(self, path):
        """Byte-compile a shipped tool; a cfile in the sandbox, never /dev/null."""
        out = self.tmp / (Path(path).name + ".pyc")
        subprocess.run(
            [sys.executable, "-c",
             "import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2],"
             " doraise=True)", str(path), str(out)],
            check=True, timeout=60, capture_output=True)

    def tool(self, project, name, *args, cwd=None):
        return subprocess.run([sys.executable, str(project / "bin" / name), *args],
                              cwd=str(cwd or project), capture_output=True,
                              text=True, timeout=60)

    def ledger_rows(self, campaign, notes_len=500):
        """A campaign directory with the pinned six-column ledger (4.2.2 5)."""
        campaign.mkdir(parents=True, exist_ok=True)
        rows = ["unit\tSA#\tfunction\tverdict\tgoals\tnotes",
                "zlib/adler32.c\tSA1\tadler32\tVERIFIED\t131/136\t" + "x" * notes_len,
                "dtrace/x.c\t-\tfoo\tRESIDUE(A)\t3/9\tout-of-reach: casts",
                "zlib/inflate.c\tSA3\tinflate\tPARSE-BLOCKED\t\tc23 attribute"]
        (campaign / "verdicts.tsv").write_text("\n".join(rows) + "\n")

    def test_tools_installed_in_both_languages(self):
        """Both languages get both tools, as real files, mode 0755."""
        for language in ("c", "rust"):
            with self.subTest(language=language):
                project = self.generate(language)
                for name in self.NEW_TOOLS:
                    tool = project / "bin" / name
                    self.assertTrue(tool.is_file() and not tool.is_symlink(), name)
                    self.assertTrue(os.access(tool, os.X_OK), f"{name} not executable")
                    self.assertEqual(stat.S_IMODE(tool.stat().st_mode), 0o755, name)
                    src = TEMPLATES / "common/tools/bin" / name
                    self.assertEqual(tool.read_bytes(), src.read_bytes(), name)
                    # Read-only by construction: no open() for writing.
                    self.assertEqual(
                        re.findall(r'open\([^)]*"[wax][b+t]*"', tool.read_text()), [],
                        f"{name} opens a file for writing")

    def test_ledger_finds_the_campaign_in_both_layouts(self):
        """The ledger path is discovered, so one tool serves both layers."""
        for language, campaign in (("c", "xnu-analysis-acsl"), ("rust", "sudo-rs-creusot")):
            with self.subTest(language=language):
                project = self.generate(language)
                self.ledger_rows(project / campaign)
                r = self.tool(project, "ledger")
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertIn("adler32", r.stdout)
                self.assertIn("3 ledger rows; 3 matched; 3 shown", r.stdout)

    def test_ledger_filters_clips_caps_and_says_what_it_omitted(self):
        project = self.generate("c")
        self.ledger_rows(project / "xnu-analysis-acsl")
        # Selection by status, with the columns asked for.
        r = self.tool(project, "ledger", "-s", "RESIDUE", "-c", "unit,verdict")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("dtrace/x.c\tRESIDUE(A)", r.stdout)
        self.assertNotIn("adler32", r.stdout)
        # Clipping: the 500-character notes field does not reach the context.
        r = self.tool(project, "ledger", "-u", "adler32", "-c", "notes", "-w", "40")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("x" * 60, r.stdout)
        self.assertIn("1 fields clipped at 40 chars", r.stdout)
        # Row cap, and a count of what it dropped.
        r = self.tool(project, "ledger", "-n", "1")
        self.assertIn("2 rows omitted by -n 1", r.stdout)
        # --count prints the number only.
        r = self.tool(project, "ledger", "--count", "-s", "VERIFIED")
        self.assertIn("1 matching rows of 3", r.stdout)
        # No ledger, and none in the project either: exit 2, say where it looked.
        bare = self.tmp / "bare"
        bare.mkdir()
        r = subprocess.run([sys.executable, str(project / "bin/ledger")], cwd=str(bare),
                           capture_output=True, text=True, timeout=60,
                           env=dict(os.environ, AUTOWP_PROJECT_DIR=str(bare)))
        self.assertEqual(r.returncode, 2)
        self.assertIn("no campaign ledger found", r.stderr)
        self.assertIn("--file", r.stderr)

    def test_ledger_never_writes_the_ledger(self):
        project = self.generate("c")
        campaign = project / "xnu-analysis-acsl"
        self.ledger_rows(campaign)
        before = (campaign / "verdicts.tsv").read_bytes()
        os.chmod(campaign / "verdicts.tsv", 0o444)
        self.assertEqual(self.tool(project, "ledger", "-c", "all").returncode, 0)
        self.assertEqual((campaign / "verdicts.tsv").read_bytes(), before)

    def test_check_delivery_gates_a_claimed_delivery(self):
        if shutil.which("git") is None:
            self.skipTest("git not installed")
        project = self.generate("c")
        campaign = project / "xnu-analysis-acsl"
        self.ledger_rows(campaign)
        unit = campaign / "units/zlib-r16"
        (unit / "logs").mkdir(parents=True)
        # 1. Nothing delivered: NOT-DELIVERED, exit 1, all three named.
        r = self.tool(project, "check-delivery", "194")
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("c194 NOT-DELIVERED", r.stdout)
        self.assertIn("FAILED: report,logs,commit", r.stdout)
        self.assertEqual(len(r.stdout.strip().splitlines()), 1, "one line of output")
        # 2. A stub report is not a report (the 500-byte floor).
        (unit / "REPORT.md").write_text("# c194 - VERIFIER report: zlib\n")
        r = self.tool(project, "check-delivery", "194")
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("STUB", r.stdout)
        # 3. Real report, empty log: still NOT-DELIVERED.
        (unit / "REPORT.md").write_text("# c194 - VERIFIER report: zlib\n" + "body " * 200)
        (unit / "logs/wp.log").write_text("")
        r = self.tool(project, "check-delivery", "194")
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("log files are EMPTY", r.stdout)
        # 4. Report, log and commit: DELIVERED, exit 0.
        (unit / "logs/wp.log").write_text("Valid 131/136\n")
        git = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.com",
                   GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com")
        for cmd in (["add", "-A"], ["commit", "-qm", "c194: zlib adler32 VERIFIED"]):
            subprocess.run(["git", "-C", str(project), *cmd], check=True, timeout=60,
                           env=git, capture_output=True)
        r = self.tool(project, "check-delivery", "194", "-v")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("c194 DELIVERED", r.stdout)
        self.assertIn("units/zlib-r16/REPORT.md", r.stdout)
        # The cycle id is accepted in the forms the skill uses.
        for spelling in ("c194", "194", "cycle194"):
            self.assertEqual(self.tool(project, "check-delivery", spelling).returncode,
                             0, spelling)
        self.assertEqual(self.tool(project, "check-delivery", "nonsense").returncode, 2)

    def test_check_delivery_finds_a_rust_campaign(self):
        """No `units/` under Rust, so reports are looked for in the campaign itself."""
        project = self.generate("rust")
        campaign = project / "sudo-rs-creusot"
        self.ledger_rows(campaign)
        r = self.tool(project, "check-delivery", "12")
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("c12 NOT-DELIVERED", r.stdout)
        self.assertIn("*/REPORT.md", r.stdout)
        # No campaign at all is an environment error, not a verdict.
        bare = self.tmp / "nocampaign"
        bare.mkdir()
        r = subprocess.run([sys.executable, str(project / "bin/check-delivery"), "12"],
                           cwd=str(bare), capture_output=True, text=True, timeout=60,
                           env=dict(os.environ, AUTOWP_PROJECT_DIR=str(bare)))
        self.assertEqual(r.returncode, 2, r.stdout)
        self.assertIn("UNKNOWN", r.stdout)

    def test_new_tools_are_stdlib_only(self):
        """Like auto-wp.py itself (2): no third-party import in a shipped tool."""
        allowed = {"argparse", "glob", "os", "re", "subprocess", "sys"}
        for name in self.NEW_TOOLS:
            with self.subTest(tool=name):
                text = (TEMPLATES / "common/tools/bin" / name).read_text()
                self.assertTrue(text.startswith("#!/usr/bin/env python3\n"), name)
                found = set(re.findall(r"^(?:import|from)\s+([A-Za-z_][\w.]*)",
                                       text, re.MULTILINE))
                self.assertLessEqual(found, allowed, f"{name} imports {found - allowed}")
                self.assertCompiles(TEMPLATES / "common/tools/bin" / name)

    def test_watchdog_fails_loudly(self):
        """The heartbeat stops re-firing on a broken run (ideas item 7)."""
        project = self.generate("c")
        watchdog = project / "bin/time-loop-watchdog.py"
        self.assertCompiles(watchdog)
        r = subprocess.run([sys.executable, str(watchdog), "--help"], cwd=str(project),
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        for flag in ("--min-runtime", "--expect-model", "--no-fail-fast"):
            self.assertIn(flag, r.stdout, flag)
        text = watchdog.read_text()
        # The alert file is what makes the failure outlive the run.
        self.assertIn(".time-loop-watchdog.alert", text)
        # A benign tool failure must not halt the campaign: the `✗ <tool>
        # failed` marker is what tells the two apart.
        self.assertIn("TOOL_FAILURE", text)
        r = subprocess.run([sys.executable, str(watchdog), "status"], cwd=str(project),
                           capture_output=True, text=True, timeout=60)
        self.assertIn("watchdog stopped", r.stdout)
        self.assertNotIn("ALERT PENDING", r.stdout)
        (project / ".time-loop-watchdog.alert").write_text("boom\n")
        r = subprocess.run([sys.executable, str(watchdog), "status"], cwd=str(project),
                           capture_output=True, text=True, timeout=60)
        self.assertIn("ALERT PENDING", r.stdout)
        # Defaults, as the skills document them.
        r = subprocess.run([sys.executable, str(watchdog), "start", "nope", "1", "p",
                            "--min-runtime", "-1"], cwd=str(project),
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 2)
        self.assertIn("min-runtime must be nonnegative", r.stderr)

    def test_heavy_sizes_its_slots_to_the_cores(self):
        """R6's slot pool is cores / -wp-par, not a flat 4 (ideas item 3)."""
        project = self.generate("c")
        heavy = project / "bin/heavy"
        subprocess.run(["bash", "-n", str(heavy)], check=True, timeout=30,
                       capture_output=True)
        text = heavy.read_text()
        self.assertIn("SLOTS=${HEAVY_SLOTS:-$DEFAULT_SLOTS}", text)
        self.assertNotIn("SLOTS=${HEAVY_SLOTS:-4}", text)
        # The computation itself, run in isolation: 6 cores / -wp-par 2 = 3,
        # and never 0 on a single-core machine.
        block = "\n".join(text.splitlines()[text.splitlines().index("set -u"):])
        block = block.split("MEM_KB=", 1)[0]
        for cores, par, expected in (("6", "2", "3"), ("1", "2", "1"), ("12", "4", "3")):
            with self.subTest(cores=cores, par=par):
                r = subprocess.run(
                    ["bash", "-c", f'nproc() {{ echo {cores}; }}\n{block}\necho "$SLOTS"'],
                    capture_output=True, text=True, timeout=30,
                    env=dict(os.environ, HEAVY_WP_PAR=par))
                self.assertEqual(r.stdout.strip(), expected, r.stderr)
        # An explicit HEAVY_SLOTS still wins.
        r = subprocess.run(["bash", "-c", f'{block}\necho "$SLOTS"'],
                           capture_output=True, text=True, timeout=30,
                           env=dict(os.environ, HEAVY_SLOTS="7"))
        self.assertEqual(r.stdout.strip(), "7", r.stderr)

    def test_time_loop_skills_point_at_the_new_tools(self):
        """Both layers' time-loop skills carry the CONTEXT HYGIENE block (4.2.2)."""
        for language, ledger in (("c", "XXX-analysis-acsl/verdicts.tsv"),
                                 ("rust", "XXX-creusot/verdicts.tsv")):
            with self.subTest(language=language):
                text = (TEMPLATES / language / "skills/time-loop/SKILL.md").read_text()
                self.assertIn("CONTEXT HYGIENE", text)
                self.assertIn("bin/ledger", text)
                self.assertIn("bin/check-delivery", text)
                self.assertIn(ledger, text)
                # The spill path the model guessed wrong three times.
                self.assertIn("/home/workshop/.local/share/opencode/tool-output/", text)
                self.assertIn("300 lines / 12 KiB", text)
                # The fail-loud flags, so a campaign on another model knows.
                self.assertIn("--expect-model", text)
                self.assertNotIn("`HEAVY_SLOTS`, default 4", text)
        # time-loop is a language-layer skill in both layers, not a common one,
        # so there is no third copy to keep in step.
        self.assertFalse((TEMPLATES / "common/skills/time-loop").exists())


class TestLocalInference(AutoWpTestCase):
    """--local-inference / --no-local-inference under --harness opencode."""

    HOOK = ".workshop/autowp-packages/hooks/setup-base"
    SNIPPET = TEMPLATES / "common/harness/opencode-local-inference.sh"

    def hook(self, project):
        return (project / self.HOOK).read_text()

    def baseline(self, language):
        """The hook as --no-local-inference leaves it: base + opencode.sh."""
        base = (TEMPLATES / language
                / "workshop/autowp-packages/hooks/setup-base").read_text()
        return base + "\n" + (TEMPLATES / "common/harness/opencode.sh").read_text()

    def test_off_is_byte_identical_to_previous_behavior(self):
        """--no-local-inference, and the flagless default, change nothing."""
        for language in ("c", "rust"):
            for args, name in ((("--no-local-inference",), "off"), ((), "default")):
                with self.subTest(language=language, name=name):
                    target = f"{language}-{name}"
                    self.assertOk(self.run_auto_wp(
                        "--" + language, "--harness", "opencode", *args, target))
                    project = self.tmp / target
                    self.assertEqual(self.hook(project), self.baseline(language))
                    manifest = json.loads((project / "config/auto-wp.json").read_text())
                    self.assertIs(manifest["local_inference"], False)

    PROJECT_HOOK = ".workshop/autowp-packages/hooks/setup-project"

    def test_on_puts_the_snippet_in_setup_project_not_setup_base(self):
        """Workshop mounts the project *after* setup-base and before setup-project.

        The snippet reads the address file from the mount and writes into the
        workshop user's home, so it only works in the later hook. In
        `setup-base` it ran before the mount and skipped every first launch --
        observed twice on a real project before this moved.
        """
        for language in ("c", "rust"):
            with self.subTest(language=language):
                target = f"{language}-on"
                r = self.run_auto_wp("--" + language, "--harness", "opencode",
                                     "--local-inference", target)
                self.assertOk(r)
                self.assertIn("harness:  opencode (local inference)", r.stdout)
                project = self.tmp / target
                # setup-base: the installer only, exactly as without the flag.
                self.assertEqual(self.hook(project), self.baseline(language))
                self.assertNotIn("AUTOWP_INFERENCE_HOST", self.hook(project))
                # setup-project: the template's byobu hook plus the snippet.
                proj_hook = (project / self.PROJECT_HOOK).read_text()
                template = (TEMPLATES / language
                            / "workshop/autowp-packages/hooks/setup-project").read_text()
                self.assertEqual(proj_hook,
                                 template + "\n" + self.SNIPPET.read_text())
                for text in (self.hook(project), proj_hook):
                    subprocess.run(["bash", "-n"], input=text, text=True,
                                   check=True, timeout=15)
                manifest = json.loads((project / "config/auto-wp.json").read_text())
                self.assertIs(manifest["local_inference"], True)

    def test_no_byobu_still_gets_the_snippet(self):
        """--no-byobu removes setup-project, so it has to be recreated for it."""
        for language in ("c", "rust"):
            with self.subTest(language=language):
                target = f"{language}-nobyobu"
                self.assertOk(self.run_auto_wp(
                    "--" + language, "--harness", "opencode", "--local-inference",
                    "--no-byobu", target))
                hook = self.tmp / target / self.PROJECT_HOOK
                text = hook.read_text()
                self.assertIn("AUTOWP_INFERENCE_HOST", text)
                # The byobu *configuration* is gone. Not the word: the header
                # that replaces it explains which option removed it.
                for marker in ("byobu-enable", "BYOBU_BACKEND",
                               "#byobu-autoattach#", "configure()"):
                    self.assertNotIn(marker, text, f"{marker} survived --no-byobu")
                self.assertEqual(stat.S_IMODE(hook.stat().st_mode), 0o644)
                subprocess.run(["bash", "-n"], input=text, text=True,
                               check=True, timeout=15)
                # And byobu is still out of setup-base's apt line.
                self.assertNotIn("byobu", self.hook(self.tmp / target))

    def run_snippet(self, **env):
        """Run the generated hook's snippet against a throw-away home.

        getent does not know the test user, so the snippet falls back to
        /home/$user; redirect that to the temporary tree.
        """
        script = self.SNIPPET.read_text().replace("/home/$user", str(self.tmp / "home/$user"))
        # The model check is a network request, and most of these tests pin
        # address resolution or config content. Off unless a test asks for
        # it, so the suite does not pay a connect timeout per run.
        env.setdefault("AUTOWP_INFERENCE_CHECK", "0")
        return subprocess.run(["bash", "-s"], input=script, text=True,
                              capture_output=True, timeout=60,
                              env=dict(os.environ, AUTOWP_INFERENCE_USER="tester", **env))

    def test_snippet_reads_the_local_llm_ip_file(self):
        """The host comes from ~/.local-llm-machine-ip.txt, not from a default."""
        home = self.tmp / "home/tester"
        home.mkdir(parents=True)
        # One line, the address only; surrounding whitespace is ignored.
        (home / ".local-llm-machine-ip.txt").write_text("  198.51.100.7  \n")
        r = self.run_snippet()
        self.assertEqual(r.returncode, 0, r.stderr)
        cfg = json.loads((home / ".config/opencode/opencode.json").read_text())
        self.assertEqual(cfg["providers"]["ollama"]["settings"]["baseURL"],
                         "http://198.51.100.7:11434/v1")
        self.assertEqual(cfg["providers"]["ollama-sub"]["settings"]["baseURL"],
                         "http://198.51.100.7:11435/v1")
        self.assertIn(".local-llm-machine-ip.txt", r.stdout)

    def test_snippet_reads_the_project_copy_when_home_has_none(self):
        """The first-launch case: only the mounted project dir can have the file.

        The hook runs at launch and refresh, and the container's home does not
        exist before the first launch, so a home-only file can never be found
        on that first run. The project directory is mounted, so it can.
        """
        home = self.tmp / "home/tester"
        home.mkdir(parents=True)
        project = self.tmp / "mounted-project"
        project.mkdir()
        (project / ".local-llm-machine-ip.txt").write_text("203.0.113.9\n")
        r = self.run_snippet(AUTOWP_PROJECT_DIR=str(project))
        self.assertEqual(r.returncode, 0, r.stderr)
        cfg = json.loads((home / ".config/opencode/opencode.json").read_text())
        for pid, port in (("ollama", 11434), ("ollama-sub", 11435)):
            self.assertEqual(cfg["providers"][pid]["settings"]["baseURL"],
                             f"http://203.0.113.9:{port}/v1")
        # The shipped gates read ~/.local-llm-machine-ip.txt, so the home copy
        # must be seeded or the cross-provider judge still has no address.
        self.assertEqual((home / ".local-llm-machine-ip.txt").read_text().strip(),
                         "203.0.113.9")
        self.assertIn("seeded", r.stdout)

    def test_snippet_prefers_the_home_copy_over_the_project_copy(self):
        home = self.tmp / "home/tester"
        home.mkdir(parents=True)
        (home / ".local-llm-machine-ip.txt").write_text("198.51.100.7\n")
        project = self.tmp / "mounted-project"
        project.mkdir()
        (project / ".local-llm-machine-ip.txt").write_text("203.0.113.9\n")
        r = self.run_snippet(AUTOWP_PROJECT_DIR=str(project))
        self.assertEqual(r.returncode, 0, r.stderr)
        cfg = json.loads((home / ".config/opencode/opencode.json").read_text())
        self.assertEqual(cfg["providers"]["ollama"]["settings"]["baseURL"],
                         "http://198.51.100.7:11434/v1")

    def test_generation_seeds_the_ip_file_from_this_machine(self):
        """--local-inference copies the generating machine's file into the project."""
        fake_home = self.tmp / "fakehome"
        fake_home.mkdir()
        (fake_home / ".local-llm-machine-ip.txt").write_text("  203.0.113.9  \nignored\n")
        r = self.run_auto_wp("--c", "--harness", "opencode", "--local-inference",
                             "seeded", env={"HOME": str(fake_home)})
        self.assertOk(r)
        ip = self.tmp / "seeded/.local-llm-machine-ip.txt"
        # Stripped to the address alone, first line only.
        self.assertEqual(ip.read_text(), "203.0.113.9\n")
        self.assertIn("copied  seeded/.local-llm-machine-ip.txt", r.stdout)

    def test_generation_warns_when_this_machine_has_no_ip_file(self):
        fake_home = self.tmp / "emptyhome"
        fake_home.mkdir()
        r = self.run_auto_wp("--c", "--harness", "opencode", "--local-inference",
                             "unseeded", env={"HOME": str(fake_home)})
        self.assertOk(r)
        self.assertFalse((self.tmp / "unseeded/.local-llm-machine-ip.txt").exists())
        self.assertIn(".local-llm-machine-ip.txt", r.stderr)
        self.assertIn("before `workshop launch`", r.stderr)

    def test_generation_seeds_nothing_without_local_inference(self):
        fake_home = self.tmp / "home2"
        fake_home.mkdir()
        (fake_home / ".local-llm-machine-ip.txt").write_text("203.0.113.9\n")
        for args, name in ((("--no-local-inference",), "off"), ((), "plain")):
            with self.subTest(name=name):
                r = self.run_auto_wp("--c", "--harness", "opencode", *args, name,
                                     env={"HOME": str(fake_home)})
                self.assertOk(r)
                self.assertFalse((self.tmp / name / ".local-llm-machine-ip.txt").exists())

    def test_snippet_writes_nothing_without_the_ip_file(self):
        """No file and no override: explain, write nothing, never guess."""
        for name, prepare in (("missing", lambda h: None),
                              ("empty", lambda h: (h / ".local-llm-machine-ip.txt")
                               .write_text("\n"))):
            with self.subTest(case=name):
                home = self.tmp / "home/tester"
                shutil.rmtree(home, ignore_errors=True)
                home.mkdir(parents=True)
                prepare(home)
                r = self.run_snippet()
                # Provisioning must still succeed: the file lives in a home
                # that does not exist before this hook runs.
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertFalse((home / ".config/opencode/opencode.json").exists())
                self.assertIn(".local-llm-machine-ip.txt", r.stderr)
                self.assertIn("was NOT written", r.stderr)

    def test_no_hardcoded_address_anywhere(self):
        """Neither the snippet nor the generated README may carry an address."""
        octet = r"(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)"
        # 192.0.2.0/24 is the RFC 5737 documentation range, allowed as an
        # example; any other literal IPv4 address is not.
        real_ip = re.compile(rf"(?<![\d.])(?!192\.0\.2\.)(?!0\.0\.0\.0)(?!127\.0\.0\.1)"
                             rf"{octet}\.{octet}\.{octet}\.{octet}(?![\d.])")
        self.assertOk(self.run_auto_wp("--c", "--harness", "opencode",
                                       "--local-inference", "scan"))
        for label, text in (("snippet", self.SNIPPET.read_text()),
                            ("README", (self.tmp / "scan/README.md").read_text())):
            with self.subTest(file=label):
                self.assertEqual(real_ip.findall(text), [], f"literal address in {label}")

    def test_snippet_writes_valid_json_and_honours_the_environment(self):
        home = self.tmp / "home/tester"
        home.mkdir(parents=True)
        r = self.run_snippet(AUTOWP_INFERENCE_HOST="10.1.2.3",
                             AUTOWP_INFERENCE_PORT="9100",
                             AUTOWP_INFERENCE_SUBAGENT_PORT="9101",
                             AUTOWP_INFERENCE_MODEL="some-model:7b")
        self.assertEqual(r.returncode, 0, r.stderr)
        conf = home / ".config/opencode/opencode.json"
        cfg = json.loads(conf.read_text())
        self.assertEqual(cfg["$schema"], "https://opencode.ai/config.json")
        # Discovery would otherwise replace settings and drop the timeouts.
        self.assertIn("-opencode.provider.ollama", cfg["plugins"])
        self.assertEqual(cfg["providers"]["ollama"]["settings"]["baseURL"],
                         "http://10.1.2.3:9100/v1")
        self.assertEqual(cfg["providers"]["ollama-sub"]["settings"]["baseURL"],
                         "http://10.1.2.3:9101/v1")
        for provider in cfg["providers"].values():
            settings = provider["settings"]
            self.assertEqual(settings["headerTimeout"], 3600000)
            self.assertIs(settings["chunkTimeout"], False)
            self.assertIs(settings["timeout"], False)
            self.assertIn("some-model:7b", provider["models"])
        # Subagents run on the second server, so they cannot evict the
        # parent session's prompt cache.
        for agent in ("general", "explore"):
            self.assertEqual(cfg["agents"][agent]["model"],
                             "ollama-sub/some-model:7b")
        self.assertEqual(cfg["model"], "ollama/some-model:7b")
        self.assertEqual(cfg["compaction"]["buffer"], "50%")

    def written_config(self, **env):
        """Run the snippet against a throw-away home; return the JSON it wrote."""
        home = self.tmp / "home/tester"
        shutil.rmtree(home, ignore_errors=True)
        home.mkdir(parents=True)
        r = self.run_snippet(AUTOWP_INFERENCE_HOST="192.0.2.10", **env)
        self.assertEqual(r.returncode, 0, r.stderr)
        conf = home / ".config/opencode/opencode.json"
        # Valid JSON whatever the combination of optional keys.
        return json.loads(conf.read_text())

    def test_snippet_declares_the_context_limit_on_every_model(self):
        """Undeclared, OpenCode assumes 262 144 and compacts at about 131k."""
        cfg = self.written_config()
        for provider in cfg["providers"].values():
            for name, entry in provider["models"].items():
                with self.subTest(model=name):
                    self.assertEqual(entry["limit"],
                                     {"context": 120000, "output": 16000})
        cfg = self.written_config(AUTOWP_INFERENCE_CONTEXT="65536",
                                  AUTOWP_INFERENCE_OUTPUT="8000")
        for provider in cfg["providers"].values():
            for name, entry in provider["models"].items():
                with self.subTest(model=name, override=True):
                    self.assertEqual(entry["limit"],
                                     {"context": 65536, "output": 8000})

    def test_snippet_writes_the_measured_budget_defaults(self):
        cfg = self.written_config()
        # Kept text is re-read after every compaction, and compactions are
        # more frequent once the window is declared.
        self.assertEqual(cfg["compaction"]["keep"]["tokens"], 15000)
        self.assertEqual(cfg["compaction"]["buffer"], "50%")
        self.assertEqual(cfg["tool_output"], {"max_lines": 300, "max_bytes": 12288})
        cfg = self.written_config(AUTOWP_INFERENCE_KEEP_TOKENS="9000",
                                  AUTOWP_INFERENCE_TOOL_MAX_LINES="120",
                                  AUTOWP_INFERENCE_TOOL_MAX_BYTES="4096")
        self.assertEqual(cfg["compaction"]["keep"]["tokens"], 9000)
        self.assertEqual(cfg["tool_output"], {"max_lines": 120, "max_bytes": 4096})

    def test_snippet_sets_the_reasoning_effort_on_the_request_body(self):
        """83.5 % of decode tokens were invisible reasoning.

        Through the per-agent request body, never a model variant: a variant
        changes the model id, and an id the provider cannot resolve falls back
        to a cloud model without saying so.
        """
        cfg = self.written_config()
        self.assertEqual(cfg["agents"]["build"],
                         {"request": {"body": {"reasoning_effort": "low"}}})
        self.assertNotIn("#", json.dumps(cfg), "no model variant in the config")
        cfg = self.written_config(AUTOWP_INFERENCE_REASONING_EFFORT="medium")
        self.assertEqual(
            cfg["agents"]["build"]["request"]["body"]["reasoning_effort"], "medium")
        # An empty value omits the key entirely, leaving the model's default.
        cfg = self.written_config(AUTOWP_INFERENCE_REASONING_EFFORT="")
        self.assertNotIn("build", cfg["agents"])
        self.assertEqual(sorted(cfg["agents"]), ["explore", "general"])

    def test_snippet_small_model_is_opt_in(self):
        """Unset, `explore` stays on the subagent slot exactly as before."""
        cfg = self.written_config(AUTOWP_INFERENCE_MODEL="some-model:7b")
        self.assertEqual(cfg["agents"]["explore"]["model"], "ollama-sub/some-model:7b")
        self.assertEqual(list(cfg["providers"]["ollama"]["models"]), ["some-model:7b"])
        # Set, it joins the main provider with its own limit and takes explore.
        cfg = self.written_config(AUTOWP_INFERENCE_MODEL="some-model:7b",
                                  AUTOWP_INFERENCE_SMALL_MODEL="small-model:3b")
        self.assertEqual(list(cfg["providers"]["ollama"]["models"]),
                         ["some-model:7b", "small-model:3b"])
        self.assertEqual(cfg["providers"]["ollama"]["models"]["small-model:3b"]["limit"],
                         {"context": 120000, "output": 16000})
        self.assertEqual(cfg["agents"]["explore"]["model"], "ollama/small-model:3b")
        # The parent and `general` are untouched by it.
        self.assertEqual(cfg["model"], "ollama/some-model:7b")
        self.assertEqual(cfg["agents"]["general"]["model"], "ollama-sub/some-model:7b")
        self.assertEqual(list(cfg["providers"]["ollama-sub"]["models"]),
                         ["some-model:7b"])
        # Both optional keys off at once is still valid JSON with no stray comma.
        cfg = self.written_config(AUTOWP_INFERENCE_REASONING_EFFORT="",
                                  AUTOWP_INFERENCE_SMALL_MODEL="small-model:3b")
        self.assertEqual(cfg["agents"]["explore"]["model"], "ollama/small-model:3b")
        self.assertNotIn("build", cfg["agents"])

    def test_snippet_documents_every_variable_it_reads(self):
        """Each setting is parameterised, with its default in the header block."""
        text = self.SNIPPET.read_text()
        header = text.split("(\n    set -eu", 1)[0]
        read = set(re.findall(r"\$\{(AUTOWP_[A-Z_]+)[:\-}]", text))
        self.assertIn("AUTOWP_INFERENCE_CONTEXT", read)
        for name in sorted(read):
            with self.subTest(variable=name):
                self.assertIn(name, header, f"{name} is not documented")

    def serve_tags(self, names, spaced=False):
        """A throwaway /api/tags server; returns its port.

        The hook must not need the real inference host, so the model check is
        exercised against a stub that answers like ollama does.
        """
        # ollama answers compact; `spaced` pins that the hook's extraction
        # also survives whitespace around the colon, which is legal JSON.
        models = {"models": [{"name": n, "model": n} for n in names]}
        payload = json.dumps(
            models, separators=((", ", ": ") if spaced else (",", ":"))).encode()

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body = payload if self.path == "/api/tags" else b"{}"
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *a):
                pass

        class Server(http.server.HTTPServer):
            def server_bind(self):
                # Skip http.server's own server_bind: it calls
                # socket.getfqdn(), a reverse lookup that takes ~35s on a
                # network that cannot answer it.
                super(http.server.HTTPServer, self).server_bind()
                self.server_name, self.server_port = self.server_address[:2]

        server = Server(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.shutdown)
        return server.server_port

    def test_snippet_checks_the_model_against_the_server(self):
        """The model name is never discovered, so the hook asks whether it exists.

        Advisory only: a model absent from the server, and a server that
        cannot be reached at all, both warn and still write the
        configuration. Provisioning must not need the inference host to be
        up, and a model can be pulled afterwards.
        """
        served = ["qwen3.8:27b-mlx", "gemma4:12b-mlx"]
        port = self.serve_tags(served)
        home = self.tmp / "home/tester"

        with self.subTest(case="model present"):
            shutil.rmtree(home, ignore_errors=True)
            home.mkdir(parents=True)
            r = self.run_snippet(AUTOWP_INFERENCE_HOST="127.0.0.1",
                                 AUTOWP_INFERENCE_PORT=str(port),
                                 AUTOWP_INFERENCE_CHECK="1")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertNotIn("WARNING", r.stderr)
            self.assertNotIn("unchecked", r.stderr)

        with self.subTest(case="model absent"):
            shutil.rmtree(home, ignore_errors=True)
            home.mkdir(parents=True)
            r = self.run_snippet(AUTOWP_INFERENCE_HOST="127.0.0.1",
                                 AUTOWP_INFERENCE_PORT=str(port),
                                 AUTOWP_INFERENCE_MODEL="not-pulled:1b",
                                 AUTOWP_INFERENCE_CHECK="1")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("WARNING: not-pulled:1b is not on", r.stderr)
            for name in served:                     # it says what IS there
                self.assertIn(name, r.stderr)
            self.assertIn("ollama pull not-pulled:1b", r.stderr)
            # Advisory: the configuration is written regardless.
            cfg = json.loads((home / ".config/opencode/opencode.json").read_text())
            self.assertIn("not-pulled:1b", cfg["providers"]["ollama"]["models"])

        with self.subTest(case="small model absent"):
            shutil.rmtree(home, ignore_errors=True)
            home.mkdir(parents=True)
            r = self.run_snippet(AUTOWP_INFERENCE_HOST="127.0.0.1",
                                 AUTOWP_INFERENCE_PORT=str(port),
                                 AUTOWP_INFERENCE_SMALL_MODEL="tiny:0b",
                                 AUTOWP_INFERENCE_CHECK="1")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("WARNING: tiny:0b is not on", r.stderr)

        with self.subTest(case="whitespace in the server's JSON"):
            shutil.rmtree(home, ignore_errors=True)
            home.mkdir(parents=True)
            r = self.run_snippet(AUTOWP_INFERENCE_HOST="127.0.0.1",
                                 AUTOWP_INFERENCE_PORT=str(self.serve_tags(served, spaced=True)),
                                 AUTOWP_INFERENCE_CHECK="1")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertNotIn("WARNING", r.stderr)
            self.assertNotIn("could not list", r.stderr)

        with self.subTest(case="server unreachable"):
            shutil.rmtree(home, ignore_errors=True)
            home.mkdir(parents=True)
            # 127.0.0.1 on a port nothing listens on: refused at once, so the
            # test does not wait out the hook's 5-second timeout.
            with socket.socket() as probe:
                probe.bind(("127.0.0.1", 0))
                dead = probe.getsockname()[1]
            r = self.run_snippet(AUTOWP_INFERENCE_HOST="127.0.0.1",
                                 AUTOWP_INFERENCE_PORT=str(dead),
                                 AUTOWP_INFERENCE_CHECK="1")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("could not list models", r.stderr)
            self.assertNotIn("WARNING", r.stderr)
            self.assertTrue((home / ".config/opencode/opencode.json").is_file(),
                            "an unreachable server must not stop the config")

    def test_snippet_keeps_an_existing_config(self):
        home = self.tmp / "home/tester"
        conf = home / ".config/opencode/opencode.json"
        conf.parent.mkdir(parents=True)
        conf.write_text('{"mine": true}\n')
        script = self.SNIPPET.read_text().replace("/home/$user", str(self.tmp / "home/$user"))
        r = subprocess.run(["bash", "-s"], input=script, text=True, capture_output=True,
                           timeout=60, env=dict(os.environ, AUTOWP_INFERENCE_USER="tester"))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(conf.read_text()), {"mine": True})
        self.assertIn("left as it is", r.stderr)

    def test_flag_requires_harness_opencode(self):
        for harness in ("claude", "copilot", "none"):
            for flag in ("--local-inference", "--no-local-inference"):
                with self.subTest(harness=harness, flag=flag):
                    r = self.run_auto_wp("--c", "--harness", harness, flag, "foo")
                    self.assertEqual(r.returncode, 2, r.stderr)
                    self.assertIn("only valid with --harness opencode", r.stderr)
                    self.assertEqual(os.listdir(self.tmp), [])
        # Without --harness at all the harness is not yet known, so the
        # option has nothing to attach to.
        r = self.run_auto_wp("--c", "--local-inference", "foo")
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn("only valid with --harness opencode", r.stderr)
        # The two spellings exclude each other.
        r = self.run_auto_wp("--c", "--harness", "opencode",
                             "--local-inference", "--no-local-inference", "foo")
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn("not allowed with argument", r.stderr)
        self.assertEqual(os.listdir(self.tmp), [])

    def test_other_harnesses_record_no_local_inference(self):
        for harness in ("claude", "copilot", "none"):
            with self.subTest(harness=harness):
                self.assertOk(self.run_auto_wp("--c", "--harness", harness, harness))
                manifest = json.loads(
                    (self.tmp / harness / "config/auto-wp.json").read_text())
                self.assertNotIn("local_inference", manifest)

    def test_readme_documents_the_inference_host(self):
        self.assertOk(self.run_auto_wp("--c", "--harness", "opencode",
                                       "--local-inference", "on"))
        self.assertOk(self.run_auto_wp("--c", "--harness", "opencode",
                                       "--no-local-inference", "off"))
        on = (self.tmp / "on/README.md").read_text()
        off = (self.tmp / "off/README.md").read_text()
        self.assertNotIn("{{", on)
        self.assertIn("**Local inference.**", on)
        # The address file, in the location that works on a first launch: the
        # project directory, not the container's home.
        self.assertIn("echo 192.0.2.10 > .local-llm-machine-ip.txt", on)
        self.assertNotIn("> ~/.local-llm-machine-ip.txt", on)
        # Both servers, and the two ways to get them wrong.
        self.assertIn("OLLAMA_HOST=0.0.0.0:11435", on)
        self.assertIn("OLLAMA_CONTEXT_LENGTH", on)
        self.assertIn("OLLAMA_KEEP_ALIVE", on)
        # The overrides are pointed at rather than listed, so the README does
        # not carry three copies of the whole table (§3.4: HARNESS_LOGIN is
        # substituted once per quick-start path).
        self.assertIn("AUTOWP_INFERENCE_*", on)
        self.assertIn("hooks/setup-project", on)
        # The cloud-login paragraph is replaced, not added to.
        self.assertNotIn("/connect", on)
        self.assertIn("/connect", off)
        self.assertNotIn("Local inference", off)

    def test_readme_names_every_installed_tool(self):
        """The README's `bin/` list must not fall behind what is installed."""
        for language in ("c", "rust"):
            with self.subTest(language=language):
                target = f"tools-{language}"
                self.assertOk(self.run_auto_wp("--" + language, "--harness",
                                               "none", target))
                project = self.tmp / target
                readme = (project / "README.md").read_text()
                for tool in sorted(p.name for p in (project / "bin").iterdir()):
                    # The campaign scripts are covered by one `bin/framac-*.sh`
                    # glob rather than named one by one.
                    if tool.startswith("framac-"):
                        continue
                    # Whole name only: a bare `in` check would let
                    # `bin/ledger-ratchet.sh` stand in for `bin/ledger`.
                    pattern = re.escape(f"bin/{tool}") + r"(?![A-Za-z0-9_.-])"
                    self.assertRegex(readme, pattern,
                                     f"bin/{tool} is installed but not named in the README")


class TestHarnessReadmeTemplates(AutoWpTestCase):
    """The harness README prose lives in templates/common/harness/*.md (§4.4)."""

    HARNESS_DIR = TEMPLATES / "common/harness"
    PLACEHOLDERS = {"HARNESS", "HARNESS_INSTALL", "HARNESS_START",
                    "HARNESS_LOGIN", "HARNESS_HOST"}

    def sections(self, name):
        """Parse a harness .md the way auto-wp.py does."""
        out, key = {}, None
        for line in (self.HARNESS_DIR / f"{name}.readme.md").read_text().splitlines(keepends=True):
            tag = line.strip()
            marker = (tag[5:-4].strip()
                      if tag.startswith("<!-- ") and tag.endswith(" -->") else "")
            if marker and marker.replace("_", "").isalpha() and marker.isupper():
                key = marker
                out[key] = ""
            elif key is not None:
                out[key] += line
        return {k: v.rstrip("\n") for k, v in out.items()}

    def test_one_file_per_harness_with_every_placeholder(self):
        for harness in ("claude", "opencode", "copilot", "none"):
            with self.subTest(harness=harness):
                self.assertEqual(set(self.sections(harness)), self.PLACEHOLDERS)
                # Each has a shell snippet beside it, except `none`.
                self.assertEqual((self.HARNESS_DIR / f"{harness}.sh").is_file(),
                                 harness != "none")

    def test_no_template_file_collides_with_an_agent_instruction_file(self):
        """`claude.md` is `CLAUDE.md` on a case-insensitive filesystem.

        A harness file named `<harness>.md` was picked up as this repository's
        agent instructions on macOS, handing the prose to the agent as its
        orders. The suffix keeps them distinct on every filesystem.
        """
        reserved = {"claude.md", "agents.md", "gemini.md", "copilot.md",
                    "codex.md", "cursor.md", "readme.md"}
        for path in TEMPLATES.rglob("*.md"):
            with self.subTest(path=str(path.relative_to(TEMPLATES))):
                if path.parent.name in ("commands", "getting-better"):
                    continue          # a command or note, legitimately named
                self.assertNotIn(path.name.lower(), reserved - {"readme.md"},
                                 f"{path} collides with an agent instruction file")

    def test_the_local_inference_file_overrides_only_the_login(self):
        self.assertEqual(set(self.sections("opencode-local-inference")),
                         {"HARNESS_LOGIN"})

    def test_no_value_ends_in_a_newline(self):
        """The rule that makes `rstrip` lossless.

        A placeholder is substituted mid-sentence in the README templates, so
        a value carrying a trailing newline breaks the line it lands in --
        which is exactly what a first version of the parser did.
        """
        for name in ("claude", "opencode", "copilot", "none",
                     "opencode-local-inference"):
            with self.subTest(name=name):
                for key, value in self.sections(name).items():
                    self.assertEqual(value, value.rstrip("\n"), f"{name}/{key}")

    def test_every_placeholder_is_consumed(self):
        """No README template may carry a placeholder no harness file defines."""
        defined = set(self.PLACEHOLDERS)
        for language in ("c", "rust"):
            text = (TEMPLATES / language / "README.md").read_text()
            used = {t.split("}}")[0] for t in text.split("{{")[1:]}
            harness_used = {u for u in used if u.startswith("HARNESS")
                            and u != "HARNESS_CAMPAIGN_NOTE"}
            self.assertEqual(harness_used, defined,
                             f"{language}/README.md placeholders differ from the "
                             "harness files' sections")

    def test_substitution_does_not_break_the_sentence_it_lands_in(self):
        """`{{HARNESS}}` sits mid-sentence, so a trailing newline is visible.

        The suite's other README checks look at stdout or at substrings that
        survive a stray newline, so nothing caught this when the parser
        stripped one newline instead of all of them.
        """
        for language in ("c", "rust"):
            for harness in ("claude", "opencode", "copilot", "none"):
                with self.subTest(language=language, harness=harness):
                    target = f"sub-{language}-{harness}"
                    self.assertOk(self.run_auto_wp("--" + language, "--harness",
                                                   harness, target))
                    readme = (self.tmp / target / "README.md").read_text()
                    name = self.sections(harness)["HARNESS"]
                    self.assertIn(f"start {name} in `tmux`", readme,
                                  "a harness section leaked a newline into the "
                                  "sentence it was substituted into")

    def test_a_file_with_no_sections_is_an_error(self):
        prog = self._copy_program()
        (prog / "templates/common/harness/claude.readme.md").write_text("just a comment\n")
        r = self.run_auto_wp("--c", "--harness", "claude", "foo",
                             script=prog / "auto-wp.py")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("defines no sections", r.stderr)
        self.assertFalse(os.path.lexists(self.tmp / "foo"),
                         "a bad harness file must roll the run back")


class TestInitialCommit(AutoWpTestCase):
    """The generated project starts from a committed baseline (§3.9)."""

    # .kb/fips-corpus.md §1: these four and nothing else.
    SPECS_TRACKED = ["specs/.gitignore", "specs/MANIFEST.tsv",
                     "specs/README.md", "specs/import-specs.py"]

    def tracked(self, project):
        out = subprocess.run(["git", "-C", str(project), "ls-files"],
                             capture_output=True, text=True, timeout=30)
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout.split()

    def test_every_language_and_driver_commits_once(self):
        for language in ("c", "rust"):
            for driver in ("rmf", "fips"):
                with self.subTest(language=language, driver=driver):
                    target = f"{language}-{driver}"
                    args = ["--" + language, "--harness", "none",
                            "--driver", driver]
                    if driver == "fips":
                        args += ["--level", "3"]
                    r = self.run_auto_wp(*args, target)
                    self.assertOk(r)
                    project = self.tmp / target
                    self.assertRegex(r.stdout.splitlines()[-1],
                                     rf"^git     committed {target} \(\d+ files\) on main$")
                    count = subprocess.run(
                        ["git", "-C", str(project), "rev-list", "--count", "HEAD"],
                        capture_output=True, text=True, timeout=30)
                    self.assertEqual(count.stdout.strip(), "1")
                    status = subprocess.run(
                        ["git", "-C", str(project), "status", "--porcelain"],
                        capture_output=True, text=True, timeout=30)
                    self.assertEqual(status.stdout, "",
                                     "nothing generated may be left uncommitted")
                    # The message records what produced the tree.
                    msg = subprocess.run(
                        ["git", "-C", str(project), "log", "-1", "--format=%B"],
                        capture_output=True, text=True, timeout=30).stdout
                    self.assertIn("auto-wp 0.9.0", msg)   # VERSION, as test_11 pins it
                    self.assertIn(f"language {language}", msg)
                    self.assertIn(f"driver {driver}", msg)
                    if driver == "fips":
                        self.assertIn("level 3", msg)

    def test_the_fips_corpus_is_never_committed(self):
        """.kb/fips-corpus.md §1 -- no PDF, no text/, no checklist/, ever."""
        self.assertOk(self.run_auto_wp("--c", "--harness", "none", "--driver",
                                       "fips", "--level", "1", "corpus"))
        tracked = self.tracked(self.tmp / "corpus")
        self.assertEqual(sorted(p for p in tracked if p.startswith("specs/")),
                         self.SPECS_TRACKED)
        for path in tracked:
            self.assertFalse(path.endswith(".pdf"), f"{path} is a corpus document")
            self.assertFalse(path.startswith(("specs/pdf/", "specs/text/",
                                              "specs/checklist/")), path)

    def test_gitignored_paths_stay_out_of_the_commit(self):
        self.assertOk(self.run_auto_wp("--c", "--harness", "none", "ignored"))
        tracked = self.tracked(self.tmp / "ignored")
        for prefix in (".workshop.lock", "framac-src", "macsl", "_build",
                       ".time-loop-watchdog"):
            self.assertEqual([p for p in tracked if p.startswith(prefix)], [],
                             f"{prefix} must be ignored, not committed")

    IDENT = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
             "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com"}

    def make_repo(self, path, *, commit="theirs"):
        path.mkdir(parents=True, exist_ok=True)
        for cmd in (["git", "init", "-q", "-b", "main", "."],
                    ["git", "commit", "-q", "--allow-empty", "-m", commit]):
            subprocess.run(cmd, cwd=path, check=True, timeout=30,
                           env=dict(os.environ, **self.IDENT))

    def test_a_nested_project_gets_its_own_repository(self):
        """Inside another work tree, the project is still its own repository.

        The containing repository must come out untouched: its history, its
        index and its dirty files are not this program's to write.
        """
        outer = self.tmp / "outer"
        self.make_repo(outer)
        (outer / "their-wip.txt").write_text("unstaged work\n")
        r = self.run_auto_wp("--c", "--harness", "none", "outer/inner")
        self.assertOk(r)
        inner = outer / "inner"
        self.assertTrue((inner / ".git").is_dir())
        self.assertRegex(r.stdout.splitlines()[-1],
                         r"^git     committed outer/inner \(\d+ files\) on main$")
        # The nested repository holds the baseline...
        count = subprocess.run(["git", "-C", str(inner), "rev-list", "--count", "HEAD"],
                               capture_output=True, text=True, timeout=30)
        self.assertEqual(count.stdout.strip(), "1")
        self.assertGreater(len(self.tracked(inner)), 100)
        # ...and the outer repository is exactly as it was.
        outer_count = subprocess.run(["git", "-C", str(outer), "rev-list", "--count", "HEAD"],
                                     capture_output=True, text=True, timeout=30)
        self.assertEqual(outer_count.stdout.strip(), "1",
                         "committed into a repository it did not create")
        staged = subprocess.run(["git", "-C", str(outer), "diff", "--cached", "--name-only"],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(staged.stdout, "")
        self.assertEqual(self.tracked(outer), [],
                         "the outer repository must have nothing of ours tracked")
        self.assertTrue((outer / "their-wip.txt").is_file())
        # git does not recurse into a nested repository: one untracked entry.
        status = subprocess.run(["git", "-C", str(outer), "status", "--porcelain", "inner"],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(status.stdout, "?? inner/\n")

    def test_a_target_that_already_has_commits_is_not_committed_to(self):
        """Filling a project that is already a repository with history.

        `add -A` there would sweep in whatever its work tree was carrying, so
        the repository is (re)initialised and nothing is staged or committed.
        """
        target = self.tmp / "refill"
        self.make_repo(target, commit="their own work")
        (target / "their-wip.txt").write_text("WIP\n")
        r = self.run_auto_wp("--c", "--harness", "none", "refill")
        self.assertOk(r)
        self.assertIn("git     refill is already a git repository; nothing staged or committed",
                      r.stdout.splitlines())
        count = subprocess.run(["git", "-C", str(target), "rev-list", "--count", "HEAD"],
                               capture_output=True, text=True, timeout=30)
        self.assertEqual(count.stdout.strip(), "1", "their history was modified")
        staged = subprocess.run(["git", "-C", str(target), "diff", "--cached", "--name-only"],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(staged.stdout, "", "their work tree was staged")
        # The project is still generated, just left for them to commit.
        self.assertTrue((target / "README.md").is_file())
        self.assertTrue((target / ".git").is_dir())

    def test_no_git_identity_warns_and_leaves_the_project_usable(self):
        blank = {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull,
                 "GIT_CONFIG_NOSYSTEM": "1", "GIT_AUTHOR_NAME": "",
                 "GIT_AUTHOR_EMAIL": "", "GIT_COMMITTER_NAME": "",
                 "GIT_COMMITTER_EMAIL": ""}
        r = self.run_auto_wp("--c", "--harness", "none", "noid", env=blank)
        self.assertOk(r)                      # generation still succeeds
        self.assertIn("git commit failed", r.stderr)
        self.assertIn("user.name", r.stderr)
        project = self.tmp / "noid"
        self.assertTrue((project / "README.md").is_file())
        # Staged, so the user's own commit is one command away.
        staged = subprocess.run(["git", "-C", str(project), "diff", "--cached",
                                 "--name-only"], capture_output=True, text=True,
                                timeout=30)
        self.assertGreater(len(staged.stdout.split()), 100)


class TestTemplateByproducts(AutoWpTestCase):
    """A template's own Python byproducts must never reach a project.

    `tools/bin/` ships Python tools and a skill's `scripts/` does too, so
    running either in place leaves a `__pycache__` next to the sources. Before
    IGNORED_COPIES covered it, that directory was copied into every project
    generated afterwards.
    """

    BYPRODUCTS = [
        "templates/common/tools/bin/__pycache__/ledger.cpython-99.pyc",
        "templates/common/tools/bin/stale.pyc",
        "templates/common/skills/sl-internal/scripts/__pycache__/x.cpython-99.pyc",
        "templates/c/skills/time-loop/leftover~",
    ]

    def test_pycache_and_backups_are_not_installed(self):
        prog = self._copy_program()
        for rel in self.BYPRODUCTS:
            victim = prog / rel
            victim.parent.mkdir(parents=True, exist_ok=True)
            victim.write_bytes(b"byproduct")
        for lang in ("c", "rust"):
            with self.subTest(lang=lang):
                target = "noby-" + lang
                self.assertOk(self.run_auto_wp("--" + lang, "--harness", "none",
                                               target, script=prog / "auto-wp.py"))
                project = self.tmp / target
                strays = [str(p.relative_to(project))
                          for p in project.rglob("*")
                          if p.name == "__pycache__"
                          or p.suffix in (".pyc", ".pyo")
                          or p.name.endswith("~")]
                self.assertEqual(strays, [], f"byproducts copied into {target}")
                # The tools themselves must still be there.
                self.assertTrue((project / "bin/ledger").is_file())


if __name__ == "__main__":
    unittest.main()
