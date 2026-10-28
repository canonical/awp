---
name: ebios-risk-manager
description: Conduct a digital/cyber risk assessment using ANSSI's EBIOS Risk Manager (EBIOS RM) method — the French national cybersecurity agency's 5-workshop methodology. Use this whenever the user wants to assess, analyse, or treat cyber/digital risk for a system, product, or organisation; mentions EBIOS, EBIOS RM, or ANSSI risk methodology; needs to identify business assets, supporting assets, feared events, a security baseline, risk origins, target objectives, strategic scenarios, operational scenarios, or a risk treatment plan; is preparing a security accreditation, risk mapping, or a security continuous improvement plan (SCIP); or asks to build any of the EBIOS RM deliverables. Trigger this even when the user describes the task in their own words ("help me figure out who might attack our system and how", "map our cyber risks", "build a risk treatment plan") without naming the method explicitly.
license: Method © ANSSI, published under the Open Licence (Etalab v1). This skill is a derivative reformatting for assistant use.
---

# EBIOS Risk Manager (EBIOS RM)

EBIOS RM is the method for assessing and treating **digital risk** published by ANSSI (the French National Cybersecurity Agency) with Club EBIOS. It is a toolbox: which activities you run, how deep you go, and in what order, all adapt to the goal of the study. It is compatible with ISO 31000 (risk management) and the ISO/IEC 27000 series (cybersecurity).

Use this skill to **guide a user through a risk study, produce the workshop deliverables, or answer methodology questions**. Do not invent ANSSI doctrine — when a detail of a specific workshop is needed, read the matching reference file rather than relying on memory.

## The core idea: compliance + scenarios

EBIOS RM combines two complementary approaches, pictured as the *digital risk management pyramid*:

- **Approach through compliance** establishes a **security baseline** (basic cyber hygiene, regulatory and standards framework). It is assumed to handle *accidental and environmental* risks a priori.
- **Approach through scenarios** builds on that baseline to study **targeted and sophisticated intentional threats** — the deliberate attacker.

So the scenario work (workshops 2–4) deliberately focuses on **intentional threats**, trusting the baseline (workshop 1) to cover the rest. Don't try to model accidental/environmental risk through scenarios; put it in the baseline.

## The five workshops

| # | Workshop | Produces |
|---|----------|----------|
| 1 | **Scope & Security Baseline** | Framing, missions, business assets, supporting assets, feared events + severity, security baseline + gaps |
| 2 | **Risk Origins** | Risk origin / target objective (RO/TO) pairs, assessed and selected; risk-origin mapping |
| 3 | **Strategic Scenarios** | Ecosystem digital threat mapping, critical stakeholders, high-level attack paths with severity, ecosystem security measures |
| 4 | **Operational Scenarios** | Technical attack sequences on supporting assets, assessed for likelihood |
| 5 | **Risk Treatment** | Risk summary/mapping, treatment strategy, security measures (SCIP), residual risks, monitoring framework |

Detailed how-to for each lives in `references/workshop-N-*.md`. **Read the relevant reference before running or explaining that workshop in depth.** A glossary of EBIOS RM terms is in `references/glossary.md` — consult it when a term's precise meaning matters.

## How the workshops chain together

This linkage is the backbone of the whole method — keep it straight:

```
RO/TO pair (W2)
   └─ Strategic scenario (W3)  ── severity (from feared events, W1)
        ├─ Attack path 1 ── Operational scenario 1 (W4) ── likelihood
        └─ Attack path n ── Operational scenario n (W4) ── likelihood
                                   └─ Risk scenario = attack path + its operational scenario
                                          └─ Risk level = severity × likelihood (W5)
```

- **Severity** is set once per strategic scenario (from the feared events it hits) and is shared by all its attack paths.
- **Likelihood** is assessed per operational scenario.
- A **risk scenario** pairs an attack path with its operational scenario; its **risk level** combines that scenario's severity and likelihood.

## The two cycles

Durations are fixed in workshop 1.
- **Strategic cycle** revisits the whole study, especially strategic scenarios. Typical default for an accreditation: **3 years**.
- **Operational cycle** revisits operational scenarios in light of incidents, new vulnerabilities, and evolving attack methods. Typical default: **1 year**.

Workshops 3 and 4 are fed over successive iterations — but cap it at **two iterations** to avoid over-complicating the analysis.

## Adapting the method to the goal

