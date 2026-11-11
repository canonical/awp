"""Level 1 template checks T1-T13 (tests.md 3.2).

auto-wp.py copies the templates byte for byte, so these check the template
files themselves, on the host. They only read templates/ (and, for part of
T4, ../use-creusot/config/foo/ when that checkout exists) — except T10-T12,
which run the shipped linter/ratchet/generator scripts on fixtures in a
temporary directory (tests.md 3.2).
"""

import hashlib
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
TEMPLATES = REPO / "templates"
USE_CREUSOT = Path(os.environ.get("USE_CREUSOT", REPO.parent / "use-creusot"))

COMMON_SKILLS = [
    "directory-structure", "ebios-risk-manager", "ebios-sl", "fips-sl", "lean",
    "polish-skill", "rmf-sl", "rocq", "sl-auditor", "sl-builder",
    "sl-internal", "sl-monitoring-sl", "stride", "workshop",
]
C_LAYER_SKILLS = [
    "frama-c", "frama-c-api", "frama-c-internals", "frama-c-launch",
    "frama-c-monitoring", "framac-sl", "linux-api", "ocaml", "time-loop",
]
C_COMMANDS = ["ebios", "fips", "rmf", "time-loop"]
RUST_COMMANDS = ["time-loop"]
RUST_LAYER_SKILLS = [
    "creusot", "creusot-launch", "creusot-monitoring", "creusot-sl",
    "sl-auditor", "sl-builder", "sl-internal", "sl-monitoring-sl", "time-loop",
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

    def test_agent_skills_frontmatter(self):
        class UniqueLoader(yaml.SafeLoader):
            pass

        def mapping(loader, node):
            result = {}
            for key, value in node.value:
                key = loader.construct_object(key)
                if key in result:
                    raise ValueError(f"duplicate YAML key: {key}")
                result[key] = loader.construct_object(value)
            return result

        UniqueLoader.add_constructor(
            yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)
        for path in TEMPLATES.glob("*/skills/*/SKILL.md"):
            with self.subTest(path=path):
                data = yaml.load(front_matter(path.read_text()), Loader=UniqueLoader)
                self.assertEqual(data["name"], path.parent.name)
                self.assertIsInstance(data["description"], str)
                self.assertTrue(1 <= len(data["description"]) <= 1024)
        self.assertEqual(list(TEMPLATES.glob("**/.github/hooks")), [])

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
        self.assertEqual(len(skills("common")), 14)
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
        self.assertEqual(commands("rust"), RUST_COMMANDS)
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
        # fips-skill-spec.md 7.3: the three placeholders {{DRIVER}},
        # {{FEEDBACK}} and {{DRIVER_LINE}} join {{DIR}}/{{LANGUAGE}} in the C
        # README ({{DRIVER_LINE}} only in Rust). The fips-only sentence after
        # the quick-start command is inserted by the program, not a placeholder.
        expected = {"c": {"DIR", "LANGUAGE", "DRIVER", "FEEDBACK", "DRIVER_LINE"},
                    "rust": {"DIR", "LANGUAGE", "DRIVER_LINE"}}
        for placeholders in expected.values():
            placeholders.update({"HARNESS", "HARNESS_INSTALL", "HARNESS_START",
                                 "HARNESS_LOGIN", "HARNESS_HOST", "HARNESS_CAMPAIGN_NOTE"})
        for lang in ("c", "rust"):
            with self.subTest(lang=lang):
                text = (TEMPLATES / lang / "README.md").read_text()
                found = set(re.findall(r"\{\{(.*?)\}\}", text, re.S))
                self.assertEqual(found, expected[lang])
                stripped = text
                for ph in expected[lang]:
                    stripped = stripped.replace("{{%s}}" % ph, "")
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

    def test_T6_rust_time_loop(self):
        """The Rust /time-loop (auto-wp.md 4.3.7 step 5): same contract as the C one."""
        cmd = (TEMPLATES / "rust/commands/time-loop.md").read_text()
        skill = (TEMPLATES / "rust/skills/time-loop/SKILL.md").read_text()
        for text, name in ((cmd, "rust commands/time-loop.md"),
                           (skill, "rust skills/time-loop/SKILL.md")):
            with self.subTest(name=name):
                self._report_and_deadline(text, name)
                n = norm(text)
                self.assertNotIn("diminishing returns)", n)
                self.assertRegex(text, r"[Nn]ever run `cargo`", "XXX/ must stay pristine")
                self.assertIn("XXX-creusot/time-loop.state", text)
        fm = front_matter(skill)
        self.assertIsNotNone(fm)
        self.assertRegex(fm, r"(?m)^name: time-loop$")
        d = re.search(r"^description: >-\n((?:  .*\n)+)", fm + "\n", re.M)
        self.assertIsNotNone(d)
        desc = " ".join(l.strip() for l in d.group(1).splitlines())
        self.assertLessEqual(len(desc), 1024, "description over the Agent Skills limit")
        self.assertIn("There is no diminishing-returns stop", desc)
        n = norm(skill)
        # The pinned state lines and ledger header are those of the C skill (tests/test_harness.py).
        for pinned in ("`start=<epoch>`", "`deadline=<epoch>`", "`wake=<epoch>`", "`cycle <n>: `"):
            self.assertIn(pinned, skill, pinned)
        self.assertIn("`unit\tSA#\tfunction\tverdict\tgoals\tnotes`", skill)
        for rule in ("TIME BOX — 45 minutes", "at most `nproc / 2`", "No no-op cycle",
                     "never verifies inline", "commit and push"):
            self.assertIn(norm(rule), n, rule)
        self.assertIn("/time-loop sudo-rs 96", cmd)

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
        self.assertEqual(len(c_only), 22)
        names = sorted(common + c_only)
        self.assertEqual(len(names), 23)
        self.assertEqual(len(set(names)), 23, "a script in both layers")
        # The vendored PDF ships in the common layer's tools/ (fips-skill-spec.md 6).
        self.assertEqual(sorted(p.name for p in tools[0].iterdir() if p.is_file()),
                         ["NIST.FIPS.140-3.pdf"])
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


class TestFipsSkill(unittest.TestCase):
    """T9-T13 (fips-skill-spec.md 4, 5, 7.1; tests.md 3.2): the fips-sl skill,
    its linter, the ledger ratchet and the crosswalk generator."""

    FIPS_SL = TEMPLATES / "common/skills/fips-sl"
    FIPS_LINT = TEMPLATES / "c/tools/bin/fips-lint.sh"
    PDF_SHA256 = "942a4f929dfbd2b4af2e4e03df7f6e6377054346afd9bee346ed0ebac5db384b"

    def run_script(self, script, *args, cwd=None, env=None):
        e = dict(os.environ)
        if env:
            e.update(env)
        return subprocess.run([str(script), *args], capture_output=True, text=True,
                              cwd=cwd, env=e)

    # T9
    def test_T9_fips_sl_skill(self):
        text = (self.FIPS_SL / "SKILL.md").read_text()
        fm = front_matter(text)
        self.assertIsNotNone(fm, "SKILL.md does not start with a YAML front matter")
        m = re.search(r"^name:\s*(\S+)\s*$", fm, re.M)
        self.assertIsNotNone(m, "no name: in front matter")
        self.assertEqual(m.group(1), "fips-sl")
        for ref in ("references/report-format.md", "references/skeleton.md",
                    "references/area-properties.md", "references/crosswalk-format.md"):
            self.assertTrue((self.FIPS_SL / ref).is_file(), ref)
        # The SL registry passes the mechanical disjointness check (single-loop mode).
        checker = TEMPLATES / "common/skills/sl-internal/scripts/sl_disjointness_check.py"
        r = subprocess.run(["python3", str(checker), str(self.FIPS_SL / "fips-sl.sl.json")],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        # The vendored PDF is the spec's document, byte for byte.
        digest = hashlib.sha256(
            (TEMPLATES / "common/tools/NIST.FIPS.140-3.pdf").read_bytes()).hexdigest()
        self.assertEqual(digest, self.PDF_SHA256)
        # The skeleton fixture shown in report-format.md is the fixture file.
        rf = (self.FIPS_SL / "references/report-format.md").read_text()
        block = re.search(r"~~~markdown\n(.*?)~~~", rf, re.S).group(1)
        self.assertEqual(block, (self.FIPS_SL / "references/skeleton.md").read_text())

    # T10
    BROKEN = [
        ("dup-rq", "F-C0",
         ["employs only Approved security functions.==>employs only Approved security functions.\n"
          "- RQ1 — AR1 — src:PDF-ann10 — duplicate home line"]),
        ("no-f4", "F-C1", ["## F4 — Verification obligations==>## F4removed — Verification obligations"]),
        ("level2", "F-C2", ["level: 3==>level: 2"]),
        ("no-ar6", "F-C3", ["- AR6 N/A — software-only module, no physical enclosure.==>"]),
        ("no-src", "F-C4",
         ["- RQ2 — AR2 — src:UNSOURCED — no data output while MOD1 is in an error or self-test state.==>"
          "- RQ2 — AR2 — no data output while MOD1 is in an error or self-test state."]),
        ("bad-src", "F-C5", ["RQ2 — AR2 — src:UNSOURCED==>RQ2 — AR2 — src:PDF-ann1"]),
        ("vo-no-rq", "F-C6", ["- VO1 — FM1 — RQ5 — zeroize==>- VO1 — FM1 — zeroize"]),
        ("minmax", "F-C7", ["min-level 2==>min-level 4"]),
        ("no-sc", "F-C8",
         ["- RR8 — AR7 — plane side-channel — treatment: constant-time tooling and leakage "
          "assessment, not WP — STANDING.==>"]),
        ("code-art", "F-C9",
         ["software-only module, no physical enclosure.==>software-only module, no physical "
          "enclosure; see parser.c."]),
    ]

    def test_T10_fips_lint(self):
        skeleton = self.FIPS_SL / "references/skeleton.md"
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "config").mkdir()
            (tmp / "config/auto-wp.json").write_text(
                json.dumps({"driver": "fips", "fips_level": 3}))
            r = self.run_script(self.FIPS_LINT, skeleton, cwd=tmp)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("FIPS-LINT PASS", r.stdout)
            for name, want, edits in self.BROKEN:
                with self.subTest(canary=name):
                    text = skeleton.read_text()
                    for e in edits:
                        old, new = e.split("==>", 1)
                        self.assertIn(old, text, f"canary edit target missing: {name}")
                        text = text.replace(old, new, 1)
                    br = tmp / f"broken-{name}.md"
                    br.write_text(text)
                    r = self.run_script(self.FIPS_LINT, br, cwd=tmp)
                    self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                    fails = sorted(set(re.findall(r"FAIL (F-C\d+)", r.stdout)))
                    self.assertEqual(fails, [want],
                                     f"canary {name} must fail with {want} alone")
            # The manifest is required when FIPS_LEVEL is not set; FIPS_LEVEL overrides it.
            (tmp / "config/auto-wp.json").write_text("{}")
            r = self.run_script(self.FIPS_LINT, skeleton, cwd=tmp)
            self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
            self.assertIn("fips_level", r.stderr)
            r = self.run_script(self.FIPS_LINT, skeleton, cwd=tmp, env={"FIPS_LEVEL": "3"})
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    # T11
    FIPS_XWALK = """# FIPS 140-3 crosswalk — test

## 3. Coverage ledger — VO# × obligation

# ledger: fips

| VO# | AR# | Class | Coverage |
|---|---|---|---|
| VO1 | AR8 | zeroize | `PROVED` |
| VO2 | AR2 | output-inhibit | `TRUSTED-PENDING` |
| VO3 | AR9 | selftest-order | `UNMODELED` |
"""

    def test_T11_ledger_ratchet_fips(self):
        ratchet = TEMPLATES / "c/tools/bin/ledger-ratchet.sh"
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            xw = tmp / "t-crosswalk.md"
            xw.write_text(self.FIPS_XWALK)
            base = tmp / "t-crosswalk.md.ledger-baseline.tsv"
            # Bootstrap: the baseline's first line is '# ledger: fips'.
            r = self.run_script(ratchet, xw, cwd=tmp)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("bootstrap", r.stdout)
            self.assertTrue(base.read_text().startswith("# ledger: fips"))
            self.assertIn("VO1\tPROVED", base.read_text())
            # A PROVED cell backsliding to UNMODELED FAILS after the round trip.
            xw.write_text(self.FIPS_XWALK.replace("| VO1 | AR8 | zeroize | `PROVED` |",
                                                  "| VO1 | AR8 | zeroize | `UNMODELED` |"))
            r = self.run_script(ratchet, xw, cwd=tmp)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("RATCHET regression", r.stdout)
            # TRUSTED-PENDING only warns.
            xw.write_text(self.FIPS_XWALK.replace("| VO1 | AR8 | zeroize | `PROVED` |",
                                                  "| VO1 | AR8 | zeroize | `TRUSTED-PENDING` |"))
            r = self.run_script(ratchet, xw, cwd=tmp)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("WARN", r.stdout)
            # The WS1 race rule is a STRIDE rule: a header cell named "race" with a
            # PROVED FIPS row passes.
            xw.write_text(self.FIPS_XWALK.replace("| VO# | AR# | Class | Coverage |",
                                                  "| VO# | AR# | Class (race) | Coverage |"))
            r = self.run_script(ratchet, xw, cwd=tmp)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            # A STRIDE baseline (first line '# ledger-baseline.tsv') is not a FIPS one.
            base.write_text("# ledger-baseline.tsv — frozen STRIDE ledger (crosswalk-template §3.2)\n"
                            "SA1\tUNMODELED\tPROVED\tUNMODELED\tUNMODELED\tUNMODELED\tUNMODELED\n")
            r = self.run_script(ratchet, xw, cwd=tmp)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("not a FIPS baseline", r.stdout)
        # The STRIDE path still reads its seven-column baseline (T9b's last case).
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            xw = tmp / "s-crosswalk.md"
            xw.write_text("# stride crosswalk\n\n| Asset | S | T | R | I | D | E | ATT&CK |\n"
                          "|---|---|---|---|---|---|---|---|\n"
                          "| SA1 | `UNMODELED` | `PROVED` | `UNMODELED` | `UNMODELED` | "
                          "`UNMODELED` | `UNMODELED` | |\n")
            r = self.run_script(ratchet, xw, cwd=tmp)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            base = Path(r.stdout.split("baseline at '")[1].split("'")[0]) \
                if "baseline at '" in r.stdout else tmp / "s-crosswalk.md.ledger-baseline.tsv"
            self.assertTrue(base.exists())
            self.assertTrue(base.read_text().startswith("# ledger-baseline.tsv"))
            self.assertRegex(base.read_text(), r"SA1\tUNMODELED\tPROVED")

    # T12
    def _fips_fixture(self, tmp):
        (tmp / "mbed-analysis-acsl").mkdir(parents=True, exist_ok=True)
        shutil_copy = (self.FIPS_SL / "references/skeleton.md").read_text()
        (tmp / "mbed-analysis-fips-report.md").write_text(shutil_copy)
        (tmp / "mbed-analysis-acsl/verdicts.tsv").write_text(
            "VO#\tverdict\tunit\tgoals\tnotes\n"
            "VO1\tPROVED 12/12\tcipher_free\t12/12\tfaithful\n"
            "VO2\tUNMODELED\t-\t-\tBLOCKED row\n")
        (tmp / "mbed-analysis-acsl/fips-ledger.tsv").write_text(
            "VO1\tAR8\tzeroize\tPROVED\n"
            "VO2\tAR2\toutput-inhibit\tUNMODELED\n")

    def test_T12_crosswalk_gen_fips(self):
        gen = TEMPLATES / "c/tools/bin/crosswalk-gen.sh"
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            self._fips_fixture(tmp)
            # Kind auto-detected from the report; --kind fips explicit as well.
            for args in ([], ["--kind", "fips"]):
                for p in tmp.glob("mbed-analysis-crosswalk.md"):
                    p.unlink()
                r = self.run_script(gen, "mbed-analysis", *args, cwd=tmp)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                xw = tmp / "mbed-analysis-crosswalk.md"
                self.assertIn("kind=fips", r.stdout)
                self.assertIn("# ledger: fips", xw.read_text())
                self.assertRegex(xw.read_text(), r"\| \*\*VO1\*\* \| .* \| `cipher_free` \| ")
                self.assertIn("| VO1 | AR8 | zeroize | PROVED |", xw.read_text())
                self.assertIn("| VO1 | FM1 | RQ5 | zeroize | P1 |", xw.read_text())
            # A fabricated PROVED fails generation (no-blend, enforced).
            (tmp / "mbed-analysis-acsl/fips-ledger.tsv").write_text(
                "VO1\tAR8\tzeroize\tPROVED\nVO2\tAR2\toutput-inhibit\tPROVED\n")
            r = self.run_script(gen, "mbed-analysis", cwd=tmp)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("FAITHFULNESS FAIL", r.stderr)
            # Drift: --check fails when the committed crosswalk is out of sync.
            self._fips_fixture(tmp)
            self.run_script(gen, "mbed-analysis", cwd=tmp)
            (tmp / "mbed-analysis-acsl/fips-ledger.tsv").write_text(
                "VO1\tAR8\tzeroize\tPROVED\nVO2\tAR2\toutput-inhibit\tTRUSTED\n")
            r = self.run_script(gen, "mbed-analysis", "--check", cwd=tmp)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("DRIFT", r.stderr)
        # The RMF and EBIOS kinds still detect as before.
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "w-analysis-acsl").mkdir(parents=True)
            (tmp / "w-analysis-rmf-report.md").write_text(
                "- SA1 cert parser: X.509\n"
                "- RS1: TE1 exploits VU1 → corruption; covers IM1 — likelihood L3 — "
                "risk High — control CTL1.\n- RR1 — spoofing residual\n")
            (tmp / "w-analysis-acsl/verdicts.tsv").write_text(
                "SA#\tverdict\tunit\tgoals\nSA1\tValid 5/5\tasn1.c\t5/5\n")
            (tmp / "w-analysis-acsl/stride-ledger.tsv").write_text(
                "SA\tS\tT\tR\tI\tD\tE\tattack\n"
                "SA1\tUNMODELED\tPROVED\tUNMODELED\tUNMODELED\tUNMODELED\tUNMODELED\t\n")
            r = self.run_script(gen, "w-analysis", cwd=tmp)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("kind=rmf", r.stdout)

    # T10 of fips-skill-spec.md 8 (here T13): the F-C5 section list matches the PDF.
    def test_T13_pdf_sections(self):
        import shutil
        if not shutil.which("pdftotext"):
            self.skipTest("pdftotext not installed")
        pdf = TEMPLATES / "common/tools/NIST.FIPS.140-3.pdf"
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "fips.txt"
            subprocess.run(["pdftotext", "-layout", str(pdf), str(out)], check=True)
            text = out.read_text()
        # The four sections a requirement may cite hold their normative text
        # (fips-skill-spec.md 1, verbatim quotes verified by the reviews).
        for needle in ("This standard shall be used in designing and implementing cryptographic modules",
                       "must be chosen to provide a level of security appropriate",
                       "shall employ Approved security functions",
                       "is not sufficient to ensure that a particular module is secure"):
            self.assertIn(needle, text, needle)
        # The eleven areas and the four level names are in the PDF.
        for area in ("cryptographic module specification", "self-tests", "life-cycle assurance",
                     "mitigation of other attacks"):
            self.assertIn(area, text, area)
        for lvl in ("Level 1", "Level 2", "Level 3", "Level 4"):
            self.assertIn(lvl, text, lvl)


if __name__ == "__main__":
    unittest.main()
