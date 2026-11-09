# auto-wp — test specification

This file specifies how `auto-wp.py` (specified in `auto-wp.md`) is tested.
The host tests check the program and its templates. The container tests check
the claim the generated README makes: on a clean machine, the commands it
shows work as written, up to a real `/time-loop` campaign.

## 1. Layout

```
tests/
├── test_auto_wp.py          level 1: program tests (auto-wp.md §5), both languages
├── test_templates.py        level 1: template-seeding checks (§3.2)
├── lib/
│   ├── lxc.sh               shared LXD helpers: pool, network, launch, push, exec, cleanup
│   ├── harness.sh           starts the agent harness in tmux and types a command (§3.5)
│   └── secret.sh            moves the harness credential into a container (§7)
├── c/
│   ├── provision.sh         builds the reusable C base container (§5.1)
│   ├── install-test.sh      level 2: auto-wp.py --c + git clone grub (§5.2)
│   ├── smoke-test.sh        level 3: 3-hour /time-loop run (§5.3)
│   ├── gzip-test.sh         level 3: /time-loop run on gzip 1.9 (96 h by default), LXD or Workshop (§5.5)
│   └── acceptance.sh        level 4: /time-loop grub 72 (§5.4)
└── rust/
    ├── provision.sh         builds the reusable Rust base container (§6.1)
    ├── install-test.sh      level 2: auto-wp.py --rust (§6.2)
    ├── workspace-test.sh    level 3: why3find.json workspace pitfall, cases A–H (§6.3)
    └── smoke-test.sh        level 3: creusot-launch + creusot-monitoring on a small crate (§6.4)
```

The Python tests stay at the top of `tests/` because they cover both
languages, as `auto-wp.md` §5 already says. Every script under `tests/c/` and
`tests/rust/` is a bash script (`#!/usr/bin/env bash`, `set -euo pipefail`),
runnable from any working directory. Each prints `PASS: <id>` or
`FAIL: <id>: <reason>` per check, and exits 0 only if every check passed.
Checks marked *informational* print `INFO: <id>: ...` and never fail the
script.

## 2. Levels and cost

| Level | What | Where | Duration | Needs |
|---|---|---|---|---|
| 1 | program and template tests | host | seconds | Python 3.10+, git |
| 2 | README quick start up to the harness, on a stock image | fresh LXD container | minutes | LXD, network |
| 3 | a short campaign in the harness, or a tool-level regression | container copied from a provisioned base | 1–4 h | level 2, a harness credential |
| 4 | `/time-loop grub 72`, plus a resume run | container copied from a provisioned base | 72 h + 4 h | level 3 |

Levels 1 and 2 run on every change to `auto-wp.py` or the templates. Level 3
runs before a release and after a change to the skills. Level 4 runs by hand.

**Cost.** Levels 3 and 4 run on the same harness session as the host (a
Claude subscription, or the provider account behind OpenCode), and share its
usage limits (rolling and weekly). A 72-hour run will
reach those limits, and so will the host if it is used at the same time.
`acceptance.sh start` refuses to start unless `ACCEPT_COST=1` is set, and the
run is best scheduled when the host session is idle. While the session
is rate-limited, the harness waits: `acceptance.sh status` reports the time
spent waiting (from the tmux pane), and check C4.2 accounts for it.

## 3. Shared setup

### 3.1 LXD (`tests/lib/lxc.sh`)

Checked on the host on 2026-10-28: LXD 6.10 LTS, usable by the user without
sudo (member of the `lxd` group); the `default` profile has only a root disk
and **no network device**; the managed bridges `vmodel-net` and `workshopbr0`
belong to other projects; the `default` storage pool uses the `dir` driver;
`ubuntu 24.04 LTS amd64` (serial 20260321) is cached.

- **Storage pool.** With the `dir` driver every snapshot and every
  `lxc copy` is a full file copy of the root file system (about 6 GB for a
  provisioned C base). The helper therefore creates its own pool `autowp`
  with the `zfs` driver (a loop file managed by LXD) if it does not exist,
  and puts all test containers on it. If `zfs` is not available it falls back
  to `default` and prints a warning.
- **Network.** It creates a managed bridge `autowp-net` (NAT, DHCP) if it
  does not exist and attaches it as `eth0` to every test container. It does
  not reuse `vmodel-net` or `workshopbr0`.
- **Egress check first.** Docker is installed on the host (`docker0`), and
  Docker's firewall rules commonly block traffic from other bridges. Right
  after a container starts, the helper runs
  `curl -sSfI https://gitlab.freedesktop.org` in it and stops with a clear
  error if it fails, before any other step.
- **Image.** `ubuntu:24.04`, pinned with `IMAGE` (default: the cached
  fingerprint, so tests do not silently pick up a newer serial). Containers
  are named `autowp-<lang>-<level>-<timestamp>`; base containers are
  `autowp-c-base` and `autowp-rust-base`.
- **User.** Every command runs as the image's `ubuntu` user (uid 1000) with a
  login environment:
  `lxc exec "$C" --user 1000 --group 1000 --cwd /home/ubuntu --env HOME=/home/ubuntu -- bash -lc '...'`.
  A plain `su ubuntu -c` would miss `~/.local/bin` on the `PATH` and the opam
  environment. Running as root is not an option anyway: Claude Code refuses
  `--dangerously-skip-permissions` as root, and an agent running as root in
  the container would defeat the confinement the tests check (K3).
- **Copying files in.** Through a tar pipe, never a bind mount, so a test
  cannot change the host:
  `tar -C <src> -cf - <files> | lxc exec "$C" -- tar -C <dst> -xf -`,
  followed by `chown -R ubuntu:ubuntu <dst>`. For the project this copies
  `auto-wp.py` and `templates/` into `/home/ubuntu/auto-wp/`: `auto-wp.py`
  alone is not enough, because it reads its templates from `templates/` next
  to itself (`auto-wp.md` §4).
