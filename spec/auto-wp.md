# auto-wp — specification

`auto-wp.py` bootstraps a new verification project: it creates a directory
pre-loaded with the agent configuration (skills and slash commands) needed to
drive a formal-verification campaign on C or Rust code. The configuration is
modelled on `../use-frama-c/config/` (C) and `../use-creusot/config/` (Rust).

Version described: **0.3.0**. Compared with 0.2.0, the common layer has a
`tools/` directory of its own, merged with the language layer's (§3.6, §4.1):
`bin/rmf-lint.sh`, the machine gate of the `rmf-sl` risk study, is installed
in Rust projects too, its endogeneity tripwire recognises Rust code as well
as C, and `rmf-sl` names its Rust consumer, `creusot-monitoring` (§4.3.4).
Compared with 0.1.0, the 0.2.0 generated project
also carries a Workshop definition (`.workshop/`, §3.7), so that its
toolchain can come from the SDKs of `sdks/` (§4.5) instead of being built in
the container; the README's quick start gains the matching Workshop and
Multipass routes (§3.4). The 0.1.0 behaviour (LXD container, toolchain built
by hand or by `frama-c-launch`) is kept as the fallback.

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
`.agents` and `.claude/{skills,commands}`, the tools of the language layer,
a `README.md`, a Workshop definition in `.workshop/` (§3.7), and a git
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
   it: `config`, `.agents`, `.claude/skills`, `.claude/commands`, a
   `.claude` that is not a directory, `.workshop/autowp.yaml`,
   `.workshop/autowp-packages`, or a `.workshop` that is not a directory
   (the list `RESERVED` in the program). An existing `.claude/` directory is
   fine (it often holds `settings.json`) and is reused; so is an existing
   `.workshop/` directory (a checkout that already has workshops of its own,
   §3.7.4). Other existing content is left untouched, so `auto-wp.py` can be
   run inside an existing source checkout.

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

