# auto-wp — specification

`auto-wp.py` bootstraps a new verification project: it creates a directory
pre-loaded with the agent configuration (skills and slash commands) needed to
drive a formal-verification campaign on C or Rust code. The configuration is
modelled on `../use-frama-c/config/` (C) and `../use-creusot/config/` (Rust).

Version described: **0.1.0**.

## 1. Command line

```
./auto-wp.py [--c|--rust] <directory-name>
```

| Argument           | Meaning                                                                  |
|--------------------|--------------------------------------------------------------------------|
| `--c`              | Install the C configuration (Frama-C/WP). This is the default.           |
| `--rust`           | Install the Rust configuration (Creusot).                                |
| `<directory-name>` | Path of the project directory to create. Relative paths resolve against the current working directory. |

- `--c` and `--rust` are mutually exclusive; giving both is a usage error.
- Exactly one positional argument is required.
- `-h` / `--help` prints usage and exits with status 0.

Example:

```
./auto-wp.py --c foobar
```

creates `foobar/` containing `config/` (skills and commands), the links
`.agents` and `.claude/{skills,commands}`, a `README.md`, and a git
repository (§3).

## 2. Implementation constraints

- A single executable file `auto-wp.py` at the repository root, starting with
  `#!/usr/bin/env python3`, mode `0755`.
- Python ≥ 3.10, standard library only (`argparse`, `pathlib`, `shutil`,
  `json`, `datetime`, `subprocess`).
- Runs on Linux; nothing in it may prevent it from running on macOS.
- Does not use the network and does not read `../use-frama-c` or
  `../use-creusot` at run time (see §4).
- The only external program it runs is `git` (§3.5), and only if it is on the
  `PATH`.

## 3. Behaviour

### 3.1 Target directory

1. If `<directory-name>` does not exist, create it (including missing
   parents). If it is a symbolic link to a directory, use that directory.
2. If it exists and is not a directory, fail (exit 1).
3. Fail (exit 1) without modifying anything if any of these already exists in
   it: `config`, `.agents`, `.claude/skills`, `.claude/commands`, or a
   `.claude` that is not a directory. An existing `.claude/` directory is
   fine (it often holds `settings.json`) and is reused. Other existing content
   is left untouched, so `auto-wp.py` can be run inside an existing source
   checkout.

### 3.2 The `config/` tree

The skills and commands are installed in `<directory-name>/config/`, with the
same layout as `use-frama-c/config/` and `use-creusot/config/`:

```
<directory-name>/
├── config/
│   ├── skills/
│   │   └── <skill-name>/
│   │       ├── SKILL.md
│   │       ├── references/   (optional)
│   │       ├── scripts/      (optional)
│   │       ├── templates/    (optional)
│   │       └── ...           (any other files the skill ships)
│   ├── commands/
│   │   └── <command>.md
│   └── auto-wp.json
└── .agents -> config
```

The directory is named `config/`, not `.agents/`, because the skills refer to
their own files by paths starting with `config/` relative to the project root
(43 occurrences in `use-frama-c/config/`, 17 in `use-creusot`; for example
`config/skills/sl-internal/scripts/no_ceiling_gate.py`, and the
`config/skills/*/references/` directories where the loops record what they
learn). Installing at the same path keeps all of them valid without rewriting
any file. `.agents` is a relative symbolic link to `config`, for harnesses
that look there.

`config/` is built by copying the `skills/` and `commands/` directories of two
template layers, in order:

1. `templates/common/` — skills shared by both languages;
2. `templates/c/` or `templates/rust/` — the language layer selected on the
   command line.

Only `skills/` and `commands/` are copied from a layer; other files at a
layer's root (such as `README.md`, §3.4) are not.

Overriding works at skill-directory granularity: if the language layer
contains `skills/<name>/`, the common layer's `skills/<name>/` is not copied at
all, so no stray file from the common version survives next to the language
version. A command file in the language layer overrides the common one with
the same name.

Copying preserves file contents byte for byte and permission bits: a file
executable in the templates is executable in the project, and only those.
Symbolic links in the templates are copied as links.

`config/auto-wp.json` records what was installed:

```json
{
  "language": "c",
  "auto_wp_version": "0.1.0",
  "created": "2026-10-27T21:30:00Z",
  "skills": ["directory-structure", "ebios-risk-manager", "..."],
  "commands": ["ebios", "rmf", "time-loop"]
}
```

`created` is the UTC time of the run in ISO 8601. `skills` and `commands` are
sorted lists of the names actually installed.

### 3.3 Harness wiring

To make the configuration visible to Claude Code, as both source repositories
do, create `<directory-name>/.claude/` if it does not exist, then:

```
<directory-name>/.claude/skills   -> ../config/skills
<directory-name>/.claude/commands -> ../config/commands
<directory-name>/.agents          -> config
```

All three are relative symbolic links, so the project directory can be moved
or cloned without breaking them.

### 3.4 `README.md` in the generated directory

`auto-wp.py` also writes `<directory-name>/README.md`. Its job is to show that
the generated directory is ready to use: clone a code base into it, start the
agent harness in it, type one command.

**Source.** The README comes from a per-language template,
`templates/c/README.md` or `templates/rust/README.md`. The program replaces two
placeholders in it and changes nothing else:

| Placeholder | Replaced by |
|---|---|
| `{{DIR}}` | `Path(<directory-name>).resolve().name`, so `foobar`, `foobar/` and `./foobar` all give `foobar`, and `.` gives the name of the current directory |
| `{{LANGUAGE}}` | `C (Frama-C/WP)` or `Rust (Creusot)` |

**Content of the C README** (`--c`, or no flag). In this order:

1. A title (`# {{DIR}} — automated verification of {{LANGUAGE}} code`) and one
   sentence saying the directory was generated by `auto-wp.py` and is ready to
   use.
