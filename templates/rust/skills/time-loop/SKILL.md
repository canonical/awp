---
name: time-loop
description: >-
  An N-hour, deadline-driven META loop for Rust that drives creusot-monitoring
  (and its creusot-sl sub-loops) on a crate XXX to maximize high-value proved
  coverage, ranked by a code-blind risk study (rmf-sl, or fips-sl under the fips
  driver). It does not prove code itself: each cycle it triages the open items
  (class A Creusot/solver limit, class B crypto, OUT OF REACH system state,
  class C unfinished contract work - the only class budget is spent on), drives
  one thread in a time-boxed verifier sub-agent, judges the delivered verdicts,
  records them in XXX-creusot/verdicts.tsv, rewrites the report XXX.md, commits
  and pushes, and re-arms its heartbeat. There is no diminishing-returns stop:
  it ends only at the true terminus and pauses at the deadline. A re-run keeps
  the original deadline. XXX/ stays pristine (never run cargo in it). Use for
  `/time-loop XXX N` on a Rust crate.
---

# time-loop (Rust) — an N-hour Creusot campaign over a crate `XXX`

This is a **meta / monitoring** loop (the `sl-monitoring-sl` pattern, time-boxed). The *base*
loop is `creusot-monitoring`, which verifies a crate file by file with `creusot-sl`. `time-loop`
does not write contracts or proofs; it **triages, ranks, drives and monitors** that base loop over
`N` hours, and is the disjoint actor that catches its two failures: relabelling unfinished work as
an exemption, and burning the clock — on one hard function, or on idle cycles.

It is the Rust port of the C `time-loop` (Frama-C/WP). The cycle, the state file, the heartbeat
and the report are the same; the verifier, the residue classes and the oracles are Creusot's.

## The campaign driver

The `driver` key of `config/auto-wp.json` selects the code-blind risk study. Without it, `rmf`.

| | `rmf` | `fips` |
|---|---|---|
| risk study skill | `rmf-sl` | `fips-sl` |
| report | `XXX-analysis-rmf-report.md` | `XXX-analysis-fips-report.md` |
| feedback | `XXX-analysis-monitor-feedback-NN.md` | `XXX-analysis-fips-feedback-NN.md` |
| linter | `bin/rmf-lint.sh` | `bin/fips-lint.sh` |
| ranked item and scale | `RS#`, `High`/`Moderate`/`Low` | `VO#`, `P1`/`P2`/`P3` |
| terminus signs | Authorizing Official | the owner of the protected information |
| compliance dossier | — | `XXX-fips-compliance/`, regenerated with every `XXX.md` (`fips-sl` §10) |

## 0. Artifacts (all in the project root, next to `XXX/`, never inside it)

| Path | Content |
|---|---|
| `XXX/` | the crate under study — **read-only**, for builds too |
| `XXX-analysis-rmf-report.md` | the code-blind risk study (per the driver table) |
| `XXX-creusot/` | the overlay: a Cargo workspace of its own that depends on `creusot-std`; one member crate per modelled area; `failing/` (outside the workspace) holds the expected-failing models that witness findings |
| `XXX-creusot/time-loop.state` | the campaign state (§2) |
| `XXX-creusot/verdicts.tsv` | the verdict ledger, the single source of truth (§5) |
| `XXX-creusot/trusted-base.md` | every `#[trusted]` item, every transcription assumption, every abstraction, each REDUCIBLE or IRREDUCIBLE-with-reason |
| `XXX-analysis-found-issues.md` | the finding ledger `FI-1`, `FI-2`, … (append-only) |
| `XXX-analysis-monitor-feedback-NN.md` | the scenario-keyed feedback to the risk study, on a verdict delta only |
| `XXX.md` | the report of the run (§6) |

When `XXX` is a path, the artifacts use a root-safe slug (`crates/foo` → `crates-foo`).

## 1. Bounds and invariants

- **L (ground truth):** `cargo creusot` verdicts (Why3 + the solvers) on the overlay; the
  faithfulness check (§5); a **running reproduction** of every finding on the unmodified code,
  built in a copy.
- **U (target):** the code-blind risk study's ranked items on the crate's untrusted-input surface,
  bounded by what Creusot can express (the moving frontier of L).
- **Invariants, inherited by every sub-agent (put them in its prompt):**
  - **`XXX/` is pristine — BUILD IN A COPY.** Never run `cargo`, a build script or any tool that
    writes inside `XXX/` (cargo rewrites `Cargo.lock`, and the SDK's global `[patch]` adds a
    `[[patch.unused]]` stanza). To build or run the real code: `cp -a XXX /tmp/XXX-build` and
    build there with `--target-dir` outside the project. After any build step,
    `git -C XXX status --short` must be empty.
  - No `#[trusted]`, `assume` or `#[ensures(false)]` in a shipped proof unless the item is an entry
    of `trusted-base.md`. A proof that relies on an unlisted trusted item is REJECTED.
  - Honest residuals: an item is PROVEN, a finding, a filed Creusot bug, or OUT OF REACH with a
    reason. "Hard" is not a status.
  - The Authorize step stays **PENDING**: the human signs (driver table), the loop never does.