- **Cleanup.** Each script registers a `trap` on `EXIT` that deletes the
  containers it created, whether it passed or failed, unless `KEEP=1` is set.
  `provision.sh` deletes a half-built base container on failure. Base
  containers and their `ready` snapshots are kept.

### 3.2 Template checks (`tests/test_templates.py`, level 1)

`auto-wp.py` copies templates byte for byte, so checks on the templates' own
content belong on the host, not in a container:

| # | Check |
|---|---|
| T1 | No file under `templates/rust/` mentions "repo-root `creusot-sl.md`" (the rewrite of `auto-wp.md` §4.3.2). |
| T2 | `templates/rust/skills/creusot-sl/SKILL.md` starts with a YAML front matter whose `name` is `creusot-sl`. |
| T3 | `templates/common/` has the 14 skills of `auto-wp.md` §4.1, `templates/c/` the 9 of §4.2 and the 4 commands, `templates/rust/` the skills of §4.3.2 that exist so far. |
| T4 | No editor backup (`*~`) and nothing from `use-creusot/config/foo/` in `templates/`. |
| T5 | The `README.md` templates contain only these placeholders: `{{DIR}}`, `{{LANGUAGE}}`, `{{DRIVER}}`, `{{FEEDBACK}}`, `{{DRIVER_LINE}}` and `{{DRIVER_NOTE}}` (C), `{{DIR}}`, `{{LANGUAGE}}` and `{{DRIVER_LINE}}` (Rust). `{{DRIVER_NOTE}}` is the one sentence the fips driver adds after the quick-start command (`fips-skill-spec.md` §7.3). |
| T6 | The three `time-loop` changes of `auto-wp.md` §4.2.2 are in `templates/c/`: `commands/time-loop.md` no longer contains "Stop early" nor "(diminishing returns)", and contains the replacement "Stop" bullet; `skills/time-loop/SKILL.md` no longer contains "DIMINISHING-RETURNS stop fires ONLY", and its description contains "There is no diminishing-returns stop"; both files name `XXX.md` as the report file and state that a re-run keeps the stored deadline. |
| T7 | `templates/common/tools/bin/` holds `rmf-lint.sh` and `templates/c/tools/bin/` the other 22 scripts (`auto-wp.md` §4.1, §4.2.1; 23 in all, no name in both), `templates/common/tools/` holds the vendored `NIST.FIPS.140-3.pdf`, neither `tools/` has a `*.sh` at its top level, `templates/rust/tools/` holds only `.gitignore`, and no file under `templates/` outside the two `tools/` names one of these scripts without its `bin/` prefix (bare or `./name.sh`). |
| T8 | The `workshop/` layer of each language (`auto-wp.md` §3.7.1) holds exactly `autowp.yaml`, `autowp-packages/sdk.yaml` and an executable `autowp-packages/hooks/setup-base` starting with `#!/bin/bash`; `autowp.yaml` has `name: autowp`, `base: ubuntu@24.04`, and the `sdks` names `frama-c-sdk`, `rocq`, `lean`, `project-autowp-packages` (C) or `creusot`, `rocq`, `lean`, `project-autowp-packages` (Rust), the three Store entries on `channel: latest/edge`; `sdk.yaml` has `name: autowp-packages`; no file of the layer names `sdks/`, `~/git/` or a `{{` placeholder; `setup-base` passes `shellcheck` when it is installed; each layer's `tools/.gitignore` lists `/.workshop.lock`. |

The program tests 20–22 of `auto-wp.md` §5 (the generated `.workshop/`
per language, the reserved `.workshop` paths, the rollback of `.workshop/`)
are in `test_auto_wp.py` next to tests 1–19.

The fips-driver checks (`fips-skill-spec.md` §8, numbered T8/T9/T9b/T9c/T10
there) are T9–T13 here, after the workshop test T8:

| # | Check |
|---|---|
| T9 | `templates/common/skills/fips-sl/` holds `SKILL.md` (front matter `name: fips-sl`), `fips-sl.sl.json` and the four reference files; `sl_disjointness_check.py fips-sl.sl.json` exits 0 (single-loop mode); the vendored PDF's sha256 is the spec's; the skeleton shown in `report-format.md` is byte-for-byte `skeleton.md`. |
| T10 | `bin/fips-lint.sh` on `fips-sl/references/skeleton.md` passes (exit 0), and each of the ten broken copies (`fips-skill-spec.md` §5) fails with its check ID and no other failing check; a manifest without `fips_level` exits 2; `FIPS_LEVEL=3` overrides the manifest. |
| T11 | `bin/ledger-ratchet.sh` on a FIPS ledger (the `# ledger: fips` form): the first run writes the baseline whose first line is `# ledger: fips`; a `PROVED` cell changed to `UNMODELED` FAILs after the round trip through the baseline file; `TRUSTED-PENDING` only warns; a header cell containing "race" with a `PROVED` row passes (the WS1 rule is not applied to the FIPS form); a STRIDE baseline is refused as "not a FIPS baseline"; the STRIDE path still reads its seven-column baseline. |
| T12 | `bin/crosswalk-gen.sh --kind fips` on a fixture `PREFIX-fips-report.md`, `PREFIX-acsl/fips-ledger.tsv` and a `verdicts.tsv` with a `VO#` header: it detects the FIPS kind, writes §1 with one row per `VO#` and its units and coverage filled, writes the §3 FIPS ledger with the `# ledger: fips` marker, fails when a `PROVED` cell has no matching verdict, and `--check` fails on drift. The existing RMF and EBIOS kinds still detect as before. |
| T13 | The PDF's normative sections hold their quotes (Ann. 6, 7, 10, 13 — the only sections an `RQ#` may cite), and the eleven areas and four level names appear in it; from `pdftotext` when installed, skipped otherwise. |

