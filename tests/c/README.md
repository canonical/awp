# C tests

Container tests for a C project generated with `auto-wp.py`, on GRUB.
Every check is specified in `../../spec/tests.md` §5; the IDs below are those of
that section. Run the scripts from any directory, or through the `make`
targets at the repository root. See `../README.md` for the levels, the LXD
objects and the harness credential.

| Script | Level | `make` target | Duration | Token |
|---|---|---|---|---|
| `install-test.sh` | 2 | `test-c-l2` | minutes | no |
| `provision.sh` | — | `provision-c` | hours | no |
| `smoke-test.sh` | 3 | `smoke-c` | 3–5 h | yes |
| `gzip-test.sh` | 3 | `smoke-c-gzip`, `smoke-c-gzip-ws` | 96–98 h (`GZIP_HOURS`) | yes (not with `SETUP_ONLY=1`) |
| `mbed-tls-test.sh` | 3 | `smoke-c-mbedtls`, `smoke-c-mbedtls-ws` | 96 h (default; level 4) | yes (not with `SETUP_ONLY=1`) |
| `acceptance.sh` | 4 | none | 72 h + 6 h | yes |

## `install-test.sh` — level 2

In a fresh `ubuntu:24.04` container, with its stock `python3` and `git`:
runs `auto-wp.py --c --harness "$HARNESS" foobar`, checks the README, clones GRUB, and runs
`auto-wp.py` a second time.

- C2.1 — `auto-wp.py` exits 0 and prints `skills:   23` and `commands: 3`.
- C2.2 — the in-container block of `foobar/README.md` starts with the lines
  this test runs and ends with `claude --dangerously-skip-permissions`, and
  the README documents the OpenCode alternative.
- C2.3 — `git clone` of GRUB works, and `foobar/grub/` is its own work tree.
- C2.4 — `foobar` is a git work tree with no commits, and does not track
  `grub/`.
- C2.5 — a second run exits 1 and changes nothing in `foobar/`.

It does not install a harness or the toolchain; level 3 covers the rest.

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

A one-hour campaign on GNU gzip 1.9 (`../../spec/gzip-test.md`, `tests.md`
§5.5), in a copy of `autowp-c-base/ready`. In the container it generates
`gzip-analyze`, downloads `gzip-1.9.zip` from the first of five mirrors that
answers, checks its sha256 and its GPG signature (signing key pinned), unzips
it, commits it as the baseline, and runs `/time-loop gzip-1.9 1` in the
harness. Budget `GZIP_HOURS` (default 96), hard limit that plus 2 hours.

- G.0 — the archive is the pinned one, correctly signed; otherwise the test
  exits 2 before the token is moved in.
- G.1–G.10 — the level 3 checks of `smoke-test.sh`, adapted: `gzip-1.9/`
  unchanged since the import commit, the RMF report passes
  `bin/rmf-lint.sh`, an N-hour deadline, the wake count only reported,
  the interim report in `gzip-1.9.md`.
- G.11 — at least one unit has `PROVED` goals; the counts of units, proofs
  and found issues are printed. A failure can come from an hour lost to rate
  limits: read the pane transcript first.

**Workshop mode** (`make smoke-c-gzip-ws`, `gzip-test.md` §7): with
`WORKSHOP=1`, the project is generated on the host and the campaign runs in
its workshop, the toolchain coming from the `frama-c-sdk` SDK instead of
`autowp-c-base`. Extra checks W.1 (the generated `.workshop/autowp.yaml`),
W.2 (launch, `ready`), W.3 (`frama-c` 32.1 from the SDK), W.4
(`framac-src` linked to the SDK's sources). Options:

- `WORKSHOP_BASE=ubuntu@26.04` — the base of the definition;
- `WORKSHOP_TRY="rocq lean"` — use `try-<name>` (packed here with
  `sdkcraft try`) for SDKs not released on the Store for that base
  (`sdk info <name>` lists the bases released per channel);
- `SETUP_ONLY=1` — stop after G.0 and W.1–W.4: no token, a few minutes.

```
WORKSHOP=1 SETUP_ONLY=1 tests/c/gzip-test.sh
```

## `mbed-tls-test.sh` — level 3 (fips driver)

The `--driver fips` counterpart of `gzip-test.sh`: a `/time-loop mbedtls N`
campaign on [Mbed TLS](https://github.com/Mbed-TLS/mbedtls), a real
cryptographic library, so that `fips-sl` studies a module that is one
(`fips-skill-spec.md` §9, open point 2). Clones the pinned tag
(`MBEDTLS_TAG`, default `mbedtls-3.6.7`, verified against `MBEDTLS_SHA`),
generates the project with `--driver fips --level N` (`FIPS_LEVEL`, default
**4**), runs the campaign for `MBEDTLS_HOURS` (default **96** — the cost
profile of `acceptance.sh`; the credential must outlive the run, and
`ACCEPT_TOKEN_EXPIRY=1` accepts an unknown lifetime), then checks the fips
artifacts: the `*-fips-report.md` accepted by `bin/fips-lint.sh`, the
time-loop state (deadline, wakes, cycles), one commit per cycle in
`~/remote.git`, the token never leaked (K2), nothing written outside the
allowlist (K3), the consolidated report, and at least one unit with PROVED
goals. For a cheap smoke instead, pass `FIPS_LEVEL=2 MBEDTLS_HOURS=2`. The
run's artifacts survive by default (`KEEP=1` is the default of this script,
unlike the others): the FIPS documents stay in `/home/ubuntu/mbedtls-analyze/`
in the kept container — read them with `lxc exec` or copy them out with
`lxc file pull -r` (the container name is in the cleanup line) — or, with
`WORKSHOP=1`, in `~/.awp/autowp-mbedtls-analyze-ws.<suffix>/mbedtls-analyze/`
on the host. `KEEP=0` restores delete-on-exit; `make clean-lxc` sweeps
leftover `autowp-*` containers. A
guard prints SKIP and exits 0 if a fips-driver piece is missing
(`auto-wp.py --driver/--level`, `commands/fips.md`, `bin/fips-lint.sh`, the
time-loop driver table) — all four exist since the driver landed
(`fips-skill-spec.md` §6–7). `WORKSHOP=1` runs it in
the generated project's workshop like `gzip-test.sh` does; `SETUP_ONLY=1`
stops after the setup checks.

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