2. **Quick start**, the example that has to work as written once the
   prerequisites of item 4 are met. It runs Claude Code in an LXD container,
   because the campaign runs for days with `--dangerously-skip-permissions`:
   the agent can then change only the container and `foobar`, which LXD
   mounts into it, not the user's other files, SSH keys or Claude login.
   Three steps:

   1. *On the host*, from the directory that contains `foobar`: set
      `CT=wp-foobar` and `NET=lxdbr0`; create the bridge when `lxc network show "$NET"` fails (`lxc network create "$NET"`); `lxc launch ubuntu:24.04 "$CT" --network "$NET"`; wait with
      `lxc exec "$CT" -- cloud-init status --wait`, so that cloud-init
      creates `/home/ubuntu` before the mount does; mount `foobar` with
      `lxc config device add "$CT" foobar disk source="$PWD/foobar"
      path=/home/ubuntu/foobar shift=true` (the user asked for a mount
      instead of a copy, 2026-10-30; `shift=true` maps the host owner to
      `ubuntu`, verified 2026-10-30: files the agent creates are owned by the
      host user, and commit, push and a container restart work); install the packages
      (git, python3, tmux, curl, opam, the Frama-C build dependencies and the
      GRUB build dependencies, the same list as `tests/c/provision.sh`);
      unload the AppArmor profile Ubuntu 24.04 ships for opam
      (`apparmor_parser -R /etc/apparmor.d/opam`, plus a link in
      `/etc/apparmor.d/disable/`), which inside an LXD container denies
      opam's downloads their network sockets (verified 2026-10-28: `opam
      init` fails with "Could not resolve host"); open a shell as `ubuntu` with `lxc exec "$CT" -- sudo -iu ubuntu`. One
      paragraph says that this line creates `lxdbr0` when missing (verified
      2026-10-28: without it, `lxc launch --network lxdbr0` fails with
      "Network not found" on this host), that `NET` can name an existing
      bridge with `MANAGED` `YES` in `lxc network list`, and why
      `--network` is given: the `default` profile of some LXD installs, this
      host's among them, has no NIC, and `apt-get update` then fails.
   2. *In the container*:

      ```
      cd foobar
      git clone https://gitlab.freedesktop.org/gnu-grub/grub.git
      git config user.name "Your Name"
      git config user.email "you@example.com"
      git init --bare ~/foobar.git
      git remote add origin ~/foobar.git
      opam init --disable-sandboxing -y --bare
      bin/fetch-sources.sh
      curl -fsSL https://claude.ai/install.sh | bash
      . ~/.profile
      tmux new -s wp
      claude --dangerously-skip-permissions
      ```

      The user logs in to Claude Code inside the container (URL and code).
      The README says never to copy `~/.claude/.credentials.json` from the
      host.
   3. *In the harness*:

      ```
      /time-loop grub 72
      ```

      with how to detach from `tmux` and re-attach
      (`lxc exec wp-foobar -- sudo -iu ubuntu tmux attach -t wp`).

   This runs the time-loop campaign on the directory `grub` for 72 hours. The
   README says that:
   - the source directory (`grub/`) is kept untouched, and every result is
     written next to it, in `foobar`, under the prefix `grub-analysis`
     (`grub-analysis-rmf-report.md`, `grub-analysis-found-issues.md`,
     `grub-analysis-acsl/`, the numbered
     `grub-analysis-monitor-feedback-NN.md`);
   - the report of the run (the final report, or an interim report when the
     deadline is reached first) is written to `grub.md`, next to `grub/`
     (§4.2.2);
   - the run can be stopped and started again with the same command. The
     loop picks up from its saved state and **keeps the original deadline**:
     `/time-loop grub 72` restarted after 10 hours has 62 hours left, not 72
     (§4.2.2);
   - on the first run `frama-c-launch` builds the toolchain in the container,
     which takes hours of the budget;
   - the loop commits a checkpoint after every cycle and pushes it, so
     `foobar` needs a git identity and a remote (`auto-wp.py` has already run
     `git init`, §3.5). The remote is a bare repository in the container, so
     no credential enters it. The files and the commits (`foobar/.git`) are
     on the host through the mount, so nothing has to be copied out;
   - the agent can write anything in `foobar`, `.git/hooks/` and `bin/`
     included, so the README says to check, before running git or a script
     there on the host, that `.git/hooks/` holds only `*.sample` files and
     to read `git diff` of `bin/`;
   - `grub/` is a separate git repository; git does not track it inside
     `foobar` unless it is added as a submodule;
   - `lxc delete --force wp-foobar` removes the container and the login,
     and leaves `foobar` on the host; the container name must contain only letters,
     digits and hyphens.

   One closing paragraph says `claude` can also run directly in `foobar` on
   the host, with the agent acting with all the user's rights, so the
   permission prompts stay on.
3. **Other commands**: one line each for `/rmf <dir> <dir>-analysis` (a single
   campaign without a time budget), `/ebios`, and the `/time-loop` options
   (`--dir=`, `--machdep=`, `--linux`, `--full-tu`, `--fresh`, `--no-coq`),
   pointing to `config/commands/time-loop.md` for details.
4. **Prerequisites**:
   - On the host: LXD usable by the user, and nothing else. The project is
     stand-alone: it never refers to a checkout on the host such as
     `~/git/use-frama-c`. The tools the C skills call from the project root
     are copied into it (§4.2.1), and `bin/fetch-sources.sh` (step 2) downloads
     the two trees too large to ship.
   - In the container: Claude Code (installed in step 2), and Frama-C 32.1
     with WP and the provers, in the `framac-coq8` opam switch.
     `frama-c-launch` checks the toolchain on the first run and builds it
     from `framac-src/` (fetched with `frama-c-patches/` applied) if it is
     missing.
   - Optional: `~/.local-llm-machine-ip.txt` in the container, one line with
     the IP of a local LLM host (for example an ollama server) that the
     container can reach. It is used by the cross-provider judge in
     `sl-auditor` and `no_ceiling_gate.py`. Without it those steps are
     advisory, and `sl-auditor` asks the user before going on.
5. **What is in this directory**: `config/` (skills and commands, listed in
   `config/auto-wp.json`), `.agents` and `.claude/` (links to it), the tools
   of §4.2.1 (the scripts in `bin/`), and what `bin/fetch-sources.sh` downloads. One line saying the
   skills can be edited in place and that the loops add what they learn under
   `config/skills/*/getting-better/` and `config/skills/*/references/learned-*.md`.

**Content of the Rust README** (`--rust`). Same five items, with these
differences:

- *Quick start.* It uses a Rust crate instead of GRUB, with the same three
  LXD steps, with `foobar` mounted the same way. Step 1 installs the Creusot
  build dependencies instead (the list of `tests/rust/provision.sh`). Step 2
  runs `opam init --disable-sandboxing -y --bare`, installs rustup, clones
  Creusot into `~/git/creusot` and runs its `./INSTALL`, then
  `cd foobar`, `git clone <crate-url> mycrate`, the git identity and the
  bare remote, the Claude Code install, `tmux` and `claude`. Until roadmap
  step 5 (§4.3.7) is done, there is no `/time-loop` command for Rust, so the
  README must not contain the string `/time-loop mycrate 72`. Step 3 is
  instead a plain request: `onboard the crate mycrate with creusot-launch,
  then analyze it with creusot-monitoring`.
  When `templates/rust/commands/time-loop.md` exists, the template is updated
  to show `/time-loop mycrate 72`, exactly as in the C README. This is a
  template change only; the program does not change.
- *Other commands.* While `config/commands/` is empty for Rust, this item says
  there are no slash commands yet and lists the skills to ask for by name:
  `creusot-launch`, `creusot-monitoring`, `creusot-sl`, `creusot`.
- *Prerequisites.* On the host, LXD. In the container (step 2), Creusot
  (`cargo creusot`), Why3, why3find, the solvers (Alt-Ergo, Z3, CVC4, CVC5),
  and the nightly toolchain pinned by Creusot. One
  line says `creusot-launch` checks them but does not install them, and that
  the Creusot checkout must stay where it was installed from (§4.3.6). No
  `use-frama-c` checkout is needed. The optional
  `~/.local-llm-machine-ip.txt` line is the same as for C.
- One extra line says that the generated directory should not be inside a
  Cargo project, and that the crate is cloned next to its overlay, not under
  it. The reason (`cargo creusot new` writes `why3find.json` next to a parent
  `Cargo.toml`) is in §4.3.5.

**Existing README.** If `<directory-name>/README.md` already exists (for
example when running inside an existing checkout), it is left untouched and the
program prints `kept    foobar/README.md (already exists)` instead of failing.

### 3.5 Git repository

The time-loop commits and pushes a checkpoint every cycle
(`use-frama-c/config/skills/time-loop/SKILL.md`, step 5 of the cycle), so the
project must be a git repository.

- If `git` is on the `PATH` and `<directory-name>` is not already inside a git
  work tree (`git -C <dir> rev-parse --is-inside-work-tree` fails),
  `auto-wp.py` runs `git init` in it. It does not commit and does not add a
  remote; the README explains how to add one (§3.4).
- If it is already inside a work tree, nothing is done.
- If `git` is not on the `PATH`, the program prints
  `warning: git not found; run 'git init' in foobar before /time-loop` on
  stderr and still succeeds.

### 3.6 Output and exit status

- On success, print one line per action, with paths written as given on the
  command line (here `foobar`), e.g. for `--c`:

  ```
  created foobar/config (language: c)
    skills:   21
    commands: 3
  copied  foobar/.gitignore
  copied  foobar/bin
  copied  foobar/frama-c-patches
  copied  foobar/framac-gold
  copied  foobar/no-ceiling.md
  linked  foobar/.agents          -> config
  linked  foobar/.claude/skills   -> ../config/skills
  linked  foobar/.claude/commands -> ../config/commands
  wrote   foobar/README.md
  git     initialized foobar
  ```

  and exit 0. With `--rust` the counts are `skills: 16` and `commands: 0`
  (§4.3.2), and there is no `copied` line (the Rust layer has no
  `tools/`). An entry that already exists in the target is not overwritten:
  the program prints `kept    foobar/<name> (already exists)` instead of
  its `copied` line. The `git` line reads `git     foobar is already in a git work
  tree` when nothing was done.
- Usage errors (unknown option, both `--c` and `--rust`, missing or extra
  positional argument): message on stderr, exit 2 (`argparse` default).
  Nothing is created.
- Run-time errors (target is a file, one of the paths of §3.1 item 3 already
  present, missing template directory, I/O error, `git init` failing): message
  on stderr prefixed with `auto-wp: error:`, exit 1.
- **Rollback.** On a run-time error, at whatever point it happens, remove
  everything this run created, in reverse order: `.git/` (if this run
  initialised it), `README.md`, the three links, the copied tools, `.claude/` (only if this run
  created it and it is now empty), `config/`, and `<directory-name>` itself
  plus any parents (only those this run created, and only if empty). Never
  remove anything that existed before the run. A re-run then starts from the
  same state as the first one.

## 4. Templates

The templates ship in this repository, next to `auto-wp.py`, and are located
relative to the script (`Path(__file__).resolve().parent / "templates"`), not
relative to the current directory:

```
auto-wp/
├── auto-wp.py
├── auto-wp.md
├── tests/
└── templates/
    ├── common/{skills,commands}/
    ├── c/{skills,commands,tools}/ + README.md
    └── rust/{skills,commands}/ + README.md
