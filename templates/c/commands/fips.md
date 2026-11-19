---
description: Run the FIPS-SL (code-blind) -> frama-c-launch/monitoring verification campaign on a directory
argument-hint: <source-dir> [artifact-prefix]
---

Run the two-phase FIPS 140-3 + Frama-C campaign on the target directory.

**Resolve these placeholders first** by parsing the raw arguments `$ARGUMENTS` (one or two whitespace-separated tokens), then execute the two phases below:
- `DIR` = the **first** token of `$ARGUMENTS` — the source directory under analysis (may be nested, e.g. `zephyr/kernel`). If `$ARGUMENTS` is empty, stop and ask which directory.
- `PREFIX` = the **second** token if present, else a short **root-safe slug** of `DIR` (replace `/` with `-`; e.g. `zephyr/kernel` -> `zephyr-kernel`). So `/fips zephyr/kernel zk37` => DIR=`zephyr/kernel`, PREFIX=`zk37`.
- **Before launching, verify `DIR/` exists** (`ls -d DIR`); if not, stop and report rather than proceeding on a mis-parsed path.
- **The target level.** Read `fips_level` from `config/auto-wp.json` (the manifest is the single
  place the level is stored). If the key is missing (a hand-edited manifest), **stop with a
  message**: the study needs a target FIPS 140-3 security level (Ann. 7 — the level is chosen,
  never defaulted). Regenerate the project with `--driver fips --level N` or add the key by hand.
- **ALL generated artifacts use `PREFIX` and live at the repository root** (never inside `DIR` — it is vendored source that must stay pristine for the faithfulness baseline). Two kinds:
  - **Consolidated (single file, updated in place each run):** `PREFIX-fips-report.md`, `PREFIX-found-issues.md`, `PREFIX-fips-gaps.md`, and the overlay `PREFIX-acsl/`. These hold *current truth*.
  - **The compliance dossier (regenerated in full at the end of every run):** `XXX-fips-compliance/`, where `XXX` is the root-safe slug of `DIR` (not `PREFIX`) — nine files, every finding included, per `fips-sl` §10 and `fips-sl/references/compliance-dossier.md`. Phase 2 writes it last, after the feedback packet; it is code-aware, so the Phase-1 `fips-sl` agent never reads it.
  - **Numbered (one per cycle, never overwritten):** the feedback packet `PREFIX-fips-feedback-NN.md` (zero-padded, e.g. `-01`, `-02`) — the verification evidence the residual-risk owner (Ann. 13) adjudicates. Each run emits the **next** index so the sequence is the revalidation history.
  - Substitute `DIR` for `XXX/` and `PREFIX` for the `XXX-` artifact names in the prompt below.

**Flag parsing.** Treat any `--`-prefixed token in `$ARGUMENTS` as a non-positional flag and strip
it out BEFORE computing `DIR`/`PREFIX` from the positional tokens. Recognized: `--fresh`/`--force`,
`--monitor-only`/`--quick`, `--no-coq` (Phase-0 run modes, below), `--linux`/`--full-tu` (next), and
`--machdep=<name>` (a value-bearing flag — everything after `=` is the value, not a positional).

**Machdep override (`--machdep=<name>`).** When present, **pin Frama-C's `-machdep` to `<name>` for the
whole campaign**, overriding the value the Phase-2 `frama-c-launch` prober would otherwise derive from the
real build. Forward it to `frama-c-launch` (its §8b onboarding profile / preprocess-context step), which
records it as the **pinned** machdep in the onboarding package and the generated `verify.sh`; the real
build (the `-I`/`-D`/force-includes + build-generated headers) is still required and unchanged — only the
width/alignment model is pinned. `<name>` must be one Frama-C accepts (`frama-c -machdep help`). For
cross/embedded targets with no exact Frama-C machdep, use the ABI proxy: **`gcc_x86_32` for 32-bit ARM**
(Cortex-M/Zephyr `mps2_an385`), **`macos_arm` for AArch64**. With no flag, the prober derives it as today
(default `gcc_x86_64`).

**Linux-kernel onboarding profile (`--linux` / `--full-tu`).** If `$ARGUMENTS` contains `--linux`
(optionally also `--full-tu`), this is the Linux-kernel profile of `linux-analysis.md` (repo root).
Parse the two positionals as **`<kernel-src-subdir> <analysis-dir>`** (NOT `DIR`/`PREFIX`):
- `KSRC` = first positional (e.g. `linux/linux-7.1.1/security`); `ADIR` = second positional (e.g.
  `linux/linux-sec-analysis`) — the analysis dir where onboarding writes its config. Verify `KSRC/`
  exists; if `ADIR` is omitted, derive it as a root-safe slug (`linux/linux-7.1.1/security` ->
  `linux-7.1.1-security-analysis`).
