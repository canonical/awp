---
description: Run the time-loop META squeeze — drive /rmf XXX XXX-analysis to maximize high-value verified coverage within an N-hour budget
argument-hint: <source-dir> <hours> [--dir=<subdir>] [--machdep=<name>] [--linux] [--full-tu] [--fresh] [--no-coq]
---

Run the **`time-loop`** meta squeeze loop: an `N`-hour, budget-disciplined campaign that drives the
existing `/rmf` loop to **maximize high-value verified coverage** of a target — not raw PROVED-cell
count. **Invoke the `time-loop` skill** (it holds the full design — residue triage, bounds, gates,
the deadline loop) and run it per that skill.

**The campaign driver.** Which base loop `/rmf` names depends on the project: the `driver` key of
`config/auto-wp.json` (what `auto-wp.py --driver` records) selects it, and every RMF-specific name
below is read through this table. Without a `driver` key, assume `rmf`.

| | `rmf` | `fips` |
|---|---|---|
| base command | `/rmf` | `/fips` |
| report | `XXX-analysis-rmf-report.md` | `XXX-analysis-fips-report.md` |
| gaps | `XXX-analysis-rmf-gaps.md` | `XXX-analysis-fips-gaps.md` |
| feedback | `XXX-analysis-monitor-feedback-NN.md` | `XXX-analysis-fips-feedback-NN.md` |
| linter | `bin/rmf-lint.sh` | `bin/fips-lint.sh` |
| ranked item and scale | `RS#`, risk `High`/`Moderate`/`Low` | `VO#`, priority `P1`/`P2`/`P3` |
| Plane W (WP) | Tier-1 untrusted-input `RS#` | `VO#` of class `zeroize`, `no-plain-ssp-out` |
| Plane H (macsl system properties) | Tier-3 authorization/integrity `RS#` | `VO#` of the six system-level classes of `fips-sl/references/area-properties.md` |
| outside both planes | — | `approved-only` (a call-graph check, not a WP proof) |
| terminus | Authorizing Official | the owner of the protected information, or the agency's responsible authority (Ann. 13) |

**Parse `$ARGUMENTS` (strip flags first):**
- Treat any `--`-prefixed token as a non-positional **flag**; strip them out BEFORE computing the
  positionals. Recognized flags are **forwarded verbatim to the underlying `/rmf`**: `--machdep=<name>`,
  `--linux`, `--full-tu`, `--fresh`/`--force`, `--no-coq`. (`--linux`/`--full-tu` select the Linux-kernel
  onboarding profile of `/rmf`; `--fresh` and `--no-coq` are `/rmf` run-modes.) **`--dir=<subdir>` is the
  one exception — it is a time-loop-level SCOPE FILTER, NOT forwarded to `/rmf`** (see its bullet below).
- **`--machdep=<name>`** (value-bearing, e.g. `--machdep=gcc_x86_32`) **pins Frama-C's `-machdep`** for
  the whole campaign, overriding the value `frama-c-launch`'s prober would otherwise derive from the real
  build. Use it when the target's architecture differs from the x86_64 default — most often a **cross /
  embedded** target. Frama-C 32.1 has **no 32-bit bare-metal ARM machdep**; the ABI-faithful proxies are
  **`gcc_x86_32` for 32-bit ARM** (Cortex-M / Zephyr on `mps2_an385`: ILP32, same 4/4/4 int/long/ptr,
  little-endian) and **`macos_arm` for AArch64** (LP64). The name must be one Frama-C accepts
  (`frama-c -machdep help`): `avr_16 avr_8 gcc_x86_16 gcc_x86_32 gcc_x86_64 macos_arm msvc_x86_64 ppc_32
  x86_16 x86_32 x86_64`. It does **not** replace the real build — the `-I`/`-D`/force-includes still come
  from the target's actual compilation; `--machdep` only pins the width/alignment model WP reasons under.
- **`--dir=<subdir>`** (value-bearing) **scopes an EXISTING campaign to a subdirectory** of `XXX`'s
  source — NOT a fresh campaign. `XXX` still names the existing campaign (its `XXX-analysis-rmf-report.md`,
  onboarding, build, and harness are **reused, not re-bootstrapped**); `--dir` only **narrows the
  time-loop's own working set** to the in-scope C under the **source-root-relative** path `XXX/<subdir>`.
  Concretely the loop restricts, to that subtree: the Phase-0 reconcile, the residue **triage**, the
  **coverage/enumeration ledger**, and the **terminus enumeration cross-check** (`{in-scope C functions
  under <subdir>} ∖ {covered} == ∅`). Use it to focus a campaign on one attack surface — most usefully a
  subsystem the code-blind RMF report named only **generically by role** (so the specific files were never
  enumerated). A C file under `<subdir>` that the report never named is therefore **an in-scope class-C
  scope-gap to DRIVE** (Plane-W memory-safety + any Plane-H gate found by the privilege-op enumeration),
  not out-of-scope. **Verify the resolved dir exists** (`ls -d XXX/<subdir>`, or the campaign's real source
  root + `<subdir>`) before launching; if absent, stop and report. The scope is persisted in
  `time-loop.state` so re-invocations stay focused. It is **NOT** forwarded to `/rmf` (onboarding still
  covers the whole build; the filter acts on which units the loop's cycles target).
- `XXX` = the **first** positional token — **the exact name of an existing source directory at repo
  root** (or, under `--linux`, the kernel source subdir, e.g. `linux/linux-7.1.1/security/apparmor`).
  **Before launching, verify it exists** (`ls -d XXX`); if not, **stop and report** rather than
  proceeding on a mis-parsed path. Use the directory name exactly (e.g. `openssl-3.5.5`, hyphen — not
  a normalized/underscored variant); the `/rmf` `DIR` must match the real directory.
- `N` = the **second** positional token — a **positive number of hours** (the wall-clock budget).
  If `$ARGUMENTS` lacks either positional, **stop and ask** for the missing one.
- The base campaign driven each cycle is `/rmf XXX XXX-analysis <forwarded-flags>` (its `PREFIX` =
  `XXX-analysis`, root-safe slug if `XXX` is nested). Under `--linux`, the two positionals are the
  kernel-src subdir + the analysis dir, per `/rmf`'s `--linux` profile (and `meta-penguin` is the
  worked instance) — forward them through unchanged.