```

They are seeded once from `../use-frama-c/config/` (common and C layers) and
`../use-creusot/` (Rust layer), following §4.4, then maintained here, so
`auto-wp.py` works on a machine with neither repository, and the projects it
creates do not need them either (§4.2.1).

### 4.1 `templates/common/` — shared skills

Skills: `directory-structure`, `ebios-risk-manager`, `ebios-sl`, `lean`,
`polish-skill`, `rmf-sl`, `rocq`, `sl-auditor`, `sl-builder`, `sl-internal`,
`sl-monitoring-sl`, `stride` (12).

Commands: none.

These cover the Squeeze Loop machinery, risk studies done without reading the
code (RMF, EBIOS, STRIDE) and the proof assistants used to discharge goals the
automatic provers cannot close. **They are not all language-independent
yet**: they were written for the Frama-C flow and still mention it (Frama-C,
ACSL or WP mentions per `SKILL.md`: `rmf-sl` 82, `sl-monitoring-sl` 61,
`ebios-sl` 48, `sl-builder` 47, `rocq` 10, `sl-internal` 10). `rmf-sl` and
`ebios-sl` hand their result to `frama-c-launch` and use `rmf-lint.sh` /
`ebios-lint.sh` from `use-frama-c` as their machine gate. For `sl-builder`,
`sl-internal` and `sl-monitoring-sl` the mentions are examples and the method
applies to any language. For `rmf-sl` and `ebios-sl` they are wiring, which
roadmap steps 2 and 3 (§4.3.7) make language-independent. The four `sl-*`
skills are replaced in the Rust layer by the `use-creusot` versions (§4.3.3).

### 4.2 `templates/c/` — C with Frama-C/WP

Skills: `frama-c`, `frama-c-api`, `frama-c-internals`, `frama-c-launch`,
`frama-c-monitoring`, `framac-sl`, `linux-api`, `ocaml`, `time-loop` (9).

Commands: `ebios`, `rmf`, `time-loop`.

A `--c` project therefore has 21 skills (12 common + 9) and 3 commands.

`meta-penguin` is not included: it is `time-loop` specialised to two Linux
kernel subsystems of one campaign, not reusable for a new project.

#### 4.2.1 Root-level tools: `templates/c/tools/`

The C skills also call files from the project root, outside `config/`. In
`use-frama-c` they live at the root of the repository. The generated project
is stand-alone, so they ship in `templates/c/tools/`, and `auto-wp.py` copies
every entry of a layer's `tools/` to the project root (§3.6), keeping
permission bits. The layer holds:

- `bin/`, with every script: the 20 `*.sh` scripts at the root of
  `use-frama-c`, each referenced from `config/` (`rmf-lint.sh` and
  `ebios-lint.sh`, the machine gates of `rmf-sl` and `ebios-sl`;
  `framac-onboard.sh`, `framac-gen-report.sh`, `framac-squeeze-audit.sh`,
  `framac-monitor-check.sh`, `ledger-ratchet.sh`, `crosswalk-gen.sh` and the
  other `framac-*.sh`), plus `fetch-sources.sh`, written for auto-wp;
- `frama-c-patches/`, `framac-gold/` and `no-ceiling.md`, the data the
  scripts and skills read, at the project root as in `use-frama-c`;
- a `.gitignore`, written for auto-wp.

The scripts are in `bin/`, not at the root as in `use-frama-c`, so the
project root stays readable. Every caller in the skills and commands calls
them as `bin/<name>.sh`, from the project root (§4.4); they still read and
write paths relative to the current directory (`framac-gold/`, the campaign
directories), so they must be run from the project root. The two scripts that
locate files from their own path go one level up: `framac-canary.sh` (to find
`config/`) and `fetch-sources.sh` (to put `framac-src/` and `macsl/` at the
root).

Together about 1.3 MB, seeded with `git archive` from the committed tree of
`use-frama-c` (commit `9b0c95145`). Two trees are too large to ship and are
public, so `bin/fetch-sources.sh` downloads them into the project root instead;
`.gitignore` keeps them, and every `_build/`, out of the project history:

- `framac-src/` (127 MB of source, 1.2 GB once built):
  the release archive `https://www.frama-c.com/download/frama-c-32.1-Germanium.tar.gz`,
  checked against the sha256 of opam's `frama-c.32.1` package (`opam source`
  is not used: it needs an opam switch, and a fresh `opam init --bare` has
  none), then the patches: `frama-c-patches/apply.sh`
  (`0001-*`, `0002-*`), `cabs2cil-c23-auto.patch` (with `patch -p0`), the
  `wp-cbits-bound-lemmas` axioms into
  `src/plugins/wp/share/why3/frama_c_wp/cbits.mlw`, and its
  `Cbits.v.realization` appended to `src/plugins/wp/share/coqwp/Cbits.v`.
  Verified 2026-10-28: the result equals `use-frama-c/framac-src` except for
  one axiom, `land_lor_absorb` (AppArmor deny-dominance), that is in
  `use-frama-c/framac-src` but in no file of `frama-c-patches/`. A campaign
  that needs it must add it as a patch first.
