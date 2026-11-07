# auto-wp tests

Tests for `auto-wp.py` and the projects it generates. The full specification,
with every check and its rationale, is `../spec/tests.md`. This file says what is
here and how to run it.

## Levels

| Level | What | Where | Duration | Needs |
|---|---|---|---|---|
| 1 | program and template tests | host | seconds | Python 3.10+, git |
| 2 | `auto-wp.py` and the README clone step, on a stock image | fresh LXD container | minutes | LXD, network |
| 3 | a short campaign in the harness, or a tool-level regression | copy of a provisioned base container | 1–4 h | level 2, a harness credential |
| 4 | `/time-loop grub 72`, plus a resume run (C only) | copy of a provisioned base container | 72 h + 4 h | level 3 |

Run levels 1 and 2 after every change to `auto-wp.py` or the templates.
Levels 3 and 4 use a paid harness session and take hours: they are run by
hand, never by `make test` or `make test-l2`.

## Running

From the repository root:

```
make test            # level 1
make test-l2         # level 2, C and Rust (or test-c-l2, test-rust-l2)
make check-scripts   # bash -n and shellcheck on every script
make help            # every target
```

Levels 3 and 4 need a provisioned base container first:

```
make provision-c     # or provision-rust; builds autowp-c-base (hours)
make smoke-c         # level 3, C
make smoke-c-gzip    # level 3, C, gzip 1.9 (one hour)
make smoke-c-mbedtls # level 3, C, a fips campaign on Mbed TLS (SKIPs until
                     # the fips driver exists)
make workspace-rust  # level 3, Rust, no token needed
make smoke-rust      # level 3, Rust
tests/c/acceptance.sh start   # level 4, see c/README.md
```

Each script prints `PASS: <id>`, `FAIL: <id>: <reason>`, `SKIP: <id>: ...`
or `INFO: <id>: ...` per check, and exits 0 only if no check failed. The
`make` targets also write a log to `tests/out/`.

## What is here

- `test_auto_wp.py` — level 1 program tests: the numbered tests of
  `auto-wp.md` §5 (layout, flags, usage errors, refusals, rollback, git,
  manifest, symlinks, exec bits, READMEs, tools), for both languages. It
  runs `auto-wp.py` in temporary directories and touches nothing else.
- `test_templates.py` — level 1 template checks T1–T7 (`tests.md` §3.2):
  it reads `templates/` and checks what `auto-wp.py` copies byte for byte.
- `lib/` — shell helpers sourced by the container tests:
  - `lxc.sh` — LXD setup and container handling (pool, bridge, launch,
    copy, exec, push, cleanup) and the PASS/FAIL reporting;
  - `secret.sh` — moves the harness credential into a container
    (`tests.md` §7);
  - `harness.sh` — starts the agent harness in `tmux` in a container and
    types a command (`tests.md` §3.5). `HARNESS=claude` (default) drives
    Claude Code; `HARNESS=opencode` drives OpenCode (its launcher exports
    the provider API key named by `AUTOWP_OPENCODE_KEY_ENV`, default
    `ANTHROPIC_API_KEY`, and runs `opencode --standalone`).
- `c/` and `rust/` — the container tests for each language; see their
  README files.
- `out/` — logs written by the `make` targets. `make clean` removes it.

## LXD objects

The container tests create only objects named `autowp*`:

- the storage pool `autowp` and the bridge `autowp-net`, created when
  missing and kept;
- the base containers `autowp-c-base` and `autowp-rust-base`, each with a
  snapshot `ready`, kept;
- test containers `autowp-*`, deleted at the end of each script unless
  `KEEP=1` is set.

They never change other containers, networks, profiles or pools. `make
clean-lxc` deletes leftover test containers and keeps the two bases.
Override the defaults with `AUTOWP_POOL`, `AUTOWP_NET` and `IMAGE`
(see the header of `lib/lxc.sh`).

## The harness credential

Levels 3 and 4 read a long-lived credential from `AUTOWP_TOKEN_FILE` (default
`~/.config/auto-wp/claude-oauth-token`, mode 600; with `HARNESS=opencode`,
`~/.config/auto-wp/opencode-provider-key`). For Claude Code, create it
yourself once with `claude setup-token`. For OpenCode, write the provider API
key its launcher exports (an Anthropic key by default) into the file, mode
600. The scripts never read the host's `~/.claude/.credentials.json` or
`~/.local/share/opencode/auth.json`, and never put the credential on a
command line, in LXD's configuration or in their output: it goes through
stdin into a tmpfs file in the container, which the launcher reads and
deletes. `tests.md` §7 explains why, and what an agent in the container can
still do with it.

## Differences from the README quick start

The container tests do not follow the generated README step by step. They
copy the project into the container instead of mounting it, and use
`~/remote.git` as the checkpoint remote instead of `~/foobar.git`, so that a
test run never writes into a host directory. Level 2 checks that the
in-container block of the C README starts with the lines it runs (C2.2).
