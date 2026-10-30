---
description: Run the EBIOS-SL (code-blind) -> frama-c-launch/monitoring verification campaign on a directory
argument-hint: <source-dir> [artifact-prefix]
---

Run the two-phase EBIOS + Frama-C campaign on the target directory.

**Resolve these placeholders first** by parsing the raw arguments `$ARGUMENTS` (one or two whitespace-separated tokens), then execute the two phases below:
- `DIR` = the **first** token of `$ARGUMENTS` — the source directory under analysis (may be nested, e.g. `zephyr/kernel`). If `$ARGUMENTS` is empty, stop and ask which directory.
- `PREFIX` = the **second** token if present, else a short **root-safe slug** of `DIR` (replace `/` with `-`; e.g. `zephyr/kernel` -> `zephyr-kernel`). So `/ebios zephyr/kernel zk37` ⇒ DIR=`zephyr/kernel`, PREFIX=`zk37`.
- **Before launching, verify `DIR/` exists** (`ls -d DIR`); if not, stop and report rather than proceeding on a mis-parsed path.
- **ALL generated artifacts use `PREFIX` and live at the repository root** (never inside `DIR` — it is vendored source that must stay pristine for the faithfulness baseline). Two kinds:
  - **Consolidated (single file, updated in place each run):** `PREFIX-ebios-report.md`, `PREFIX-found-issues.md`, `PREFIX-ebios-gaps.md`, and the overlay `PREFIX-acsl/`. These hold *current truth*.
  - **Numbered (one per cycle, never overwritten):** the W5 feedback `PREFIX-W5-ebios-feedback-NN.md` (zero-padded, e.g. `-01`, `-02`). Each run emits the **next** index so the sequence is the continuous-improvement history the risk owner reviews.
  - Substitute `DIR` for `XXX/` and `PREFIX` for the `XXX-` artifact names in the prompt below.

**Flag parsing.** Treat any `--`-prefixed token in `$ARGUMENTS` as a non-positional flag and strip
it out BEFORE computing `DIR`/`PREFIX` from the positional tokens. Recognized: the Phase-0 run-mode
flags (below) and `--linux`/`--full-tu` (next).

**Linux-kernel onboarding profile (`--linux` / `--full-tu`).** If `$ARGUMENTS` contains `--linux`
(optionally also `--full-tu`), this is the Linux-kernel profile of `linux-analysis.md` (repo root).
Parse the two positionals as **`<kernel-src-subdir> <analysis-dir>`** (NOT `DIR`/`PREFIX`):
- `KSRC` = first positional (e.g. `linux/linux-7.1.1/security`); `ADIR` = second positional (e.g.
  `linux/linux-sec-analysis`) — the analysis dir where onboarding writes its config. Verify `KSRC/`
  exists; if `ADIR` is omitted, derive a root-safe slug.
- **Registration replaces the generic Phase-2 overlay derivation:** run
  `linux/linux-acsl/onboard-linux.sh "$ADIR" [--full-tu] --kernel-src "$KSRC"` (idempotent). It emits
  `linux-acsl.env` + `verify.sh` + `setup.log`, registering the `linux/linux-acsl/` modeled-runtime
  overlay, the WP cbits patch, and (under `--full-tu`) the **patched verifier binary** + real-TU
  recipe. Phase 2 verifies through that generated **`$ADIR/verify.sh`** instead of building `DIR` +
  creating `PREFIX-acsl/`; per-unit verdicts go to `$ADIR/verdicts.tsv` (VERIFIED / PARSE-BLOCKED
  with `<file:line>`, never a silent skip). Forward onboarding profile `linux` to `frama-c-launch`
  (its §8b). Provenance/soundness ledger is `$ADIR/setup.log`.
- **Phase 1 (code-blind EBIOS W1–W4) is UNCHANGED** — `--linux` does NOT feed source to the risk
  study (linux-analysis.md §2/§6); the W1–W3 exogeneity barrier holds. At most it sets
  `system-type = linux-kernel` in the threat model — derivable without reading the implementation.