Only `skills/` and `commands/` go into `config/`. A layer's `tools/` goes to
the project root (§4.2.1) and its `workshop/` to `.workshop/` (§3.7); other
files at a layer's root (such as `README.md`, §3.4) are not copied.

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
  "auto_wp_version": "0.3.0",
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
   prerequisites of item 4 are met. It runs Claude Code in a container,
   because the campaign runs for days with `--dangerously-skip-permissions`:
   the agent can then change only the container and `foobar`, which is
   mounted into it, not the user's other files, SSH keys or Claude login.
   The README gives three ways to get that container, in this order, and
   the user follows one of them:

   - **A. Workshop (Linux)**: the container is a workshop built from
     `.workshop/autowp.yaml` (§3.7); the toolchain comes from the SDKs
     (§4.5) and nothing is built in the container.
   - **B. Multipass (macOS)**: Workshop runs only on Linux, so on a Mac the
     README creates an arm64 Ubuntu VM with Multipass and follows A inside
     it, with the arm64 builds of the SDKs.
   - **C. LXD (fallback)**: a plain LXD container, in which the toolchain is
     built, by `frama-c-launch` on its first run (C) or by hand (Rust). It is
     the way for a Linux host without Workshop (and, until the arm64 SDKs
     are on the SDK Store, §3.7.3, the simpler way on an arm64 host).

   Each way has a step 1 (*on the host*) and a step 2 (*in the container*)
   that end with `claude --dangerously-skip-permissions`. Step 3 (*in the
   harness*) and the explanations that follow it are written once, after
   the three (item 2D below), with the few lines that differ per way marked
   there: the path of the project in the container, the command to come
   back to the run, the command that removes the container. The README
   does not repeat the `/time-loop grub 72` explanation per way.

   Status (2026-11-05): C is the quick start verified on the dates its
   notes give. A and B are design: the SDKs they rely on are built and
   tested (§4.5), but no generated project has yet been launched from its
   `.workshop/autowp.yaml`, and the README must not claim otherwise. The
   facts of B that were observed on a Mac are dated below; the rest is to
   be verified (§7).

   **2A. Workshop (Linux).**

   1. *On the host*, in `foobar`, the directory of the README:

      ```
      workshop launch
      workshop shell
      ```

      The README says what `workshop launch` does: it reads
      `.workshop/autowp.yaml`, creates an LXD container named `autowp`,
      installs the SDKs listed there (for C: Frama-C 32.1 with WP, macsl,
      Why3, Coq 8.20.1 for WP, Alt-Ergo and Z3; Rocq 9.2; Lean 4 with elan,
      Lake and lean-lsp-mcp; for Rust: Creusot with its Rust nightly, Why3,
      why3find and the provers, instead of Frama-C) and the project's own
      apt packages (`.workshop/autowp-packages/`, §3.7.2), then mounts
      `foobar` at `/project`. It takes minutes, mostly to download the
      SDKs (packed, amd64, measured 2026-10-31 and 2026-11-01: 929 MB
      Frama-C, 400 MB Rocq, 684 MB Lean, 438 MB Creusot). `workshop shell`
      opens a login shell in `/project` as the user `workshop`, who maps to
      the host user, so the files the agent creates belong to the user on
      the host (Workshop's documented behaviour, the counterpart of
      `shift=true` in C; not yet verified by auto-wp with a campaign). One
      paragraph says that `workshop info` shows the status, which is
      `ready` only when every SDK's health check passed, and that a failed
      launch is read with `workshop changes` and `workshop tasks`, or
      re-run with `workshop launch --verbose --wait-on-error`. One
      sentence says that the SDKs come from the SDK Store, channel
      `latest/edge` (§3.7.3), so that nothing beyond Workshop is needed on
      the host, and that `latest/edge` is where auto-wp's builds appear
      first; the README does not describe the `try-` route, which is for
      testing unpublished SDK changes from the auto-wp repository, not for
      users. The commands name no workshop, which is valid
      while the project has one definition; a checkout with workshops of
      its own needs `workshop launch autowp` and `workshop shell autowp`.
   2. *In the workshop*, where the shell already is in `/project`:

      ```
      git clone https://gitlab.freedesktop.org/gnu-grub/grub.git
      git config user.name "Your Name"
      git config user.email "you@example.com"
      git init --bare ~/foobar.git
      git remote add origin ~/foobar.git
      bin/fetch-sources.sh
      curl -fsSL https://claude.ai/install.sh | bash
      . ~/.profile
      tmux new -s wp
      claude --dangerously-skip-permissions
      ```

      Compared with step 2 of C: no `cd foobar` (the shell starts in
      `/project`); no `opam init`, since nothing is built and the SDK's
      opam switch is read-only; `bin/fetch-sources.sh` stays, and in a
      workshop, where `FRAMA_C_SDK_SRC` is set, it links `framac-src` to the
      SDK's patched Frama-C sources instead of downloading the archive, and
      still clones `macsl/` (§4.5 item 1, written but not yet run in a
      workshop). The login paragraph (URL and
      code, never copy `~/.claude/.credentials.json`) is the same as in C.
      One line says that Alt-Ergo, bundled in the Frama-C and Creusot SDKs,
      is under the OCamlPro Non-Commercial Purpose License (research use
      only; the licence files are in the SDK under
      `share/licenses/alt-ergo/`), and that WP and Creusot still have Z3
      (and CVC5) without it. One paragraph says what `workshop refresh` and
      `workshop restore` do during a campaign: they rebuild the container
      outside `/project` and the SDK mounts, so Claude Code, its login and
      `~/foobar.git` are gone afterwards and the last lines of step 2 must
      be run again, while `~/.cargo`, `~/.rustup` and `~/.elan` survive,
      being mount plugs of the SDKs; so no refresh while a run is going.

   **2B. Multipass (macOS).** Workshop runs only on Linux. On a Mac the
   README uses Multipass to create an arm64 Ubuntu VM, installs Workshop in
   it, and follows 2A inside it with the arm64 SDKs. Everything in this
   item is design except the facts dated 2026-11-05, which were observed on
   an Apple Silicon Mac running macOS 15, where a VM was created with the
   values shown; no workshop of a generated project has been launched
   there yet.

   1. *On the Mac*:

      ```
      multipass launch 24.04 --name autowp --cpus 6 --memory 12G --disk 150G
      multipass shell autowp
      ```

      These are the sizes used on 2026-11-05; smaller ones have not been
      tried, and the README says so rather than giving a minimum. The disk
      holds the VM's LXD storage pool for the workshop (the SDKs, the
      Frama-C sources and the project's builds), so it is the value to be
      generous with. *In the VM*, install LXD 6 (Ubuntu 24.04 images ship
      LXD as a snap; Workshop needs 6.8 or later), Workshop and, until the
      arm64 SDKs are on the SDK Store (§3.7.3), sdkcraft:

      ```
      sudo snap refresh lxd --channel=6/stable || sudo snap install lxd --channel=6/stable
      sudo lxd init --auto
      sudo usermod -aG lxd "$USER"
      sudo snap install --classic workshop
      sudo snap install --classic sdkcraft
      ```

      then leave the VM shell and open it again, so the group change
      applies. Until the arm64 SDKs are on the Store, one paragraph says
      that the VM must get them another way: `sdkcraft try` in each
      `sdks/<name>/` of a clone of the auto-wp repository (hours for
      Frama-C and Creusot), then `try-<name>` in place of each Store entry
      of `.workshop/autowp.yaml`, by hand, in the VM's copy of the project
      (§3.7.3; whether the arm64 `.sdk` files built by CI can be used
      instead is open, §7). This paragraph leaves the README with the arm64
      publication.
   2. *Get the project into the VM.* The project must be in the VM's own
      filesystem. Either generate it there (`auto-wp.py` runs on Linux; the
      auto-wp repository is cloned in the VM for that, and until the arm64
      publication it is needed there anyway), or copy a project
      generated on the Mac with `multipass transfer -r foobar autowp:`, or
      push it to a remote and clone it in the VM. The README says not to use
      `multipass mount`: Multipass mounts are SSHFS, and whether LXD can
      mount a directory that is itself an SSHFS mount into the workshop,
      with its id shifting, is unverified and expected to fail (§7). The
      consequence, which the README states: on macOS the project and its
      results live in the VM.
   3. *In the VM*, from the project directory: steps 1 and 2 of 2A. On arm64
      the Creusot SDK has no CVC4 (no arm64 build exists) and its Alt-Ergo
      is built from opam, so Creusot projects there prove with Alt-Ergo, Z3
      and CVC5; the C side is the same as on amd64 (§4.5 for the test
      status of the arm64 SDKs).
   4. *Getting results out*: `multipass transfer -r autowp:foobar/grub.md .`
      for a file or a directory, or, from a VM shell, `git push` of `foobar`
      to a remote the user controls; the agent's own remote stays the bare
      repository inside the workshop.
   5. *Keeping the run going*: the VM does not run while the Mac sleeps, so
      a campaign needs the Mac kept awake for its whole budget, for example
      with `caffeinate -s` in a terminal on the Mac (observed 2026-11-05).
   6. *One troubleshooting line*: `multipass shell` fails with
      `ssh connection failed: 'Failed to connect: No route to host'` when it
      is run from an SSH session into the Mac, and works from the Mac's own
      console (seen 2026-11-05 on macOS 15; the likely cause is macOS's
      Local Network privacy setting). Workarounds: start `tmux` at the Mac's
      console and attach to it from the SSH session, or reach the VM
      directly with `ssh -J <mac> ubuntu@<vm-ip>` (the IP from
      `multipass info autowp`, after adding a public key to the VM's
      `~/.ssh/authorized_keys`).

   **2C. LXD (fallback).** The quick start of version 0.1.0, unchanged in
   substance. The README introduces it as the way for a host without
   Workshop. Three steps:

   1. *On the host*. In the C README this step is one command,
      `bin/launch_lxc.sh` (§4.2.1), run from `foobar`; the script finds the
      project from its own path, takes `CT` and `NET` from the environment,
      stops if the container already exists, and the README lists what it
      does in five bullets (network, container, mount, packages, AppArmor).
      The Rust README, whose project has no `bin/`, gives the same commands
      inline. The commands: starting in `foobar`, the directory of the
      README, `cd ..` (the mount line uses `$PWD/foobar`, and running it from
      inside `foobar` fails with "Missing source path", seen
      2026-10-30); set
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

   **2D. In the harness** (shared by A, B and C):

   ```
   /time-loop grub 72
   ```

   with how to detach from `tmux` and re-attach: `workshop shell`, then
   `tmux attach -t wp` (A; in B after `multipass shell autowp`), or
   `lxc exec wp-foobar -- sudo -iu ubuntu tmux attach -t wp` (C).

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
   - with C, on the first run `frama-c-launch` builds the toolchain in the
     container, which takes hours of the budget; with A and B the SDK
     provides it and no hour goes to the build;
   - the loop commits a checkpoint after every cycle and pushes it, so
     `foobar` needs a git identity and a remote (`auto-wp.py` has already run
     `git init`, §3.5). The remote is a bare repository in the container, so
     no credential enters it. The files and the commits (`foobar/.git`) are
     on the host through the mount (`/project` with A, the LXD disk device
     with C), so nothing has to be copied out; with B they are in the VM
     (2B, step 4);
   - the agent can write anything in `foobar`, `.git/hooks/`, `bin/` and
     `.workshop/` included, so the README says to check, before running git
     or a script there on the host, that `.git/hooks/` holds only `*.sample`
     files and to read `git diff` of `bin/` and, before the next
     `workshop launch` or `refresh`, of `.workshop/` (its hooks run as root
     in the container);
   - `grub/` is a separate git repository; git does not track it inside
     `foobar` unless it is added as a submodule;
   - `workshop remove` (A, B) or `lxc delete --force wp-foobar` (C) removes
     the container and the login, and leaves `foobar` and its results where
     they are. With A and B, `foobar` must never be deleted before
     `workshop remove`, or the workshop is orphaned, and `.workshop.lock`,
     which `workshop launch` writes in `foobar`, is listed in `.gitignore`
     (§4.2.1) and must not be copied with the project. With C, the
     container name must contain only letters, digits and hyphens.

   One closing paragraph says `claude` can also run directly in `foobar` on
   the host, with the agent acting with all the user's rights, so the
   permission prompts stay on.
3. **Other commands**: one line each for `/rmf <dir> <dir>-analysis` (a single
   campaign without a time budget), `/ebios`, and the `/time-loop` options
   (`--dir=`, `--machdep=`, `--linux`, `--full-tu`, `--fresh`, `--no-coq`),
   pointing to `config/commands/time-loop.md` for details.