- `macsl/` (the macsl plugin): `git clone https://github.com/canonical/macsl.git`
  at commit `b7a472e`, the commit of the `use-frama-c` submodule. Verified
  identical to the submodule, without its `_build*/` directories.

The script leaves an existing `framac-src/` or `macsl/` as it is, and
assembles `framac-src/` in a temporary directory, so a failed download leaves
nothing behind. It needs curl, sha256sum, tar, git, patch and network
access, but not opam. Verified 2026-10-28: the archive gives the same tree as
`opam source frama-c.32.1`.

Four skill files that pointed into `~/git/use-frama-c` are rewritten to the
project root (§4.4). `frama-c-launch`'s build recipe uses the vendored
`./framac-src` when it exists. It also calls
`frama-c-patches/cabs2cil-c23-auto/apply.sh`, which does not exist in
`use-frama-c`. That is harmless here, because `bin/fetch-sources.sh` has already
applied that patch.

#### 4.2.2 Changes to the `time-loop` skill and command

`templates/c/skills/time-loop/SKILL.md` and
`templates/c/commands/time-loop.md` are copied from `use-frama-c` with three
behaviour changes, decided on 2026-10-28. These are the only content changes
in the C layer (§4.4).

1. **A re-run keeps the original deadline.** The deadline is fixed by the
   first invocation (`deadline = start + N hours`, stored in
   `XXX-analysis-acsl/time-loop.state`). A later `/time-loop XXX N` on the
   same campaign, after a stop, a crash or a reboot, reuses the stored start
   and deadline and does not compute new ones; the `N` it is given is
   ignored when a state file exists. If the stored deadline has already
   passed, the run does the terminus step straight away (final or interim
   report) and stops. A new budget needs `--fresh`, which starts a new
   campaign. The source files leave this open: the skill stores the deadline
   in the state file but also says `N` bounds "the budget per invocation".
   The template replaces that sentence with this rule.
2. **The report goes to `XXX.md`.** `/time-loop toto 72` writes its report to
   `toto.md` in the project root, next to `toto/`. It is the final report at
   the terminus, or the interim report when the run pauses at the deadline;
   each new report replaces the previous one in that file, and git history
   keeps the earlier versions. When `XXX` is a path (`zephyr/kernel`), the
   file name uses the same root-safe slug as the artifact prefix
   (`zephyr-kernel.md`), so the report is never written inside the source
   tree. The source files require the report but never name its file.
3. **No "diminishing returns" stop.** The loop stops only at the true
   terminus or pauses at the deadline:
   - *True terminus:* every in-scope goal is in one of the three end states
     of the skill (proven; a code bug, reported; a Frama-C bug, diagnosed to
     a reproducer and filed), and the Gate-T checklist passes. The final
     report goes to `XXX.md`.
   - *Deadline:* the run pauses, writes the interim report to `XXX.md`, and
     continues from its saved state on the next invocation (change 1).

   Running out of class-C work is therefore not a reason to stop. The
   remaining class-A goals (true, but not provable with today's toolchain)
   are retried with the patched Frama-C and Coq, and each one that stays
   unprovable is turned into a filed Frama-C bug. Class-B matter (crypto,
   entropy, side channels, supply chain) is declared out of scope in the
   scope statement at the start, not left over at the end. This is what the
   body of the skill already requires (§0, §3 Gate S, §6). The template
   removes the two places that contradict it:
   - In `commands/time-loop.md`, the "Stop early" bullet becomes:
     "**Stop** only on: the true terminus (every in-scope goal PROVEN,
     VIOLATION reported, or BUG IN FRAMA-C filed, and Gate T passes) — emit
     the final report to `XXX.md`; or the deadline / budget exhausted — a
     **pause**, not a finish: emit the interim report to `XXX.md` and resume
     from the checkpoint on the next invocation. Running out of class-C work
     is not a stop: drive the remaining class-A goals to PROVEN or to a filed
     Frama-C bug. **Never** burn remaining hours re-grinding the same class
     A/B items without a new lever." The report contents keep their list,
     without the "next-budget target" item.
   - In the skill's `description` (its YAML front matter), the sentence that
     starts "The DIMINISHING-RETURNS stop fires ONLY when…" is replaced by
     "There is no diminishing-returns stop: the loop ends only at the true
     terminus (every goal PROVEN, VIOLATION reported, or BUG IN FRAMA-C
     filed, and Gate T passes) and pauses at the deadline." The rest of the
     sentence, which forbids terminating early on plane exhaustion or
     stopping to ask, is kept.

   The other mentions of diminishing returns in the skill's body already
   forbid such a stop, or describe the trap the triage exists to prevent,
   and are kept unchanged.