- Without `--linux`, keep the existing `DIR`/`PREFIX` behavior below.

---

PHASE 0 — RECONCILE WITH EXISTING ARTIFACTS (stateful; do this before launching anything).
The campaign is **resumable and idempotent** — reuse completed/converged work, never clobber a
committed/hand-authored artifact, but **CONVERGE BY DEFAULT**: any in-scope unit/scenario that is not
yet spec-converged is *the loop's unfinished work*, not "done", and **must be driven to convergence
before reporting** (the `frama-c-monitoring` KEY PRINCIPLE — drive `framac-sl` where needed). First
inspect what exists for `PREFIX` and decide the minimum work:
 - **Run-mode flags (parse from `$ARGUMENTS`):**
   - `--fresh` / `--force` → skip reconcile, run the full pipeline from scratch (still number the W5;
     never delete prior numbered W5 files).
   - `--w5-only` / `--quick` → **opt OUT of convergence**: reuse all consolidated artifacts as-is, do
     **no** new verification, and just (re-)emit the next-numbered W5 from the *existing* verdicts.
     This is the only mode allowed to emit a flat / no-delta W5 cycle.
   - `--no-coq` → **opt OUT of the Coq-discharge stage only**: still converge by spec-authoring, but
     do not escalate probe-confirmed true-but-hard goals to interactive Coq (leave them as
     `COQ-NEEDED` residue). Use for a faster spec-only pass.
   - *(default, no flag)* → **converge AND discharge with Coq**: reuse what's converged, finish what
     isn't by spec-authoring, then escalate the probe-confirmed true-but-hard residue to Coq (below).
 - `PREFIX-ebios-report.md` exists and passes `bin/ebios-lint.sh` (exit 0) → **reuse it; skip Phase 1.**
   If it is missing or lint-dirty → run Phase 1.
 - `PREFIX-acsl/` overlay + its verdicts/patches exist → **reuse them; do NOT re-verify converged
   units from scratch — but "exists" ≠ "converged".** Identify every **not-yet-converged (AMBER)**
   unit/scenario from `PREFIX-found-issues.md` / `PREFIX-ebios-gaps.md` (undischarged non-refuted
   Timeouts) and, by default, **continue Phase 2 on exactly those** until they converge or hit a
   genuine probe-confirmed residue; UPDATE the consolidated `PREFIX-found-issues.md` /
   `PREFIX-ebios-gaps.md` in place. Never silently overwrite the overlay or its patches (full redo →
   `--fresh`). *(Skip this continuation only under `--w5-only`.)*
 - A real build dir (`build_<prefix>/` or the recorded one) with `compile_commands.json` exists →
   reuse it; rebuild only if the config/profile changed.
 - **W5 feedback numbering:** `ls PREFIX-W5-ebios-feedback-*.md`, take the highest index `NN`, write
   `PREFIX-W5-ebios-feedback-<NN+1>.md` (start `-01` if none); **never overwrite a prior numbered W5
   file.** Emit a new numbered W5 **only when this run produced a verdict delta** (convergence
   happened) **or** the campaign is now fully converged **or** `--w5-only` was given. **Do NOT emit a
   flat no-delta cycle by default** — if the default (converge) run found nothing left to converge and
   no delta, say so and emit nothing new (the latest existing W5 already reflects current truth).
 - Report the reconcile decision up front: per artifact `reuse | continue-converge | (re)generate`,
   the list of AMBER units to be converged this run, and the chosen next W5 index (or "none — no
   delta"). Under `--w5-only`, the whole run reduces to emitting the next-numbered W5 from existing
   verdicts.

PHASE 1 — EBIOS, CODE-BLIND (separate agent; this barrier is load-bearing).
Spawn an agent to run the `ebios-sl` loop on `DIR/` and generate `PREFIX-ebios-report.md`
(W1–W4; W5 left PENDING). It MUST NOT read any implementation source under `DIR/`
(mission/threat-model/public docs only) — that exogeneity is what makes the report a
valid bound. It must pass `bin/ebios-lint.sh` (exit 0, endogeneity tripwire clear).

PHASE 2 — VERIFICATION, CODE-AWARE (a SEPARATE agent consuming PREFIX-ebios-report.md).
Run the `frama-c-launch` loop and its downstream `frama-c-monitoring`. Run unsupervised
to completion — do not stop for my approval; record any choice as ASSUMPTION: and only
halt on a hard blocker. The loop must:
 - ACTUALLY BUILD DIR for the shipped/default profile (configure/CMake/make/west build)
   and record the config; the preprocess flags + generated headers MUST come from that
   real build's compile_commands.json — do not hand-synthesize flags. If it genuinely
   cannot be built in this environment, that is a hard blocker to report, NOT a BLOCKED
   unit (un-built ≠ BLOCKED, no leaf-driver fallback);
 - create an overlay in PREFIX-acsl/ annotating the *.c units, keeping DIR PRISTINE
   (reversible patches in PREFIX-acsl/patches/; pin the faithfulness baseline — git HEAD per
   repo + each submodule, or a sha256 manifest if the tree is untracked);
 - prove RTE- and functional-level absence of defect on the risk-ranked Tier-1/Tier-2
   queue. A Timeout is the loop's UNFINISHED WORK, not a verdict: re-invoke `framac-sl`
   to author the missing contracts (requires \valid / terminates / loop variants /
   callee-ensures propagation / invented cross-callee system invariants) until WP
   converges. Before tagging ANY goal residual/COQ-NEEDED, run the refutation probe —
   add the antecedent the goal points at and re-run; instant Valid ⇒ spec gap, keep
   going. **Then, by default, DISCHARGE the probe-confirmed true-but-hard goals with Coq (do not
   merely classify them):** escalate each to the `framac-coq8` toolchain
   (`-wp-prover …,coq -wp-interactive`), accept a Coq close ONLY under the soundness audit
   (cache-clean replay with `-wp-cache none`, `Print Assumptions` ⊆ the standard set, **zero
   admits**) — a Coq-closed goal is a verdict delta. Interactive Coq is not guaranteed to auto-close
   every goal; what even Coq cannot close stays residue, now tagged **Coq-attempted**. (Skip this Coq
   stage under `--no-coq`, leaving them `COQ-NEEDED`.) Write real bugs + the residue that survives
   *both* the probe *and* the Coq stage (Coq-attempted, unmodelled construct, or a tooling defect) to
   PREFIX-found-issues.md. **If you fan out units in
   parallel, each sub-agent MUST run in its own worktree (`isolation: 'worktree'`), never a shared
   checkout — concurrent patch apply/revert on one tree corrupts peers (frama-c-monitoring §5.4);
   harvest each unit's reversible patch back to PREFIX-acsl/patches/ afterward;**
 - add HAPPY (MAcsl) keywords for the Tier-3 logic risks and write the coverage gaps vs
   PREFIX-ebios-report.md to PREFIX-ebios-gaps.md;
 - for BLOCKED items (crypto/entropy/supply-chain) record residual risk rather than
   stopping; leave the EBIOS W5 sign-off PENDING (I'm the risk owner);
 - **if this run produced a verdict delta** (convergence happened) **or** the campaign is now fully
   converged **or** `--w5-only` was given, generate the next-numbered PREFIX-W5-ebios-feedback-NN.md
   (Phase 0 picked NN) — otherwise emit nothing new and say "no delta" (no flat cycles): the
   frama-c-monitoring §8e W5 PROPOSAL (per
   frama-c-launch/references/ebios-feedback.md, the forward + return halves) — verdicts →
   *proposed* likelihood deltas (likelihood only, severity never, branch-local) +
   residuals, keyed to the report's scenario IDs / supporting assets. Its content must be
   scenario-keyed control-effectiveness signals ONLY — no implementation detail or proof
   internals — so a future code-blind `ebios-sl` re-run can consume it without becoming
   endogenous. I adjudicate it (human terminus).
