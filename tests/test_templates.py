"""Level 1 template checks T1-T8 (tests.md 3.2).

auto-wp.py copies the templates byte for byte, so these check the template
files themselves, on the host. They only read templates/ (and, for part of
T4, ../use-creusot/config/foo/ when that checkout exists).
"""

import os
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TEMPLATES = REPO / "templates"
USE_CREUSOT = Path(os.environ.get("USE_CREUSOT", REPO.parent / "use-creusot"))

COMMON_SKILLS = [
    "directory-structure", "ebios-risk-manager", "ebios-sl", "lean",
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
# Not written yet (auto-wp.md 4.3.7: "Until a step is done, its files are absent").
PENDING_RUST = {"creusot-launch": "roadmap step 1 (auto-wp.md 4.3.7)"}


def norm(text):
    """Collapse whitespace and drop Markdown emphasis, for phrase matching."""
    return re.sub(r"\s+", " ", text.replace("*", "")).strip()


def skills(layer):
    d = TEMPLATES / layer / "skills"
    return sorted(p.name for p in d.iterdir() if p.is_dir() and not p.name.startswith("."))


def commands(layer):
    d = TEMPLATES / layer / "commands"
    return sorted(p.stem for p in d.glob("*.md"))


def all_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        for n in dirnames + filenames:
            yield Path(dirpath) / n


def front_matter(text):
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end < 0:
        return None
    return text[4:end]


class TestTemplates(unittest.TestCase):

    # T1
    def test_T1_no_repo_root_creusot_sl(self):
        pat = re.compile(r"repo-root\s*\\?[`'\"]?\s*creusot-sl\.md")
        hits = []
        for p in all_files(TEMPLATES / "rust"):
            if p.is_file() and not p.is_symlink():
                text = p.read_text(errors="replace")
                if pat.search(text) or pat.search(norm(text)):
                    hits.append(str(p.relative_to(TEMPLATES)))
        self.assertEqual(hits, [], "files still mention repo-root `creusot-sl.md`")

    # T2
    def test_T2_creusot_sl_front_matter(self):
        text = (TEMPLATES / "rust/skills/creusot-sl/SKILL.md").read_text()
        fm = front_matter(text)
        self.assertIsNotNone(fm, "SKILL.md does not start with a YAML front matter")
        m = re.search(r"^name:\s*(\S+)\s*$", fm, re.M)
        self.assertIsNotNone(m, "no name: in front matter")
        self.assertEqual(m.group(1), "creusot-sl")
        d = re.search(r"^description:", fm, re.M)
        self.assertIsNotNone(d, "no description: in front matter")
        desc = norm(fm[d.end():])
        self.assertIn("A Squeeze Loop (SL) that annotates existing Rust with Pearlite "
                      "and proves it with Creusot", desc)
        self.assertNotIn("**", fm, "Markdown emphasis left in the description")
        # auto-wp.md 4.3.2: the original **Name:** line is kept.
        self.assertRegex(text, r"(?m)^\*\*Name:\*\* `?creusot-sl`?")
        self.assertTrue((TEMPLATES / "rust/skills/creusot-sl/creusot-sl.sl.json").is_file())

    # T3
    def test_T3_common_layer(self):
        self.assertEqual(skills("common"), sorted(COMMON_SKILLS))
        self.assertEqual(len(skills("common")), 13)
        self.assertEqual(commands("common"), [])

    def test_T3_c_layer(self):
        self.assertEqual(skills("c"), sorted(C_LAYER_SKILLS))
        self.assertEqual(len(skills("c")), 9)
        self.assertEqual(commands("c"), C_COMMANDS)
        self.assertTrue((TEMPLATES / "c/README.md").is_file())

    def test_T3_rust_layer(self):
        present = skills("rust")
        unexpected = sorted(set(present) - set(RUST_LAYER_SKILLS))
        self.assertEqual(unexpected, [], "skills not listed in auto-wp.md 4.3.2")
        missing = sorted(set(RUST_LAYER_SKILLS) - set(present))
        self.assertEqual([s for s in missing if s not in PENDING_RUST], [],
                         "skills of 4.3.2 missing that are not pending roadmap steps")
        self.assertEqual(commands("rust"), [])
        self.assertTrue((TEMPLATES / "rust/README.md").is_file())
        for s in present:
            self.assertTrue((TEMPLATES / "rust/skills" / s / "SKILL.md").is_file(), s)

    def test_T3_rust_creusot_launch(self):
        d = TEMPLATES / "rust/skills/creusot-launch"
        if not d.is_dir():
            self.skipTest("creusot-launch not written yet: " + PENDING_RUST["creusot-launch"])
        self.assertTrue((d / "SKILL.md").is_file())

    def test_T3_every_skill_has_SKILL_md(self):
        for layer in ("common", "c", "rust"):
            for s in skills(layer):
                with self.subTest(layer=layer, skill=s):
                    self.assertTrue((TEMPLATES / layer / "skills" / s / "SKILL.md").is_file())

    # T4
    def test_T4_no_editor_backups(self):
        backups = [str(p.relative_to(TEMPLATES)) for p in all_files(TEMPLATES)
                   if p.name.endswith("~")]
        self.assertEqual(backups, [])

    def test_T4_no_config_foo(self):
        named_foo = [str(p.relative_to(TEMPLATES)) for p in all_files(TEMPLATES)
                     if p.name == "foo"]
        self.assertEqual(named_foo, [])
        foo = USE_CREUSOT / "config/foo/skills"
        good = USE_CREUSOT / "config/skills"
        if not foo.is_dir():
            self.skipTest(f"{foo} not present; only the name check was done")
        # Files whose foo/ version differs from config/skills/: the template
        # must not hold the stale foo/ content.
        stale = []
        for p in all_files(foo):
            if not p.is_file():
                continue
            rel = p.relative_to(foo)
            g = good / rel
            if g.is_file() and g.read_bytes() == p.read_bytes():
                continue
            t = TEMPLATES / "rust/skills" / rel
            if t.is_file() and t.read_bytes() == p.read_bytes():
                stale.append(str(rel))
        self.assertEqual(stale, [], "template files equal to the stale config/foo/ version")

    # T5
    def test_T5_readme_placeholders(self):
        for lang in ("c", "rust"):
            with self.subTest(lang=lang):
                text = (TEMPLATES / lang / "README.md").read_text()
                found = set(re.findall(r"\{\{(.*?)\}\}", text, re.S))
                self.assertEqual(found, {"DIR", "LANGUAGE"})
                stripped = text.replace("{{DIR}}", "").replace("{{LANGUAGE}}", "")
                self.assertNotIn("{{", stripped)
                self.assertNotIn("}}", stripped)

    # T6
    def test_T6_time_loop_command(self):
        text = (TEMPLATES / "c/commands/time-loop.md").read_text()
        n = norm(text)
        self.assertNotIn("Stop early", text)
        self.assertNotIn("(diminishing returns)", text)
        stop = norm(
            "**Stop** only on: the true terminus (every in-scope goal PROVEN, "
            "VIOLATION reported, or BUG IN FRAMA-C filed, and Gate T passes) — emit "
            "the final report to `XXX.md`; or the deadline / budget exhausted — a "
            "**pause**, not a finish: emit the interim report to `XXX.md` and resume "
            "from the checkpoint on the next invocation. Running out of class-C work "
            "is not a stop: drive the remaining class-A goals to PROVEN or to a filed "
            "Frama-C bug. **Never** burn remaining hours re-grinding the same class "
            "A/B items without a new lever.")
        self.assertIn(stop, n, "replacement Stop bullet (auto-wp.md 4.2.2) not found")
        self.assertRegex(text, r"(?m)^- \*\*Stop\*\* only on:")
        self.assertNotIn("next-budget target", n)
        self._report_and_deadline(text, "commands/time-loop.md")

    def test_T6_time_loop_skill(self):
        text = (TEMPLATES / "c/skills/time-loop/SKILL.md").read_text()
        self.assertNotIn("DIMINISHING-RETURNS stop fires ONLY", text)
        fm = front_matter(text)
        self.assertIsNotNone(fm)
        d = re.search(r"^description:", fm, re.M)
        self.assertIsNotNone(d)
        desc = norm(fm[d.end():])
        self.assertIn(norm(
            "There is no diminishing-returns stop: the loop ends only at the true "
            "terminus (every goal PROVEN, VIOLATION reported, or BUG IN FRAMA-C "
            "filed, and Gate T passes) and pauses at the deadline"), desc)
        # "The rest of the sentence ... is kept" (auto-wp.md 4.2.2).
        self.assertIn("never terminate early", desc)
        self.assertNotIn("budget per invocation", norm(text))
        self._report_and_deadline(text, "skills/time-loop/SKILL.md")

    def _report_and_deadline(self, text, name):
        n = norm(text)
        self.assertIn("`XXX.md`", text, f"{name}: report file XXX.md not named")
        self.assertIn("re-run keeps the original deadline", n,
                      f"{name}: no 'a re-run keeps the original deadline'")
        self.assertRegex(n, r"reuses the stored start and deadline",
                         f"{name}: does not say the stored deadline is reused")
        self.assertIn("--fresh", text, f"{name}: no --fresh for a new budget")

    # T7 (auto-wp.md 4.1, 4.2.1): the root scripts live in bin/ and are called there.
    def test_T7_scripts_in_bin(self):
        tools = [TEMPLATES / "common/tools", TEMPLATES / "c/tools"]
        common = sorted(p.name for p in (tools[0] / "bin").glob("*.sh"))
        self.assertEqual(common, ["rmf-lint.sh"])
        c_only = sorted(p.name for p in (tools[1] / "bin").glob("*.sh"))
        self.assertEqual(len(c_only), 21)
        names = sorted(common + c_only)
        self.assertEqual(len(names), 22)
        self.assertEqual(len(set(names)), 22, "a script in both layers")
        for t in tools:
            self.assertEqual(sorted(p.name for p in t.glob("*.sh")), [])
        self.assertEqual(sorted(p.name for p in (TEMPLATES / "rust/tools").iterdir()),
                         [".gitignore"])
        pat = re.compile(r"(?<![\w/.-])(?:\./)?(" + "|".join(map(re.escape, names)) + r")")
        bad = []
        for p in TEMPLATES.rglob("*"):
            if not p.is_file() or any(t in p.parents for t in tools):
                continue
            try:
                text = p.read_text()
            except UnicodeDecodeError:
                continue
            for m in pat.finditer(text):
                bad.append(f"{p.relative_to(TEMPLATES)}: {m.group(0)}")
        self.assertEqual(bad, [], "script referenced without its bin/ prefix")

    # T8 (auto-wp.md 3.7, 4.5): the workshop/ layer files.
    WORKSHOP_SDKS = {
        "c": ["frama-c-sdk", "rocq", "lean", "project-autowp-packages"],
        "rust": ["creusot", "rocq", "lean", "project-autowp-packages"],
    }

    def test_T8_workshop_layer(self):
        import shutil
        import subprocess
        for lang in ("c", "rust"):
            with self.subTest(lang=lang):
                ws = TEMPLATES / lang / "workshop"
                files = sorted(str(p.relative_to(ws)) for p in all_files(ws) if p.is_file())
                self.assertEqual(files, ["autowp-packages/hooks/setup-base",
                                         "autowp-packages/sdk.yaml", "autowp.yaml"])
                hook = ws / "autowp-packages/hooks/setup-base"
                self.assertTrue(os.access(hook, os.X_OK), "setup-base not executable")
                self.assertTrue(hook.read_text().startswith("#!/bin/bash\n"))
                text = (ws / "autowp.yaml").read_text()
                names = re.findall(r"(?m)^\s*-\s*name:\s*(\S+)", text)
                self.assertEqual(names, self.WORKSHOP_SDKS[lang])
                self.assertEqual(len(re.findall(r"(?m)^\s+channel:\s*latest/edge\s*(#.*)?$",
                                                text)), 3)
                self.assertRegex(text, r"(?m)^name: autowp$")
                self.assertRegex(text, r"(?m)^base: ubuntu@24\.04\b")
                self.assertRegex((ws / "autowp-packages/sdk.yaml").read_text(),
                                 r"(?m)^name: autowp-packages$")
                for p in all_files(ws):
                    if p.is_file():
                        t = p.read_text()
                        self.assertNotIn("sdks/", t, p.name)
                        self.assertNotIn("~/git/", t, p.name)
                        self.assertNotIn("{{", t, p.name)
                if shutil.which("shellcheck"):
                    r = subprocess.run(["shellcheck", str(hook)], capture_output=True, text=True)
                    self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                # The .gitignore of each layer lists .workshop.lock (3.7.4).
                gi = (TEMPLATES / lang / "tools/.gitignore").read_text()
                self.assertIn("/.workshop.lock", gi)
        for lang in ("c", "rust"):
            readme = (TEMPLATES / lang / "README.md").read_text()
            self.assertNotIn("~/git/use-frama-c", readme)


if __name__ == "__main__":
    unittest.main()