4. **Prerequisites**:
   - On the host, one of:
     - *A, Linux:* LXD 6.8 or later and Workshop
       (`sudo snap install --channel=6/stable lxd`, or a `snap refresh` to
       that channel, then `sudo snap install --classic workshop`), and
       nothing else: the SDKs come from the SDK Store (§3.7.3). Only
       Linux, amd64: Workshop does not run on macOS or Windows, and the
       arm64 SDKs are not on the Store yet.
     - *B, macOS:* Multipass on an Apple Silicon Mac; the rest is installed
       in the VM (2B), including, until the arm64 SDKs are published,
       `sdkcraft` and a clone of the auto-wp repository to build them.
     - *C:* LXD usable by the user, and nothing else.

     The project is stand-alone: it never refers to a checkout on the host
     such as `~/git/use-frama-c`. The tools the C skills call from the
     project root are copied into it (§4.2.1), and `bin/fetch-sources.sh`
     (step 2) downloads, or in a workshop links, the two trees too large to
     ship. The one exception, stated as such and temporary, is B until the
     arm64 SDKs are published: the SDKs must then be built in the VM from
     the auto-wp repository (§3.7.3, §7). The generated project itself
     still names no host path.
   - In the container: Claude Code (installed in step 2), and Frama-C 32.1
     with WP and the provers, in the `framac-coq8` opam switch. With A and
     B the switch is the one the `frama-c-sdk` SDK ships, read-only under
     `/opt/frama-c-sdk`, with `frama-c`, `why3`, `alt-ergo` and `z3` on
     `PATH` and the variables `FRAMA_C_SDK_SWITCH`, `FRAMA_C_SDK_MACSL`,
     `FRAMA_C_SDK_SRC` set; `frama-c-launch` accepts it on its first run
     (§4.5 item 2, written but not yet run in a workshop). With C,
     `frama-c-launch` checks the toolchain on the
     first run and builds it from `framac-src/` (fetched with
     `frama-c-patches/` applied) if it is missing.
   - Optional: `~/.local-llm-machine-ip.txt` in the container, one line with
     the IP of a local LLM host (for example an ollama server) that the
     container can reach. It is used by the cross-provider judge in
     `sl-auditor` and `no_ceiling_gate.py`. Without it those steps are
     advisory, and `sl-auditor` asks the user before going on.
5. **What is in this directory**: `config/` (skills and commands, listed in
   `config/auto-wp.json`), `.agents` and `.claude/` (links to it), the tools
   of §4.2.1 (the scripts in `bin/`), what `bin/fetch-sources.sh` downloads,
   and `.workshop/` (§3.7): the Workshop definition `autowp.yaml` and the
   project-local SDK `autowp-packages/`, whose `hooks/setup-base` holds the
   apt packages of the code under study, to be edited for another code
   base (then `workshop refresh`). One line saying the
   skills can be edited in place and that the loops add what they learn under
   `config/skills/*/getting-better/` and `config/skills/*/references/learned-*.md`.

**Content of the Rust README** (`--rust`). Same five items, with these
differences:

- *Quick start.* It uses a Rust crate instead of GRUB, with the same three
  ways A, B and C and the same shared item 2D, with `foobar` mounted the
  same way.
  - *A (Workshop)*: step 1 is the same two commands; `workshop launch`
    installs the `creusot` SDK (Creusot at `f15b985`, its Rust nightly,
    Why3, why3find, Alt-Ergo, Z3, CVC4 and CVC5), Rocq, Lean and the
    project's packages. Step 2, in `/project`: `git clone <crate-url>
    mycrate`, the git identity and the bare remote, the Claude Code
    install, `tmux` and `claude`; no opam, no rustup, no Creusot checkout
    and no `./INSTALL`, and no `bin/fetch-sources.sh` (the Rust project
    has none). The SDK's `setup-project` has already pointed
    `~/.cargo/config.toml` at the SDK's Creusot sources, so the "keep the
    checkout where it was installed from" rule of C does not apply. The
    Alt-Ergo licence line is the same as in the C README.
  - *B (Multipass)*: the same as for C, with the arm64 note of 2B step 3
    (Alt-Ergo, Z3 and CVC5; no CVC4).
  - *C (LXD)*: step 1 installs the Creusot build dependencies instead (the
    list of `tests/rust/provision.sh`). Step 2 runs
    `opam init --disable-sandboxing -y --bare`, installs rustup, clones
    Creusot into `~/git/creusot` and runs its `./INSTALL`, then
    `cd foobar`, `git clone <crate-url> mycrate`, the git identity and the
    bare remote, the Claude Code install, `tmux` and `claude`.

  Until roadmap
  step 5 (§4.3.7) is done, there is no `/time-loop` command for Rust, so the
  README must not contain the string `/time-loop mycrate 72`. Step 3 (2D) is
  instead a plain request: `onboard the crate mycrate with creusot-launch,
  then analyze it with creusot-monitoring`.
  When `templates/rust/commands/time-loop.md` exists, the template is updated
  to show `/time-loop mycrate 72`, exactly as in the C README. This is a
  template change only; the program does not change.
- *Other commands.* While `config/commands/` is empty for Rust, this item says
  there are no slash commands yet and lists the skills to ask for by name:
  `creusot-launch`, `creusot-monitoring`, `creusot-sl`, `creusot`, and
  `rmf-sl` (the code-blind risk study, `mycrate-analysis-rmf-report.md`,
  checked by `bin/rmf-lint.sh`, which `creusot-monitoring` uses to rank what
  to prove; the item gives the request that asks for both).
- *Prerequisites.* On the host, the same three options as for C. In the
  container, Creusot
  (`cargo creusot`), Why3, why3find, the solvers (Alt-Ergo, Z3, CVC4, CVC5),
  and the nightly toolchain pinned by Creusot: with A and B from the
  `creusot` SDK (`cargo creusot` on `PATH`, `CREUSOT_SDK_SRC` and
  `CREUSOT_SDK_COMMIT` set, `~/.cargo` and `~/.rustup` seeded and kept
  across refreshes), with C installed in step 2. One
  line says `creusot-launch` checks them but does not install them, and that
  with C the Creusot checkout must stay where it was installed from (§4.3.6). No
  `use-frama-c` checkout is needed. The optional
  `~/.local-llm-machine-ip.txt` line is the same as for C.
- *What is in this directory.* `bin/` holds only `bin/rmf-lint.sh` (§4.1),
  run from the project root; `.workshop/` as for C, with
  `autowp-packages/hooks/setup-base` holding only `tmux` and `curl` and a
  comment where to add the crate's own apt packages (§3.7.2).
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
    skills:   22
    commands: 3
  copied  foobar/.gitignore
  copied  foobar/bin
  copied  foobar/frama-c-patches
  copied  foobar/framac-gold
  copied  foobar/no-ceiling.md
  copied  foobar/.workshop (workshop: autowp)
  linked  foobar/.agents          -> config
  linked  foobar/.claude/skills   -> ../config/skills
  linked  foobar/.claude/commands -> ../config/commands
  wrote   foobar/README.md
  git     initialized foobar
  ```

  and exit 0. With `--rust` the counts are `skills: 17` and `commands: 0`
  (§4.3.2), and the only `copied` lines are `foobar/.gitignore` (the Rust
  layer's `tools/` holds nothing else, §4.3.2), `foobar/bin` (the common
  layer's `bin/rmf-lint.sh`, §4.1) and `foobar/.workshop`. An entry of
  `tools/` present in both layers is merged when it is a directory (`bin/`:
  the C project's `bin/` holds the common script and the 21 C ones; the
  language layer's file wins on a same-named file) and is the language
  layer's when it is a file. An entry of `tools/` that already exists in
  the target is not overwritten: the program prints
  `kept    foobar/<name> (already exists)` instead of its `copied` line. The `.workshop` entries have no `kept` case: they are
  reserved (§3.1 item 3), so an existing one is a run-time error. The `git`
  line reads `git     foobar is already in a git work tree` when nothing
  was done.
- Usage errors (unknown option, both `--c` and `--rust`, missing or extra
  positional argument): message on stderr, exit 2 (`argparse` default).
  Nothing is created.
- Run-time errors (target is a file, one of the paths of §3.1 item 3 already
  present, missing template directory, I/O error, `git init` failing): message
  on stderr prefixed with `auto-wp: error:`, exit 1.
- **Rollback.** On a run-time error, at whatever point it happens, remove
  everything this run created, in reverse order: `.git/` (if this run
  initialised it), `README.md`, the three links, `.workshop/autowp.yaml` and
  `.workshop/autowp-packages/` then `.workshop/` itself (only if this run
  created it and it is now empty), the copied tools, `.claude/` (only if this run
  created it and it is now empty), `config/`, and `<directory-name>` itself
  plus any parents (only those this run created, and only if empty). Never
  remove anything that existed before the run. A re-run then starts from the
  same state as the first one.

### 3.7 `.workshop/` — the Workshop definition

So that the generated project can run in a [Workshop](https://ubuntu.com/workshop/docs/)
workshop (quick start A of §3.4), `auto-wp.py` writes a definition and a
project-local SDK into `<directory-name>/.workshop/`. The design is
`spec/workshop-autowp-c-base-spec.md` §3.5 and §6 and
`spec/workshop-autowp-rust-base-spec.md` §7; the SDKs themselves are in
`sdks/` (§4.5). Facts about Workshop this section relies on
(`templates/common/skills/workshop/`, read 2026-11-05): a definition is
`.workshop/<name>.yaml` with `name`, `base` and an ordered list of `sdks`;
`workshop launch` builds the container and `workshop shell` opens it, with
the project mounted at `/project` and the user `workshop` mapped to the host
user; an in-project SDK is a directory `.workshop/<name>/` holding an
`sdk.yaml` (only `name` is required) and `hooks/`, and is listed as
`project-<name>`; SDKs are installed in list order, each in its own
snapshot layer, and a change to one reinstalls it and every SDK listed
after it; Workshop runs only on Linux and needs LXD 6.8 or later.

#### 3.7.1 What is written

```
<directory-name>/.workshop/
├── autowp.yaml                 the definition (workshop name: autowp)
└── autowp-packages/            the project-local SDK, listed as project-autowp-packages
    ├── sdk.yaml
    └── hooks/
        └── setup-base          executable; apt-get install of the project's packages
```

The three files come verbatim from `templates/c/workshop/` or
`templates/rust/workshop/` (§4), copied like the tools of §4.2.1 (byte for
byte, permission bits kept, `*~` skipped) to `<directory-name>/.workshop/`,
which is created if missing. There is no common layer for `workshop/`: the
definition differs per language in full. The program replaces no
placeholder in them (the workshop name is the fixed `autowp`, not the
project's name, so that the commands of the README are the same for every
project and no name rule of Workshop's is hit). The files are therefore
template changes only, and what follows fixes their content.

`.workshop/autowp.yaml` for `--c`:

```yaml
# Workshop definition written by auto-wp.py. From this directory:
#   workshop launch      builds the container (SDKs below, this directory at /project)
#   workshop shell       opens a shell in it as the user "workshop"
# Edit .workshop/autowp-packages/hooks/setup-base for the apt packages of
# the code under study, then `workshop refresh`.
name: autowp
base: ubuntu@24.04      # or ubuntu@26.04; the SDKs are built for both
sdks:
  # From the SDK Store. latest/edge is where auto-wp's builds are released
  # first; change the channel to a stable one (for example 32/stable for
  # frama-c-sdk) when it exists, then `workshop refresh`.
  - name: frama-c-sdk            # Frama-C 32.1 with WP, macsl, Why3, Coq 8.20.1, Alt-Ergo, Z3
    channel: latest/edge
  - name: rocq                   # Rocq 9.2, for the rocq skill
    channel: latest/edge
  - name: lean                   # Lean 4 (elan, Lake, lean-lsp-mcp), for the lean skill
    channel: latest/edge
  - name: project-autowp-packages   # this project's apt packages (.workshop/autowp-packages/)
```

For `--rust`, the same file with `creusot` in place of `frama-c-sdk`
(comment: `Creusot f15b985, its Rust nightly, Why3, why3find, Alt-Ergo, Z3,
CVC4, CVC5`; its future stable channel is `0.15/stable`), the same
`channel: latest/edge`, and the two others unchanged. The names and the
channel are explained in §3.7.3. `rocq` and `lean` are listed by default in
both languages (decided 2026-11-05; this settles open point 8 of the C base
spec): they are common skills, the three SDKs together add about 1.1 GB of
download and were tested together with each language's SDK (§4.5), and a
user who wants neither deletes two lines. The project-local SDK is listed
last, so that editing its package list, the one change a user is expected
to make, reinstalls only that layer on `workshop refresh`.

#### 3.7.2 The project-local SDK

The SDKs of §4.5 carry the toolchains and the packages every campaign runs
(the Frama-C SDK: `build-essential`, `pkg-config`, `bear`, `git`, `ripgrep`,
`python3`; the Creusot SDK: `build-essential`, `pkg-config`, `git`, `curl`,
`ca-certificates`, `ripgrep`, `python3`). What the code under study needs
to configure and build is not theirs: it goes in the project, as the
in-project SDK `autowp-packages`, whose `setup-base` runs as root at launch
and on refresh, as the C base spec §3.5 asks (the spec names it
`autowp-project`; `autowp-packages` says what it holds, and the name is
otherwise free). `sdk.yaml`, the same in both languages but for the
example in the description:

```yaml
name: autowp-packages
version: "0.1"
summary: apt packages of the code under study, next to the auto-wp SDKs
description: |
  Project-local SDK written by auto-wp.py. Its setup-base installs, with
  apt, the build dependencies of the code under study (as generated: GRUB's)
  and the tools the README's quick start uses (tmux, curl). Edit
  hooks/setup-base for another code base, then run `workshop refresh`.
```

`hooks/setup-base` for `--c`, the GRUB build dependencies of
`bin/launch_lxc.sh` without the Frama-C ones, which the SDK makes
unnecessary (opam, the GTK and graphviz development packages, `rsync`,
`m4`, `unzip`, `libgmp-dev`, `zlib1g-dev`):

```bash
#!/bin/bash
# Runs as root when the workshop is launched or refreshed (apt is preset to
# -y and no recommends). The Frama-C toolchain comes from the frama-c-sdk
# SDK; this installs only what the code under study needs to configure and
# build (as generated: GRUB), plus tmux and curl for the README's quick
# start. Edit the list for another code base, then `workshop refresh`.
apt-get update
apt-get install tmux curl \
    autoconf automake autopoint gettext bison flex libtool \
    libdevmapper-dev libfreetype-dev libfuse3-dev liblzma-dev fonts-unifont
```

For `--rust`, the same header (with "the creusot SDK") and only
`apt-get install tmux curl`, with a comment saying where to add the crate's
own packages (for example a crate with C bindings). Both hooks must be
`bash`, executable, idempotent and ShellCheck-clean, as Workshop's hook
contract asks, even though in-project SDKs are not packed and so not
linted. No `setup-project` and no `check-health`: there is nothing to set
up per user, and Workshop's own in-project examples ship without a health
hook (`templates/common/skills/workshop/references/sdk-authoring.md`); that
such an SDK does not keep the workshop from `ready` is confirmed by the
first launch of a generated project (§7 item 5).

#### 3.7.3 Store names and the `latest/edge` channel

**Status (2026-11-05).** The four amd64 SDKs, for `ubuntu@24.04` and
`ubuntu@26.04`, are being uploaded to the SDK Store and released to
`latest/edge`. `creusot` 0.15.0-f15b985 is confirmed on the Store
(publisher Fabrice Derepas, licence field
`LGPL-2.1-or-later AND LicenseRef-OCamlPro-Non-Commercial-1.0`), which
also settles that the Store accepts an SDK bundling Alt-Ergo under its
non-commercial licence (C base spec §8, Rust base spec open point 5). The
upload of `frama-c-sdk`, `rocq` and `lean` is still running and their
acceptance is unconfirmed. The arm64 builds are not uploaded. Nothing in
this specification states that a generated project's `workshop launch`
succeeded; the README must not either until it is checked (§7 item 1).

**Decision (2026-11-05): Store names with `channel: latest/edge`.** The
definition is written for the published state: each SDK by its Store name,
on the channel where auto-wp's builds are released first. Once the upload
has succeeded, the quick start works as written with nothing on the host
but LXD and Workshop, and the generated project depends on no checkout, so
the stand-alone rule holds for amd64. An earlier draft of this section,
written the same day before the upload started, chose `try-` names so that
the quick start would work before publication; that would have tied every
generated project to this repository, and is superseded. The risk of the
chosen form is that `workshop launch` fails on the first entry if the
upload fails or is rejected; the fallbacks are the `try-` route below for
a developer, and quick start C for a user.

**Channels.** `latest/edge` receives every build. A stable channel per
track (`32/stable` for `frama-c-sdk`, `0.15/stable` for `creusot`,
`latest/stable` for `rocq` and `lean`) is promoted by hand after the
auto-wp level 3 test passes on an edge revision (C base spec §8). When a
stable channel exists, the template changes one `channel` line per entry
and test 20's expected channel; projects generated before that edit their
own file and `workshop refresh` (§6). Until then, `workshop refresh` on a
project pulls whatever is newest on edge, which the README's "no refresh
during a run" paragraph (§3.4 item 2A) already covers.

**`sdkcraft try` is for testing unpublished changes only.** A change to an
SDK's sources in `sdks/<name>/` is tested before upload with `sdkcraft try`
there (for `frama-c-sdk`, `prepare.sh` first), which puts the packed SDK in
the host's try area, and a test project whose definition names
`try-<name>` (what `sdks/test-sdk.sh` and the `make sdk-*` targets do;
`sdks/README.md`). A generated project can be pointed at a tried SDK the
same way, by editing its `.workshop/autowp.yaml` by hand, which is how item
5 of §4.5 will be tested before the changes are released. This is a
developer's route: the README does not describe it for Linux, and a
generated `.workshop/autowp.yaml` never contains a `try-` name (test 20).

**arm64 (quick start B).** Until the arm64 SDKs are on the Store, a Mac
user cannot use the definition as written: the VM must build the SDKs with
`sdkcraft try` from a clone of the auto-wp repository (hours for Frama-C
and Creusot), and the definition's entries must be edited to `try-<name>`
in the VM's copy of the project. The README's 2B says so in one paragraph,
which leaves it with the arm64 publication; whether the arm64 `.sdk` files
that `.github/workflows/sdks-arm64.yml` keeps as artifacts can be used
without rebuilding (copied into `~/.local/share/workshop/try/` by hand) is
not verified (§7). This is the one remaining dependency of a generated
project on this repository, and it is temporary and arm64-only; the
project's files still name no host path.

#### 3.7.4 Existing files, rollback, git

- `.workshop/autowp.yaml` and `.workshop/autowp-packages` are reserved
  (§3.1 item 3): if either exists, the run fails before writing anything,
  as for `config/`. A `.workshop` that is not a directory fails the same
  way. An existing `.workshop/` directory is reused and its other entries
  are left alone (a checkout may already define workshops of its own; the
  README's `workshop launch` and `workshop shell` then need the name
  `autowp`, §3.4 item 2A). The rule mirrors the one for `.claude/`.
- Rollback removes the two entries and then `.workshop/` itself, only if
  this run created it and it is now empty (§3.6).
- `.workshop/` is meant to be committed (Workshop's own guidance), and the
  time-loop's checkpoints commit it with the rest of the project.
  `.workshop.lock`, which `workshop launch` writes at the project root to
  tie the project to its workshops, must not be committed or copied:
  `.gitignore` lists it (§4.2.1, §4.3.2).
- The program does not run `workshop`, and §2 is unchanged: no network,
  `git` the only external program.

## 4. Templates

The templates ship in this repository, next to `auto-wp.py`, and are located
relative to the script (`Path(__file__).resolve().parent / "templates"`), not
relative to the current directory:

```
auto-wp/
├── auto-wp.py
├── spec/                 this file, tests.md, the Workshop SDK specs
├── tests/
├── sdks/                 the Workshop SDKs (§4.5); not read by auto-wp.py
└── templates/
    ├── common/{skills,commands}/
    ├── c/{skills,commands,tools,workshop}/ + README.md
    └── rust/{skills,commands,tools,workshop}/ + README.md
```

A layer's `workshop/` holds the three files of §3.7.1 and is copied to
`<directory-name>/.workshop/` (§3.7); only the language layers have one.

They are seeded once from `../use-frama-c/config/` (common and C layers) and
`../use-creusot/` (Rust layer), following §4.4, then maintained here, so
`auto-wp.py` works on a machine with neither repository, and the projects it
creates do not need them either (§4.2.1).

### 4.1 `templates/common/` — shared skills

Skills: `directory-structure`, `ebios-risk-manager`, `ebios-sl`, `lean`,
`polish-skill`, `rmf-sl`, `rocq`, `sl-auditor`, `sl-builder`, `sl-internal`,
`sl-monitoring-sl`, `stride`, `workshop` (13).

Commands: none.

Tools (since 0.3.0): `tools/bin/rmf-lint.sh`, the structure, coverage and
endogeneity linter that is the machine gate of `rmf-sl`, moved here from
`templates/c/tools/bin/` so that both languages install it as
`bin/rmf-lint.sh` (§3.6: `tools/` directories are merged across layers). Its
C8 endogeneity tripwire fails on C source artifacts (`.c`/`.h`, `#include`,
`#define`, `0x` hex, `::`, `->`) and on Rust ones (`.rs`, `fn name(`,
`impl X`, `unsafe {`, `#[attr]`, `&mut`, `Vec<`/`Option<`/`Result<`/`Box<`,
`macro!(`, `.unwrap()`) in R1–R4, whatever the language of the project; the
pinned format (`rmf-sl/references/report-format.md`, Rule 5) says so.

`workshop` is written for auto-wp, not seeded from a source repository: it
documents Workshop itself (definitions, the `workshop` commands, interfaces,
SDK authoring and publishing), so that the agent can operate the project's
workshop (§3.7) and diagnose it. It is in the common layer because both
languages use the same definition layout.

These cover the Squeeze Loop machinery, risk studies done without reading the
code (RMF, EBIOS, STRIDE) and the proof assistants used to discharge goals the
automatic provers cannot close. **They are not all language-independent
yet**: they were written for the Frama-C flow and still mention it (Frama-C,
ACSL or WP mentions per `SKILL.md`: `rmf-sl` 82, `sl-monitoring-sl` 61,
`ebios-sl` 48, `sl-builder` 47, `rocq` 10, `sl-internal` 10; counted before
0.3.0). `ebios-sl` hands its result to `frama-c-launch` and uses
`ebios-lint.sh` from the C layer as its machine gate. Since 0.3.0 `rmf-sl`
names both consumers — "the launch loop": `frama-c-launch` for C,
`creusot-launch` / `creusot-monitoring` (its Phase 0) for Rust — and its
gate `bin/rmf-lint.sh` ships with both languages (above); its Frama-C
examples and the C crosswalk references are kept. For `sl-builder`,
`sl-internal` and `sl-monitoring-sl` the mentions are examples and the method
applies to any language. For `ebios-sl` they are wiring, which roadmap step 3
(§4.3.7) makes language-independent. The four `sl-*` skills are replaced in
the Rust layer by the `use-creusot` versions (§4.3.3).

### 4.2 `templates/c/` — C with Frama-C/WP

Skills: `frama-c`, `frama-c-api`, `frama-c-internals`, `frama-c-launch`,
`frama-c-monitoring`, `framac-sl`, `linux-api`, `ocaml`, `time-loop` (9).

Commands: `ebios`, `rmf`, `time-loop`.

A `--c` project therefore has 22 skills (13 common + 9) and 3 commands.

`meta-penguin` is not included: it is `time-loop` specialised to two Linux
kernel subsystems of one campaign, not reusable for a new project.

#### 4.2.1 Root-level tools: `templates/c/tools/`

The C skills also call files from the project root, outside `config/`. In
`use-frama-c` they live at the root of the repository. The generated project
is stand-alone, so they ship in `templates/c/tools/`, and `auto-wp.py` copies
every entry of a layer's `tools/` to the project root (§3.6), keeping
permission bits. The layer holds:

- `bin/`, with every C script: 19 of the 20 `*.sh` scripts at the root of
  `use-frama-c`, each referenced from `config/` (`ebios-lint.sh`, the
  machine gate of `ebios-sl`; `framac-onboard.sh`, `framac-gen-report.sh`,
  `framac-squeeze-audit.sh`, `framac-monitor-check.sh`, `ledger-ratchet.sh`,
  `crosswalk-gen.sh` and the other `framac-*.sh`), plus `fetch-sources.sh`
  and `launch_lxc.sh` (step 1 of the README quick start), written for
  auto-wp: 21 scripts. The twentieth `use-frama-c` script, `rmf-lint.sh`,
  is in the common layer since 0.3.0 (§4.1) and merged into the same
  `bin/`, so a C project still has 22;
- `frama-c-patches/`, `framac-gold/` and `no-ceiling.md`, the data the
  scripts and skills read, at the project root as in `use-frama-c`;
- a `.gitignore`, written for auto-wp: `/framac-src/`, `/macsl/`, `_build/`
  and, since 0.2.0, `/.workshop.lock` (§3.7.4).

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
├── commands/                  empty
├── tools/
│   └── .gitignore             /.workshop.lock (§3.7.4); bin/rmf-lint.sh comes
│                              from templates/common/tools/ (§4.1, 0.3.0)
└── workshop/                  .workshop/ of a Rust project (§3.7.1)
    ├── autowp.yaml
    └── autowp-packages/{sdk.yaml,hooks/setup-base}
```

`tools/` and `workshop/` are additions of 0.2.0 (written 2026-11-05).

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

A `--rust` project therefore has 17 skills: the 8 skills of the Rust layer
(`creusot`, `creusot-launch`, `creusot-monitoring`, `creusot-sl` and the four
Creusot-flavoured `sl-*` skills) and the 9 common skills that are not
overridden (`directory-structure`, `ebios-risk-manager`, `ebios-sl`, `lean`,
`polish-skill`, `rmf-sl`, `rocq`, `stride`, `workshop`). Seven of those nine
are not in `use-creusot`: `ebios-risk-manager`, `ebios-sl`, `lean`, `rmf-sl`,
`rocq`, `stride`, `workshop`. `ebios-sl` is still wired to Frama-C; `rmf-sl`
names both consumers and its linter is installed since 0.3.0 (§4.1).

#### 4.3.3 Divergent SL skills

The four SL skills changed independently in the two repositories, and each
side has content the other lacks:

| Skill | Only in `use-frama-c` | Only in `use-creusot` |
|---|---|---|
| `sl-builder` | the "not addressable by our tool is a category error" corollary; an "Encoding note (SL-1.0)" block | "Phase 0 — architectural audit" (endogenous vs exogenous `U`) |
| `sl-auditor` | about 50 more lines, including the "Reaching the cross-provider judge" paragraph, which appears **twice** (a duplicated paragraph) | references to six check scripts `verify/{perturbation,category_overreach,flag_rate,claim_consistency,editorial_gate,apparatus_described}.py`, which **exist nowhere** |
| `sl-monitoring-sl` | about 45 more lines; bundled copies of `sl-auditor`, `sl-builder`, `sl-internal` | — |
| `sl-internal` | scripts `no_ceiling_gate.py`, `sl2doc.py`; different `refutation_probe.py` and `sl_disjointness_check.py` | — |

Version 0.2.0 does not merge them: each language gets the version from its own
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
- The RMF risk study is wired into the Creusot loop since 0.3.0: `rmf-sl`
  names `creusot-monitoring` as its Rust consumer, `creusot-monitoring`'s
  Phase 0 says how a code-blind `<target>-analysis-rmf-report.md` (written
  first, by a fresh sub-agent that never sees the crate, and passing
  `bin/rmf-lint.sh`) refines its value/risk ranking and scope map, and the
  linter is installed. What is still missing: a Rust counterpart of
  `frama-c-launch/templates/rmf-crosswalk.md` and of the Monitor-step
  feedback, and the `/rmf` command (roadmap step 4); the mission has to ask
  for the study by name. `ebios-sl` is installed but still hands its result
  to `frama-c-launch` only.
- There is no runnable faithfulness check: `monitor-check.sh` depends on a
  `strip-creusot` binary whose source is not in `use-creusot`.
- Installing Creusot itself (`cargo creusot`, Why3, solvers, the pinned
  nightly toolchain) is up to the user, as Frama-C is for `--c`, unless the
  project runs in a workshop, where the `creusot` SDK provides it (§4.5).
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
| Toolchain check (`frama-c -wp-detect`, opam switch) | Check `cargo creusot version`, Why3, why3find, the solvers (Alt-Ergo, Z3, CVC4, CVC5; on arm64 no CVC4, §4.5), the pinned nightly toolchain, and the path of the Creusot checkout that `~/.cargo/config.toml` points to (§4.3.6). In a workshop (`CREUSOT_SDK_SRC` set), accept the `creusot` SDK when `cargo creusot config` prints `No problems found.`, and record `CREUSOT_SDK_COMMIT` with the versions (Rust base spec §7). Report anything missing; do not install. |
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

Each step adds or changes template files; `auto-wp.py` itself does not
change, with one exception so far: step 2 made it merge the `tools/`
directories of the two layers (0.3.0, §3.6).

1. **`creusot-launch`** (§4.3.5), in `templates/rust/skills/`, including its
   faithfulness (stripping) script and the toolchain check that accepts
   the `creusot` SDK (§4.5). Installed with `--rust` only.
2. **Make `rmf-sl` language-independent.** *Done in 0.3.0 (2026-11-06),
   minimally:* the description, the opening, the handoff, the topology and
   the reference list of `SKILL.md` name "the launch loop" (`frama-c-launch`
   for C, `creusot-launch` / `creusot-monitoring` for Rust) and the Rust
   consumer; the lint gate `rmf-lint.sh` moved to `templates/common/tools/bin/`
   and is installed with both languages, its C8 tripwire catching Rust code
   artifacts too (§4.1); `report-format.md` Rule 5 lists them;
   `creusot-monitoring` Phase 0 consumes the report (§4.3.4). The remaining
   Frama-C mentions in `rmf-sl` are examples (the STRIDE → property table,
   the `--linux` profile, the C crosswalk and feedback references), kept as
   they are. The skill stays in `templates/common/`.
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

### 4.5 Workshop SDKs: `sdks/`

`sdks/` holds the four Workshop SDKs that package the proof environments
the skills need, so that a workshop installs a prebuilt, versioned
toolchain in minutes instead of building it for hours in the container.
`auto-wp.py` does not read `sdks/`; the generated project refers to the
SDKs by name only (§3.7), never to this directory. `sdks/README.md` is the
reference for building and using them; the designs are
`spec/workshop-autowp-c-base-spec.md` and
`spec/workshop-autowp-rust-base-spec.md`.

| SDK | Version | Provides | Listed by |
|---|---|---|---|
| `frama-c-sdk` | 32.1 | Frama-C 32.1 built from source with `templates/c/tools/frama-c-patches/` applied, macsl, Why3 1.8, Coq 8.20.1 (pinned, for WP), Alt-Ergo, Z3; `bear` and the C build tools. Wrappers `frama-c`, `frama-c-gui`, `why3`, `alt-ergo`, `z3`, `dune`, `ocamlfind` on `PATH`; `frama-c-sdk-exec <cmd>` for any other command of the switch; `FRAMA_C_SDK_SWITCH`, `FRAMA_C_SDK_MACSL` (the `.cmxs`), `FRAMA_C_SDK_SRC` (the patched sources) | `--c` |
| `rocq` | 9.2.0 | Rocq 9.2.0 and its standard library: `rocq`, `coqc`, `coqtop`, `coqdep` | both |
| `lean` | 4.35.0 | elan with `leanprover/lean4:v4.35.0`, Lake, ripgrep, lean-lsp-mcp; `~/.elan` and Mathlib's cache kept across refreshes | both |
| `creusot` | 0.15.0-f15b985 | Creusot at `f15b985` (the commit of §4.3.6), Rust `nightly-2026-08-03`, Creusot's Why3 and why3find, Alt-Ergo, Z3, CVC4, CVC5, the sources `creusot-std` is patched to; `~/.cargo` and `~/.rustup` seeded and kept across refreshes; `CREUSOT_SDK_SRC`, `CREUSOT_SDK_COMMIT` | `--rust` |

Alt-Ergo 2.6.4 is bundled in `frama-c-sdk` and `creusot` under the
OCamlPro Non-Commercial Purpose License (research use only; the licence
files ship in the SDK); the READMEs say so (§3.4).

**Verification status (2026-11-05).**

- *Verified:* amd64, on the bases `ubuntu@24.04` and `ubuntu@26.04`. Each
  SDK passes its checks in `sdks/test-sdk.sh` alone, and the four together
  in one workshop (`make test-sdks`), with `sdkcraft` 0.9.4, `workshop`
  0.9.9 and LXD 6.10.1 (results in the two SDK specs, §11).
- *Declared, not verified:* the arm64 platforms (`ubuntu@24.04:arm64`,
  `ubuntu@26.04:arm64`), built by `.github/workflows/sdks-arm64.yml` on
  GitHub's `ubuntu-24.04-arm` runner and kept as workflow artifacts; no
  arm64 workshop has run them. Known difference: the Creusot SDK ships no
  CVC4 on arm64 (no arm64 build exists) and builds Alt-Ergo from opam, so
  Creusot projects there prove with Alt-Ergo, Z3 and CVC5.
- *In progress (2026-11-05):* publication to the SDK Store (C base spec
  §8). The four amd64 SDKs, for both bases, are being uploaded and released
  to `latest/edge`: `creusot` is confirmed on the Store with its licence
  field accepted; `frama-c-sdk`, `rocq` and `lean` are still uploading and
  unconfirmed. The arm64 builds are not uploaded. The generated definition
  is written for the published state (§3.7.3).
- *Not done:* launching a generated project's workshop and running a
  campaign in it.

**What the templates must gain** for the skills to use the SDKs, from the C
base spec §3.5 and the Rust base spec §7. Each item carries its status:
*written* once its template change exists (and is checked by the level 1
tests where a static check is possible), *pending* otherwise; none has run
in a workshop yet (item 5 is what verifies them). Without the SDK (quick
start C), every behaviour stays as it is.

1. *Written 2026-11-05, unverified in a workshop.* `bin/fetch-sources.sh`: when `FRAMA_C_SDK_SRC` is set and
   `framac-src/` is absent, create `framac-src` as a symbolic link to it
   instead of downloading and patching the archive (the SDK's tree is the
   same release with the same patches applied by the same script). For
   `macsl/`: the skills expect a built source tree
   (`macsl/_build/default/src/macsl.cmxs` in
   `frama-c-monitoring/canaries/macsl-contexts-sync.sh` and
   `frama-c-api/references/macsl-contexts.md`), while the SDK ships only the
   `.cmxs` named by `FRAMA_C_SDK_MACSL`. The script keeps cloning `macsl/`,
   and the two files above take `FRAMA_C_SDK_MACSL` as their default when it
   is set, so nothing is built; the C base spec's "same for `macsl/`" is
   read this way.
2. *Written 2026-11-05, unverified in a workshop.* `frama-c-launch`'s toolchain confirmation (its §0 item 2 and
   the "toolchain absent" branch): when `FRAMA_C_SDK_SWITCH` is set, the SDK
   is a conformant toolchain if `frama-c -version` is `32.1`,
   `frama-c -wp-detect` lists Alt-Ergo, Z3 and Coq, the patch-liveness
   probe passes (`land_le_l` in the installed `cbits.mlw`) and
   `frama-c -load-module "$FRAMA_C_SDK_MACSL" -version` works (the checks
   of the SDK's `check-health`); the skill then skips the build, records
   the `FRAMA_C_SDK_*` values as the toolchain provenance, and never calls
   `opam switch` or `opam env` (the switch is read-only and there is no opam
   root of the user's). The skill mentions opam 21 times and
   `frama-c/references/install.md` 26 times; the latter gains a first
   section "In a workshop: add `frama-c-sdk` to the definition" before the
   build recipe, which stays for quick start C. `bin/framac-onboard.sh`,
   the prober's oracle, reports the switch as present when
   `FRAMA_C_SDK_SWITCH` names it, instead of asking `opam switch list`.
3. *Pending (with roadmap step 1, §4.3.7).* `creusot-launch`'s toolchain
   check accepts the `creusot` SDK (§4.3.5). The first section of
   `creusot/references/install.md` ("In a workshop: add `creusot` to the
   definition") is written (2026-11-05).
4. *Written 2026-11-05.* `templates/c/workshop/` and `templates/rust/workshop/`
   (§3.7.1), `templates/rust/tools/.gitignore`, the `/.workshop.lock` line
   in `templates/c/tools/.gitignore`, and the three quick starts in both
   READMEs (§3.4); checked by tests 13, 13b, 14, 20 and T8.
5. *Pending.* `tests/c/provision.sh` and `tests/rust/provision.sh` gain a
   Workshop mode that launches a workshop from the generated definition
   instead of building the toolchain (`tests.md`), which is also how item
   2 and 3 get verified.

Other skills that name the toolchain (`frama-c/SKILL.md`, `ocaml`,
`frama-c-internals`, `framac-onboard.sh`, `framac-smoke.sh`) refer to the
`framac-coq8` switch or to opam in passing; whether any of them breaks
without an opam root of the user's is found by item 5, not guessed here.

## 5. Tests

`tests/test_auto_wp.py`, runnable with `python3 -m unittest`, working in a
temporary directory. Unless stated otherwise, each test runs the program as a
subprocess.

1. `--c foo` creates `foo/config/skills/frama-c/SKILL.md`,
   `foo/config/commands/rmf.md` and `foo/config/skills/sl-internal/SKILL.md`,
   22 skill directories and 3 commands, and no `creusot*` skill (in particular
   no `creusot-launch`).
2. `--rust foo` creates `foo/config/skills/{creusot,creusot-launch,creusot-monitoring,creusot-sl}/SKILL.md`,
   17 skill directories and no command, and no `frama-c*` skill.
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
    `/time-loop grub 72` and `bin/fetch-sources.sh`, exactly one
    occurrence of `/time-loop grub 72` in a code block (the explanation is
    shared, §3.4 item 2D), the three quick starts in order (`workshop
    launch` before `multipass launch` before `bin/launch_lxc.sh`), the
    strings `/project`, `workshop shell`, `workshop remove`, `caffeinate`
    and `multipass transfer`, and contains no `{{`,
    no `~/git/` and no `UFC` (until the arm64 publication the README does
    name the auto-wp repository's `sdks/` directory, in the arm64
    paragraph of 2B, by the repository's URL and relative paths inside a
    clone of it, never by a host path).
13b. `--c foobar` copies the tools of §4.2.1 to `foobar/` as regular files
    (22 `bin/*.sh` and no `*.sh` at the root, `frama-c-patches/apply.sh`,
    `framac-gold/`, `no-ceiling.md`, `.gitignore` listing `/framac-src/`
    and `/.workshop.lock`),
    with the executable bit on every script, `bin/rmf-lint.sh` identical to
    `templates/common/tools/bin/rmf-lint.sh` (§4.1); `--rust` creates a
    `bin/` holding only that same `rmf-lint.sh` (a regular, executable
    file), none of the C data (`frama-c-patches/`, `framac-gold/`,
    `no-ceiling.md`), and a `.gitignore` listing `/.workshop.lock`; an
    existing `foo/.gitignore` is kept and reported with `kept`.
14. `--rust foobar` writes a README that contains `creusot-launch`,
    `workshop launch`, `multipass launch` and `cargo creusot`, no
    `bin/fetch-sources.sh`, and
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
20. Workshop definition (§3.7): for both `--c` and `--rust`,
    `foo/.workshop/autowp.yaml`, `foo/.workshop/autowp-packages/sdk.yaml`
    and `foo/.workshop/autowp-packages/hooks/setup-base` exist, are regular
    files identical to the language layer's `workshop/` files, and the hook
    is executable. Parsed as YAML (the test may use a minimal line parser,
    the standard library has no YAML module), `autowp.yaml` has
    `name: autowp`, `base: ubuntu@24.04`, and `sdks` whose names are, in
    order, `frama-c-sdk`, `rocq`, `lean`, `project-autowp-packages` for
    `--c`, and `creusot`, `rocq`, `lean`, `project-autowp-packages` for
    `--rust`, the three Store entries each with `channel: latest/edge` and
    the `project-` entry with no channel; no `try-` name. The C hook contains
    `apt-get install` and `libfuse3-dev`; the Rust hook contains
    `apt-get install` and no `libfuse3-dev`. Neither language's
    `.workshop/` files contain `{{`, `~/git/` or `sdks/`. The output
    contains `copied  foo/.workshop (workshop: autowp)`.
21. Reserved `.workshop` paths (§3.1 item 3): a pre-existing
    `foo/.workshop/autowp.yaml`, or `foo/.workshop/autowp-packages/`, or a
    regular file `foo/.workshop`, makes the run exit 1 and change nothing
    (`foo/config` is not created). A pre-existing `foo/.workshop/other.yaml`
    is preserved, the run succeeds, and `foo/.workshop/autowp.yaml` is
    written next to it.
22. Rollback of `.workshop/` (§3.6): with the failure of test 19 injected
    after `.workshop/` was written, `foo/.workshop/` no longer exists when
    this run created it; when `foo/.workshop/other.yaml` existed before,
    `foo/.workshop/` still holds exactly that file afterwards.

The template checks of `tests.md` (§3.2 there) gain: the `workshop/` files
of each language layer are the three of §3.7.1, with the exact `sdks` list
of §3.7.1 and an executable `setup-base` that passes `shellcheck` when it is
installed; no file under `templates/*/workshop/` names `sdks/`; and no file
under `templates/*/workshop/` or either README names a path under `~/git/`.

## 6. Out of scope for version 0.3.0

- Updating an existing project from newer templates (`--update`), including
  moving `.workshop/autowp.yaml` from `latest/edge` to a stable channel in
  projects generated before one exists.
- Merging the divergent SL skills into one common version, and fixing the
  known defects listed in §4.3.3.
- Generating `CLAUDE.md`/`AGENTS.md` or source scaffolding inside the project.
- Adding a git remote or making a first commit.
- Running any analysis, `workshop` or `multipass`: the program writes files
  only.
- Choosing SDKs on the command line (for example `--no-lean`); the user
  edits `.workshop/autowp.yaml`.
- Installing Claude Code from an SDK or a hook (C base spec open point 9):
  the README installs it in step 2, and the login stays interactive and in
  the container.

## 7. Open points (Workshop)

1. **Publication, amd64.** The upload of the four amd64 SDKs to
   `latest/edge` was in progress on 2026-11-05 and its acceptance is
   unconfirmed (§3.7.3). To check: `workshop launch` of a generated `--c`
   project and of a `--rust` project on a host with LXD and Workshop only
   (no `sdkcraft`, no try area), reaching `ready`. Until that check passes,
   quick start A is unverified at its first command, and §3.7.3 keeps the
   `try-` route as the developer's fallback. Promotion to stable channels
   follows the level 3 tests (C base spec §8).
   Status 2026-11-06: the generated `--rust` definition (base
   `ubuntu@24.04`) reaches `ready` with `creusot`, `rocq` and `lean` all
   from the Store (`sudo-rs-test.md` §7). `rocq` and `lean` have no
   `ubuntu@26.04` revision released, and `frama-c-sdk` has no
   `ubuntu@24.04` revision released (`gzip-test.md` §7.3). Later the same
   day `sdk info` showed all four SDKs on both bases, and the generated
   `--c` definition reached `ready` from the Store too (`gzip-test.md`
   §7.3). Left to check: a host without `sdkcraft` and without a try area.
2. **Publication, arm64, and prebuilt `.sdk` files.** The arm64 SDKs are
   not uploaded, so quick start B depends on building them in the VM from
   this repository (§3.7.3), a temporary exception to the stand-alone rule.
   Two things end it: uploading the arm64 builds (after §7 item 3), or,
   sooner, finding whether a packed `.sdk` copied into
   `~/.local/share/workshop/try/` by hand is accepted by `workshop launch`
   as `try-<name>` without `sdkcraft`, which would let a Mac user take the
   CI artifacts. To test on amd64 first with one of the built files in
   `sdks/*/`.
3. **arm64.** The arm64 SDKs have never been installed in a workshop. The
   first test is `sdks/test-sdk.sh` in an arm64 VM (quick start B's VM),
   then a generated project's `workshop launch` there.
4. **macOS and `multipass mount`.** Whether a workshop can mount a project
   that sits on a Multipass SSHFS mount (LXD disk device with id shifting
   on top of SSHFS) is unverified and expected to fail; the README says to
   keep the project in the VM (§3.4 item 2B). To verify once, and to drop
   the restriction if it works, which would let the project stay on the
   Mac's disk.
5. **The first launch of a generated project.** No `workshop launch` has
   been run from a generated `.workshop/autowp.yaml`, and no campaign has
   run in a workshop: whether `fetch-sources.sh`, `frama-c-launch`, the
   canaries and the `opam`-mentioning skills behave with the read-only
   switch (§4.5 items 1, 2 and the last paragraph) is what item 5 of §4.5
   will show. Until then quick starts A and B are design.
6. **`workshop refresh` during a campaign.** It removes Claude Code, its
   login and the bare remote `~/foobar.git` (§3.4 item 2A). Whether to move
   the remote into a mount plug of the project-local SDK (a `mount` plug
   with `workshop-target: /home/workshop/foobar.git` would keep it across
   refreshes) is open; it would make the project-local SDK the owner of
   a host directory under `~/.local/share/workshop/`, which `workshop
   remove` deletes.
7. **Package list of the project-local SDK.** As generated it is GRUB's
   (C) or empty but for `tmux` and `curl` (Rust). A future `--target`
   option, or `/time-loop` installing what `configure` reports missing,
   would remove the hand edit; neither is specified.
8. **Workshop and sdkcraft move fast.** The versions the SDKs were tested
   with are recorded in §4.5; the installed `workshop` 0.1.29 found on this
   host on 2026-10-31 could not launch anything on LXD 6.10 (C base spec
   §11). The README's prerequisite says "the current `latest/stable`" and
   names no version.