EBIOS RM is not always run end-to-end. Match the workshops to the objective:

| Goal | Workshops |
|------|-----------|
| Identify the security baseline for the object | 1 |
| Be compliant with security reference standards | 1, 2 |
| Assess the ecosystem's threat level | 3 (step a only; doesn't require W1–W2 first) |
| Identify high-level scenarios incl. ecosystem | 1, 3 |
| Preliminary risk study (priority improvement axes) | 1*, 3, 5 (step b only) |
| Complete, fine risk study (e.g. accreditation) | 1, 2, 3, 4, 5 |
| Direct a security audit / pentest | 3, 4 |
| Direct detection & response (e.g. a SOC) | 3, 4 |

\* In a preliminary study, adapt the depth of W1 (e.g. list business assets only, do a summary baseline analysis).

When a user's goal is narrower than a full study, **say which workshops apply and skip the rest** rather than forcing all five.

## Cross-cutting scales

These scales recur across workshops. They are illustrative defaults from ANSSI's worked example — adapt the wording to the organisation, but keep the 4/4/3-level structure unless the user wants otherwise. The aim is a *relative* ranking, not an absolute truth.

### Severity of feared events (set in W1, used through W5)

| Level | Name | Meaning (abridged) |
|-------|------|--------------------|
| G4 | Critical | Cannot sustain all/part of activity; possible serious safety impact; survival threatened |
| G3 | Serious | High degradation; possible significant safety impact; overcomes with serious difficulty (highly degraded mode) |
| G2 | Significant | Activity degraded, no safety impact; overcomes with some difficulty (degraded mode) |
| G1 | Minor | No real operational impact; overcomes by consuming margins |

For availability-type feared events, **state the threshold** at which the severity is reached (e.g. "service unavailable > 2h"). Estimate severity from all impact types — internal, external, direct, indirect.

### Likelihood of operational scenarios (W4)

| Level | Name | Meaning |
|-------|------|---------|
| V4 | Nearly certain | RO will certainly reach its objective by one of the attack methods |
| V3 | Very likely | RO will probably reach it |
| V2 | Likely | RO could reach it |
| V1 | Rather unlikely | RO has little chance of reaching it |

### Risk acceptability (W5)

| Risk level | Acceptability | Decision |
|-----------|---------------|----------|
| Low | Acceptable as is | No action |
| Moderate | Tolerable under control | Follow-up + medium/long-term continuous-improvement actions |
| High | Unacceptable | Risk-reduction measures mandatory short-term, else refuse all/part of the activity |

Risk scenarios are usually plotted on a grid / radar / **Farmer diagram** by severity × likelihood to form the risk mapping (before treatment), then again after treatment for residual risk.

## Running a study with a user — workflow

1. **Frame it first.** Establish the *studied object* (organisation, system, or product), the *goal* of the study, and therefore which workshops apply (see the adaptation table). Identify who accepts residual risk. Set the cycle durations.
2. **Work one workshop at a time.** Read `references/workshop-N-*.md` before going deep. Produce that workshop's named outputs before moving on; later workshops consume them.
3. **Keep it agile, not exhaustive.** ANSSI's volume guidance: ~5–10 business assets, 3–6 RO/TO pairs, 1–3 attack paths per RO/TO pair. Favour a varied, representative panel over completeness.
4. **Preserve the chain.** Severity flows from feared events (W1) into strategic scenarios (W3); likelihood is set in W4; risk level combines them in W5. Don't reassess severity per attack path.
5. **Check coverage at the end.** In W5, verify every high-severity feared event from W1 is reflected in at least one risk scenario; a gap means iterating W2–W4.
6. **Format deliverables as tables/diagrams** the way each reference shows, so they're usable in a real risk file or accreditation dossier.

When producing a substantial written deliverable (a full study report, a baseline table, a SCIP, a residual-risk dossier), create an actual file rather than only answering inline, and follow the relevant document skill if one applies.

## Output conventions

- Use the EBIOS RM vocabulary precisely (business asset vs supporting asset; risk origin vs threat; feared event vs risk scenario; strategic vs operational scenario). When in doubt, check `references/glossary.md`.
- Label scenarios with stable IDs (R1, R2, …) and stakeholders with category codes (clients C1…, partners P1…, providers F1…) so they can be cross-referenced across workshops, as ANSSI's example does.
- Attribute the method to ANSSI when presenting formal output.