### 3.3 The agent harness in the container

`provision.sh` installs Claude Code without credentials (§7 covers the
token), and OpenCode too when its binary is on the host:

- **Binary.** It pushes the host's binary (`readlink -f $(which claude)`, a
  dynamically linked ELF that needs only glibc ≥ 2.26; Ubuntu 24.04 has 2.39)
  to `/home/ubuntu/.local/bin/claude`, so the container runs the same version
  as the host. The launcher sets `DISABLE_AUTOUPDATER=1`, otherwise the
  updater can replace the binary during a run. OpenCode is installed the same
  way (`readlink -f $(which opencode)`, a self-contained ELF of about
  250 MB) to `/home/ubuntu/.local/bin/opencode`, with a global
  `~/.config/opencode/opencode.json` that allows every action (its base
  policy otherwise asks before reading `.env` files) and a `cli.json` without
  the release-highlights popup.
- **First-run prompts (Claude Code).** Three prompts would otherwise stop an
  unattended
  run, or swallow the command typed into it:
  - onboarding: `~/.claude.json` with `hasCompletedOnboarding: true`;
  - folder trust: in the same file,
    `projects["/home/ubuntu/foobar"].hasTrustDialogAccepted: true`;
  - the bypass-permissions warning: `~/.claude/settings.json` with
    `skipDangerousModePermissionPrompt: true`.

  `harness.sh` writes the folder-trust entry for the exact project path
  before each start. OpenCode has no such dialogs; `harness.sh` writes its
  global config instead.
- **Do not use `--bare`**: it reads only `ANTHROPIC_API_KEY` and ignores the
  OAuth token.

