# EBIOS RM W5 risk-feedback — verification verdicts → risk treatment

The **downstream** half of the EBIOS bridge (the upstream half is `../templates/ebios-crosswalk.md`).
After `frama-c-monitoring` finishes a campaign, its per-unit WP verdicts become evidence for EBIOS
**workshop 5** (risk treatment): proofs are security measures, gaps are residual risks. This file is
the how-to the campaign-close step runs (triggered from `frama-c-monitoring` SKILL §8e); it fills
crosswalk §3 and feeds the human risk owner. Two halves: the **forward** half (verdicts → a W5
proposal, below) and the **return** half (feeding the result back into a code-blind `ebios-sl`
re-run without breaking exogeneity — see the last section).

## What / who / when
- **When:** at `frama-c-monitoring` campaign close, after the verdict log is final — **only if** an
  EBIOS study + a filled `../templates/ebios-crosswalk.md` exist (else skip: there is no W5 to feed).
- **Who:** the coordinator (or a thin risk-liaison) **PROPOSES** the W5 delta from the verdict log +
  the crosswalk; the **EBIOS risk owner** — the person who accepts residual risk in W5 — **ADJUDICATES**
  it. The step produces a *proposal*; the human re-rates and signs. This is the MACHINE-DONE → DONE
  human terminus (`frama-c-monitoring` §8): the verification is machine-closed, the risk re-rating is
  the soft residual a human outside the loop adjudicates.

## Two disciplines (non-negotiable)
- **No-blend.** The WP verdict is a **hard** machine truth; EBIOS severity/likelihood are **soft**
  normative judgments. The verdict **informs** the likelihood; it does **not set** it. Write a
  *proposed* likelihood delta + the evidence and let the risk owner re-rate — never silently rewrite a
  risk level from a verdict. Severity (W1) is **never** changed by a verdict.
- **Honest likelihood-reduction.** A `PROVED` RTE-robust unit retires the **memory-safety class** of
  attack steps on the **amenable** surface of **one** supporting asset — not logic bugs, not crypto,
  not the state machine, not the BLOCKED parts. Name the step retired *and* what is left.
- **Corroboration ≠ control (two evidence tiers — do not conflate).** Only a **machine-checked control**
  (a `PROVED`/banked goal on the branch) supports a **likelihood ↓**. An **independent second method that
  finds 0 counterexamples** on a residue (e.g. a second memory model, fuzzing, a cross-prover replay)
  is weaker: it **corroborates the residue as non-exploitable** and supports a **residual-risk-WEIGHT ↓**,
  *not* a likelihood drop. State which tier each delta is. (Worked example: a byte-model pass finding 0
  counterexamples on the cast-model residue → residual-weight ↓; only once those goals are *banked* as
  Valid does the branch earn a likelihood ↓.)

## The mapping  (verdict class → W5 contribution)
| Verdict (frama-c-monitoring) | EBIOS W5 contribution |
|---|---|
| **PROVED** (RTE-robust, faithful) | **SCIP security measure**: "formally verified RTE-robustness of `<asset>` (N/N WP goals, faithfulness gate, 0 admits)". **Proposed** likelihood reduction for the *memory-corruption steps* of the scenarios traversing this asset (state the step: e.g. "OOB write in the DER decoder excluded → V3→V2 for R1"). Severity unchanged. |
| **PARTIAL** | Partial measure **+** a residual risk for the un-discharged goals; name the residual class (alloc/`\fresh`, `+cast`-frame, crypto-oos, termination, libc-init, cast-residual). **No** likelihood reduction for the un-covered steps. |
| **BLOCKED** (out of WP scope) | **Residual risk**, citable to the EBIOS scenario ID; route to **non-formal** treatment (pentest / fuzzing / the compliance baseline / a different control). Formal verification does not touch it. |
| **REFUTED** (a suspected bug shown safe) | Evidence the feared step does not occur as feared; note in W5 (may lower likelihood for that step, with the same propose-then-adjudicate discipline). |
| **a confirmed RTE bug found** | A **finding**: the feared event is realizable → raises/confirms likelihood; route to `bugs-to-report/` and to W5 as an **unacceptable** risk pending fix (do not propose a reduction). |

## Procedure
1. Read the final verdict log (`<target>-acsl/verdicts.tsv` / `framac/.verdicts.tsv`) + the crosswalk.
2. For each verified unit, find its supporting asset + scenario(s) in crosswalk §1/§2.
3. Fill **crosswalk §3** (one row per scenario touched): verdict, property proved, *proposed*
   likelihood delta (honest), residual risk, SCIP measure.
4. Re-plot the Farmer diagram post-treatment with the **proposed** likelihoods, labelled
   "proposed — pending risk-owner sign-off".