## 2. State — `XXX-creusot/time-loop.state`

**Pinned lines** (`key=value`, one per line, epoch seconds from `date +%s`; tests and resumes parse
them, so never reword them): `start=<epoch>` and `deadline=<epoch>` once, written on the first
invocation and never changed; then **`wake=<epoch>` appended as the first action of every wake**,
never rewritten or removed; `scope=<subdir>` when `--dir` is given; and each cycle's log entry starts
`cycle <n>: ` (a space before the number). Take every time from `date -u` or `date +%s`, never from
your own estimate. Free text goes on other lines.

**A re-run keeps the original deadline:** if the state file exists, the invocation reuses the
stored start and deadline and ignores its own `N`; if the stored deadline has passed, it writes the
report (§6) and stops. Only `--fresh` writes a new `start` and `deadline` (append a `fresh=<epoch>`
line first; never delete the old log).

## 3. First cycle — the risk study and the overlay

1. **Code-blind risk study.** If the driver's report does not exist, spawn a **fresh sub-agent
   that never sees `XXX/`** (give it the crate's name, its public documentation URL and its role,
   never a path into the source) to write it with the driver's skill. It must pass the driver's
   linter (`bin/rmf-lint.sh XXX-analysis-rmf-report.md`). Only then may anything read the code.
2. **Overlay.** If `creusot-launch` is installed (`config/skills/creusot-launch/`), run it on `XXX`.
   Otherwise create `XXX-creusot/` as a Cargo workspace of its own whose members depend on
   `creusot-std` (`config/skills/creusot/references/install.md`), and check the toolchain once
   (`cargo creusot version`, `cargo creusot config`). Each member models one area: the crate's
   functions transcribed verbatim (or as close as Creusot allows; every deviation goes in
   `trusted-base.md`), with their contracts.
3. **Baseline build in a copy:** `cp -a XXX /tmp/XXX-build && cargo build` there. Record whether
   the crate builds as shipped (a missing system library is an apt package for
   `.workshop/autowp-packages/hooks/setup-base`; with sudo in the container, install it and record
   it in the report).
4. **Schedule:** the `creusot-monitoring` Phase-0 audit ranks the files by exposure to untrusted
   input, refined by the risk study's levels, leaf files first within a level.

## 4. The cycle (resumable, idempotent, deadline-aware)

Each wake, in this order:

0. **Reconcile.** Append `wake=<epoch>`. If `now > deadline` → step 6. Check the heartbeat is live
   (§7) and re-arm it if not. `cargo creusot` on the overlay must still print `Proved` for every
   item the ledger calls VERIFIED; a regression is the first thread of this cycle.
1. **Triage (Gate A).** Classify every open item:
   - **Class A — a Creusot / Why3 / solver limit** on an expressible goal (an unsupported feature:
     `fn` pointers, some closures, trait objects; solver incompleteness). **Skip**, unless the
     toolchain improved since it was tried. A class-A claim needs: the failing goal named (not
     "timeout"), a minimal reproduction that still fails, and a disjoint check (another solver, a
     split goal, a manual Why3 session). Without them it is **class C**. A genuine Creusot bug
     with a reproducer goes to `config/skills/creusot/bugs-to-report/`.
   - **Class B — crypto, entropy, side channels, supply chain.** Residual by design. **Skip.**
   - **OUT OF REACH — system state.** FFI, `unsafe` over raw memory, PAM, `exec`, terminals,
     signals, file-system races, the libc. **Recorded, never modelled with trusted axioms.** Its
     *pure* parts are not out of reach: an index computation, a parser of a `/proc` line, a
     permission predicate are extracted and proved (they are class C).
   - **Class C — unfinished contract work:** a missing `#[requires]`, a loop `#[invariant]` or
     `#[variant]`, a callee `#[ensures]`, a model of a std type. **The only class budget is spent
     on.**
   - **Value order, all by default within the budget — never stop to ask between tiers:**
     1. finding-bearing class C, by risk rank on the untrusted-input surface;
     2. absence of panics, overflows and out-of-bounds accesses on every remaining in-scope
        function;
     3. stronger, functional properties (the reference model, if the crate ships one) on the
        items already proved;
     4. reducing the trusted base: every REDUCIBLE entry of `trusted-base.md` proved away.
