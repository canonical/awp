# Workshop 5 — Risk Treatment

Summarises the **risk scenarios**, decides a **risk treatment strategy**, defines **security measures** (collected in a Security Continuous Improvement Plan, SCIP), then documents **residual risks** and sets up **risk monitoring**.

## Participants
Same as W1: top management; business teams; CISO; IT department / information management team.

## Outputs
- Risk treatment strategy.
- Summary of residual risks.
- Security Continuous Improvement Plan (SCIP).
- Risk-monitoring framework.

## Steps
a. Create the summary of risk scenarios.
b. Decide the treatment strategy and define security measures.
c. Assess and document residual risks.
d. Set up the risk-monitoring framework.

Variable length: ~2–4 half-days.

Needs: security baseline (W1); strategic scenarios (W3); ecosystem security measures (W3); operational scenarios (W4).

---

## a. Summarise the risk scenarios
A **risk scenario** = an attack path + its operational scenario, running from risk origin to target objective, carrying a **severity** (from W3) and a **likelihood** (from W4). Give each a stable ID (R1, R2, …).

Plot them by **severity × likelihood** on a grid / radar / **Farmer diagram** — this is the **initial risk mapping** (before treatment). Optionally re-cut the view by risk origin / target objective to expose the most critical zones.

**Coverage check:** review every feared event from W1 and flag any of substantial severity not covered by a risk scenario — a blind spot. If found, decide whether to iterate W2–W4. A coverage matrix (feared events × risk scenarios) helps.

## b. Treatment strategy & security measures
For each risk scenario, agree an **acceptance threshold** and the security level to reach if not accepted. Formalise this as the treatment strategy, using acceptance classes (see SKILL.md): Low = acceptable as is; Moderate = tolerable under control; High = unacceptable (mandatory short-term reduction). Acceptability is usually deduced directly from the risk level.

**Acceptance class ≠ treatment option.** The class above decides *the risk level you will tolerate*; it does not decide *the move you make*. The threshold is the organisation's **risk appetite** (owned by the risk owner, not fixed by the method): the same "High" may be "reduce now" at one organisation and "retain with justification" at another. Once a scenario is not accepted as-is, pick a **treatment option** (EBIOS RM / ISO 27005 — one or a combination per scenario):

| Treatment option | What it does | Effect on the scenario |
|---|---|---|
| **Reduce** (mitigate) | add/strengthen security measures that harden the attack path | lowers **likelihood** (and sometimes severity, e.g. sandboxing/segmentation that caps impact) |
| **Avoid** (suppress) | remove the function, asset, or exposure that creates the risk (drop a feature, disconnect an interface) | removes the scenario entirely |
| **Share** (transfer) | shift part of the risk to a third party — insurance, or delegating the asset to a more capable provider | unchanged technically; **redistributes who bears the residual impact** |
| **Retain** (accept) | keep the risk deliberately, with justification, optionally under surveillance | unchanged; recorded as an accepted residual (risk-owner decision) |

Most scenarios are treated by **reduce**, which is what the security measures below implement; **avoid/share/retain** are the alternatives the risk owner weighs when reduction is too costly, infeasible, or unwarranted. A purely formal-verification measure (e.g. a Frama-C/WP proof) is a **reduce** move that lowers *likelihood* on the proven branch only — never severity, never the BLOCKED branches it did not cover.

Then define the **security measures** that treat each scenario — ad hoc measures or reinforced baseline measures, supplementing the ecosystem measures from W3. Run through each strategic/operational scenario and ask: *which elementary phases/actions should be hardened to make the attacker's task harder and lower its success probability?* Prioritise:
- the elementary actions with the **highest likelihood**,
- the **strategic/operational nodes** the RO must pass through,
- and therefore the **critical supporting assets** involved.

Document everything in the **SCIP**, scheduled and structured. Each measure records: responsible person, brakes/difficulties, cost/complexity, timeframe, status. ANSSI groups measures along four complementary lines: **Governance, Protection, Defence, Resilience**.

SCIP row shape: *Security measure | Associated risk scenarios | Person responsible | Brakes & difficulties | Cost/complexity | Timeframe | Status*.

## c. Assess & document residual risks (RR)
Residual risk = the scenario re-assessed **after** applying the treatment measures. Document each, e.g.:
- summary description (incl. feared impacts),
- residual vulnerabilities the RO could still exploit,
- other aggravating causes/factors,
- feared events concerned,
- existing + additional treatment measures,
- assessment: *initial* severity/likelihood/risk level vs *residual* severity/likelihood/risk level,
- residual-risk management (specific monitoring/control measures).

Plot a **residual risk mapping** in the same form as the initial one — it's the decision-support tool for an accreditation commission accepting residual risks. Attaching a residual mapping to each SCIP milestone (T0+3m, T0+6m…) shows risk evolution over time. Management may deliberately **retain** a high residual risk (with justification) or put an unlikely-but-feared threat **under surveillance**.

## d. Risk-monitoring framework
Base ongoing risk management on **steering indicators** that verify measure effectiveness and fit to the threat state. Define/refine the continuous-improvement process and its governance (roles, responsibilities, committees). Recommended: a **steering committee** meeting **every 6 months** during ramp-up, **every 12 months** at cruising speed, to track indicators, SCIP progress, and risk change.

Update the study per the scheduled strategic and operational cycles, and out-of-cycle on major events (new threat, significant change to the ecosystem or the studied object).
