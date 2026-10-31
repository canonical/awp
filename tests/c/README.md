# C tests

Container tests for a project generated with `auto-wp.py --c`, on GRUB.
Every check is specified in `../../tests.md` §5; the IDs below are those of
that section. Run the scripts from any directory, or through the `make`
targets at the repository root. See `../README.md` for the levels, the LXD
objects and the Claude token.

| Script | Level | `make` target | Duration | Token |
|---|---|---|---|---|
| `install-test.sh` | 2 | `test-c-l2` | minutes | no |
| `provision.sh` | — | `provision-c` | hours | no |
| `smoke-test.sh` | 3 | `smoke-c` | 3–5 h | yes |
| `gzip-test.sh` | 3 | `smoke-c-gzip` | 1–3 h | yes |
| `acceptance.sh` | 4 | none | 72 h + 6 h | yes |

## `install-test.sh` — level 2

In a fresh `ubuntu:24.04` container, with its stock `python3` and `git`:
runs `auto-wp.py --c foobar`, checks the README, clones GRUB, and runs
`auto-wp.py` a second time.

- C2.1 — `auto-wp.py` exits 0 and prints `skills:   21` and `commands: 3`.
- C2.2 — the in-container block of `foobar/README.md` starts with the lines
  this test runs and ends with `claude --dangerously-skip-permissions`.
- C2.3 — `git clone` of GRUB works, and `foobar/grub/` is its own work tree.
- C2.4 — `foobar` is a git work tree with no commits, and does not track
  `grub/`.
- C2.5 — a second run exits 1 and changes nothing in `foobar/`.

It does not install Claude Code or the toolchain; level 3 covers the rest.

## `provision.sh` — base container

Builds `autowp-c-base` and its snapshot `ready`, which levels 3 and 4 copy:
the packages of the README, the AppArmor fix for opam, the C tools of
`templates/c/tools/` in `~/toolchain`, then `bin/fetch-sources.sh` and the
Frama-C 32.1 toolchain build in the `framac-coq8` opam switch. Nothing comes
from a checkout on the host.

- `SKIP_TOOLCHAIN=1` skips the toolchain build; `/time-loop` must then build
  it itself through `frama-c-launch`.
- `FORCE=1` deletes an existing base first.
- `KEEP=1` keeps a half-built base on failure.

## `smoke-test.sh` — level 3

Copies `autowp-c-base/ready`, generates `foobar`, clones GRUB, and runs
`/time-loop grub 3` in the harness. It waits for the loop to stop (at most
5 hours), then checks C3.1–C3.10:

- the command was loaded, and `grub/` is untouched;
- the RMF report and the time-loop state file exist, with a 3-hour deadline;
- the loop re-armed itself at least once, and committed and pushed every
  cycle;
- it stopped on time and wrote the interim report to `foobar/grub.md`;
- the token was not written anywhere, and files changed outside the
  expected places are listed (informational).

## `gzip-test.sh` — level 3, gzip 1.9

A one-hour campaign on GNU gzip 1.9 (`../../gzip-test.md`, `tests.md`
§5.5), in a copy of `autowp-c-base/ready`. In the container it generates
`gzip-analyze`, downloads `gzip-1.9.zip` from the first of five mirrors that
answers, checks its sha256 and its GPG signature (signing key pinned), unzips
it, commits it as the baseline, and runs `/time-loop gzip-1.9 1` in the
harness. Hard limit 3 hours.

- G.0 — the archive is the pinned one, correctly signed; otherwise the test
  exits 2 before the token is moved in.
- G.1–G.10 — the level 3 checks of `smoke-test.sh`, adapted: `gzip-1.9/`
  unchanged since the import commit, the RMF report passes
  `bin/rmf-lint.sh`, a 1-hour deadline, the wake count only reported,
  the interim report in `gzip-1.9.md`.
- G.11 — at least one unit has `PROVED` goals; the counts of units, proofs
  and found issues are printed. A failure can come from an hour lost to rate
  limits: read the pane transcript first.

## `acceptance.sh` — level 4

The README example itself, `/time-loop grub 72`, and a resume run. The main
run lasts 72 hours, so the script has sub-commands:

```
ACCEPT_COST=1 tests/c/acceptance.sh start   # start the 72-hour run
tests/c/acceptance.sh status                # elapsed, cycles, time rate-limited
tests/c/acceptance.sh attach                # tmux attach in the container
tests/c/acceptance.sh check                 # C4.1-C4.5, after the run
tests/c/acceptance.sh stop | restart | destroy
ACCEPT_COST=1 tests/c/acceptance.sh resume  # C4.6-C4.8, about 6 h
```

Run `status` periodically during the run (for example `watch -n 600
tests/c/acceptance.sh status`): it measures the time spent rate-limited,
which C4.2 subtracts when it checks the stop time. `ACCEPT_COST=1` is
required because the run uses the Claude subscription for days.

- C4.1–C4.5 — the level 3 checks on this run; it stopped at the deadline or
  at the true terminus, never for "diminishing returns"; one commit per
  cycle; numbered monitor feedback; the found-issues file and the report.
- C4.6–C4.8 — a restart keeps the original deadline and the work list; a
  restart after the deadline only writes the report; there is no second
  onboarding; `--dir=grub-core/fs` limits the new cycles to that directory.