**Examples:**
- `/time-loop openssl-3.5.5 6` ⇒ `time-loop` with `XXX=openssl-3.5.5`, `N=6` → drives
  `/rmf openssl-3.5.5 openssl-analysis` continue-converge cycles for 6 hours.
- `/time-loop BearSSL 2 --fresh` ⇒ `XXX=BearSSL`, `N=2`, forwarding `--fresh` to `/rmf`.
- `/time-loop linux/linux-7.1.1/kernel/bpf 6 --linux --full-tu` ⇒ the Linux profile (cf. `meta-penguin`).
- `/time-loop zephyr 8 --machdep=gcc_x86_32` ⇒ `XXX=zephyr`, `N=8`, pinning the 32-bit-ARM ABI proxy for
  a Cortex-M Zephyr build (forwarded to `/rmf` → `frama-c-launch`).
- `/time-loop zephyr 3 --dir=subsys/dfu/boot --machdep=gcc_x86_32` ⇒ the **existing** `zephyr` campaign,
  3-hour budget, but the loop **focuses only on `zephyr/subsys/dfu/boot/`** (e.g. the MCUboot DFU shim
  `mcuboot.c` — an RS7-class flash-parse the code-blind report named only generically). Reuses the zephyr
  onboarding/build/harness; the `--machdep` still pins the Cortex-M ABI.

**What the run does (per the `time-loop` skill — do not re-derive it here):**
- `deadline = start + N hours`, state in `XXX-analysis-acsl/time-loop.state`. **A re-run keeps the
  original deadline:** the first invocation fixes start and deadline; a later `/time-loop XXX N` on the
  same campaign (after a stop, a crash or a reboot) reuses the stored start and deadline and ignores its
  `N`; if the stored deadline has already passed, it emits the report straight away and stops. A new
  budget needs `--fresh`, which starts a new campaign. Resumable, idempotent, deadline-aware; scheduled via the harness heartbeat (Claude Code: `/loop` / `ScheduleWakeup`; OpenCode: the external `opencode run` watchdog — the time-loop skill, "The heartbeat on each harness") (per-cycle checkpoint + ~20-min watchdog),
  reserving the last ~15–20 min for the terminus report.
- **Each cycle:** TRIAGE the residue ledger into class **A** (tool / `U`-ceiling — SKIP, retry only if
  the toolchain was enriched), class **B** (BLOCKED crypto/entropy — SKIP), class **C**
  (unfinished-contract — a refutation probe flips it — the ONLY class spent on); pick the highest-value
  class-C thread by RMF risk on the untrusted-input attack surface; drive ONE targeted `/rmf`
  continue-converge cycle **as a sub-agent**; monitor its claims (PASS/CARVE-OUT/REJECT) against U/L;
  emit the next `XXX-analysis-monitor-feedback-NN.md` on a verdict delta; **commit + push a
  crash-safe checkpoint**.
- **Stop** only on: the true terminus (every in-scope goal PROVEN, VIOLATION reported, or BUG IN
  FRAMA-C filed, and Gate T passes) — emit the final report to `XXX.md`; or the deadline / budget
  exhausted — a **pause**, not a finish: emit the interim report to `XXX.md` and resume from the
  checkpoint on the next invocation. Running out of class-C work is not a stop: drive the remaining
  class-A goals to PROVEN or to a filed Frama-C bug. **Never** burn remaining hours re-grinding the same
  class A/B items without a new lever. The report (triage verdict, units WITNESSED, attack-surface
  coverage gained, residue ledger by class) goes to `XXX.md` in the project root, next to `XXX/` (root-safe
  slug when `XXX` is a path: `zephyr/kernel` → `zephyr-kernel.md`), never inside the source tree; each new
  report replaces the previous one.
- **Inherited invariants:** pure WP, **NO EVA** (TCB-minimization); admit-free audited Coq; `XXX/`
  kept pristine (faithfulness baseline); honest residuals; **R5/Authorize PENDING — the human AO
  signs, the loop never does.**

Activating an N-hour autonomous campaign is a deliberate, resource-significant step: confirm `XXX`
exists and `N` is set, then arrange the schedule and run the `time-loop` skill's cycle.
