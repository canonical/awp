"""Level 1 program tests for auto-wp.py (auto-wp.md section 5, tests 1-22).

Run from the repository root:

    python3 -m unittest discover -s tests -v

Every test runs auto-wp.py as a subprocess in a fresh temporary directory
outside the repository.

Known pending skill: `creusot-launch` is roadmap step 1 (auto-wp.md 4.3.7,
"Until a step is done, its files are absent"). The expected Rust skill set is
the list of auto-wp.md 4.3.2 minus the pending skills whose template is
absent; every check that needs such a skill is reported as a skip, never as a
silent pass.
"""

import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

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
    "sl-auditor", "sl-builder", "sl-internal", "sl-monitoring-sl",
]
RUST_COMMANDS = []

C_SKILLS = sorted(set(COMMON_SKILLS) | set(C_LAYER_SKILLS))            # 23
RUST_SPEC_SKILLS = sorted(set(COMMON_SKILLS) | set(RUST_LAYER_SKILLS))  # 17

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
    """Base: a temporary working directory outside the repository."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="autowp-test-")).resolve()
        self.addCleanup(self._cleanup)
        if REPO in self.tmp.parents:
            self.fail(f"temporary directory {self.tmp} is inside the repository")

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
            timeout=120)

    def assertOk(self, r):
        self.assertEqual(r.returncode, 0,
                         f"exit {r.returncode}\nstdout:\n{r.stdout}\nstderr:\n{r.stderr}")

    def _copy_program(self):
        """A private copy of auto-wp.py + templates whose templates we may break."""
        prog = self.tmp / "prog"
        prog.mkdir()
        shutil.copy2(SCRIPT, prog / "auto-wp.py")
        shutil.copytree(TEMPLATES, prog / "templates", symlinks=True)
        return prog


class TestAutoWp(AutoWpTestCase):

    # 1 ----------------------------------------------------------------------
    def test_01_c_layout(self):
        r = self.run_auto_wp("--c", "foo")
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
        r = self.run_auto_wp("--rust", "foo")
        self.assertOk(r)
        foo = self.tmp / "foo"
        for s in ["creusot", "creusot-launch", "creusot-monitoring", "creusot-sl"]:
            if s in RUST_ABSENT_PENDING:
                continue  # reported by test_02b
            self.assertTrue((foo / "config/skills" / s / "SKILL.md").is_file(),
                            f"missing config/skills/{s}/SKILL.md")
        skills = skill_dirs(foo)
        self.assertEqual(skills, RUST_SKILLS,
                         f"expected the 18 skills of auto-wp.md 4.3.2 minus "
                         f"{RUST_ABSENT_PENDING or 'nothing'}")
        self.assertEqual(len(skills), 18 - len(RUST_ABSENT_PENDING))
        self.assertEqual(command_names(foo), [])
        self.assertEqual([s for s in skills if s.startswith("frama-c")], [])
        self.assertEqual(
            (foo / "config/skills/sl-builder/SKILL.md").read_bytes(),
            (TEMPLATES / "rust/skills/sl-builder/SKILL.md").read_bytes())
        self.assertFalse(os.path.lexists(
            foo / "config/skills/sl-internal/scripts/no_ceiling_gate.py"))

    def test_02b_rust_creusot_launch_installed(self):
        """The part of test 2 that needs creusot-launch (spec count: 17)."""
        if RUST_ABSENT_PENDING:
            self.skipTest(pending_note(RUST_ABSENT_PENDING) +
                          "; --rust installs %d skills instead of 17" % len(RUST_SKILLS))
        r = self.run_auto_wp("--rust", "foo")
        self.assertOk(r)
        self.assertTrue((self.tmp / "foo/config/skills/creusot-launch/SKILL.md").is_file())
        self.assertEqual(len(skill_dirs(self.tmp / "foo")), 17)

    def test_02c_rust_only_pending_skills_absent(self):
        """Every Rust-layer skill of 4.3.2 that is not pending has a template."""
        missing = [s for s in RUST_LAYER_SKILLS
                   if not (TEMPLATES / "rust/skills" / s).is_dir() and s not in PENDING_RUST]
        self.assertEqual(missing, [])

    # 3 ----------------------------------------------------------------------
    def test_03_default_is_c(self):
        r1 = self.run_auto_wp("foo")
        self.assertOk(r1)
        r2 = self.run_auto_wp("--c", "bar")
        self.assertOk(r2)
        self.assertEqual(skill_dirs(self.tmp / "foo"), C_SKILLS)
        self.assertEqual(command_names(self.tmp / "foo"), C_COMMANDS)
        self.assertEqual(
            {k: v[:3] if v[0] == "file" else v
             for k, v in snapshot(self.tmp / "foo/config").items()
             if k != "auto-wp.json"},
            {k: v[:3] if v[0] == "file" else v
             for k, v in snapshot(self.tmp / "bar/config").items()
             if k != "auto-wp.json"})
        m = json.loads((self.tmp / "foo/config/auto-wp.json").read_text())
        self.assertEqual(m["language"], "c")
        self.assertEqual(r1.stdout.replace("foo", "X"), r2.stdout.replace("bar", "X"))
        # Whole words only: the README also contains `--bare`.
        self.assertEqual(re.sub(r"\bfoo\b", "X", (self.tmp / "foo/README.md").read_text()),
                         re.sub(r"\bbar\b", "X", (self.tmp / "bar/README.md").read_text()))

    # 4 ----------------------------------------------------------------------
    def test_04_both_flags_usage_error(self):
        r = self.run_auto_wp("--c", "--rust", "foo")
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertNotEqual(r.stderr.strip(), "")
        self.assertFalse(os.path.lexists(self.tmp / "foo"))
        self.assertEqual(os.listdir(self.tmp), [])

    def test_04b_other_usage_errors(self):
        """auto-wp.md 3.6: unknown option, missing or extra positional -> exit 2."""
        for args in [(), ("a", "b"), ("--bogus", "foo"), ("--rust",)]:
            with self.subTest(args=args):
                r = self.run_auto_wp(*args)
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
                r = self.run_auto_wp(*args)
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
                self.assertEqual(os.listdir(self.tmp), [])

    # 6 ----------------------------------------------------------------------
    def test_06_second_run_fails_unchanged(self):
        for lang in ("--c", "--rust"):
            with self.subTest(lang=lang):
                name = "foo" + lang.strip("-")
                self.assertOk(self.run_auto_wp(lang, name))
                before = snapshot(self.tmp / name)
                r = self.run_auto_wp(lang, name)
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
        self.assertOk(self.run_auto_wp("--c", "foo"))
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
                r = self.run_auto_wp("--c", foo.name)
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
                r = self.run_auto_wp("--c", name)
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                self.assertIn("auto-wp: error:", r.stderr)
                self.assertEqual(snapshot(d), before)

    def test_08c_target_is_a_file(self):
        (self.tmp / "foo").write_text("plain file\n")
        before = snapshot(self.tmp)
        r = self.run_auto_wp("--c", "foo")
        self.assertEqual(r.returncode, 1)
        self.assertIn("auto-wp: error:", r.stderr)
        self.assertEqual(snapshot(self.tmp), before)

    def test_08d_target_symlink_to_dir(self):
        """auto-wp.md 3.1 item 1: a symlink to a directory is used as the directory."""
        (self.tmp / "real").mkdir()
        (self.tmp / "foo").symlink_to("real")
        self.assertOk(self.run_auto_wp("--c", "foo"))
        self.assertTrue((self.tmp / "foo").is_symlink())
        self.assertTrue((self.tmp / "real/config/skills/frama-c/SKILL.md").is_file())

    # 9 ----------------------------------------------------------------------
    def test_09_relative_symlinks(self):
        for lang in ("--c", "--rust"):
            with self.subTest(lang=lang):
                foo = self.tmp / ("foo" + lang.strip("-"))
                self.assertOk(self.run_auto_wp(lang, foo.name))
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
                self.assertOk(self.run_auto_wp("--" + lang, foo.name))
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
                self.assertOk(self.run_auto_wp("--" + lang, foo.name))
                m = json.loads((foo / "config/auto-wp.json").read_text())
                self.assertEqual(m["language"], lang)
                self.assertEqual(m["auto_wp_version"], "0.5.0")
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
        r = self.run_auto_wp("--c", "foo", cwd=elsewhere)
        self.assertOk(r)
        self.assertEqual(len(skill_dirs(elsewhere / "foo")), 23)
        # absolute target path as well
        r = self.run_auto_wp("--rust", str(self.tmp / "abs"), cwd=elsewhere)
        self.assertOk(r)
        self.assertEqual(skill_dirs(self.tmp / "abs"), RUST_SKILLS)

    # 13 ---------------------------------------------------------------------
    def test_13_c_readme(self):
        self.assertOk(self.run_auto_wp("--c", "foobar"))
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
        self.assertOk(self.run_auto_wp("--c", "foobar"))
        d = self.tmp / "foobar"
        for rel in ("bin/rmf-lint.sh", "bin/fips-lint.sh", "bin/ebios-lint.sh",
                    "bin/ledger-ratchet.sh",
                    "bin/crosswalk-gen.sh", "bin/fetch-sources.sh", "no-ceiling.md", ".gitignore",
                    "frama-c-patches/apply.sh", "framac-gold", "NIST.FIPS.140-3.pdf"):
            self.assertTrue(os.path.lexists(d / rel), rel)
            self.assertFalse((d / rel).is_symlink(), rel)
        # bin/ merges the common layer (rmf-lint.sh) and the C layer (22): 4.1, 4.2.1.
        self.assertEqual(len(list(d.glob("bin/*.sh"))), 23)
        self.assertEqual((d / "bin/rmf-lint.sh").read_bytes(),
                         (TEMPLATES / "common/tools/bin/rmf-lint.sh").read_bytes())
        self.assertEqual((d / "bin/fips-lint.sh").read_bytes(),
                         (TEMPLATES / "c/tools/bin/fips-lint.sh").read_bytes())
        self.assertEqual((d / "NIST.FIPS.140-3.pdf").read_bytes(),
                         (TEMPLATES / "common/tools/NIST.FIPS.140-3.pdf").read_bytes())
        self.assertEqual(list(d.glob("*.sh")), [], "scripts belong in bin/, not the root")
        for s in d.glob("bin/*.sh"):
            self.assertTrue(os.access(s, os.X_OK), s.name)
        self.assertIn("/framac-src/", (d / ".gitignore").read_text())
        self.assertIn("/.workshop.lock", (d / ".gitignore").read_text())

    def test_13c_rust_has_only_common_tools(self):
        """--rust gets bin/ with the common layer's rmf-lint.sh only (4.1), no C tool."""
        self.assertOk(self.run_auto_wp("--rust", "foobar"))
        d = self.tmp / "foobar"
        self.assertEqual(sorted(p.name for p in (d / "bin").iterdir()), ["rmf-lint.sh"])
        lint = d / "bin/rmf-lint.sh"
        self.assertTrue(lint.is_file() and not lint.is_symlink())
        self.assertTrue(os.access(lint, os.X_OK))
        self.assertEqual(lint.read_bytes(),
                         (TEMPLATES / "common/tools/bin/rmf-lint.sh").read_bytes())
        self.assertEqual((d / "NIST.FIPS.140-3.pdf").read_bytes(),
                         (TEMPLATES / "common/tools/NIST.FIPS.140-3.pdf").read_bytes())
        for rel in ("frama-c-patches", "framac-gold", "no-ceiling.md"):
            self.assertFalse(os.path.lexists(d / rel), rel)
        gi = self.tmp / "foobar/.gitignore"
        self.assertTrue(gi.is_file() and not gi.is_symlink())
        self.assertIn("/.workshop.lock", gi.read_text())

    def test_13d_existing_tool_kept(self):
        foo = self.tmp / "foo"
        foo.mkdir()
        (foo / ".gitignore").write_text("mine\n")
        r = self.run_auto_wp("--c", "foo")
        self.assertOk(r)
        self.assertEqual((foo / ".gitignore").read_text(), "mine\n")
        self.assertIn("kept    foo/.gitignore (already exists)", r.stdout.splitlines())
        self.assertNotIn("copied  foo/.gitignore", r.stdout.splitlines())
        self.assertIn("copied  foo/bin", r.stdout.splitlines())

    # 14 ---------------------------------------------------------------------
    def test_14_rust_readme(self):
        self.assertOk(self.run_auto_wp("--rust", "foobar"))
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
        r = self.run_auto_wp("--c", ".", cwd=bar)
        self.assertOk(r)
        title = (bar / "README.md").read_text().splitlines()[0]
        self.assertTrue(title.startswith("# bar"), title)
        for spelled in ("baz/", "./qux"):
            with self.subTest(spelled=spelled):
                self.assertOk(self.run_auto_wp("--c", spelled))
                name = spelled.strip("./")
                title = (self.tmp / name / "README.md").read_text().splitlines()[0]
                self.assertTrue(title.startswith(f"# {name} "), title)

    # 16 ---------------------------------------------------------------------
    def test_16_existing_readme_kept(self):
        foo = self.tmp / "foo"
        foo.mkdir()
        (foo / "README.md").write_text("my own readme\n")
        before = snapshot(foo / "README.md")
        r = self.run_auto_wp("--c", "foo")
        self.assertOk(r)
        self.assertEqual(snapshot(foo / "README.md"), before)
        self.assertIn("kept    foo/README.md (already exists)", r.stdout.splitlines())

    # 17 ---------------------------------------------------------------------
    def test_17_git(self):
        if shutil.which("git") is None:
            self.skipTest("git not installed")
        probe = subprocess.run(["git", "-C", str(self.tmp), "rev-parse",
                                "--is-inside-work-tree"], capture_output=True, text=True)
        if probe.returncode == 0:
            self.fail(f"temporary directory {self.tmp} is already inside a git work tree")
        r = self.run_auto_wp("--c", "foo")
        self.assertOk(r)
        self.assertIn("git     initialized foo", r.stdout.splitlines())
        out = subprocess.run(["git", "-C", str(self.tmp / "foo"), "rev-parse",
                              "--show-toplevel"], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0)
        self.assertEqual(Path(out.stdout.strip()).resolve(), (self.tmp / "foo").resolve())
        log = subprocess.run(["git", "-C", str(self.tmp / "foo"), "rev-list", "--all"],
                             capture_output=True, text=True)
        self.assertEqual(log.stdout.strip(), "", "auto-wp.py must not commit")
        remotes = subprocess.run(["git", "-C", str(self.tmp / "foo"), "remote"],
                                 capture_output=True, text=True)
        self.assertEqual(remotes.stdout.strip(), "", "auto-wp.py must not add a remote")
        # inside an existing work tree
        outer = self.tmp / "outer"
        outer.mkdir()
        subprocess.run(["git", "init", "-q", str(outer)], check=True)
        r = self.run_auto_wp("--c", "outer/foo")
        self.assertOk(r)
        self.assertFalse(os.path.lexists(outer / "foo/.git"))
        self.assertIn("git     outer/foo is already in a git work tree", r.stdout.splitlines())

    # 18 ---------------------------------------------------------------------
    def test_18_no_git(self):
        empty_bin = self.tmp / "emptybin"
        empty_bin.mkdir()
        r = self.run_auto_wp("--c", "foo", env={"PATH": str(empty_bin)})
        self.assertOk(r)
        self.assertIn("warning: git not found; run 'git init' in foo before /time-loop",
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
            r = self.run_auto_wp("--c", "foo", cwd=work, script=script)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("auto-wp: error:", r.stderr)
            self.assertEqual(r.stdout, "")
            self.assertFalse(os.path.lexists(work / "foo"))
            self.assertEqual(os.listdir(work), [])

        with self.subTest(case="missing parents created by the run"):
            r = self.run_auto_wp("--c", "a/b/foo", cwd=work, script=script)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertEqual(os.listdir(work), [])

        with self.subTest(case="existing target with content and .claude/"):
            foo = work / "existing"
            (foo / ".claude").mkdir(parents=True)
            (foo / ".claude/settings.json").write_text("{}\n")
            (foo / "src.c").write_text("int x;\n")
            before = snapshot(foo)
            r = self.run_auto_wp("--c", "existing", cwd=work, script=script)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertEqual(snapshot(foo), before)

        with self.subTest(case="re-run after fixing starts from the same state"):
            victim.chmod(0o644)
            r = self.run_auto_wp("--c", "foo", cwd=work, script=script)
            self.assertOk(r)
            self.assertEqual(len(skill_dirs(work / "foo")), 23)

    def test_19b_rollback_missing_template_dir(self):
        """Missing template directory: run-time error, exit 1, nothing created."""
        prog = self._copy_program()
        shutil.rmtree(prog / "templates/rust")
        r = self.run_auto_wp("--rust", "foo", script=prog / "auto-wp.py")
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
        r = self.run_auto_wp("--c", "foo", env={"PATH": f"{fakebin}"})
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
                r = self.run_auto_wp("--" + lang, foo.name)
                self.assertOk(r)
                self.assertIn(f"copied  {foo.name}/.workshop (workshop: autowp)",
                              r.stdout.splitlines())
                ws = foo / ".workshop"
                for rel in ("autowp.yaml", "autowp-packages/sdk.yaml",
                            "autowp-packages/hooks/setup-base"):
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
                r = self.run_auto_wp("--c", name)
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                self.assertIn("auto-wp: error:", r.stderr)
                self.assertEqual(snapshot(d), before)
                self.assertFalse(os.path.lexists(d / "config"))
        with self.subTest(case="other definition preserved"):
            d = self.tmp / "other"
            (d / ".workshop").mkdir(parents=True)
            (d / ".workshop/other.yaml").write_text("name: other\n")
            before = snapshot(d / ".workshop/other.yaml")
            r = self.run_auto_wp("--c", "other")
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
            r = self.run_auto_wp("--c", "foo", cwd=work, script=script)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertFalse(os.path.lexists(work / "foo"))
        with self.subTest(case="pre-existing .workshop/other.yaml kept"):
            foo = work / "existing"
            (foo / ".workshop").mkdir(parents=True)
            (foo / ".workshop/other.yaml").write_text("name: other\n")
            before = snapshot(foo)
            r = self.run_auto_wp("--c", "existing", cwd=work, script=script)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertEqual(snapshot(foo), before)
            self.assertEqual(os.listdir(foo / ".workshop"), ["other.yaml"])


class TestOutputAndConstraints(AutoWpTestCase):
    """auto-wp.md 2 and 3.6 (exact output), not numbered in 5."""

    def test_c_output_exact(self):
        r = self.run_auto_wp("--c", "foobar")
        self.assertOk(r)
        self.assertEqual(r.stdout, (
            "created foobar/config (language: c)\n"
            "  driver:   rmf\n"
            "  skills:   23\n"
            "  commands: 3\n"
            "copied  foobar/.gitignore\n"
            "copied  foobar/NIST.FIPS.140-3.pdf\n"
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
            "git     initialized foobar\n"))

    def test_rust_output_counts(self):
        r = self.run_auto_wp("--rust", "foobar")
        self.assertOk(r)
        lines = r.stdout.splitlines()
        self.assertEqual(lines[0], "created foobar/config (language: rust)")
        self.assertEqual(lines[1], "  driver:   rmf")
        self.assertEqual(lines[2], f"  skills:   {len(RUST_SKILLS)}")
        self.assertEqual(lines[3], "  commands: 0")
        self.assertEqual(lines[4:8], ["copied  foobar/.gitignore",
                                      "copied  foobar/NIST.FIPS.140-3.pdf",
                                      "copied  foobar/bin",
                                      "copied  foobar/.workshop (workshop: autowp)"])

    def test_rust_output_spec_count_18(self):
        if RUST_ABSENT_PENDING:
            self.skipTest(pending_note(RUST_ABSENT_PENDING) +
                          f"; prints 'skills:   {len(RUST_SKILLS)}', spec says 18")
        r = self.run_auto_wp("--rust", "foobar")
        self.assertIn("  skills:   18", r.stdout.splitlines())

    def test_script_header_and_mode(self):
        self.assertTrue(SCRIPT.read_text().startswith("#!/usr/bin/env python3\n"))
        # The mode that ships is the index's (spec §5: 0755). The working
        # tree may carry extra group-write bits from the checkout's umask
        # (a group-shared clone with umask 002 yields 0775), so compare the
        # index entry and require the exec bit locally.
        index = subprocess.run(
            ["git", "-C", str(REPO), "ls-files", "-s", "--", "auto-wp.py"],
            capture_output=True, text=True, check=True).stdout.split()
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
        r = self.run_auto_wp("--driver", "fips", "--level", "3", "foobar")
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
        # linters, the vendored PDF, the same links and the workshop definition.
        self.assertIn("fips-sl", m["skills"])
        self.assertIn("rmf-sl", m["skills"])
        self.assertTrue((d / "bin/fips-lint.sh").is_file())
        self.assertTrue((d / "bin/rmf-lint.sh").is_file())
        self.assertTrue((d / "NIST.FIPS.140-3.pdf").is_file())
        self.assertTrue((d / ".workshop/autowp.yaml").is_file())
        self.assertTrue((d / ".opencode/skills").is_symlink())

    def test_default_generation_has_rmf_only(self):
        r = self.run_auto_wp("--c", "foobar")
        self.assertOk(r)
        d = self.tmp / "foobar"
        self.assertTrue((d / "config/commands/rmf.md").is_file())
        self.assertFalse(os.path.lexists(d / "config/commands/fips.md"))

    def test_fips_readme(self):
        self.run_auto_wp("--driver", "fips", "--level", "2", "foobar")
        text = (self.tmp / "foobar/README.md").read_text()
        self.assertIn("Requirement study: FIPS 140-3, security level 2 (fips-sl).", text)
        self.assertIn("/fips <dir> <dir>-analysis", text)
        self.assertIn("bin/fips-lint.sh grub-analysis-fips-report.md", text)
        self.assertIn("--dir=grub-core/lib/libgcrypt", text)
        self.assertNotIn("{{", text)
        self.assertNotIn("/rmf <dir>", text)
        # The default driver's README keeps its line and has no fips note.
        self.run_auto_wp("--c", "rmfbar")
        text = (self.tmp / "rmfbar/README.md").read_text()
        self.assertIn("Risk study: NIST RMF (rmf-sl).", text)
        self.assertNotIn("libgcrypt", text)
        self.assertNotIn("{{", text)

    def test_fips_rust(self):
        r = self.run_auto_wp("--driver", "fips", "--level", "4", "--rust", "foobar")
        self.assertOk(r)
        d = self.tmp / "foobar"
        m = json.loads((d / "config/auto-wp.json").read_text())
        self.assertEqual(m["driver"], "fips")
        self.assertEqual(m["fips_level"], 4)
        self.assertEqual(m["commands"], [])          # no campaign command under --rust
        self.assertTrue((d / "NIST.FIPS.140-3.pdf").is_file())
        text = (d / "README.md").read_text()
        self.assertIn("Requirement study: FIPS 140-3, security level 4 (fips-sl).", text)
        self.assertNotIn("{{", text)

    def test_fips_rollback(self):
        if os.geteuid() == 0:
            self.skipTest("running as root: an unreadable file is still readable")
        prog = self._copy_program()
        victim = prog / "templates/c/skills/time-loop/SKILL.md"
        victim.chmod(0)
        work = self.tmp / "work"
        work.mkdir()
        r = self.run_auto_wp("--driver", "fips", "--level", "2", "foo",
                             cwd=work, script=prog / "auto-wp.py")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertEqual(r.stdout, "")
        self.assertFalse(os.path.lexists(work / "foo"))
        self.assertEqual(os.listdir(work), [])


if __name__ == "__main__":
    unittest.main()