2. **Drive one thread per verifier, as a sub-agent.** The coordinator **never verifies inline**:
   writing a model, running `cargo creusot` or a reproduction is done only inside a spawned
   sub-agent (`creusot-monitoring` / `creusot-sl` for that file), and the coordinator records only
   its delivered report, never a mid-run artifact.
   - **TIME BOX — 45 minutes of wall clock per verifier** (state it in its prompt). At the box it
     stops and delivers: each finished item with its verdict, each unfinished one as `RESIDUE(C)`
     with its last `valid/total` goal count, the obstacle and the next lever. Re-queue the open
     part as a narrower thread. A verifier still running 15 minutes past its box is stopped
     (`TaskStop`) and its thread re-spawned narrower.
   - **PARALLEL** — never wait on one verifier while a disjoint file is nameable; at most
     `nproc / 2` verifiers at once (overloaded solvers time out: flaky verdicts, not residue).
   - **BUILD IN A COPY** (§1) is in every verifier's prompt.
   - **A finding needs two witnesses:** an expected-failing model in `XXX-creusot/failing/<name>/`
     (the faithful model has exactly the unproved goal; the minimal fix makes it prove) **and**,
     wherever the code can run, a reproduction on the unmodified code (built in a copy, or the
     verbatim function in a small `main.rs`). A finding seen only by reading is labelled so.
3. **Monitor (`sl-monitoring-sl`).** Judge the delivered verdicts against U and L only:
   **PASS** (proved with no unlisted trusted item; a finding with its witnesses) · **CARVE-OUT** (a
   claim wider than its proof → narrow it) · **REJECT** (an unlisted `#[trusted]`/`assume`, a model
   that does not match the source, a class-A label without its evidence, a build inside `XXX/`) →
   discard and re-plan.
4. **Record.** Append to `verdicts.tsv` and, for a new finding, to `XXX-analysis-found-issues.md`
   (`## FI-<n>: <title>` — the trigger, the effect, the witnesses, the fix). Emit the next feedback
   file on a verdict delta only (scenario-keyed, no proof internals, so a re-run of the risk study
   stays code-blind).
5. **Checkpoint.** Rewrite `XXX.md` from the ledger (§6). **Gate ND:** the cumulative artifacts
   (`verdicts.tsv`, the finding ledger, `time-loop.state`, `trusted-base.md`) only grow — append or
   edit, never re-`Write` an existing one; `git diff --stat` must be net-additive. Then **commit and
   push**: invoking `/time-loop` is the user's standing request to commit and push to `origin` at
   every cycle boundary — do it without asking (rebase before push; never stage `target/` or solver
   caches; `XXX/` is a separate repository and is never staged). Append the `cycle <n>: ` line.
   Arm the next wake as the **last** action (§7).
6. **Terminus or pause.** If every in-scope function is PROVEN, a VIOLATION reported or a Creusot
   bug filed, every OUT OF REACH item is recorded with its reason, and Gate T passes (§6), write
   the final report and stop the heartbeat. Otherwise, at the deadline, this is a **pause**: write
   the interim report and stop the heartbeat; a later `/time-loop XXX N` resumes from the
   checkpoint. **Never** "converged, the next budget should target …": if you can name the next
   target, drive it.

**No no-op cycle.** While the deadline is ahead, a cycle that finds nothing new on the current
thread is not a pause: it must start the first of these that applies, in order —
1. an unproved function in an in-scope file;
2. a **mutation check** for a proof that lacks one (break the code or drop a `#[requires]`, and the
   proof must fail — otherwise the contract is vacuous);
3. a finding not yet witnessed by a failing model in `XXX-creusot/failing/` or by a reproduction;
4. the next file by exposure, including the pure-logic parts of files first classed OUT OF REACH;
5. a stronger, functional property for an item already proved;
6. a REDUCIBLE entry of `trusted-base.md`.
Logging "nothing new" and re-arming is a loop-behaviour bug.

## 5. Oracles and the ledger

- **Proof:** `cargo creusot` in `XXX-creusot/` (`cargo creusot prove` for one member); `--no-cache`
  for the final re-check before the terminus.
- **Faithfulness:** each transcribed function names its source span (`file:line` and the crate's
  commit) in a comment; a model's code, with the Creusot attributes and ghost code removed, must
  match the source span up to the deviations listed in `trusted-base.md`. Until `creusot-launch`
  supplies a mechanical strip-and-diff script, the check is a sub-agent's side-by-side reading,
  recorded as such.
- **Reproduction:** the unmodified crate built in a copy, or the verbatim function in
  `XXX-creusot/failing/<name>/repro/main.rs`.
