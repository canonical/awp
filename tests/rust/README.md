# Rust tests

Container tests for a project generated with `auto-wp.py --rust`, which
verifies Rust code with Creusot. Every check is specified in
`../../spec/tests.md` §6; the IDs below are those of that section. Run the
scripts from any directory, or through the `make` targets at the repository
root. See `../README.md` for the levels, the LXD objects and the Claude
token.

| Script | Level | `make` target | Duration | Token |
|---|---|---|---|---|
| `install-test.sh` | 2 | `test-rust-l2` | minutes | no |
| `provision.sh` | — | `provision-rust` | an hour or more | no |
| `workspace-test.sh` | 3 | `workspace-rust` | minutes | no |
| `smoke-test.sh` | 3 | `smoke-rust` | up to 4 h | yes |

## `install-test.sh` — level 2

In a fresh `ubuntu:24.04` container, with its stock `python3` and `git`:
runs `auto-wp.py --rust foobar` and a second time.

- R2.1 — exits 0, prints `commands: 0`, and installs the 16 skills of
  `auto-wp.md` §4.3.2. `creusot-launch` is not written yet (roadmap step 1,
  `auto-wp.md` §4.3.7): the test then expects 15 and reports `SKIP` for
  it, instead of passing silently.
- R2.2 — `foobar/README.md` exists and names `creusot-launch`.
- R2.3 — `foobar` is a git work tree.
- R2.4 — a second run exits 1 and changes nothing.

## `provision.sh` — base container

Builds `autowp-rust-base` and its snapshot `ready`: the packages of the
README, the AppArmor fix for opam, opam, rustup, and Creusot built with its
`./INSTALL`.

- `CREUSOT_COMMIT=<sha>` picks the Creusot commit (default `f15b985`,
  `auto-wp.md` §4.3.6).
- `FORCE=1` deletes an existing base first.
- `KEEP=1` keeps a half-built base on failure.

## `workspace-test.sh` — level 3

A regression test of Creusot itself, with no Claude run: where
`cargo creusot new` writes `why3find.json`, in the layouts A–H of
`auto-wp.md` §4.3.6 (a crate inside or next to another Cargo project, with
or without `[workspace]`).

- R3.1 — the results match the table: A, D, F and H prove `add_one`; B, C,
  E and G fail with the stated error.
- R3.2 — an existing parent `.gitignore` is unchanged.
- R3.3 — when a result differs, for example after an upstream fix, the test
  fails and prints the new table, so that `auto-wp.md` and the bug report
  can be updated.

Run it again after every Creusot upgrade.

## `smoke-test.sh` — level 3

`creusot-launch` and `creusot-monitoring` on a small crate, through the
harness, in a copy of `autowp-rust-base/ready`:

```
MYCRATE_URL=<url> MYCRATE_COMMIT=<sha> tests/rust/smoke-test.sh
```

- R4.1 — the overlay `mycrate-creusot/` exists next to `mycrate/`, with
  `[workspace]` in its `Cargo.toml` and `why3find.json` at its root.
- R4.2 — `mycrate/` is untouched: no `why3find.json` or `.gitignore` added.
- R4.3 — `cargo creusot` succeeds in the overlay on at least one function.
- R4.4 — the onboarding package lists the toolchain versions, the trusted
  assumptions and the faithfulness-check status.
- R4.5 — the token was not written anywhere, and files changed outside the
  expected places are listed.

`SMOKE_HOURS` sets the hard limit of the run (default 4). Until
`creusot-launch` exists, the script prints `SKIP` and exits 0. The crate is
not chosen yet (`tests.md` §8): it should be small, have no dependencies,
and be pinned by URL and commit.

There is no level 4 for Rust: there is no `/time-loop` command for Rust
yet.