Which harness a level 3 or 4 script drives is `HARNESS` (default `claude`):
the launcher, the transcript location (`~/.claude/projects/*/*.jsonl`, or
OpenCode's session database `~/.local/share/opencode/opencode.db`) and the
tmux prompt pattern change with it; the typed command and the checks do not.

### 3.4 Git in the container

- `provision.sh` sets `git config --global user.name "auto-wp test"` and
  `user.email "autowp-test@localhost"` for `ubuntu`. The time-loop commits
  every cycle, and a fresh image has no identity, so `git commit` would fail.
  The generated README tells users the same (`auto-wp.md` §3.4).
- The level 3 and 4 scripts create a local bare repository `~/remote.git` and
  add it as `origin` of `foobar`, so the per-cycle push works without any git
  credentials in the container.

### 3.5 Driving the harness (`tests/lib/harness.sh`)

The time-loop re-arms itself between cycles with a scheduled wake-up
(`ScheduleWakeup` on Claude Code; on OpenCode, the external `opencode run`
watchdog, `time-loop/SKILL.md` §8). Print mode (`claude -p`, or an `opencode
run` one-shot) exits
when its first turn ends, so the wake-ups never fire and a one-shot run is at
most one cycle. **Levels 3 and 4 therefore run the interactive harness in
tmux**, as a person would:

1. `tmux new-session -d -s autowp -c ~/foobar` running the launcher:
   `DISABLE_AUTOUPDATER=1 CLAUDE_CODE_OAUTH_TOKEN=... claude --dangerously-skip-permissions`
   (Claude Code; the token comes from §7, not from the command line), or
   `ANTHROPIC_API_KEY=... opencode --standalone` (OpenCode).
2. Wait until the prompt is shown: poll `tmux capture-pane -p` until it
   contains the input prompt, up to `HARNESS_START_TIMEOUT` (default 300 s).
   OpenCode disables the shared service so the skill-owned watchdog inherits
   the launcher's provider key. Its transcript follows the `db` path from
   `opencode debug paths`, including WAL files; `harness_stop` stops the
   project-local watchdog and its active wake before closing tmux
   (`choose-harness.md` §3.2).
3. Type the command literally, without Enter: `tmux send-keys -t autowp -l '/time-loop grub 3'`.
   Wait 2 s, so slash-command completion settles, then send `Enter` on its
   own (`tmux send-keys -t autowp Enter`).
4. Confirm the command started: within 5 minutes, the newest session
   transcript (`~/.claude/projects/`, or OpenCode's session database) shows
   the `time-loop` command or
   skill being loaded.

`--dangerously-skip-permissions` is acceptable here and only here: the
container is disposable and holds no host files; the run is unattended. §7.3
covers what the agent can still reach.

## 4. Common checks for campaign runs

Used by levels 3 and 4 (C3.x, C4.x, R4.x refer to them):

| # | Check |
|---|---|
| K1 | **Source untouched.** `git -C grub rev-parse HEAD` is the cloned commit, `git -C grub diff --quiet HEAD` succeeds, and `git -C grub status --porcelain --untracked-files=no` is empty. Untracked build output inside `grub/` (configure results, `compile_commands.json` from `bear -- make`) is allowed: onboarding builds in the source tree. |
| K2 | **Token not written anywhere.** `grep -rlqF -f /run/autowp/token ~ /tmp` finds nothing, and the same over `git -C ~/remote.git log -p --all`. The pattern comes from the file, so it never appears on a command line, and `-l` prints only file names; on a hit the check prints `FAIL: K2: token found in <path>` and never the matching line. |
| K3 | *Informational.* Files changed outside an allowlist (`~/foobar`, `~/toolchain`, `~/.claude`, `~/.cache`, `~/.opam`, `~/.local/share/claude`, `~/.config`, `~/.bash_history`, `~/.gitconfig`, `~/remote.git`, `/tmp`), from a `find -newer` listing. The C tools are regular files in `foobar/`, so their writes (`framac-canary.sh` writes next to itself, `framac-corpus-db.sh` into `$(pwd)`) fall inside `~/foobar`; writes into `~/toolchain` (the base's build tree) are listed separately. |
| K4 | **Commands loaded.** Step 4 of §3.5 succeeded. |

## 5. C tests (`tests/c/`)

### 5.1 `provision.sh` — C base container

Builds `autowp-c-base` once and takes the snapshot `ready`. Later tests copy
the snapshot (`lxc copy autowp-c-base/ready <new>`). Provisioning takes
hours, mostly building the toolchain.

1. **Packages.**
   - Base: `git python3 tmux curl opam build-essential pkg-config`.
   - Required by the opam `frama-c` package (`frama-c-launch/SKILL.md`, the
     apt line in the toolchain section): `libgtk-3-dev libgraphviz-dev libgtksourceview-3.0-dev`.
   - Required by onboarding: `bear` (`framac-onboard.sh` runs `bear -- make`).
   - Required to configure and build GRUB from git: `autoconf automake
     autopoint gettext bison flex python3 libtool`, and whatever else GRUB's
     `INSTALL` lists for the checked-out commit.
2. **C tools layer.** The script copies `templates/c/tools/` (the same files
   `auto-wp.py` copies into a project, `auto-wp.md` §4.2.1) into
   `/home/ubuntu/toolchain/` with a tar pipe. No host checkout of
   `use-frama-c` is used, and nothing is cloned over SSH.
3. **Toolchain** (the `framac-coq8` switch, following `frama-c-launch`'s
   toolchain recipe). The host switch (3.6 GB, with `/home/fabrice/.opam`
   written into it) is not copied.
   - `opam init --disable-sandboxing -y`: opam's bubblewrap sandbox does not
     work in an unprivileged container.
   - `opam switch create framac-coq8 ocaml-base-compiler.4.14.2`.
   - **Coq before Why3**, and Coq pinned to 8.20: `opam install coq.8.20.1`
     first (a plain `opam install coq` now gives Rocq 9.x), then why3 1.8.x,
     alt-ergo, z3, then `why3 config detect`, then check that the Coq
     realizations (`BuiltIn.vo` under `$(why3 --print-libdir)/coq/`) exist.
   - The OCaml dependencies of the source build
     (`yaml ppx_deriving_yaml ocamlgraph ppx_inline_test unionFind`).
   - `~/toolchain/bin/fetch-sources.sh`, which downloads Frama-C 32.1 with
     its release archive (sha256 checked), applies `frama-c-patches/`, and clones `macsl/`; then
     build and install Frama-C from `~/toolchain/framac-src/`.
   - Success check: `frama-c -version` is 32.1, `frama-c -wp-detect` lists
     Alt-Ergo, Z3 and Coq, and the installed binary is the patched build.
4. **Claude Code** as in §3.3, **git** as in §3.4.
5. Stop the container, then `lxc snapshot autowp-c-base ready`.

`SKIP_TOOLCHAIN=1` skips step 3. `/time-loop` must then build the toolchain
itself through `frama-c-launch`, which tests that path (and needs sudo inside
the container for the apt step; `ubuntu` has passwordless sudo in the stock
image).

**Workshop mode (planned, not implemented).** `WORKSHOP=1 provision.sh`
would replace steps 1–3 with a workshop: generate a project with
`auto-wp.py --c`, run `workshop launch` from it (the `frama-c-sdk`, `rocq`
and `lean` SDKs from the SDK Store, channel `latest/edge`, and the
project-local `autowp-packages`, `auto-wp.md` §3.7), and use that container
as the base, so provisioning takes minutes. It is the first run of a
generated definition and what verifies `auto-wp.md` §4.5 items 1 and 2
(`bin/fetch-sources.sh` linking `framac-src` to `FRAMA_C_SDK_SRC`;
`frama-c-launch` and `bin/framac-onboard.sh` accepting the SDK's switch
without an opam root). Its checks: the workshop reaches `ready`;
`bin/fetch-sources.sh` creates `framac-src` as a link and clones `macsl/`;
`frama-c -wp-detect` lists Alt-Ergo, Z3 and Coq as the `workshop` user;
`bin/framac-onboard.sh` on a small target reports the toolchain `PASS`
without `opam` installed; the `macsl-contexts-sync.sh` canary runs with
`FRAMA_C_SDK_MACSL`. What is not settled: how the later levels copy a
workshop (LXD snapshots live in the `workshop.<user>` LXD project, not the
`default` one), and whether `lxc copy` of such a container keeps the SDK
mounts; the LXD base of steps 1–3 stays until that is known. Needs the
Store upload of the three C SDKs to be confirmed first (`auto-wp.md` §7
item 1).

### 5.2 `install-test.sh` — level 2

Uses a **fresh** `ubuntu:24.04` container, not the base. Its purpose is what
level 1 cannot show: that `auto-wp.py` works with the stock image's Python
(3.12) and git (2.43), with nothing installed, and that the README's clone
step works from there. The README's host-side LXD commands (step 1) are
not run here: the test container already plays that role. Structural checks already covered by `auto-wp.md` §5
are not repeated. Steps, as `ubuntu`:

```bash
cd ~
python3 auto-wp/auto-wp.py --c foobar
cd foobar
git clone https://gitlab.freedesktop.org/gnu-grub/grub.git
```

`claude` is not needed at this level; the harness step is covered by level 3.

| # | Check |
|---|---|
| C2.1 | `auto-wp.py` exits 0 with the stock `python3`, and prints `skills:   23` and `commands: 3`. |
| C2.2 | `foobar/README.md` exists, and the in-container block of its quick start (step 2, the code block that starts with `cd foobar`), extracted from the file, starts with exactly the lines this test ran and ends with `claude --dangerously-skip-permissions`; the README also documents the OpenCode harness (its install URL and `opencode` start line). |
| C2.3 | `git clone` exits 0 and `foobar/grub/` is a git work tree. |
| C2.4 | `foobar` is a git work tree and `grub/` is not tracked by it. |
| C2.5 | A second `auto-wp.py --c foobar` exits 1 and changes nothing: a `sha256sum` manifest of `foobar/` (excluding `grub/` and `.git/`), plus the file list, is identical before and after. |
| C2.6 | `auto-wp.py --driver fips --level 2 fipsbar` exits 0, prints `driver:   fips (FIPS 140-3 level 2)`, `skills:   23` and `commands: 3`, installs `ebios.md`, `fips.md` and `time-loop.md` (no `rmf.md`), and the manifest carries `driver: fips` and `fips_level: 2`. |

### 5.3 `smoke-test.sh` — level 3

Copies `autowp-c-base/ready`, runs the level 2 steps in it, runs
`bin/fetch-sources.sh` in `~/foobar` as the README does, sets up `origin` (§3.4), moves the token
in (§7), and starts the harness with `/time-loop grub 3` (§3.5).

- **Budget: 3 hours.** The first cycle is a full `/rmf` (risk study,
  onboarding with GRUB's configure and `bear -- make`, a smoke proof), and the
  skill reserves the last 15–20 minutes for its final report. A shorter budget
  would not reach the artifacts checked below.
- **No `--dir`.** `--dir=` only narrows an *existing* campaign and is not
  passed to `/rmf` (`time-loop.md`), so it would not shorten a first run. It
  is tested in §5.4 on an existing campaign.

The script waits for the loop to stop, with a hard limit of 5 hours, then
checks:

| # | Check |
|---|---|
| C3.1 | K4: the command was loaded. |
| C3.2 | K1: `grub/` untouched. |
| C3.3 | `grub-analysis-rmf-report.md` exists and is not empty. |
| C3.4 | `grub-analysis-acsl/time-loop.state` exists, and its deadline is 3 h after its start time (± 5 min). |
| C3.5 | **The loop re-armed itself**: the state file records at least two wakes. If it records only one, the scheduled wake-up did not fire, and the test fails with that message. |
| C3.6 | Every cycle the state file records has a matching commit in `~/remote.git` (the per-cycle checkpoint was committed and pushed). |
| C3.7 | **Stopped on time**: the last wake in the state file is not later than the deadline plus the length of the longest recorded cycle. The deadline is only checked between cycles (`time-loop/SKILL.md` §4 step 0), so this is the bound the loop actually promises. |
| C3.8 | K2: token not written anywhere. |
| C3.9 | K3 (informational). |
| C3.10 | **Report file**: `~/foobar/grub.md` exists, is not empty, and is the interim report (the 3-hour run pauses at its deadline; `auto-wp.md` §4.2.2). No other report file was created in `~/foobar` or inside `grub/`. |

### 5.4 `acceptance.sh` — level 4

The real README example. It runs for 72 hours, so the script starts the run
and returns; later sub-commands report on it.

```
tests/c/acceptance.sh start      # copy base, level 2 steps, tools, origin, token, harness: /time-loop grub 72
tests/c/acceptance.sh status     # elapsed time, cycles, time rate-limited, latest feedback file, last pushed commit
tests/c/acceptance.sh attach     # tmux attach inside the container (watch, or take over by hand)
tests/c/acceptance.sh check      # run the checks below (after the run ends)
tests/c/acceptance.sh stop       # stop the harness, keep the container
tests/c/acceptance.sh restart    # start a new harness session in the same container and retype the same command
tests/c/acceptance.sh destroy    # delete the container
```

`restart` is this script's sub-command; it starts the harness fresh, it does
not use `claude --resume`. `start` and `restart` re-send the token (§7),
because the file in `/run` is deleted once the harness has read it.

**Main run** (`start`, `/time-loop grub 72`), checks (`check`):

| # | Check |
|---|---|
| C4.1 | C3.1–C3.6, C3.8 and C3.9, on this run. |
| C4.2 | **Stopped at the right time, for an allowed reason.** Either (a) the deadline: the last wake is not later than the deadline plus the longest cycle, plus the time `status` recorded as rate-limited; or (b) the true terminus: the state file records a Gate-T PASS (every goal PROVEN, reported as a violation, or filed as a Frama-C bug; `time-loop/SKILL.md` §3). Any other stop fails the check, in particular a stop because no class-C work is left while class-A goals are neither proven nor filed as Frama-C bugs (no "diminishing returns" stop; `auto-wp.md` §4.2.2, change 3). |
| C4.3 | The number of commits in `~/remote.git` is at least the number of cycles in the state file. |
| C4.4 | Every `grub-analysis-monitor-feedback-NN.md` is numbered without gaps from `01`, and each one corresponds to a cycle the state file marks as a verdict change. (Feedback is emitted only on a verdict change, so the count itself is not checked.) |
| C4.5 | `grub-analysis-found-issues.md` exists, and `~/foobar/grub.md` holds the report (`auto-wp.md` §4.2.2): the final report for a terminus stop, the interim report for a deadline stop, matching the reason C4.2 found. Its git history in `~/remote.git` shows one version per report written. |

**Resume run**, in a separate container, budget 4 h (`/time-loop grub 4`):
`start`, then `stop` once the state file records the end of the first cycle,
then `restart`.

| # | Check |
|---|---|
| C4.6 | After `restart`, the state file is continued, not recreated: same start time, **same deadline** (start + 4 h, not restart time + 4 h; `auto-wp.md` §4.2.2), the cycle counter goes on from where it stopped, and the work-list keeps the statuses it had. The loop stops by the original deadline (plus one cycle, as C3.7). |
| C4.6b | **Restart after the deadline**: once the resume run has ended, `restart` again with `/time-loop grub 4`. The loop starts no new cycle: it writes the report to `grub.md` and stops within 30 minutes, and the deadline in the state file is unchanged. |
| C4.7 | No second onboarding: the onboarding package in `grub-analysis-acsl/` has the same modification time and content as before the stop. |
| C4.8 | `--dir`: after the resume run, `restart` with `/time-loop grub 1 --dir=grub-core/fs` on the same container. The state file then records the scope `grub/grub-core/fs`, and every unit the new cycles work on is under that directory. |

### 5.5 `gzip-test.sh` — level 3, gzip 1.9

The full specification is `gzip-test.md`. A one-hour campaign on a second
code base, GNU gzip 1.9, in a copy of `autowp-c-base/ready` (the toolchain
must already be built: a one-hour budget leaves no time to build it).

1. `python3 auto-wp.py gzip-analyze --c` in the container.
2. Download `gzip-1.9.zip` from the first of five mirrors that answers,
   check its pinned sha256 and its GPG signature (`gpgv` against the GNU
   keyring, signing key pinned by fingerprint), unzip it, run
   `bin/fetch-sources.sh`, and commit `gzip-1.9/` once in `gzip-analyze` as
   the baseline for K1. `gzip-1.9/` is a release tree, not a clone.
3. Start the harness in `~/gzip-analyze` and type `/time-loop gzip-1.9 N`,
   N = `GZIP_HOURS` (default 96). Hard limit N + 2 hours.

| # | Check |
|---|---|
| G.0 | The archive came from a listed mirror, its sha256 matches, its signature is good and made by the pinned key, and `configure` and `gzip.c` exist. On failure the test exits 2 before the token is moved in. |
| G.1 | K4. |
| G.2 | K1 for a tracked source: `git diff --quiet <import commit> -- gzip-1.9`; untracked build output allowed. |
| G.3 | `gzip-1.9-analysis-rmf-report.md` exists, is not empty, and passes `bin/rmf-lint.sh`. |
| G.4 | As C3.4, with an N-hour deadline. |
| G.5 | *Informational.* The number of wakes (a 1-hour budget may hold a single cycle). |
| G.6, G.7 | As C3.6 and C3.7. |
| G.8 | K2. |
| G.9 | *Informational.* K3, with `~/gzip-analyze` in the allowlist. |
| G.10 | As C3.10, for `~/gzip-analyze/gzip-1.9.md`. |
| G.11 | At least one unit has `PROVED` goals in a `verdicts.tsv` of the project; the counts of units, proofs and found issues are printed. |

The checks reuse `campaign_checks_c` and `report_check_c`, which read the
campaign from `CAMPAIGN_PROJECT`, `CAMPAIGN_SRC`, `CAMPAIGN_SRC_KIND`,
`CAMPAIGN_COMMIT_FILE`, `CAMPAIGN_WAKES` and `CAMPAIGN_LINT`
(`tests/lib/harness.sh`); the defaults are the GRUB campaign, so
`smoke-test.sh` and `acceptance.sh` are unchanged.

**Workshop mode** (`gzip-test.md` §7, added 2026-11-05). `WORKSHOP=1`
generates the project on the host and runs the same steps and checks in its
workshop (`workshop launch autowp`; the toolchain from `frama-c-sdk`), plus
W.1 (the generated definition), W.2 (launch, `ready`), W.3 (`frama-c` 32.1
from the SDK) and W.4 (`framac-src` linked to the SDK's sources,
`framac-onboard.sh` accepts the SDK). `WORKSHOP_BASE`, `WORKSHOP_TRY` and
`WORKSHOP_DIR` adapt it; `SETUP_ONLY=1` stops before the campaign (no
token). The helpers run in a workshop through `autowp_use_workshop`
(`tests/lib/lxc.sh`), and the campaign's directory is `CAMPAIGN_DIR`
(`/project`).

## 6. Rust tests (`tests/rust/`)

### 6.1 `provision.sh` — Rust base container

Builds `autowp-rust-base` and takes the snapshot `ready`:

1. Packages: `git python3 tmux curl opam build-essential`, plus
   `libcairo2-dev libgtk-3-dev libgtksourceview-3.0-dev`. Creusot's
   `creusot-deps.opam` depends on `why3-ide` (except in Creusot's own CI),
   which needs GTK; the installer stopped without these packages on the host
   on 2026-10-28.
2. `opam init --disable-sandboxing -y` (as in §5.1), `rustup` with its
   default toolchain, then Creusot: `git clone` of `creusot-rs/creusot` at a
   pinned commit (`CREUSOT_COMMIT`, default `f15b985`, the commit tested in
   `auto-wp.md` §4.3.6) into `/home/ubuntu/git/creusot`, then `./INSTALL`.
   This creates an opam switch in `~/.local/share/creusot`, installs the
   pinned nightly (`nightly-2026-08-03` at that commit) and the solvers.
   Success check: `cargo creusot version` lists Why3, why3find, Alt-Ergo, Z3,
   CVC4 and CVC5.
3. Claude Code as in §3.3, git as in §3.4.
4. Stop, then `lxc snapshot autowp-rust-base ready`.

**Workshop mode (planned, not implemented).** As for C (§5.1): a project
generated with `auto-wp.py --rust`, `workshop launch` with the `creusot`
SDK (on the SDK Store since 2026-11-05, `latest/edge`), `rocq`, `lean` and
`autowp-packages`; checks: `ready`, `cargo creusot version` lists the tools,
`cargo creusot config` prints `No problems found.`, and the smoke project
of `auto-wp.md` §4.3.6 case A proves. The same open question about copying
a workshop applies.

### 6.2 `install-test.sh` — level 2

Fresh `ubuntu:24.04` container, as in §5.2, then
`python3 auto-wp/auto-wp.py --rust foobar`.

| # | Check |
|---|---|
| R2.1 | Exit 0 with the stock `python3`; prints `skills:   17` and `commands: 0`. |
| R2.2 | `foobar/README.md` exists and contains `creusot-launch`. |
| R2.3 | `foobar` is a git work tree. |
| R2.4 | As C2.5: a second run exits 1 and changes nothing. |

### 6.3 `workspace-test.sh` — level 3

The end-to-end test of `auto-wp.md` §4.3.6, moved into the suite so it can be
re-run after a Creusot upgrade. It runs in a copy of `autowp-rust-base/ready`
and needs no Claude token. For each case A–H it creates a parent directory
(none, an empty `Cargo.toml`, a real workspace, or a package crate with its
own `.gitignore` absent or present), runs `cargo creusot new p`, applies the
fix (none, `[workspace]`, or `[workspace]` plus copying `why3find.json`), runs
`cargo creusot` in `p/`, and records where `why3find.json` and `.gitignore`
were written and whether an existing `.gitignore` was changed.

| # | Check |
|---|---|
| R3.1 | The results match the table of `auto-wp.md` §4.3.6: A, D, F, H prove `add_one`; B, C, E, G fail with the stated error. |
| R3.2 | An existing parent `.gitignore` is unchanged (sha256 before and after). |
| R3.3 | If a result differs (for example after an upstream fix), the test fails and prints the new table, so `auto-wp.md` §4.3.5 and the bug report can be updated. |

### 6.4 `smoke-test.sh` — level 3

Runs once `creusot-launch` exists (roadmap step 1 in `auto-wp.md` §4.3.7);
until then it prints `SKIP: creusot-launch not written yet` and exits 0.

In a copy of `autowp-rust-base/ready`: `auto-wp.py --rust foobar`, clone a
small crate with no dependencies next to it (pinned URL and commit, chosen
when the test is written), set up `origin` and the token, then start the
harness (§3.5) and type:

```
onboard the crate mycrate with creusot-launch, then analyze it with creusot-monitoring
```

This request is a single task, not a self-scheduling loop, so `claude -p`
would also work; the interactive harness is used for consistency with the C
tests.

| # | Check |
|---|---|
| R4.1 | The overlay `mycrate-creusot/` exists next to `mycrate/`, has `[workspace]` in its `Cargo.toml` and `why3find.json` at its root. |
| R4.2 | K1 applied to `mycrate/`, plus: no `why3find.json` or `.gitignore` was added to `mycrate/`. |
| R4.3 | `cargo creusot` succeeds in the overlay on at least one function. |
| R4.4 | The onboarding package lists the toolchain versions, the trusted assumptions and the faithfulness-check status. |
| R4.5 | K2 and K3. |

When `/time-loop` exists for Rust (roadmap step 5), a Rust `acceptance.sh`
is added, mirroring §5.4.

### 6.5 `sudo-rs-test.sh` — level 3, sudo-rs

The full specification is `sudo-rs-test.md` (added 2026-11-05). The Rust
counterpart of §5.5: a time-boxed Creusot campaign (default 96 hours,
`SUDORS_HOURS`) on sudo-rs v0.2.15, pinned by commit, driven by
`creusot-monitoring` through the harness, in a copy of
`autowp-rust-base/ready` or, with `WORKSHOP=1`, in the generated project's
workshop with the `creusot` SDK (W.1–W.3, shared with §5.5 through
`tests/lib/workshop.sh`). The mission also asks for a code-blind NIST RMF
risk study of sudo-rs (`rmf-sl`), written first by a sub-agent that never
sees the crate and used by `creusot-monitoring` to rank what to prove.
Checks: S.0 the pinned clone; S.1 K4; S.2 K1 on
`sudo-rs/`; S.3 the overlay `sudo-rs-creusot/` is a workspace depending on
`creusot-std`; S.4 `cargo creusot`, run by the test in the overlay, proves at
least one goal; S.5 the report `sudo-rs.md`; S.6 K2; S.7 K3 (INFO); S.8
`sudo-rs-analysis-rmf-report.md` exists, is not empty, and `bin/rmf-lint.sh`
on it exits 0 (the Rust counterpart of G.3, §5.5). `SETUP_ONLY=1` stops
after S.0, without the token.

## 7. Giving the harness access inside the container

### 7.1 Recommendation: a long-lived token from `claude setup-token`

On the host, Claude Code is signed in with a Claude subscription (an OAuth
access token and refresh token in `~/.claude/.credentials.json`), not with an
API key. To let a container use the subscription, **do not copy this
session**: create a separate long-lived token for the tests.

With `HARNESS=opencode` the credential is a provider API key instead, and the
same rules apply: store it once on the host
(`~/.config/auto-wp/opencode-provider-key`, mode 600 — the default of
`AUTOWP_TOKEN_FILE` for that harness), never copy the host's
OpenCode data directory (the database reported by `opencode debug paths`;
`auth.json` on older versions) into a container, and stream the key
through the same `/run/autowp/token` route. The launcher exports it under
the name of the provider it is for (`AUTOWP_OPENCODE_KEY_ENV`, default
`ANTHROPIC_API_KEY`); a key of another provider needs that variable set to
match. API keys do not expire the way OAuth tokens do, so the
`.created`/expiry metadata of this section is optional for them.

1. **Once, on the host:** `claude setup-token` ("Set up a long-lived
   authentication token (requires Claude subscription)"). It signs in through
   the browser and prints the token. Store it outside any repository,
   readable only by you, and record the date it was made (not secret) next to
   it:

   ```bash
   install -d -m 700 ~/.config/auto-wp
   install -m 600 /dev/null ~/.config/auto-wp/claude-oauth-token
   # paste the token into that file
   date -u +%F > ~/.config/auto-wp/claude-oauth-token.created
   ```

   The token's lifetime is not documented in `claude setup-token --help`.
   Write it into `claude-oauth-token.created` when `setup-token` states it;
   `acceptance.sh start` refuses to start a 72-hour run if the token would
   expire before the run ends, or if the lifetime is unknown and
   `ACCEPT_TOKEN_EXPIRY=1` is not set.

2. **Per harness start** (`tests/lib/secret.sh`): stream the file into a
   tmpfs file in the container through stdin, so the token never appears on a
   command line, in a process list, or in LXD's configuration:

   ```bash
   lxc exec "$C" -- install -d -m 700 -o ubuntu -g ubuntu /run/autowp
   lxc exec "$C" --user 1000 --group 1000 -- sh -c 'umask 077; cat > /run/autowp/token' \
       < ~/.config/auto-wp/claude-oauth-token
   ```

3. **The launcher** in the container reads it into the environment of the
   harness process, then deletes the file:

   ```bash
   CLAUDE_CODE_OAUTH_TOKEN=$(cat /run/autowp/token); export CLAUDE_CODE_OAUTH_TOKEN
   rm -f /run/autowp/token
   exec claude --dangerously-skip-permissions
   ```

   Check K2 runs before the launcher deletes the file, or re-streams it for
   the check and deletes it again.

`/run` is a tmpfs in the container, so even if the file were not deleted, it
would disappear when the container stops and would not be included in
snapshots or copies, which are taken of stopped containers.

### 7.2 Why not the other options

| Option | Problem |
|---|---|
| Copy `~/.claude/.credentials.json` into the container | Two independent copies of the same login then refresh their tokens separately. If the server rotates refresh tokens (not verified), whichever copy refreshes second is rejected: the container loses access in the middle of a 72-hour run, or the host session is signed out. It also hands the container the full login rather than a token made for it. |
| Bind-mount `~/.claude/` into the container | The container sees all host sessions, history and settings, and two processes write the same credentials file. A read-only mount avoids the second problem, but then token refreshes fail. |
| `lxc config set ... environment.CLAUDE_CODE_OAUTH_TOKEN` | Stored in LXD's database, shown by `lxc config show`, and copied into every snapshot and copy of the container. |
| `lxc exec --env CLAUDE_CODE_OAUTH_TOKEN=...` | Visible in the host's process list for as long as that `lxc exec` runs, which for the harness is the whole run. |
| `ANTHROPIC_API_KEY` | Works, but bills the API account, not the subscription the host session uses. |

### 7.3 What the agent in the container can do with the token

The method above keeps the token off disk and out of logs. It does **not**
hide it from the agent:

- `CLAUDE_CODE_OAUTH_TOKEN` is in the harness's environment, and every
  command the agent runs inherits it. With `--dangerously-skip-permissions`
  nothing stops the agent from reading it.
- The agent works on a cloned third-party repository, so a prompt injection
  in that repository is possible, and the bridge allows outgoing traffic to
  any host.

So treat the token as exposed to whatever runs in the container:

- Use a token made only for these tests (§7.1), never the host login.
- Optionally restrict outgoing traffic on `autowp-net` with an LXD network
  ACL (`EGRESS=strict`), allowing only the hosts the run needs: the Claude
  API, `gitlab.freedesktop.org`, and, during provisioning, the opam, Ubuntu,
  GitHub and crates.io mirrors. This is off by default because the full list
  for provisioning is long; it is recommended for level 4.
- **Revoke the token after a level 4 run**, then run `claude setup-token`
  again for the next one. It is independent of the host login, so the host
  session is not affected (where to revoke it, and whether revoking one
  token leaves the host login intact, is still to be confirmed; see §8).

### 7.4 Other credentials

- **Git:** none. `grub` is cloned over public HTTPS; the time-loop pushes to
  a local bare repository in the container (§3.4); the C tools ship in the
  project, and `bin/fetch-sources.sh` downloads Frama-C and macsl from public
  sources (§5.1). No SSH key or git credential
  is forwarded.
- **Cross-provider judge:** `~/.local-llm-machine-ip.txt` is not a secret,
  but the container can reach that host only if the bridge allows it.
  Level 3 runs without it (the judge steps are then advisory, `auto-wp.md`
  §3.4); level 4 copies the file in if it exists on the host.

## 8. Open points and issues found in the sources

Found while writing these tests; they need a decision outside `tests.md`:

1. *Resolved 2026-10-28.* The C README tells users to set a git identity
   next to adding a remote (`auto-wp.md` §3.4).
2. *Resolved 2026-10-28.* A re-run keeps the original deadline
   (`auto-wp.md` §4.2.2); checked by C4.6 and C4.6b.
3. *Resolved 2026-10-28.* There is no "diminishing returns" stop: the loop
   stops only at the true terminus or pauses at the deadline. The templates
   remove it from `time-loop.md` and from the skill's description
   (`auto-wp.md` §4.2.2, change 3); checked by C4.2 and T6.
4. *Resolved 2026-10-28.* `/time-loop XXX N` writes its report to `XXX.md`
   (`auto-wp.md` §4.2.2); checked by C3.10 and C4.5.
5. **Fractional budgets.** `time-loop.md` accepts "a positive number of
   hours", so `0.5` is allowed in principle; the tests no longer rely on it.
6. **Tools at the project root.** The use-frama-c tools now ship as regular
   files at the project root (`auto-wp.md` §4.2.1), where they lived in
   `use-frama-c`, so paths resolved from `$(dirname "$0")` or `$(pwd)` point
   at the project. C3.3–C3.6 are the first real test; K3 lists where they
   write.
7. **Not verified:** whether the server rotates refresh tokens; the
   `setup-token` lifetime and how to revoke it; whether print mode shows the
   folder-trust prompt; whether LXD network ACLs filter egress on this
   bridge.
8. **Rust smoke-test crate** (§6.4): to be chosen.
9. **Workshop mode of `provision.sh`** (§5.1, §6.1): planned only. It
   depends on the Store publication of the C SDKs and on how a workshop is
   copied for the later levels.