All three changes are listed in §4.4. `tests.md` checks the first two with
C3.x and C4.x, and the third with C4.2 and template check T6.

### 4.3 `templates/rust/` — Rust with Creusot

The Rust layer comes from `../use-creusot/`, which verifies Rust with
[Creusot](https://github.com/creusot-rs/creusot): Rust is annotated with
Pearlite contracts, translated through Coma to Why3, and the proof obligations
are discharged by SMT solvers via `cargo creusot`. It is the counterpart of
WP for Rust.

#### 4.3.1 What `use-creusot` contains

| Path | Content | Used by auto-wp |
|---|---|---|
| `config/skills/creusot/` | `SKILL.md` (376 lines): Pearlite reference, covering `#[requires]`/`#[ensures]`, the `@` model operator, the `*`/`^` prophecy operators on `&mut`, `#[invariant]`, `#[variant]`, `#[logic]`, predicates, `proof_assert!`, `snapshot!`/`ghost!`, type invariants, `View`/`DeepModel`, `Int`/`Seq`/`Mapping`/`FSet`, and the escape hatches `#[trusted]`/`assume!`/`extern_spec!`. `references/learned-{annotator,coordinator,spec-author,verifier}.md`: per-role heuristics the base loop has learned. | yes |
| `config/skills/creusot-monitoring/` | `SKILL.md` (296 lines): the top-level loop over a whole crate. It schedules files leaf-first, propagates each proven callee `#[ensures]` as the caller's `#[requires]`, runs one `creusot-sl` sub-loop per file and audits the results against the mission guidance (PASS / CARVE-OUT / REJECT). Also contains `creusot-monitoring.sl.json`, `references/learned-{coordinator,monitor,scheduler}.md`, `getting-better/` (14 Creusot tooling gaps, e.g. missing `extern_spec`s in `creusot-std`, Coma reserved identifiers) and `bugs-to-report/` (one Creusot bug, four bugs found in the `lace` crate). | yes |
| `config/skills/sl-auditor`, `sl-builder`, `sl-internal`, `sl-monitoring-sl` | Squeeze Loop methodology. These are **divergent copies** of the `use-frama-c` versions (see §4.3.3). | yes, overriding common |
| `config/skills/directory-structure`, `polish-skill` | Identical to the `use-frama-c` versions (apart from an editor backup `SKILL.md~`). | no, common has them |
| `config/foo/skills/` | An older snapshot of `config/skills/` without the `.sl.json` files or the `sl-internal` scripts. | no, stale |
| `creusot-sl.md`, `creusot-sl.sl.json` (repo root) | Spec of the **base loop**, which verifies one `*.rs` file. Roles: coordinator, spec author (no access to the implementation), annotator, verifier (mutation probes), probe. Gates A (contracts vs requirement), B (all VCs discharged, no `#[trusted]`/`assume!`), C (non-vacuity, mutation), S (audit of learned heuristics). This is not a skill, but the Creusot skills refer to it as "repo-root `creusot-sl.md`". | yes, packaged as a skill (§4.3.2) |
| `docs/` | Docs for the two loops (`creusot-sl.md`, `creusot-monitoring.md`, PNG/SVG diagrams), `u-provenance-ledger.md`, `verification-evidence-conventions.md`, an SL audit from 2026-06-28. | no |
| `training-data/`, `annotate/` | Corpus of 241 Rust files with the Creusot annotations stripped, and the same files re-annotated by a `creusot-monitoring` run, with per-file `.txt` logs, `VERDICTS.md` (118 PROVED, 8 PARTIAL, 6 FAILED, 109 TRIVIAL) and `COMPARISON-SUMMARY.md`. | no |
| `lace-*.md`, `lace-issues/`, `report.md`, `workflow.md`, `lxc-usage.md` | Results and notes from a campaign on the `lace` crate (architecture report, attack surface, claims validation, 4 issues with draft patches). | no |
| `Makefile`, `compile-check.sh`, `gen-verdicts.sh`, `monitor-check.sh` | Corpus tooling, hard-wired to `training-data/` and `annotate/`. The toolchain is `nightly-2026-04-21`. `monitor-check.sh` calls a `strip-creusot` binary at `/tmp/strip-creusot/target/release/strip-creusot`, whose source is not in the repository. | no |
| `.claude/skills` | Symlink to `../config/skills`, the same wiring as §3.3. | no, recreated by §3.3 |
| `config/commands/` | Does not exist. `use-creusot` has no slash commands. | — |

#### 4.3.2 Content of `templates/rust/`

```
templates/rust/
├── README.md
├── skills/
│   ├── creusot/               copied from use-creusot/config/skills/creusot/
│   ├── creusot-launch/        new: onboarding loop written for auto-wp (§4.3.5)
│   ├── creusot-monitoring/    copied from use-creusot/config/skills/creusot-monitoring/
│   ├── creusot-sl/            new: SKILL.md = front matter + use-creusot/creusot-sl.md
│   │   └── creusot-sl.sl.json      copied from use-creusot/creusot-sl.sl.json
│   ├── sl-auditor/            copied from use-creusot (overrides common)
│   ├── sl-builder/            copied from use-creusot (overrides common)
│   ├── sl-internal/           copied from use-creusot (overrides common)
│   └── sl-monitoring-sl/      copied from use-creusot (overrides common)
└── commands/                  empty
```

The `creusot-sl` packaging is done **once, when seeding the templates**;
`auto-wp.py` only copies the result:

- `creusot-sl/SKILL.md` is `use-creusot/creusot-sl.md` preceded by a YAML
  front matter in the style of the other skills:

  ```yaml
  ---
  name: creusot-sl
  description: >-
    <the paragraph of creusot-sl.md that starts "A **Squeeze Loop (SL)** that
    annotates **existing** Rust with Pearlite and proves it with Creusot",
    with the Markdown emphasis removed>
  ---
  ```

  The original `**Name:** creusot-sl` line is kept.
- Every mention of "repo-root `creusot-sl.md`" is rewritten to "the
  `creusot-sl` skill (`config/skills/creusot-sl/SKILL.md`)" in all the files
  where it occurs: `creusot/SKILL.md`, `creusot-monitoring/SKILL.md`,
  `creusot/references/learned-{annotator,coordinator,spec-author,verifier}.md`
  and `creusot-monitoring/creusot-monitoring.sl.json`. The seeding step greps
  for `creusot-sl.md` afterwards and must find no remaining reference to the
  repo-root file.
- `creusot-sl.md` §11 ("Knowledge capitalization — `config/skills/creusot/`")
  and its other `config/skills/...` paths stay valid as they are, because the
  project installs into `config/` (§3.2).
- Mentions of `annotate/COMPARISON-SUMMARY.md` in the Creusot skills are kept.
  They cite the evidence behind a lesson, and the file stays available in
  `use-creusot`.
- Apart from these, files are copied unchanged.

A `--rust` project therefore has 16 skills: the 8 skills of the Rust layer
(`creusot`, `creusot-launch`, `creusot-monitoring`, `creusot-sl` and the four
Creusot-flavoured `sl-*` skills) and the 8 common skills that are not
overridden (`directory-structure`, `ebios-risk-manager`, `ebios-sl`, `lean`,
`polish-skill`, `rmf-sl`, `rocq`, `stride`). Six of those eight are not in
`use-creusot`: `ebios-risk-manager`, `ebios-sl`, `lean`, `rmf-sl`, `rocq`,
`stride`. `rmf-sl` and `ebios-sl` are still wired to Frama-C (§4.1).

#### 4.3.3 Divergent SL skills

The four SL skills changed independently in the two repositories, and each
side has content the other lacks:

| Skill | Only in `use-frama-c` | Only in `use-creusot` |
|---|---|---|
| `sl-builder` | the "not addressable by our tool is a category error" corollary; an "Encoding note (SL-1.0)" block | "Phase 0 — architectural audit" (endogenous vs exogenous `U`) |
| `sl-auditor` | about 50 more lines, including the "Reaching the cross-provider judge" paragraph, which appears **twice** (a duplicated paragraph) | references to six check scripts `verify/{perturbation,category_overreach,flag_rate,claim_consistency,editorial_gate,apparatus_described}.py`, which **exist nowhere** |
| `sl-monitoring-sl` | about 45 more lines; bundled copies of `sl-auditor`, `sl-builder`, `sl-internal` | — |
| `sl-internal` | scripts `no_ceiling_gate.py`, `sl2doc.py`; different `refutation_probe.py` and `sl_disjointness_check.py` | — |

Version 0.1.0 does not merge them: each language gets the version from its own
source repository, through the override mechanism of §3.2. The two defects
(the duplicated paragraph and the missing `verify/` scripts) are kept as they
are and fixed when the skills are merged (§6), so that the templates stay
faithful copies until then.

#### 4.3.4 Gaps compared with C

- There is no onboarding loop in `use-creusot`. In the `lace` campaign,
  onboarding was done by hand by every `creusot-sl` sub-agent
  (`use-creusot/lace-workflow.md` §6): Lace targets `x86_64-unknown-uefi` and
  depends on `uefi`, `zerocopy` and `fdt`, so `cargo creusot` cannot build it
  in place, and each agent built its own scratch project. `creusot-launch`
  (§4.3.5) closes this gap.
- There is no `/rmf` or `/time-loop` command, so a Rust campaign is started by
  asking the agent to apply the `creusot-monitoring` skill to a crate.
- There is no risk study wired into the Creusot loop. `rmf-sl` and `ebios-sl`
  are installed, but they hand their result to `frama-c-launch` only.
- There is no runnable faithfulness check: `monitor-check.sh` depends on a
  `strip-creusot` binary whose source is not in `use-creusot`.
- Installing Creusot itself (`cargo creusot`, Why3, solvers, the pinned
  nightly toolchain) is up to the user, as Frama-C is for `--c`.
  `creusot-launch` checks it but does not install it.

#### 4.3.5 `creusot-launch` — onboarding a crate for Creusot

`creusot-launch` is the Rust counterpart of `frama-c-launch`. It does not
exist in either source repository: it is written in this repository, as
`templates/rust/skills/creusot-launch/SKILL.md`, and maintained here.

**Installation.** It lives only in the Rust layer, so `auto-wp.py` installs it
with `--rust` and never with `--c` (or with no flag). This needs no special
case in the program: it follows from the layer rules of §3.2.

**Role.** A Squeeze Loop that onboards a Rust crate and hands a validated
onboarding package to `creusot-monitoring`, which then drives `creusot-sl` per
file. It is written with the `sl-builder` method. Its prep work is checked by
a separate onboarding monitor, following `sl-monitoring-sl`. Mission shape:
"onboard the crate `<xxx>` in directory `<yyy>` for verification". As with
`frama-c-launch`, the skill says when the full loop is worth its cost (many or
heterogeneous crates, non-trivial feature configuration) and when a plain
onboarding script is enough.

**Responsibilities**, mapped from `frama-c-launch`:

| `frama-c-launch` (C) | `creusot-launch` (Rust) |
|---|---|
| Preprocessing context: `compile_commands.json`, `-D` defines, `-machdep` | The build configuration: Cargo features, `--target`, `no_std` vs `std`, `cfg` gates. The monitor checks that the selected features match the shipped build: a configuration that builds but selects a different feature set is the main way onboarding goes wrong. |
| Toolchain check (`frama-c -wp-detect`, opam switch) | Check `cargo creusot version`, Why3, why3find, the solvers (Alt-Ergo, Z3, CVC4, CVC5), the pinned nightly toolchain, and the path of the Creusot checkout that `~/.cargo/config.toml` points to (§4.3.6). Report anything missing; do not install. |
| `<target>-acsl/` overlay; the source is not modified | A `<crate>-creusot/` overlay next to the crate, with its own `Cargo.toml` (dependency on `creusot-std`) and `rust-toolchain.toml`. The target's `Cargo.toml` and sources are never edited, so they remain the faithfulness baseline. |
| Faithfulness baseline pinned to the right commit | Record the crate's commit, and provide the faithfulness check: annotated code, with its Pearlite annotations removed, must match the original source. `use-creusot/monitor-check.sh` does this with a `strip-creusot` tool whose source was never committed, so `creusot-launch` ships its own stripping script in `creusot-launch/scripts/` (to be written with the skill, roadmap step 1). Until it exists, the gate is reported as not run, never as passed. |
| Phase-0 scope map and attack-surface ranking | Split the crate into what Creusot can reach (pure safe Rust) and what is out of reach (`unsafe`, FFI, unmodelled dependencies such as `zerocopy`), and rank the code that handles untrusted input. `use-creusot/lace-workflow.md` §3 and `lace-attack-surface.md` are the worked example. |
| Smoke proof on one leaf unit | Run `cargo creusot` end to end on one leaf function in the overlay. |

**Rust-specific checks:**

- *Workspace pitfall.* Reported in
  `creusot-monitoring/bugs-to-report/20260616-1716-creusot-new-silent-skip-in-workspace.md`;
  the cause and the workaround below were checked against Creusot's source
  and confirmed by an end-to-end run with Creusot installed (§4.3.6).
  `cargo creusot new`/`init` does not skip `why3find.json`: it writes it, and
  a `.gitignore` if none exists there, into the directory of the nearest
  `Cargo.toml` found in a **parent** directory. It only prints an
  `Info: It seems that you are in a workspace` line. `cargo creusot` then
  looks for `why3find.json` in Cargo's workspace root, which is usually the
  overlay, so it fails. An empty `[workspace]` table in the overlay's
  `Cargo.toml` fixes only half of this:
  - It makes Cargo treat the overlay as its own workspace root in every case.
    Without it, Cargo refuses to build the overlay when a parent `Cargo.toml`
    is a real workspace or is not a valid manifest.
  - It does not change where `new`/`init` puts `why3find.json`: that code
    scans parent directories for any `Cargo.toml` and does not read the
    overlay's own manifest.

  `creusot-launch` therefore does all of the following:
  1. It puts the overlay next to the crate (`<dir>/<crate>-creusot/`), never
     inside it. Otherwise the crate's `Cargo.toml` is a parent, and
     `new`/`init` writes `why3find.json` (and possibly `.gitignore`) into the
     crate source, which must stay untouched.
  2. Before scaffolding, it lists every `Cargo.toml` in the parent
     directories of the overlay, and the `why3find.json` and `.gitignore`
     files next to them, and records them in the onboarding package.
  3. It adds an empty `[workspace]` table to the overlay's `Cargo.toml`.
  4. After scaffolding, it makes sure `why3find.json` is at the overlay root.
     If it is not, it copies it from Creusot's data directory
     (`$CREUSOT_DATA_HOME/why3find.json`, by default
     `~/.local/share/creusot/why3find.json` on Linux). It then deletes any
     `why3find.json` or `.gitignore` in a parent directory that was not in
     the list made in step 2.
  5. As the smoke test, it runs `cargo creusot` in the overlay. Gate: no
     `why3find.json not found` error.
- *Trusted assumptions.* The package lists every `extern_spec!` the overlay
  needs for dependencies or `core`, and every `#[trusted]` item. They are
  assumptions, not proofs; an over-strong one can make a false property
  provable. The monitor reviews this list.
- *Isolation.* When a function cannot be separated from an unmodelled
  dependency, it is recorded as BLOCKED with a `getting-better/` note, never
  replaced by a simplified version.

**Onboarding package** (handed to `creusot-monitoring`):
the overlay path, the selected features and target, the toolchain versions and
Creusot checkout path, the baseline commit, the scope map with the
reachable/out-of-reach split, the ranked list of files or functions, the
trusted-assumption list, the faithfulness-check status, and the smoke-proof
result.

#### 4.3.6 Workspace test (2026-10-27, 2026-10-28)

**What was tested.**
- *Creusot's source:* `creusot-rs/creusot` at commit `f15b985` (main,
  2026-10-27). Read `cargo-creusot/src/new.rs`: `create_project` and
  `find_parent_cargo_toml`. Read `cargo-creusot/src/why3find_wrapper.rs`:
  `check_why3find_json_exists` takes Cargo's `workspace_root` as its root.
  Read `cargo-creusot/src/config.rs`: `write` uses `File::create_new`, so it
  never overwrites a file and skips any file that already exists.
