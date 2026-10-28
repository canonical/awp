# NIST RMF Monitor-step feedback — verification verdicts -> ongoing authorization

The **downstream** half of the NIST RMF bridge (the upstream half is `../templates/rmf-crosswalk.md`).
After `frama-c-monitoring` finishes a campaign, its per-unit WP verdicts become **control-effectiveness
evidence** for the 800-37 **Monitor** step (step 7, ongoing authorization): proofs are evidence the
selected 800-53 controls are effective, gaps are residual risks + POA&M entries. This file is the
faithful sibling of `ebios-feedback.md` (EBIOS W5 -> RMF Monitor). It is the how-to the campaign-close
step runs (triggered from `frama-c-monitoring` SKILL §8e); it fills crosswalk §3 and feeds the human
Authorizing Official (AO). Two halves: the **forward** half (verdicts -> a Monitor proposal, below) and
the **return** half (feeding the result back into a code-blind `rmf-sl` re-run without breaking
exogeneity — see the last section).

## What / who / when
- **When:** at `frama-c-monitoring` campaign close, after the verdict log is final — **only if** an RMF
  assessment + a filled `../templates/rmf-crosswalk.md` exist (else skip: there is no Monitor step to
  feed).
- **Who:** the coordinator (or a thin risk-liaison) **PROPOSES** the Monitor delta from the verdict log
  + the crosswalk; the **Authorizing Official** — the person who accepts residual risk and re-grants
  ongoing authorization (the 800-37 Authorize / ongoing-authorization decision) — **ADJUDICATES** it.
  The step produces a *proposal*; the human re-rates and signs. This is the MACHINE-DONE -> DONE human
  terminus: the verification is machine-closed, the ongoing-authorization decision is the soft residual
  a human outside the loop adjudicates.

## Two disciplines (non-negotiable)
- **No-blend.** The WP verdict is a **hard** machine truth; RMF likelihood/impact are **soft** normative
  judgments. The verdict **informs** the likelihood / control-effectiveness rating; it does **not set**
  it. Write a *proposed* likelihood delta + the evidence and let the AO re-rate — never silently rewrite
  a risk level from a verdict. Impact (the R1 FIPS-199 categorization) is **never** changed by a verdict.
- **Honest likelihood-reduction.** A `PROVED` RTE-robust unit shows the SI-7/SC control effective for the
  **memory-safety class** of threat events on the **amenable** surface of **one** supporting asset — not
  logic bugs, not crypto, not the state machine, not the BLOCKED parts, not the accidental/environmental
  origins. Name the threat step retired *and* what is left.
- **Corroboration != control (two evidence tiers — do not conflate).** Only a **machine-checked control**
  (a `PROVED`/banked goal on the branch) supports a **likelihood ↓** / a control marked effective. An
  **independent second method that finds 0 counterexamples** on a residue (a second memory model,
  fuzzing, a cross-prover replay) is weaker: it **corroborates the residue as non-exploitable** and
  supports a **residual-risk-WEIGHT ↓**, *not* a likelihood drop. State which tier each delta is.
  (Worked example: a byte-model pass finding 0 counterexamples on the cast-model residue ->
  residual-weight ↓; only once those goals are *banked* as Valid does the branch earn a likelihood ↓
  and the control earn an "effective" rating in the POA&M.)

## The mapping  (verdict class -> Monitor-step contribution)
| Verdict (frama-c-monitoring) | RMF Monitor-step contribution |
|---|---|
| **PROVED** (RTE-robust, faithful) | **Control-effectiveness evidence**: "SI-7/SC formally verified RTE-robust on `<asset>` (N/N WP goals, faithfulness gate, 0 admits)". **Proposed** likelihood reduction for the *memory-corruption steps* of the scenarios traversing this asset (state the step: e.g. "OOB write in the DER decoder excluded -> L3->L2 for RS1"). Impact unchanged. Mark the control **effective** in the POA&M. |
| **PARTIAL** | Partial evidence **+** a residual risk + POA&M entry for the un-discharged goals; name the residual class (alloc/`\fresh`, `+cast`-frame, crypto-oos, termination, libc-init, cast-residual). **No** likelihood reduction for the un-covered steps; the control is **partially effective**. |
| **BLOCKED** (out of WP scope) | **Residual risk** (`RR#`), citable to the RMF scenario ID; route to **non-formal** treatment (pentest / fuzzing / the compliance baseline / a different 800-53 control — e.g. IA/AU for Spoofing/Repudiation, CP/PE for the environmental origins). Formal verification does not touch it; record it as an accepted/open POA&M item. |
| **REFUTED** (a suspected bug shown safe) | Evidence the feared threat step does not occur as feared; note in the Monitor packet (may lower likelihood for that step, with the same propose-then-adjudicate discipline). |
| **a confirmed RTE bug found** | A **finding**: the threat event is realizable -> raises/confirms likelihood; the control is **ineffective**; route to `bugs-to-report/` and to the Monitor packet as an **unacceptable** risk + an open POA&M item pending fix (do not propose a reduction). May trigger a re-authorization decision by the AO. |