- **`verdicts.tsv` schema (pinned; tests read it by column name):** tab-separated, first line the
  header `unit	SA#	function	verdict	goals	notes`, one row per function (or per model item).
  `unit` is the overlay member and file; `verdict` is one of `VERIFIED` (every goal proved),
  `PARSE-BLOCKED` (Creusot cannot translate it), `RESIDUE(A)`, `RESIDUE(B)`, `RESIDUE(C)`;
  OUT OF REACH items are `RESIDUE(A)` with `out-of-reach:` at the start of `notes`; `goals` is
  `<valid>/<total>`, or empty when nothing ran; `SA#` names the risk study's assets the row
  covers, or `-`. Never rename a column or add a status word; put everything else in `notes`.

## 6. Report and done criteria

`XXX.md`, in the project root next to `XXX/`, is rewritten at the end of every cycle so it is
complete at any moment (`/time-loop sudo-rs 96` → `sudo-rs.md`); git history keeps the earlier
versions. Its counts come from `verdicts.tsv` and the finding ledger, never from memory. Under the
`fips` driver, each rewrite also regenerates the compliance dossier `XXX-fips-compliance/` in full
(`fips-sl` §10). Sections:
1. summary (deadline, status: final or interim, the numbers);
2. method and toolchain versions;
3. proved, by item, with what each proof assumes;
4. the trusted base and the abstractions;
5. findings, each with trigger, effect, witnesses (failing model, reproduction, or "by reading")
   and fix;
6. out of reach, with reasons;
7. control-effectiveness evidence: risk item → proofs and findings → verdict;
8. architecture findings;
9. tooling gaps and Creusot bugs (`getting-better/`, `bugs-to-report/`);
10. pending human items (the Authorize step, the review of learned skills);
11. coverage and what is left, in value order.

**Gate T (before the final report; all must hold, logged in `time-loop.state`):** every in-scope
file enumerated and each function in one of the terminal statuses; no `RESIDUE(C)` row; no
REDUCIBLE trusted-base entry; every proof re-checked with `--no-cache`; every finding with its
witnesses; `git -C XXX status --short` empty; the report regenerated from the ledger. Any
failure is the next thread, not a stop.

## 7. Primitives on each harness

This mapping overrides Claude-specific tool names and delegation requirements elsewhere
in this skill. The risk study must still be code-blind under every harness.

The loop keeps itself alive; it never waits for a human to re-invoke it. Arm the next wake as the
cycle's **last** action (on Claude Code `ScheduleWakeup` ends the turn, so arming first would
yield before any work), keep an idle watchdog live, check both at the start of every cycle, and
stop by not re-arming.

- **Claude Code:**
  ```
  ScheduleWakeup({
    delaySeconds: 120,
    prompt: "/time-loop XXX N",          // the same invocation verbatim
    reason: "time-loop heartbeat: next cycle of the XXX Creusot campaign"
  })
  ```
  plus, on activation, a `CronCreate` restart-after-idle watchdog on an off-minute recurrence
  (e.g. `6,16,26,36,46,56 * * * *`, prompt `/time-loop XXX N`); check it with `CronList` at the
  start of every cycle and re-arm it if absent (cron jobs are session-only and expire after 7
  days). At the terminus or the deadline: `ScheduleWakeup({ stop: true })` and `CronDelete`.
  Spawn with `Agent`/`Task`, read its delivered report, and stop background work with
  `TaskStop`. Entry point: `/time-loop XXX N`.
- **OpenCode:** no in-session wakeup; the loop is resumable from `time-loop.state`, so the
  heartbeat is an external watchdog owned by the skill, in tests and manual sessions alike:
  ```bash
  opencode service set disabled true
  python3 bin/time-loop-watchdog.py start XXX-creusot/time-loop.state DEADLINE_EPOCH \
      "Load the time-loop skill and run its next cycle for XXX (budget N hours) from XXX-creusot/time-loop.state"
  ```
  The private server inherits the launcher's provider key. At the terminus or deadline create
  `.time-loop-watchdog.stop`; externally, `python3 bin/time-loop-watchdog.py stop` stops the
  recorded process group including an active wake. `status` checks the pidfile with process-start
  identity. `start` locks it against duplicate watchdogs and removes the stop flag only for an
  unexpired deadline. Check state-file freshness too; re-arm only if dead.
  Entry point: `/time-loop XXX N`. Until verifier spawn/report read-back is verified, **run
  the verifier inline**, a known weakening of the delegation barrier. If no fresh isolated
  study actor can be created, require an independently prepared code-blind risk report before
  reading source. Stop tool processes by recorded PID, never by name.
- **Copilot:** not enabled; the spike in the generator's `spec/choose-harness.md` must
  settle entry point, heartbeat and delegation first. Do not assume Claude primitives exist.

## Pairs with

`config/commands/time-loop.md` (the `/time-loop XXX N` entry point), `creusot-monitoring` (the base
loop), `creusot-sl` (one file), `creusot` (Pearlite), `creusot-launch` (onboarding, when installed),
`rmf-sl` / `fips-sl` (the code-blind risk study), `sl-monitoring-sl` (the pattern this instantiates).