- *Cargo's behaviour:* `cargo metadata` with cargo 1.88.0 on an overlay
  package `p/`, under three kinds of parent directory:

| Parent `Cargo.toml` | Overlay without `[workspace]` | Overlay with empty `[workspace]` |
|---|---|---|
| empty file (`touch`, as in the bug report) | error: failed to parse manifest | root = overlay |
| real workspace (`[workspace] members = []`) | error: package believes it's in a workspace when it's not | root = overlay |
| ordinary package crate | root = overlay | root = overlay |

In every case, `cargo creusot new`/`init` writes `why3find.json` next to the
parent `Cargo.toml`, whatever the overlay contains.

**End-to-end run** (2026-10-28). Tools: `cargo-creusot 0.15.0-dev` installed
from that commit with `./INSTALL`, Rust `nightly-2026-08-03`, Why3 1.8.2+git,
why3find v1.3.0+dev, Alt-Ergo 2.6.4, Z3 5.3.2, CVC4 1.8, CVC5 1.4.1, cargo
1.88.0. Each case runs `cargo creusot new p` in a parent directory, applies the
listed fix to `p/`, then runs `cargo creusot` in `p/`. The goal is the
generated `add_one` function.

| Case | Parent `Cargo.toml` | Fix applied to `p/` | `why3find.json` written to | `cargo creusot` in `p/` |
|---|---|---|---|---|
| A | none | none | `p/` | proved |
| B | empty file (the bug report) | none | parent | fails: `cargo metadata` cannot parse the parent manifest |
| C | empty file | `[workspace]` | parent | fails: `p/why3find.json not found` |
| D | empty file | `[workspace]` + copy `why3find.json` | parent | proved |
| E | real workspace | `[workspace]` | parent | fails: `p/why3find.json not found` |
| F | real workspace | `[workspace]` + copy | parent | proved |
| G | package crate (overlay inside the crate) | none | parent (the crate) | fails: `p/why3find.json not found` |
| H | package crate | `[workspace]` + copy | parent (the crate) | proved |

