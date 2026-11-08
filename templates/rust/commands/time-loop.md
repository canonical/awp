---
description: Run the Rust time-loop — an N-hour Creusot campaign on a crate, driving creusot-monitoring to maximize high-value proved coverage
argument-hint: <crate-dir> <hours> [--dir=<subdir>] [--fresh]
---

Run the **`time-loop`** campaign for Rust: an `N`-hour, deadline-driven campaign that drives
`creusot-monitoring` (and its `creusot-sl` sub-loops) on a crate to **maximize high-value proved
coverage** — the functions most exposed to untrusted input first, not the most functions. **Invoke
the `time-loop` skill** (it holds the full design — the cycle, the triage, the gates, the heartbeat)
and run it per that skill.

**The campaign driver.** The `driver` key of `config/auto-wp.json` (what `auto-wp.py --driver`
records) selects the code-blind risk study the campaign ranks by. Without a `driver` key, assume
`rmf`.

| | `rmf` | `fips` |
|---|---|---|
| risk study skill | `rmf-sl` | `fips-sl` |
| report | `XXX-analysis-rmf-report.md` | `XXX-analysis-fips-report.md` |
| feedback | `XXX-analysis-monitor-feedback-NN.md` | `XXX-analysis-fips-feedback-NN.md` |
| linter | `bin/rmf-lint.sh` | `bin/fips-lint.sh` |
| ranked item and scale | `RS#`, risk `High`/`Moderate`/`Low` | `VO#`, priority `P1`/`P2`/`P3` |

**Parse `$ARGUMENTS` (strip flags first):**
- Treat any `--`-prefixed token as a **flag** and strip it before computing the positionals.
  Recognized flags: `--dir=<subdir>` and `--fresh` (alias `--force`).
- `XXX` = the **first** positional token — **the exact name of an existing crate directory at the
  project root** (a directory with a `Cargo.toml`). **Verify it exists** (`ls -d XXX`,
  `test -f XXX/Cargo.toml`); if not, **stop and report** rather than proceeding on a mis-parsed path.
  A workspace root is accepted: its members are the crate set.
- `N` = the **second** positional token — a **positive number of hours** (the wall-clock budget).
  If `$ARGUMENTS` lacks either positional, **stop and ask** for the missing one.
- **`--dir=<subdir>`** scopes an existing campaign to the Rust files under `XXX/<subdir>` (for
  example `--dir=src/sudoers`): the triage, the ledger and the terminus check are computed over
  that subtree only; the overlay, the risk study and the state are reused. Verify
  `ls -d XXX/<subdir>` first; stop if absent. The scope is persisted in `time-loop.state`.
- **`--fresh`** starts a new campaign with a new budget: new start and deadline in
  `time-loop.state`. Committed artifacts are kept (git history), never deleted.

**Examples:**
- `/time-loop sudo-rs 96` ⇒ `XXX=sudo-rs`, `N=96`: the risk study, then 96 hours of Creusot
  cycles on `sudo-rs/`, the overlay in `sudo-rs-creusot/`, the report in `sudo-rs.md`.
- `/time-loop sudo-rs 6 --dir=src/sudoers` ⇒ the existing `sudo-rs` campaign, focused on the
  sudoers parser for 6 hours.
- `/time-loop mycrate 72 --fresh` ⇒ a new 72-hour campaign on `mycrate`.

**What the run does (per the `time-loop` skill — do not re-derive it here):**
- `deadline = start + N hours`, state in `XXX-creusot/time-loop.state`. **A re-run keeps the
  original deadline:** the first invocation fixes start and deadline; a later `/time-loop XXX N` on
  the same campaign (after a stop, a crash or a reboot) reuses the stored start and deadline and
  ignores its `N`; if the stored deadline has already passed, it emits the report straight away and
  stops. A new budget needs `--fresh`. Scheduled via the harness heartbeat (Claude Code:
  `ScheduleWakeup` + a `CronCreate` watchdog; OpenCode: the external `opencode run` watchdog — the
  time-loop skill, "The heartbeat on each harness").
- **First cycle:** a fresh sub-agent that never reads `XXX/` writes the code-blind risk study with
  the driver's skill, checked by the driver's linter; then the overlay `XXX-creusot/` is set up (with
  `creusot-launch` when it is installed, otherwise as a Cargo workspace of its own that depends on
  `creusot-std`, per `config/skills/creusot/references/install.md`).
- **Each cycle:** triage the open items into class **A** (a Creusot/Why3/solver limit — skip unless
  the toolchain improved), class **B** (crypto/entropy, residual by design — skip), **OUT OF REACH**
  (FFI and system state — recorded, never modelled with trusted axioms) and class **C** (a missing
  `#[requires]`, invariant, variant or callee contract — the only class budget is spent on); pick the
  highest-value thread by risk on the untrusted-input surface; drive it **as a sub-agent**
  (`creusot-monitoring` / `creusot-sl`, 45-minute time box); monitor its verdicts
  (PASS/CARVE-OUT/REJECT); record them in `XXX-creusot/verdicts.tsv`; rewrite `XXX.md`; **commit +
  push a checkpoint**. A cycle with nothing new is not allowed while the deadline is ahead: the
  skill gives the ordered list of what to start instead.
- **Stop** only on: the true terminus (every in-scope function PROVEN, VIOLATION reported, or BUG
  IN CREUSOT filed, and Gate T passes) — emit the final report to `XXX.md`; or the deadline / budget
  exhausted — a **pause**, not a finish: emit the interim report to `XXX.md` and resume from the
  checkpoint on the next invocation. **Never** burn remaining hours re-grinding the same class A/B
  items without a new lever. The report (what was proved, the findings with their reproductions,
  what is out of reach, the architecture findings) goes to `XXX.md` in the project root, next to
  `XXX/`, never inside the crate; each new report replaces the previous one.
- **Inherited invariants:** `XXX/` kept pristine — **never run `cargo` inside it** (it rewrites
  `Cargo.lock`); build a copy; no `#[trusted]` or `assume` outside the declared trusted-base
  ledger; honest residuals; **the Authorize step stays PENDING — a human signs, the loop never
  does.**

Activating an N-hour autonomous campaign is a deliberate, resource-significant step: confirm `XXX`
exists and `N` is set, then arrange the schedule and run the `time-loop` skill's cycle.
