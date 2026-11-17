#!/usr/bin/env python3
"""auto-wp: bootstrap a formal-verification project for C (Frama-C/WP) or Rust (Creusot).

Usage: ./auto-wp.py [-h] [--c|--rust] [--driver rmf|fips] [--level 1|2|3|4]
                   [--harness claude|opencode|copilot|none] [<directory-name>]

Missing language, harness and directory are asked interactively when both
stdin and stderr are terminals. Scripts must supply all three explicitly.

The generated project works with Claude Code and with OpenCode: both find the
same skills and commands through the links of §3.3. See spec/auto-wp.md.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

VERSION = "0.8.0"
TEMPLATES = Path(__file__).resolve().parent / "templates"
LANGUAGES = {"c": "C (Frama-C/WP)", "rust": "Rust (Creusot)"}
# The campaign driver (§2 of spec/fips-skill-spec.md): each driver installs its
# own campaign command and the other's is left out; everything else (both
# skills, both linters, the PDF) is installed whatever the driver.
DRIVERS = ["rmf", "fips"]
HARNESSES = ["claude", "opencode", "copilot", "none"]
DRIVER_COMMANDS = {"rmf": "rmf.md", "fips": "fips.md"}

# Links created in the project: (path relative to the project, link target).
# The first two harnesses are wired the same way: `config/` holds the skills
# and commands once, and each harness's directories link to it. `.agents`
# stays for the harnesses that look there (§3.3).
LINKS = [
    (".agents", "config"),
    (".claude/skills", "../config/skills"),
    (".claude/commands", "../config/commands"),
    (".opencode/skills", "../config/skills"),
    (".opencode/commands", "../config/commands"),
]
# Paths that must not exist before the run (§3.1 item 3).
RESERVED = ["config", ".agents", ".claude/skills", ".claude/commands",
            ".opencode/skills", ".opencode/commands",
            ".workshop/autowp.yaml", ".workshop/autowp-packages"]
# Directories that may pre-exist and are then reused (§3.1 item 3, §3.7.4).
REUSED_DIRS = [".claude", ".opencode", ".workshop"]
# The workshop definition written in .workshop/ (§3.7).
WORKSHOP_NAME = "autowp"


class AutoWpError(Exception):
    """A run-time error: reported on stderr, exit status 1."""


def prompt_choice(prompt, choices=None, error="Enter a project directory."):
    while True:
        sys.stderr.write(prompt + " ")
        sys.stderr.flush()
        line = sys.stdin.buffer.readline()
        if not line:
            raise AutoWpError("input ended before all required choices were provided")
        try:
            answer = line.decode(encoding="utf-8", errors="strict").strip()
        except UnicodeDecodeError:
            print("Input must be valid UTF-8.", file=sys.stderr)
            continue
        if choices is None and answer:
            return answer
        if choices is not None and answer in choices:
            return choices[answer]
        print(error, file=sys.stderr)


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="auto-wp.py",
        description="Create a project directory pre-loaded with the skills and "
        "commands of a formal-verification campaign.",
    )
    lang = parser.add_mutually_exclusive_group()
    lang.add_argument("--c", dest="language", action="store_const", const="c",
                      help="install the C configuration (Frama-C/WP); asked "
                      "interactively when omitted and stdin is a terminal")
    lang.add_argument("--rust", dest="language", action="store_const", const="rust",
                      help="install the Rust configuration (Creusot)")
    parser.add_argument("--driver", choices=DRIVERS, default="rmf",
                        help="which skill drives the campaign: rmf (NIST RMF, "
                        "the default) or fips (FIPS 140-3)")
    parser.add_argument("--level", type=int, choices=[1, 2, 3, 4], default=None,
                        help="the target FIPS 140-3 security level; required "
                        "with --driver fips, refused otherwise (Ann. 7: the "
                        "level is chosen, never defaulted)")
    parser.add_argument("--harness", choices=HARNESSES,
                        help="agent harness; asked interactively when omitted "
                        "and stdin is a terminal; none leaves "
                        "installation to you")
    parser.add_argument("directory", metavar="<directory-name>", nargs="?",
                        help="project directory to create (or to fill, if it exists)")
    args = parser.parse_args(argv)
    if args.driver == "fips" and args.level is None:
        parser.error("--driver fips needs --level 1, 2, 3 or 4")
    if args.driver != "fips" and args.level is not None:
        parser.error("--level is only valid with --driver fips")
    missing = [label for value, label in (
        (args.language, "--c/--rust"), (args.harness, "--harness"),
        (args.directory, "<directory-name>")) if value is None]
    if missing and not (sys.stdin.isatty() and sys.stderr.isatty()):
        parser.error(f"missing {', '.join(missing)} "
                     "(not prompting: stdin or stderr is not a terminal)")
    if args.language is None:
        args.language = prompt_choice(
            "Choose the language:\n"
            "1. C (Frama-C/WP)\n"
            "2. Rust (Creusot)\n"
            "Type 1 or 2:",
            {"1": "c", "2": "rust"}, "Type 1 or 2.")
    if args.harness is None:
        args.harness = prompt_choice(
            "Choose the agent harness:\n"
            "1. Claude Code (claude)\n"
            "2. OpenCode (opencode)\n"
            "3. GitHub Copilot (copilot)\n"
            "4. None (install a harness manually inside Workshop)\n"
            "Type 1, 2, 3 or 4:",
            {"1": "claude", "2": "opencode", "3": "copilot", "4": "none"},
            "Type 1, 2, 3 or 4.")
    if args.directory is None:
        args.directory = prompt_choice("Project directory:")
    return args


class Run:
    """One invocation. Records what it creates so it can be rolled back."""

    def __init__(self, directory, language, harness, driver="rmf", level=None):
        self.arg = directory
        self.target = Path(directory)
        self.language = language
        self.driver = driver
        self.level = level
        self.harness = harness
        self.layers = [TEMPLATES / "common", TEMPLATES / language]
        self.created = []  # (kind, path) in creation order
        self.out = []      # stdout lines, printed only on success
        self.warnings = []

    def show(self, rel):
        """A path inside the target, written as given on the command line."""
        return os.path.join(self.arg, rel)

    # --- steps ------------------------------------------------------------

    def check_templates(self):
        for layer in self.layers:
            if not layer.is_dir():
                raise AutoWpError(f"missing template directory {layer}")

    def check_target(self):
        t = self.target
        if os.path.lexists(t) and not t.is_dir():
            raise AutoWpError(f"{self.arg} exists and is not a directory")
        if not t.exists():
            return
        for rel in RESERVED:
            if os.path.lexists(t / rel):
                raise AutoWpError(f"{self.show(rel)} already exists")
        for rel in REUSED_DIRS:
            d = t / rel
            if os.path.lexists(d) and not d.is_dir():
                raise AutoWpError(f"{self.show(rel)} exists and is not a directory")

    def make_target(self):
        missing = []
        p = Path(os.path.abspath(self.target))
        while not os.path.lexists(p):
            missing.append(p)
            p = p.parent
        for d in reversed(missing):
            self.created.append(("dir", d))
            d.mkdir()

    def install_config(self):
        config = self.target / "config"
        self.created.append(("tree", config))
        config.mkdir()
        skills = self.copy_skills(config / "skills")
        commands = self.copy_commands(config / "commands")
        manifest = {
            "language": self.language,
            "auto_wp_version": VERSION,
            "driver": self.driver,
            "harness": self.harness,
            "created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "skills": skills,
            "commands": commands,
        }
        if self.driver == "fips":
            manifest["fips_level"] = self.level
        (config / "auto-wp.json").write_text(json.dumps(manifest, indent=2) + "\n")
        if self.driver == "fips":
            driver_line = f"  driver:   {self.driver} (FIPS 140-3 level {self.level})"
        else:
            driver_line = f"  driver:   {self.driver}"
        self.out += [
            f"created {self.show('config')} (language: {self.language})",
            driver_line,
            f"  harness:  {self.harness}",
            f"  skills:   {len(skills)}",
            f"  commands: {len(commands)}",
        ]

    def copy_skills(self, dest):
        """Copy skill directories; a language-layer skill replaces the common one whole."""
        chosen = {}
        for layer in self.layers:
            src = layer / "skills"
            if src.is_dir():
                for skill in src.iterdir():
                    if skill.is_dir() and not skill.name.startswith("."):
                        chosen[skill.name] = skill
        dest.mkdir()
        for name in sorted(chosen):
            shutil.copytree(chosen[name], dest / name, symlinks=True,
                            ignore=shutil.ignore_patterns("*~"))
        return sorted(chosen)

    def copy_commands(self, dest):
        """Copy command files (*.md); a language-layer file replaces the common one.

        Each driver installs its own campaign command only (§6 of
        spec/fips-skill-spec.md): rmf.md under --driver rmf, fips.md under
        --driver fips; the other driver's file is skipped here. Both skills
        and both linters are installed whatever the driver.
        """
        skip = {DRIVER_COMMANDS[d] for d in DRIVERS if d != self.driver}
        chosen = {}
        for layer in self.layers:
            src = layer / "commands"
            if src.is_dir():
                for f in src.glob("*.md"):
                    if f.name in skip:
                        continue
                    chosen[f.name] = f
        dest.mkdir()
        for name in sorted(chosen):
            shutil.copy2(chosen[name], dest / name, follow_symlinks=False)
        return sorted(Path(n).stem for n in chosen)

    def install_tools(self):
        """Copy each layer's tools/ entries to the project root; keep existing ones.

        A directory present in several layers (bin/, §4.1) is merged: the
        language layer's files are added to the common layer's and replace
        those with the same name. A file entry is the language layer's.
        """
        chosen = {}  # entry name -> its entries, one per layer that has it
        for layer in self.layers:
            src = layer / "tools"
            if src.is_dir():
                for entry in src.iterdir():
                    if not entry.name.endswith("~"):
                        chosen.setdefault(entry.name, []).append(entry)
        for name in sorted(chosen):
            dest = self.target / name
            if os.path.lexists(dest):
                self.out.append(f"kept    {self.show(name)} (already exists)")
                continue
            entries = chosen[name]
            if entries[-1].is_dir() and not entries[-1].is_symlink():
                self.created.append(("tree", dest))
                for entry in entries:
                    if entry.is_dir() and not entry.is_symlink():
                        shutil.copytree(entry, dest, symlinks=True, dirs_exist_ok=True,
                                        ignore=shutil.ignore_patterns("*~"))
            else:
                self.created.append(("file", dest))
                shutil.copy2(entries[-1], dest, follow_symlinks=False)
            self.out.append(f"copied  {self.show(name)}")

    def install_workshop(self):
        """Copy the language layer's workshop/ into .workshop/ (§3.7).

        Its entries are reserved (§3.1 item 3), so none exists here; an
        existing .workshop/ directory is reused and its other entries kept.
        """
        src = TEMPLATES / self.language / "workshop"
        if not src.is_dir():
            return
        dest_dir = self.target / ".workshop"
        if not dest_dir.is_dir():
            self.created.append(("dir", dest_dir))
            dest_dir.mkdir()
        for entry in sorted(src.iterdir()):
            if entry.name.endswith("~"):
                continue
            dest = dest_dir / entry.name
            if entry.is_dir() and not entry.is_symlink():
                self.created.append(("tree", dest))
                shutil.copytree(entry, dest, symlinks=True,
                                ignore=shutil.ignore_patterns("*~"))
            else:
                self.created.append(("file", dest))
                shutil.copy2(entry, dest, follow_symlinks=False)
        if self.harness != "none":
            hook = dest_dir / "autowp-packages/hooks/setup-base"
            snippet = (TEMPLATES / "common/harness" / f"{self.harness}.sh").read_text()
            hook.write_text(hook.read_text() + "\n" + snippet)
        self.out.append(f"copied  {self.show('.workshop')} (workshop: {WORKSHOP_NAME})")

    def link(self):
        width = len(self.show(max((rel for rel, _ in LINKS), key=len)))
        for rel, dest in LINKS:
            path = self.target / rel
            parent = path.parent
            if not parent.is_dir():
                self.created.append(("dir", parent))
                parent.mkdir()
            self.created.append(("file", path))
            path.symlink_to(dest)
            self.out.append(f"linked  {self.show(rel).ljust(width)} -> {dest}")

    def write_readme(self):
        readme = self.target / "README.md"
        if os.path.lexists(readme):
            self.out.append(f"kept    {self.show('README.md')} (already exists)")
            return
        text = (TEMPLATES / self.language / "README.md").read_text()
        harness_text = {
            "claude": (
                "Claude Code",
                "command -v claude >/dev/null || "
                "curl -fsSL https://claude.ai/install.sh | bash",
                "claude --dangerously-skip-permissions",
                "On first start, log in using the URL and code printed by Claude Code. "
                "Login stays in the container. Never copy the host's "
                "`~/.claude/.credentials.json` into it.",
                "Outside a container, omit `--dangerously-skip-permissions` "
                "and approve actions individually.",
            ),
            "opencode": (
                "OpenCode",
                "command -v opencode >/dev/null || "
                "curl -fsSL https://opencode.ai/v2/install | bash",
                "opencode service set disabled true\nopencode",
                "OpenCode V2 is required (`opencode --version`); the older "
                "`opencode.ai/install` endpoint installs V1. On first start, "
                "run `/connect` and `/models`. Anthropic requires "
                "an API key, not a Claude subscription token; OpenRouter also uses "
                "an API key. The connection is stored in the container's OpenCode "
                "database (`opencode debug paths`), not necessarily `auth.json`. "
                "Never copy the host's OpenCode data directory into it. "
                "Type `/` to list project commands. OpenCode allows actions by "
                "default; add `permissions` rules to `opencode.json` to require approval.",
                "Outside a container, add `permissions` rules to `opencode.json` "
                "to require approval; the default policy allows actions.",
            ),
            "copilot": (
                "GitHub Copilot CLI",
                'export PATH="$HOME/.local/bin:$PATH"\n'
                "command -v copilot >/dev/null || "
                "curl -fsSL https://gh.io/copilot-install | bash",
                "copilot --disable-builtin-mcps --sync-session=off",
                "Inside the container, run `copilot login --device-code` and "
                "complete the displayed authorization in your host browser. "
                "Login is stored in the container's credential store, or in "
                "plaintext under `~/.copilot/` if no credential store is available. "
                "Never copy the host's `~/.copilot/` or credentials into it. "
                "Your account and organization policy must allow Copilot CLI; "
                "model requests consume your account's allowance. The start "
                "command disables built-in MCP servers and account session sync, "
                "and keeps trust and tool-approval prompts enabled. Do not use "
                "`/delegate`, `/share` or `/remote` for campaign source code.",
                "Outside a container, keep trust and tool-approval prompts enabled; "
                "do not use `--allow-all` or `--allow-all-tools`.",
            ),
            "none": (
                "a manually installed harness", "", "",
                "No agent harness is installed. Inside `workshop shell` (or the "
                "LXD container), install a harness that reads `.agents/skills`, "
                "`.claude/skills` or `.opencode/skills`. Start it in the `tmux` "
                "session and log in inside the container. Never copy a host "
                "credential into it. Adapt the next step if your harness cannot "
                "load the project commands; load the `time-loop` skill explicitly.",
                "Choose a permission policy that asks before acting when running "
                "outside a container.",
            ),
        }[self.harness]
        for key, value in zip(
                ("HARNESS", "HARNESS_INSTALL", "HARNESS_START", "HARNESS_LOGIN",
                 "HARNESS_HOST"), harness_text):
            text = text.replace("{{" + key + "}}", value)
        manual_note = ""
        if self.harness == "copilot":
            skill = "frama-c" if self.language == "c" else "creusot"
            manual_note = (
                "**Copilot: manual use only.** Installation and skill discovery "
                "are supported, but automated Copilot campaigns are not yet "
                "enabled. In the CLI, ask it to "
                f"`Load the {skill} skill` and give it a task you supervise. "
                "The campaign instructions in the rest of this README are for "
                "Claude Code and OpenCode, not Copilot: skip their `/time-loop` "
                "quick start. No Copilot watchdog is installed, so do not rely on "
                "the session to continue unattended or enforce a campaign deadline.")
        text = text.replace("{{HARNESS_CAMPAIGN_NOTE}}", manual_note)
        text = text.replace("{{DIR}}", self.target.resolve().name)
        text = text.replace("{{LANGUAGE}}", LANGUAGES[self.language])
        if self.driver == "fips":
            text = text.replace("{{DRIVER}}", "fips")
            text = text.replace("{{FEEDBACK}}", "fips-feedback")
            text = text.replace("{{DRIVER_LINE}}",
                                f"Requirement study: FIPS 140-3, security level "
                                f"{self.level} (fips-sl).")
        else:
            text = text.replace("{{DRIVER}}", "rmf")
            text = text.replace("{{FEEDBACK}}", "monitor-feedback")
            text = text.replace("{{DRIVER_LINE}}", "Risk study: NIST RMF (rmf-sl).")
        if self.driver == "fips" and self.language == "c":
            # fips-skill-spec.md 7.3: the one fips sentence after the
            # quick-start command (GRUB as a whole is not a module; its crypto
            # library is). Inserted, not a placeholder, so the README
            # templates carry only the placeholders of §3.4.
            anchor = "/time-loop grub 72\n```"
            note = ("\n\nTo study GRUB's cryptographic library as the module, "
                    "use `/time-loop grub 72 --dir=grub-core/lib/libgcrypt`.")
            if anchor in text:
                text = text.replace(anchor, anchor + note, 1)
        self.created.append(("file", readme))
        readme.write_text(text)
        self.out.append(f"wrote   {self.show('README.md')}")

    def init_git(self):
        if shutil.which("git") is None:
            self.warnings.append(
                f"warning: git not found; run 'git init -b main' in {self.arg} before /time-loop")
            return
        probe = subprocess.run(
            ["git", "-C", str(self.target), "rev-parse", "--is-inside-work-tree"],
            capture_output=True, text=True)
        if probe.returncode == 0 and probe.stdout.strip() == "true":
            self.out.append(f"git     {self.arg} is already in a git work tree")
            return
        dot_git = self.target / ".git"
        if not os.path.lexists(dot_git):
            self.created.append(("tree", dot_git))
        result = subprocess.run(["git", "init", "-q", "-b", "main", str(self.target)],
                                capture_output=True, text=True)
        if result.returncode != 0:
            raise AutoWpError(f"git init failed: {result.stderr.strip()}")
        self.out.append(f"git     initialized {self.arg}")

    # --- driver -----------------------------------------------------------

    def execute(self):
        self.check_templates()
        self.check_target()
        self.make_target()
        self.install_config()
        self.install_tools()
        self.install_workshop()
        self.link()
        self.write_readme()
        self.init_git()

    def rollback(self):
        """Remove what this run created, newest first; never touch anything older."""
        for kind, path in reversed(self.created):
            try:
                if kind == "tree":
                    if os.path.lexists(path):
                        shutil.rmtree(path)
                elif kind == "file":
                    if os.path.lexists(path):
                        path.unlink()
                elif kind == "dir":
                    path.rmdir()  # only succeeds if empty
            except OSError:
                pass


def main(argv=None):
    run = None
    try:
        args = parse_args(argv)
        run = Run(args.directory, args.language, args.harness, args.driver, args.level)
        run.execute()
        print("\n".join(run.out))
        for w in run.warnings:
            print(w, file=sys.stderr)
    except KeyboardInterrupt:
        if run is not None:
            run.rollback()
        print("auto-wp: cancelled", file=sys.stderr)
        return 130
    except (AutoWpError, OSError, subprocess.SubprocessError) as e:
        if run is not None:
            run.rollback()
        if isinstance(e, shutil.Error) and e.args and isinstance(e.args[0], list):
            e = e.args[0][0][2]  # copytree's error list: report the first failure
        print(f"auto-wp: error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