In every case with a parent `Cargo.toml`, `new` also created a `.gitignore`
next to it, because none existed there. A parent that already has a
`.gitignore` keeps it unchanged; a cloned crate usually has one. In G and H
that means `why3find.json` (and, without an existing `.gitignore`, a new one)
were added to the crate's own source directory, which is why step 1 forbids
putting the overlay inside the crate.

**Conclusion.** An empty `[workspace]` table alone does not avoid the problem
(cases C, E). Together with copying `why3find.json` into the overlay, it does
(D, F, H). Steps 3 and 4 of §4.3.5 are both required. Step 4 also has to
remove the files `new` left in the parent directory.

The installer also edits `~/.cargo/config.toml` to point `creusot-std` at the
Creusot checkout (`[patch.crates-io] creusot-std = { path = ... }`), so the
checkout must stay where it was installed from. `creusot-launch` records that
path with the toolchain versions.

#### 4.3.7 Roadmap for the Rust layer

Each step adds or changes template files; `auto-wp.py` itself does not change.

1. **`creusot-launch`** (§4.3.5), in `templates/rust/skills/`, including its
   faithfulness (stripping) script. Installed with `--rust` only.
2. **Make `rmf-sl` language-independent.** Its `SKILL.md` mentions Frama-C or
   ACSL 34 times (37 counting WP), mostly to say that the risk study is
   handed to `frama-c-launch` and checked by `rmf-lint.sh`. Rewrite them to
   name "the launch loop (`frama-c-launch` or `creusot-launch`)", and make the
   lint gate available to both languages. The skill stays in
   `templates/common/`.
3. **Make `ebios-sl` language-independent**, in the same way: it hands its
   result to `frama-c-launch` (16 mentions) and uses `ebios-lint.sh` as its
   gate.
4. **Rust `/rmf` and `/ebios` commands**, in `templates/rust/commands/`:
   run `rmf-sl` (or `ebios-sl`) without reading the code, then
   `creusot-launch` and `creusot-monitoring`. Modelled on
   `use-frama-c/config/commands/rmf.md` and `ebios.md`.