## Procedure
1. Read the final verdict log (`<target>-acsl/verdicts.tsv` / `framac/.verdicts.tsv`) + the crosswalk.
2. For each verified unit, find its supporting asset + scenario(s) + selected control in crosswalk §1/§2.
3. Fill **crosswalk §3** (one row per scenario touched): verdict, property proved, *proposed*
   likelihood / control-effectiveness delta (honest), residual risk, 800-53 control assessed.
4. Re-plot the risk matrix post-treatment with the **proposed** likelihoods, labelled "proposed —
   pending AO sign-off".
5. Hand the proposed Monitor delta to the AO. Emit it as the soft-residual packet (the
   `PREFIX-monitor-feedback-NN.md` Monitor packet); the AO's ongoing-authorization sign-off is the
   campaign's **DONE**.
6. **Coverage check:** every **Hi-impact** categorized element (R1) must map to >=1 verified-or-residual
   scenario with a selected control in §3. A gap -> iterate RMF R2-R4 or extend the verification scope
   (a `gap-N`).
7. **Persist it NUMBERED, one per cycle:** write `<prefix>-monitor-feedback-NN.md` (zero-padded; next
   index after the highest existing — start `-01`). **Never overwrite a prior numbered packet** — the
   series *is* the ongoing-authorization history (the 800-37 Monitor doctrine "ongoing assessment +
   POA&M over time", risk evolution over cycles). This is the only per-cycle artifact; the
   `<prefix>-rmf-report.md` / `-found-issues.md` / `-rmf-gaps.md` / overlay are **consolidated** (single
   file, current truth, updated in place).

## Direction & disjointness (why this stays sound)
This closes the bridge in both directions while keeping the planes disjoint: **RMF -> launch** (the
risk-level ranking, upstream `U`) and **launch/monitoring -> RMF** (the control-effectiveness evidence,
downstream from `L`). The verdict is produced by the verification loop (hard `L`); the ongoing-
authorization decision is the AO's (soft `U`). Neither certifies the other — a proof is not an
authorization decision, and an authorization is not a proof.

## The return half — feeding a code-blind `rmf-sl` re-run (closing the cycle)
The steps above are the **forward** half (verdicts -> a Monitor proposal the AO adjudicates). The
**return** half is what lets the next `rmf-sl` study consume this feedback *without* the cycle turning
the exogenous bound endogenous — the single failure `rmf-sl`'s code barrier exists to prevent. NIST RMF
is a continuous (ongoing-authorization) loop, so this return path is intended; it is sound **only**
under these constraints:

- **Consume the latest numbered packet.** Feed the next `rmf-sl` study the **highest-index**
  `<prefix>-monitor-feedback-NN.md` (the current proposal); the lower-numbered ones are the cycle
  history, kept for the AO's risk-evolution view, not re-consumed.
- **Re-author code-blind, every cycle.** A feedback cycle is **not** a licence to read the
  implementation. The next `rmf-sl` R1-R5 is authored from mission + threat model + the NIST corpus
  only; the Gate-B endogeneity tripwire and the reviewer's anchoring tell still apply to the *new*
  report. Feedback does not relax the barrier.
- **The feedback crosses as a typed, scenario-keyed control-effectiveness signal — never as code or
  proof content.** What may re-enter is of the shape *"SA-k / its control CTL-k formally hardened ->
  likelihood ↓ on scenario RS-k; residual remains on RS-j,"* keyed to the report's scenario IDs /
  controls / supporting assets — the **same shape as any external control-assessment input** (a pentest
  result, a compliance attestation, an 800-53 assessor finding). It carries **no** translation-unit
  names, ACSL, WP goal text, proof internals, or any artefact that reveals how the code is built. The
  producer of the packet is code-aware; the **packet's content is code-free**. (Acceptance criterion: if
  a code-blind author reading it would learn an implementation fact, it leaks — strip it.)
- **It informs the Monitor status, not the re-authored R1-R4.** The signal lands in the new study's
  **R5 / Monitor status** (control-effectiveness / residual carry-over). It must **not** seed scenarios,
  vulnerabilities, or re-rated impacts in R1-R4 — those stay derived from the threat model.
- **One exception — a confirmed bug is new *threat* knowledge, handled as such.** A `confirmed RTE bug`
  (a realizable threat event) legitimately changes the threat picture, but it re-enters through **R2
  threat events** (and possibly an R1 re-categorization), authored code-blind from the **finding
  statement** ("an out-of-bounds write is reachable in the certificate parser under attacker input"),
  never by importing the reproducer or the proof. It is a fact about *system behaviour*, not about
  *code*.
- **Cadence is asymmetric.** Accumulate feedback across **many** verification runs; re-run `rmf-sl` at
  the RMF strategic / ongoing-authorization boundary, or out-of-cycle on a major event (a confirmed bug,
  a new threat, a re-categorization) — **not** after every campaign. The verification loop runs often;
  the risk study is re-authored rarely.

Soundness restated: the forward half keeps `L` (hard verdict) and `U` (soft re-rating) disjoint via the
human terminus (the AO); the return half keeps the *next* `U` exogenous via the code barrier. A feedback
packet that carries code/proof content is the cycle's coherent-and-wrong — it makes the re-authored
report self-consistent with the **code** instead of the **threat**, the exact endogeneity `rmf-sl`
forbids.