5. Hand the proposed W5 delta to the EBIOS risk owner. Emit it as part of the soft-residual packet
   (`bin/framac-soft-residual.sh` → `SOFT-RESIDUAL.md`); the owner's sign-off is the campaign's **DONE**.
6. **Coverage check:** every **high-severity** feared event (W1) must map to ≥1 verified-or-residual
   scenario in §3. A gap → iterate EBIOS W2–W4 or extend the verification scope (a `gap-N`).
7. **Persist it NUMBERED, one per cycle:** write `<prefix>-W5-ebios-feedback-NN.md` (zero-padded; next
   index after the highest existing — start `-01`). **Never overwrite a prior numbered W5 file** — the
   series *is* the continuous-improvement history (the W5-doctrine "residual mapping per SCIP
   milestone", risk evolution over cycles). This is the only per-cycle artifact; the
   `<prefix>-ebios-report.md` / `-found-issues.md` / `-ebios-gaps.md` / overlay are **consolidated**
   (single file, current truth, updated in place).

## Direction & disjointness (why this stays sound)
This closes the bridge in both directions while keeping the planes disjoint: **EBIOS → launch**
(the risk-level ranking, upstream `U`) and **launch/monitoring → EBIOS** (the treatment evidence,
downstream from `L`). The verdict is produced by the verification loop (hard `L`); the risk re-rating
is the EBIOS risk owner's (soft `U`). Neither certifies the other — a proof is not a risk decision,
and a risk rating is not a proof.

## The return half — feeding a code-blind `ebios-sl` re-run (closing the cycle)
The steps above are the **forward** half (verdicts → a W5 proposal the risk owner adjudicates). The
**return** half is what lets the next `ebios-sl` study consume this feedback *without* the cycle
turning the exogenous bound endogenous — the single failure `ebios-sl`'s code barrier exists to
prevent. EBIOS RM is a continuous-improvement loop, so this return path is intended; it is sound
**only** under these constraints:

- **Consume the latest numbered packet.** Feed the next `ebios-sl` study the **highest-index**
  `<prefix>-W5-ebios-feedback-NN.md` (the current proposal); the lower-numbered ones are the
  cycle history, kept for the risk owner's risk-evolution view, not re-consumed.
- **Re-author code-blind, every cycle.** A feedback cycle is **not** a licence to read the
  implementation. The next `ebios-sl` W1–W4 is authored from mission + threat model only; the Gate-B
  endogeneity tripwire and the reviewer's anchoring tell still apply to the *new* report. Feedback
  does not relax the barrier.
- **The feedback crosses as a typed, scenario-keyed control-effectiveness signal — never as code or
  proof content.** What may re-enter is of the shape *"SA-k formally hardened → likelihood ↓ on
  branch X; residual remains on branch Y,"* keyed to the report's scenario IDs / supporting assets —
  the **same shape as any external control input** (a pentest result, a compliance attestation). It
  carries **no** translation-unit names, ACSL, WP goal text, proof internals, or any artefact that
  reveals how the code is built. The producer of the packet is code-aware; the **packet's content is
  code-free**. (This is the W5-feedback artefact's acceptance criterion: if a code-blind author
  reading it would learn an implementation fact, it leaks — strip it.)
- **It informs W5, not the re-authored W1–W4.** The signal lands in the new study's **W5** (treatment
  status / residual carry-over). It must **not** seed scenarios, vulnerabilities, or re-rated
  severities in W1–W4 — those stay derived from the threat model.
- **One exception — a confirmed bug is new *threat* knowledge, handled as such.** A `confirmed RTE
  bug` (a realizable feared event) legitimately changes the threat picture, but it re-enters through
  **W1 feared events**, authored code-blind from the **finding statement** ("an out-of-bounds write
  is reachable in the certificate parser under attacker input"), never by importing the reproducer or
  the proof. It is a fact about *system behaviour*, not about *code*.
- **Cadence is asymmetric.** Accumulate feedback across **many** verification runs; re-run `ebios-sl`
  at the EBIOS strategic (~3 yr) / operational (~1 yr) boundary, or out-of-cycle on a major event (a
  confirmed bug, a new threat) — **not** after every campaign. The verification loop runs often; the
  risk study is re-authored rarely.

Soundness restated: the forward half keeps `L` (hard verdict) and `U` (soft re-rating) disjoint via
the human terminus; the return half keeps the *next* `U` exogenous via the code barrier. A feedback
packet that carries code/proof content is the cycle's coherent-and-wrong — it makes the re-authored
report self-consistent with the **code** instead of the **threat**, the exact endogeneity `ebios-sl`
forbids.