5. **Creusot `time-loop`**, in `templates/rust/skills/time-loop/` plus a
   `templates/rust/commands/time-loop.md`: the time-budgeted loop that drives
   the Rust `/rmf`. The C version's `SKILL.md` names Frama-C 63 times, and
   about 200 times counting ACSL and WP, so this is a port rather than a
   copy. It comes last because it depends on steps 1–4.

Until a step is done, its files are absent and `--rust` installs whatever the
Rust layer contains at that point.

### 4.4 Seeding rules

These rules apply to both source repositories. When copying from
`use-frama-c/config/` or `use-creusot/`:

- Skip editor backups (`*~`) and `use-creusot/config/foo/`.
- Copy skill directories whole, including `references/`, `templates/`,
  `scripts/`, `canaries/`, `getting-better/` and `bugs-to-report/`, keeping
  permission bits (in `use-frama-c`, 4 of the 7 `sl-internal/scripts/*.py`
  are executable; in `use-creusot`, only `sl_disjointness_check.py` is).
- Do not rewrite `config/...` paths: they stay valid because the project
  installs into `config/` (§3.2).
- The only content changes are the `creusot-sl` packaging of §4.3.2, the
  path rewrites below, and the three `time-loop` changes of §4.2.2 (deadline kept on a re-run; report in
  `XXX.md`; no "diminishing returns" stop). Known defects in the sources (§4.3.3) are copied as they are.
- Hard-coded paths into `use-frama-c` are rewritten to the project root,
  where `bin/fetch-sources.sh` puts `macsl/`: in
  `frama-c-monitoring/canaries/macsl-contexts-sync.sh` (default `MACSL_CMXS`
  computed from the script's own location),
  `frama-c-api/references/macsl-contexts.md`,
  `time-loop/getting-better/20260628-1000-macsl-context-vocabulary-under-surfaced.md`
  and `frama-c-monitoring/references/framac-workflow.md` (default `repo` is
  `.`). After seeding, no file under `templates/*/skills/` mentions
  `use-frama-c`.
- Root-level tools of `use-frama-c` are copied into `templates/c/tools/`,
  the scripts into `templates/c/tools/bin/` (§4.2.1). Every mention of one of
  these scripts in the skills, commands and README, bare (`rmf-lint.sh`) or
  with `./`, is rewritten to `bin/<name>.sh` (152 rewrites in 38 files). No
  other file named like them exists in the templates, so the rewrite is
  unambiguous; test T7 of `tests.md` keeps it so. Their historical notes (the `lsl-mul-pow2-regression`
  reproduction recipes, which name the opentitan campaign directories in
  `use-frama-c`) are kept as they are; no skill runs them.

## 5. Tests

`tests/test_auto_wp.py`, runnable with `python3 -m unittest`, working in a
temporary directory. Unless stated otherwise, each test runs the program as a
subprocess.

1. `--c foo` creates `foo/config/skills/frama-c/SKILL.md`,
   `foo/config/commands/rmf.md` and `foo/config/skills/sl-internal/SKILL.md`,
   21 skill directories and 3 commands, and no `creusot*` skill (in particular
   no `creusot-launch`).
2. `--rust foo` creates `foo/config/skills/{creusot,creusot-launch,creusot-monitoring,creusot-sl}/SKILL.md`,
   16 skill directories and no command, and no `frama-c*` skill.
   `foo/config/skills/sl-builder/SKILL.md` is identical to
   `templates/rust/skills/sl-builder/SKILL.md`, and
   `foo/config/skills/sl-internal/scripts/no_ceiling_gate.py` does not exist
   (the override replaces the whole directory).
3. No language flag behaves like `--c`.
4. `--c --rust foo` exits 2 and creates nothing (`foo` does not exist
   afterwards).
5. `--help` exits 0.
6. Running twice on the same directory: the second run exits 1 and leaves the
   first run's files unchanged.
7. A pre-existing file in the target directory is preserved.
8. A pre-existing `foo/.claude/settings.json` is preserved and the run
   succeeds; a pre-existing `foo/.claude/skills` or `foo/config` makes the run
   exit 1 and change nothing.
9. `foo/.claude/skills`, `foo/.claude/commands` and `foo/.agents` are relative
   symlinks resolving to `foo/config/skills`, `foo/config/commands` and
   `foo/config`.
10. For both `--c` and `--rust`, every file under `foo/config/skills/` has the
    same executable bit as its template (this covers `sl-internal/scripts/*.py`
    and `frama-c-monitoring/canaries/*.sh`).
11. `config/auto-wp.json` is valid JSON; its `skills` and `commands` lists
    match the directories under `config/skills/` and the files under
    `config/commands/`.
12. Running from another working directory (`cd /tmp && /path/to/auto-wp.py --c foo`)
    still finds the templates.
13. `--c foobar` writes `foobar/README.md`, which contains
    `git clone https://gitlab.freedesktop.org/gnu-grub/grub.git`,
    `/time-loop grub 72` and `bin/fetch-sources.sh`, and contains no `{{`,
    no `~/git/` and no `UFC`.
13b. `--c foobar` copies the tools of §4.2.1 to `foobar/` as regular files
    (21 `bin/*.sh` and no `*.sh` at the root, `frama-c-patches/apply.sh`,
    `framac-gold/`, `no-ceiling.md`, `.gitignore` listing `/framac-src/`),
    with the executable bit on every script; `--rust` creates no `bin/`; an existing `foo/.gitignore` is kept and
    reported with `kept`.
14. `--rust foobar` writes a README that contains `creusot-launch`, and
    contains the string `/time-loop mycrate 72` **if and only if**
    `templates/rust/commands/time-loop.md` exists.
15. `--c .` run inside a directory named `bar` writes a README whose title
    starts with `# bar`.
16. A pre-existing `foo/README.md` is unchanged after a successful run, and
    the output contains `kept    foo/README.md (already exists)`.
17. `foo` becomes a git work tree after a run; if `foo` is created inside an
    existing git work tree, no `foo/.git` is created.
18. With `PATH` set so that `git` cannot be found, the run succeeds, prints
    the warning of §3.5, and creates no `.git`.
19. Rollback: with a template file made unreadable (or the copy function
    patched to raise after a few files, when testing in-process), the run
    exits 1 and leaves the target directory exactly as before. When the run
    had created `foo`, `foo` no longer exists.

## 6. Out of scope for version 0.1.0

- Updating an existing project from newer templates (`--update`).
- Merging the divergent SL skills into one common version, and fixing the
  known defects listed in §4.3.3.
- Generating `CLAUDE.md`/`AGENTS.md` or source scaffolding inside the project.
- Adding a git remote or making a first commit.
- Running any analysis.
