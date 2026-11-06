# sudo-rs test — a time-boxed Creusot campaign on sudo-rs (draft)

This document specifies a container test that runs the Rust layer on a real,
security-relevant crate: [sudo-rs](https://github.com/trifectatechfoundation/sudo-rs),
the memory-safe reimplementation of `sudo` and `su`. It is the Rust
counterpart of `gzip-test.md`: a level 3 test in the sense of `tests.md` §2.
It costs a few hours of the Claude subscription, needs the Claude token, and
is run by hand: `tests/rust/sudo-rs-test.sh`. Written 2026-11-05; only its
setup has run (§7).

## 1. What the test does

1. Generate the project `sudo-rs-analyze` with `auto-wp.py --rust`.
2. In it, clone sudo-rs at the pinned release (§2), next to where the
   Creusot overlay will go.
3. Start the agent harness (`HARNESS`: Claude Code by default, or OpenCode)
   and give it the mission of §3, which
   asks for a code-blind RMF risk study of sudo-rs (`rmf-sl`) and then
   drives `creusot-monitoring` on the crate for a fixed budget (default 2
   hours, `SUDORS_HOURS`).
4. Stop the harness at the budget plus 30 minutes, or when the transcript
   has been idle for 30 minutes, then check the results (§5).

## 2. The crate

| | |
|---|---|
| Repository | `https://github.com/trifectatechfoundation/sudo-rs.git` |
| Release | `v0.2.15`, commit `e4cfa9cf7b71e287dd5046633c0f5276072d147d` (the tag's target, read 2026-11-05) |
| Layout | one package `sudo-rs` (edition 2024, `rust-version` 1.85), 91 `*.rs` files under `src/` (`sudoers/`, `sudo/`, `su/`, `visudo/`, `pam/`, `exec/`, `system/`, …), dependencies `libc` and `glob` only |
| Build needs | `libpam0g-dev` (sudo-rs's README) |
| Already there | `proofs/sudoers.mlw`, a Why3 model of the sudoers policy |

The test clones the tag with `--depth 1` and checks that `HEAD` is the pinned
commit, that `Cargo.toml` names `sudo-rs`, and that `src/sudoers/` and
`proofs/sudoers.mlw` exist (S.0). A moved tag fails S.0 instead of silently
testing another tree.

Why sudo-rs: it is small enough for a few hours (two dependencies, 91 files),
it is security-critical with an obvious untrusted-input surface (the sudoers
parser, the command line), it has a lot of FFI that Creusot cannot model (PAM,
`exec`, terminals), so the scope map of `creusot-monitoring`'s Phase 0
matters, and `proofs/sudoers.mlw` gives the loop an external reference model
instead of a purely endogenous upper bound.

## 3. The mission

There is no `/time-loop` for Rust yet (`auto-wp.md` §4.3.7), and
`creusot-launch` is not written (roadmap step 1). The test therefore types a
plain request that asks `creusot-monitoring` for the whole campaign, including
the overlay that `creusot-launch` would create:

- analyze the crate `sudo-rs` in directory `sudo-rs` with
  `creusot-monitoring`, as a security audit;
- first, before anything reads the code, have a fresh sub-agent that never
  sees `sudo-rs/` write a code-blind NIST RMF risk study of sudo-rs with the
  `rmf-sl` skill, to `sudo-rs-analysis-rmf-report.md` next to `sudo-rs/`,
  passing `bin/rmf-lint.sh`; `creusot-monitoring` then uses its risk levels
  to rank what to prove (its Phase 0, `auto-wp.md` §4.3.4). This is the
  Rust counterpart of the `rmf-sl` phase of the C `/rmf` campaign
  (`gzip-test.md` §1), asked for by name since there is no Rust `/rmf`;
- never modify `sudo-rs/`; every Creusot artifact goes in the overlay
  `sudo-rs-creusot/` next to it, a Cargo workspace of its own that depends on
  `creusot-std` (`auto-wp.md` §4.3.5, the `creusot` skill's install
  reference);
- rank files by exposure to untrusted input: `src/sudoers` and command-line
  parsing first;
- prove absence of panics, overflows and out-of-bounds accesses; use
  `proofs/sudoers.mlw` as a reference model;
- record PAM, `exec`, terminal and other FFI or system-state code as out of
  reach;
- write the report of the run to `sudo-rs.md`, next to `sudo-rs/`, before
  the budget ends.

When `creusot-launch` exists, the request becomes "onboard … with
`creusot-launch`, then analyze it with `creusot-monitoring`", and S.3 checks
its onboarding package as `smoke-test.sh` R4.4 does.

## 4. Where it runs

Two modes, sharing the steps and the checks:

- **LXD** (default): a copy of `autowp-rust-base/ready`
  (`tests/rust/provision.sh`), which has Creusot built from source. The test
  installs `libpam0g-dev` as root, pushes `auto-wp.py` and the templates,
  and generates the project in the container, as `smoke-test.sh` does.
- **Workshop** (`WORKSHOP=1`): as `gzip-test.md` §7. The project is generated
  on the host, `libpam0g-dev` is added to
  `.workshop/autowp-packages/hooks/setup-base` (the edit the README asks of
  users for their crate's packages), and `workshop launch` brings the
  `creusot`, `rocq` and `lean` SDKs. The shared steps are in
  `tests/lib/workshop.sh` (W.1 the generated definition lists `creusot`,
  `rocq`, `lean`, `project-autowp-packages`; W.2 launch and `ready`), and
  W.3 checks that `cargo creusot version` is 0.15 and `CREUSOT_SDK_SRC` is
  under `/opt/creusot/`. `WORKSHOP_BASE`, `WORKSHOP_TRY`, `WORKSHOP_DIR` and
  `KEEP` work as for gzip.

In both, the checkpoint remote is `~/remote.git`, and the test builds sudo-rs
once as shipped (INFO), so a build failure caused by the environment is told
apart from one caused by the overlay. `SETUP_ONLY=1` stops after S.0 (and
W.1–W.3), without the token.

## 5. Checks

| # | Check |
|---|---|
| S.0 | The clone is commit `e4cfa9c…` with the layout of §2. Failing here exits 2 before the token is moved in. INFO: whether sudo-rs builds as shipped. |
| S.1 | K4: `creusot-monitoring` was loaded within 10 minutes. |
| S.2 | K1: `sudo-rs/` is still the pinned commit, with no tracked change; and no `why3find.json`, `.gitignore` or `.coma` file was created inside it. |
| S.3 | The overlay `sudo-rs-creusot/` exists, its `Cargo.toml` has a `[workspace]` table, and it (or a member) depends on `creusot-std`. |
| S.4 | **The test runs `cargo creusot` in the overlay itself** (30-minute limit) and at least one `Proved` line comes out. The exit status and the counts of proved and failed or unknown goals are INFO. This is the objective gate: it does not rely on what the agent reports. |
| S.5 | `sudo-rs.md` exists and is not empty. INFO: the files that look like the Phase 0 architecture report, and the number of new files under `creusot-monitoring`'s `getting-better/` and `bugs-to-report/`. |
| S.6 | K2: the token was not written anywhere (in a workshop, `/project` included). |
| S.7 | *Informational.* K3, with the Rust tool directories in the allowlist. |
| S.8 | `sudo-rs-analysis-rmf-report.md` exists, is not empty, and `bin/rmf-lint.sh` on it exits 0 (structure, chaining and the C8 endogeneity tripwire, which fails on Rust code artifacts in R1–R4). The counterpart of `gzip-test.md` G.3; the `FAIL` lines of the linter are reported on failure. Added 2026-11-06, after S.7, so that the earlier IDs keep their meaning. |

As for G.11, an S.4 failure is read with the pane transcript before it is
blamed on the skills: a few hours may go to rate limits, or to building
Creusot's view of a crate full of FFI.

## 6. Open points

1. **Budget.** Two hours is a guess: enough for Phase 0 and the first
   sudoers-parser files, not for the crate. Raise `SUDORS_HOURS` once a first
   run shows the pace.
2. **Overlay without `creusot-launch`.** The mission asks
   `creusot-monitoring` to create the overlay, which is `creusot-launch`'s
   job. S.3 may fail for that reason alone until roadmap step 1 is done.
3. **Edition 2024 on Creusot's nightly.** sudo-rs needs Rust 1.85 or later;
   the `creusot` SDK's `nightly-2026-08-03` is newer, but whether Creusot
   handles every edition-2024 construct sudo-rs uses is untested.
4. **The risk study's share of the budget.** The RMF study (S.8) comes out
   of the same `SUDORS_HOURS`; in the C gzip run the `rmf-sl` phase took a
   large part of the first hour. If S.4 suffers from it, raise the budget
   rather than drop the study: an endogenous ranking is what the study is
   there to replace. S.8 has not run yet.

## 7. Results

- 2026-11-05, `WORKSHOP=1 WORKSHOP_TRY="rocq lean" SETUP_ONLY=1` on
  `ubuntu@24.04`: 4 passed, 0 failed. W.1; W.2 (launch in 1140 s, `creusot`
  0.15.0-f15b985 from the Store on `latest/edge`, `rocq` and `lean` from the
  try area, `libpam0g-dev` from `autowp-packages`; `ready`); W.3
  (`CREUSOT_SDK_SRC=/opt/creusot/src/creusot`, commit `f15b985`); S.0. The
  network checks passed, and sudo-rs v0.2.15 built as shipped with the SDK's
  nightly. The campaign itself has not run.
- 2026-11-06, `WORKSHOP=1 SETUP_ONLY=1` on `ubuntu@24.04`, every SDK from
  the Store (`latest/edge`): 4 passed, 0 failed. W.2 launched in 1105 s with
  `creusot` 0.15.0-f15b985, `rocq` 9.2.0 and `lean` 4.35.0 from the Store,
  `ready`. `WORKSHOP_TRY` is no longer needed on 24.04.
