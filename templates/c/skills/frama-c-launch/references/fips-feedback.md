# FIPS 140-3 requirement feedback — verification verdicts -> requirement evidence

The **downstream** half of the FIPS 140-3 bridge (the upstream half is `../templates/fips-crosswalk.md`).
After `frama-c-monitoring` finishes a campaign, its per-unit WP verdicts become **requirement
evidence**: a `PROVED` `VO#` is evidence that the module satisfies its `RQ#` — never a CMVP
validation, and never a proof the module is secure ("conformance is not sufficient to ensure that a
particular module is secure", Ann. 13). Gaps are residuals routed to non-formal treatment. This file
is the faithful sibling of `rmf-feedback.md` (RMF Monitor -> FIPS F5) and of `ebios-feedback.md`. It
is the how-to the campaign-close step runs; it fills crosswalk §3 and feeds the human terminus — the
**owner of the protected information, or the agency's responsible authority**, who acknowledges and
accepts the residual risk (Ann. 13). Two halves: the **forward** half (verdicts -> a requirement-
evidence proposal, below) and the **return** half (feeding the result back into a code-blind
`fips-sl` re-run without breaking exogeneity — see the last section).

## What / who / when
- **When:** at `frama-c-monitoring` campaign close, after the verdict log is final — **only if** a
  FIPS requirement study + a filled `../templates/fips-crosswalk.md` exist (else skip: there is no
  F5 to feed).
- **Who:** the coordinator (or a thin requirement-liaison) **PROPOSES** the evidence from the verdict
  log + the crosswalk; the **owner of the protected information, or the agency's responsible
  authority** (Ann. 13) **ADJUDICATES** — acknowledges and accepts the residual risk, or refuses. The
  step produces a *proposal*; the human signs. This is the MACHINE-DONE -> DONE human terminus: the
  verification is machine-closed, the residual acknowledgment is the soft residual a human outside
  the loop adjudicates. The CMVP validation itself stays outside the loop entirely (the standing
  `validation` residual).

## Two disciplines (non-negotiable)
- **No-blend.** The WP verdict is a **hard** machine truth; the study's priorities are **soft**
  normative judgments. The verdict **informs** the requirement evidence; it does **not set** the
  `VO#` priority and does **not** validate the module. Write *proposed* evidence and let the owner
  adjudicate — never silently rewrite a priority from a verdict, and never write "validated" or
  "FIPS-certified" from a proof.
- **Honest evidence scope.** A `PROVED` `zeroize` obligation shows the SSP-clearing requirement
  (`RQ#`) satisfied for the **memory-safety/amenable class** on the **obligation's** units — not the
  primitive strength (`crypto`), not the side channels (`side-channel`), not the operating
  environment (`ENV`), not the enclosure (`physical`), not the supply chain (`supply-chain`), and
  not the validation itself (`validation`). Name the property retired *and* the standing residuals
  that remain.
- **Corroboration != control (two evidence tiers — do not conflate).** Only a **machine-checked
  obligation** (a `PROVED`/banked goal on the branch) is requirement **evidence**. An **independent
  second method that finds 0 counterexamples** on a residue (a second memory model, fuzzing,
  constant-time tooling) is weaker: it **corroborates** and supports a **residual-WEIGHT ↓**, *not*
  an evidence claim. State which tier each item is.

## The mapping  (verdict class -> F5 contribution)
| Verdict (frama-c-monitoring) | F5 requirement-evidence contribution |
|---|---|
| **PROVED** (faithful) | **Requirement evidence**: "`VO1`/`RQ5` (`zeroize`) formally verified on `<units>` (N/N WP goals, faithfulness gate, 0 admits) — machine evidence for RQ5." The obligation's coverage cell may move to `PROVED` (the generator machine-checks it against the verdicts). The evidence never extends past the obligation's stated class and units. |
| **PARTIAL** | Partial evidence **+** the obligation stays open in the ledger (`UNMODELED`/`TRUSTED-PENDING`), + a residual for the un-discharged goals; name the residual class (alloc/`\fresh`, `+cast`-frame, crypto-oos, termination, libc-init, cast-residual). |
| **BLOCKED** (out of WP scope) | **Residual** (`RR#` in F5, citable to the obligation), routed to **non-formal** treatment: KAT vectors (`crypto`), constant-time tooling (`side-channel`), dependency/SLSA review (`supply-chain`), the CMVP validation itself (`validation`). Formal verification does not touch it; the owner acknowledges it or refuses. |
| **REFUTED** (a suspected bug shown safe) | Evidence the feared failure mode does not occur as feared; note it in the feedback packet (may support a residual-weight ↓, with the same propose-then-adjudicate discipline). |
| **a confirmed bug found** | A **finding**: the failure mode (F3) is **realizable** — re-enter the study's F3 from its *finding statement* (never from the reproducer), and the feedback packet marks the requirement **unmet** pending fix. The owner sees it as an open item; do not propose evidence for it. |

## Procedure
1. Read the final verdict log (`<target>-acsl/verdicts.tsv` — under `fips` the column headed `VO#`)
   + the crosswalk.
2. For each verified unit, find its obligation + requirement in crosswalk §1/§2.
3. Fill **crosswalk §3** (one row per obligation touched): verdict, property proved, *proposed*
   requirement evidence (honest), residual.
4. Hand the proposed evidence packet to the owner. Emit it as the
   `PREFIX-fips-feedback-NN.md` packet; the owner's Ann. 13 acknowledgment is the campaign's **DONE**.
5. **Coverage check:** every `P1`/`P2` obligation (F4) must map to >=1 verified-or-residual unit in
   §3. A gap -> iterate the study's F3/F4 or extend the verification scope (a `gap-N`).
6. **Persist it NUMBERED, one per cycle:** write `<prefix>-fips-feedback-NN.md` (zero-padded; next
   index after the highest existing — start `-01`). **Never overwrite a prior numbered packet** — the
   series *is* the revalidation history. This is the only per-cycle artifact; the
   `<prefix>-fips-report.md` / `-found-issues.md` / `-fips-gaps.md` / overlay are **consolidated**
   (single file, current truth, updated in place).

## Direction & disjointness (why this stays sound)
This closes the bridge in both directions while keeping the planes disjoint: **FIPS -> launch** (the
priority ranking, upstream `U`) and **launch/monitoring -> FIPS** (the requirement evidence,
downstream from `L`). The verdict is produced by the verification loop (hard `L`); the residual-risk
acknowledgment is the owner's (soft `U`). Neither certifies the other — a proof is not an
acknowledgment, and an acknowledgment is not a proof.

## The return half — feeding a code-blind `fips-sl` re-run (closing the cycle)
The steps above are the **forward** half (verdicts -> an evidence proposal the owner adjudicates).
The **return** half is what lets the next `fips-sl` study consume this feedback *without* the cycle
turning endogenous. The rule is the one `rmf-feedback.md` states for the RMF twin, with the FIPS
vocabulary:

- The feedback re-enters **code-blind**. The next `fips-sl` study re-authors F1–F5 from the corpus, the
  module's public description and the target level — the verification packet enters as a **typed,
  requirement-keyed evidence signal** (`VO#`/`RQ#` + verdict class + the property retired), the same
  shape as a laboratory report. **No TU names, no function names, no ACSL, no goal counts, no proof
  internals** — a packet carrying them is the cycle's **endogeneity breach** and must be rejected by
  the coordinator.
- A confirmed bug re-enters via **F3** from its *finding statement* ("an SSP is readable after the
  error path of a service"), never via its reproducer.
- **A `PROVED` `VO#` is evidence for its `RQ#`** — it can close the obligation's ledger cell and
  support the F5 sign-off; it is **never** a CMVP validation and never lifts the standing
  `validation` residual. A **second-method corroboration** supports a residual-weight ↓ only.
- The owner's adjudication (acknowledge / refuse) is recorded **outside** the report's F1–F4 — the
  F5 sign-off column flips from `☐ PENDING` to signed **downstream, after the verdict join**, by the
  human, never by the loop.
- Consume the **latest numbered** packet (`<prefix>-fips-feedback-NN.md`, highest `NN`) — emitted one
  per cycle and never overwritten; this loop's own `<prefix>-fips-report.md` is **consolidated**
  (re-authored in place).
