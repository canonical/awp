#!/usr/bin/env python3
"""auto-wp: bootstrap a formal-verification project for C (Frama-C/WP) or Rust (Creusot).

Usage: ./auto-wp.py [--c|--rust] <directory-name>

See spec/auto-wp.md for the specification.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

VERSION = "0.1.0"
TEMPLATES = Path(__file__).resolve().parent / "templates"
LANGUAGES = {"c": "C (Frama-C/WP)", "rust": "Rust (Creusot)"}

# Links created in the project: (path relative to the project, link target).
LINKS = [
    (".agents", "config"),
    (".claude/skills", "../config/skills"),
    (".claude/commands", "../config/commands"),
]
# Paths that must not exist before the run (§3.1 item 3).
RESERVED = ["config", ".agents", ".claude/skills", ".claude/commands"]


class AutoWpError(Exception):
    """A run-time error: reported on stderr, exit status 1."""


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="auto-wp.py",
        description="Create a project directory pre-loaded with the skills and "
        "commands of a formal-verification campaign.",
    )
    lang = parser.add_mutually_exclusive_group()
    lang.add_argument("--c", dest="language", action="store_const", const="c",
                      help="install the C configuration (Frama-C/WP); the default")
    lang.add_argument("--rust", dest="language", action="store_const", const="rust",
                      help="install the Rust configuration (Creusot)")
    parser.add_argument("directory", metavar="<directory-name>",
                        help="project directory to create (or to fill, if it exists)")
    parser.set_defaults(language="c")
    return parser.parse_args(argv)


class Run:
    """One invocation. Records what it creates so it can be rolled back."""

    def __init__(self, directory, language):
        self.arg = directory
        self.target = Path(directory)
        self.language = language
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
        claude = t / ".claude"
        if os.path.lexists(claude) and not claude.is_dir():
            raise AutoWpError(f"{self.show('.claude')} exists and is not a directory")

    def make_target(self):
        missing = []
        p = Path(os.path.abspath(self.target))
        while not os.path.lexists(p):
            missing.append(p)
            p = p.parent
        for d in reversed(missing):
            d.mkdir()
            self.created.append(("dir", d))

    def install_config(self):
        config = self.target / "config"
        config.mkdir()
        self.created.append(("tree", config))
        skills = self.copy_skills(config / "skills")
        commands = self.copy_commands(config / "commands")
        manifest = {
            "language": self.language,
            "auto_wp_version": VERSION,
            "created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "skills": skills,
            "commands": commands,
        }
        (config / "auto-wp.json").write_text(json.dumps(manifest, indent=2) + "\n")
        self.out += [
            f"created {self.show('config')} (language: {self.language})",
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
        """Copy command files (*.md); a language-layer file replaces the common one."""
        chosen = {}
        for layer in self.layers:
            src = layer / "commands"
            if src.is_dir():
                for f in src.glob("*.md"):
                    chosen[f.name] = f
        dest.mkdir()
        for name in sorted(chosen):
            shutil.copy2(chosen[name], dest / name, follow_symlinks=False)
        return sorted(Path(n).stem for n in chosen)

    def install_tools(self):
        """Copy each layer's tools/ entries to the project root; keep existing ones."""
        chosen = {}
        for layer in self.layers:
            src = layer / "tools"
            if src.is_dir():
                for entry in src.iterdir():
                    if not entry.name.endswith("~"):
                        chosen[entry.name] = entry
        for name in sorted(chosen):
            dest = self.target / name
            if os.path.lexists(dest):
                self.out.append(f"kept    {self.show(name)} (already exists)")
                continue
            if chosen[name].is_dir() and not chosen[name].is_symlink():
                shutil.copytree(chosen[name], dest, symlinks=True,
                                ignore=shutil.ignore_patterns("*~"))
                self.created.append(("tree", dest))
            else:
                shutil.copy2(chosen[name], dest, follow_symlinks=False)
                self.created.append(("file", dest))
            self.out.append(f"copied  {self.show(name)}")

    def link(self):
        claude = self.target / ".claude"
        if not claude.is_dir():
            claude.mkdir()
            self.created.append(("dir", claude))
        width = len(self.show(max((rel for rel, _ in LINKS), key=len)))
        for rel, dest in LINKS:
            path = self.target / rel
            path.symlink_to(dest)
            self.created.append(("file", path))
            self.out.append(f"linked  {self.show(rel).ljust(width)} -> {dest}")

    def write_readme(self):
        readme = self.target / "README.md"
        if os.path.lexists(readme):
            self.out.append(f"kept    {self.show('README.md')} (already exists)")
            return
        text = (TEMPLATES / self.language / "README.md").read_text()
        text = text.replace("{{DIR}}", self.target.resolve().name)
        text = text.replace("{{LANGUAGE}}", LANGUAGES[self.language])
        readme.write_text(text)
        self.created.append(("file", readme))
        self.out.append(f"wrote   {self.show('README.md')}")

    def init_git(self):
        if shutil.which("git") is None:
            self.warnings.append(
                f"warning: git not found; run 'git init' in {self.arg} before /time-loop")
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
        result = subprocess.run(["git", "init", "-q", str(self.target)],
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
    args = parse_args(argv)
    run = Run(args.directory, args.language)
    try:
        run.execute()
    except (AutoWpError, OSError, subprocess.SubprocessError) as e:
        run.rollback()
        if isinstance(e, shutil.Error) and e.args and isinstance(e.args[0], list):
            e = e.args[0][0][2]  # copytree's error list: report the first failure
        print(f"auto-wp: error: {e}", file=sys.stderr)
        return 1
    print("\n".join(run.out))
    for w in run.warnings:
        print(w, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