- **Registration replaces the generic Phase-2 overlay derivation:** run
  `linux/linux-acsl/onboard-linux.sh "$ADIR" [--full-tu] --kernel-src "$KSRC"` (idempotent). It emits
  `linux-acsl.env` + `verify.sh` + `setup.log`, registering the `linux/linux-acsl/` modeled-runtime
  overlay, the WP cbits patch, and (under `--full-tu`) the **patched verifier binary** + real-TU
  recipe. Phase 2 then verifies through that generated **`$ADIR/verify.sh`** instead of building
  `DIR` + creating `PREFIX-acsl/`; per-unit verdicts go to `$ADIR/verdicts.tsv` (VERIFIED /
  PARSE-BLOCKED with `<file:line>`, never a silent skip). Forward onboarding profile `linux` to
  `frama-c-launch` (its §8b).
- **Phase 1 (code-blind FIPS study) is UNCHANGED** — `--linux` does NOT feed source to the study
  (the F1–F4 exogeneity barrier holds). At most it notes the module's operating environment in F1
  (kernel attack surface: syscalls, `copy_*_user`, capability checks) — derivable without reading
  the implementation.
- Without `--linux`, keep the existing `DIR`/`PREFIX` behavior below.

---

PHASE 0 — RECONCILE WITH EXISTING ARTIFACTS (stateful; do this before launching anything).
The campaign is **resumable and idempotent** — reuse completed/converged work, never clobber a
committed/hand-authored artifact, but **CONVERGE BY DEFAULT**: any in-scope unit/obligation that is
not yet spec-converged is *the loop's unfinished work*, not "done", and **must be driven to
convergence before reporting** (the `frama-c-monitoring` KEY PRINCIPLE — drive `framac-sl` where
needed). First inspect what exists for `PREFIX` and decide the minimum work:
 - **Run-mode flags (parse from `$ARGUMENTS`):**
    - `--fresh` / `--force` -> skip reconcile, run the full pipeline from scratch (still number the
      feedback packet; never delete prior numbered feedback files).
    - `--monitor-only` / `--quick` -> **opt OUT of convergence**: reuse all consolidated artifacts as-is,
      do **no** new verification, and just (re-)emit the next-numbered feedback packet from the *existing*
      verdicts. This is the only mode allowed to emit a flat / no-delta cycle.
    - `--no-coq` -> **opt OUT of the Coq-discharge stage only**: still converge by spec-authoring, but
      do not escalate probe-confirmed true-but-hard goals to interactive Coq (leave them as
      `COQ-NEEDED` residue). Use for a faster spec-only pass.
    - *(default, no flag)* -> **converge AND discharge with Coq**: reuse what's converged, finish what
      isn't by spec-authoring, then escalate the probe-confirmed true-but-hard residue to Coq (below).
  - `PREFIX-fips-report.md` exists and passes `bin/fips-lint.sh` (exit 0) -> **reuse it; skip Phase 1.**
    If it is missing or lint-dirty -> run Phase 1.
  - `PREFIX-acsl/` overlay + its verdicts/patches exist -> **reuse them; do NOT re-verify converged
    units from scratch — but "exists" != "converged".** Identify every **not-yet-converged (AMBER)**
    unit/obligation from `PREFIX-found-issues.md` / `PREFIX-fips-gaps.md` (undischarged non-refuted
    Timeouts) and, by default, **continue Phase 2 on exactly those** until they converge or hit a
    genuine probe-confirmed residue; UPDATE the consolidated `PREFIX-found-issues.md` /
    `PREFIX-fips-gaps.md` in place. Never silently overwrite the overlay or its patches (full redo ->
    `--fresh`). *(Skip this continuation only under `--monitor-only`.)*
  - A real build dir (`build_<prefix>/` or the recorded one) with `compile_commands.json` exists ->
    reuse it; rebuild only if the config/profile changed.
  - **Feedback-packet numbering:** `ls PREFIX-fips-feedback-*.md`, take the highest index `NN`, write
    `PREFIX-fips-feedback-<NN+1>.md` (start `-01` if none); **never overwrite a prior numbered
    feedback file.** Emit a new numbered packet **only when this run produced a verdict delta**
    (convergence happened) **or** the campaign is now fully converged **or** `--monitor-only` was given.
    **Do NOT emit a flat no-delta cycle by default** — if the default (converge) run found nothing left
    to converge and no delta, say so and emit nothing new (the latest existing packet already reflects
    current truth).
  - Report the reconcile decision up front: per artifact `reuse | continue-converge | (re)generate`,
    the list of AMBER units to be converged this run, and the chosen next feedback index (or "none — no
    delta"). Under `--monitor-only`, the whole run reduces to emitting the next-numbered packet from
    existing verdicts.

PHASE 1 — FIPS 140-3 REQUIREMENT STUDY, CODE-BLIND (separate agent; this barrier is load-bearing).
Spawn an agent to run the `fips-sl` loop on `DIR/` and generate `PREFIX-fips-report.md`
(F1-F5; the F5 sign-off left PENDING — the owner of the protected information, or the agency's
responsible authority, signs per Ann. 13). It MUST NOT read any implementation source
under `DIR/` (the FIPS 140-3 corpus in `specs/`, the module's public description and the manifest's
target level only) — that exogeneity is what makes the study a valid bound. F2 MUST cover all eleven
requirement areas (`AR1`-`AR11`, each with requirement items or an `N/A` line with a reason), every
`RQ#` carrying at least one honest `src:<DOC>:<LOC>` token (or `src:UNSOURCED` alone). It must pass `bin/fips-lint.sh` (exit 0, endogeneity
tripwire clear, all-area coverage satisfied).

PHASE 2 — VERIFICATION, CODE-AWARE (a SEPARATE agent consuming PREFIX-fips-report.md).
Run the `frama-c-launch` loop and its downstream `frama-c-monitoring`. Run unsupervised
to completion — do not stop for my approval; record any choice as ASSUMPTION: and only
halt on a hard blocker. The loop must:
  - ACTUALLY BUILD DIR for the shipped/default profile (configure/CMake/make/west build)
    and record the config; the preprocess flags + generated headers MUST come from that
    real build's compile_commands.json — do not hand-synthesize flags. If it genuinely
    cannot be built in this environment, that is a hard blocker to report, NOT a BLOCKED
    unit (un-built != BLOCKED, no leaf-driver fallback);
  - create an overlay in PREFIX-acsl/ annotating the *.c units, keeping DIR PRISTINE
    (reversible patches in PREFIX-acsl/patches/; pin the faithfulness baseline — git HEAD per
    repo + each submodule, or a sha256 manifest if the tree is untracked);
  - prove RTE- and functional-level absence of defect on the priority-ranked Tier-1/Tier-2
    queue (ranked by the study's `VO#` priorities P1-P3 via templates/fips-crosswalk.md). A Timeout is the
    loop's UNFINISHED WORK, not a verdict: re-invoke `framac-sl` to author the missing contracts
    (requires \valid / terminates / loop variants / callee-ensures propagation / invented cross-callee
    system invariants) until WP converges. Before tagging ANY goal residual/COQ-NEEDED, run the
    refutation probe — add the antecedent the goal points at and re-run; instant Valid => spec gap,
    keep going. **Then, by default, DISCHARGE the probe-confirmed true-but-hard goals with Coq (do not
    merely classify them):** escalate each to the `framac-coq8` toolchain
    (`-wp-prover ...,coq -wp-interactive`), accept a Coq close ONLY under the soundness audit
    (cache-clean replay with `-wp-cache none`, `Print Assumptions` subset of the standard set, **zero
    admits**) — a Coq-closed goal is a verdict delta. Interactive Coq is not guaranteed to auto-close
    every goal; what even Coq cannot close stays residue, now tagged **Coq-attempted**. (Skip this Coq
    stage under `--no-coq`, leaving them `COQ-NEEDED`.) Write real bugs + the residue that survives
    *both* the probe *and* the Coq stage (Coq-attempted, unmodelled construct, or a tooling defect) to
    PREFIX-found-issues.md. **If you fan out units in
    parallel, each sub-agent MUST run in its own worktree (`isolation: 'worktree'`), never a shared
    checkout — concurrent patch apply/revert on one tree corrupts peers (frama-c-monitoring §5.4);
    harvest each unit's reversible patch back to PREFIX-acsl/patches/ afterward;**
  - add HAPPY (MAcsl) keywords for the system-level obligations (the six classes of
    `fips-sl/references/area-properties.md`: `output-inhibit`, `role-gate`, `integrity-first`,
    `selftest-order`, `error-state`, `fsm`) and write the coverage gaps vs PREFIX-fips-report.md to
    PREFIX-fips-gaps.md;
  - for residuals (crypto strength, side channels, physical, supply chain, validation — the standing
    planes) record residual risk (RR#) rather than stopping; leave the F5 sign-off PENDING (the owner
    of the protected information signs — I am not the terminus);
  - **if this run produced a verdict delta** (convergence happened) **or** the campaign is now fully
    converged **or** `--monitor-only` was given, generate the next-numbered PREFIX-fips-feedback-NN.md
    (Phase 0 picked NN) — otherwise emit nothing new and say "no delta" (no flat cycles): the
    requirement-evidence packet (per
    frama-c-launch/references/fips-feedback.md, the forward + return halves) — verdicts ->
    *proposed* requirement evidence keyed to the study's obligation IDs (VO#) and requirements (RQ#).
    Its content must be requirement-keyed evidence signals ONLY — no
    implementation detail or proof internals — so a future code-blind `fips-sl` re-run can consume it
    without becoming endogenous. A `PROVED` `VO#` is evidence for its `RQ#`, never a CMVP validation.
    The residual-risk owner adjudicates it (the human terminus — the Ann. 13 acknowledgment).
