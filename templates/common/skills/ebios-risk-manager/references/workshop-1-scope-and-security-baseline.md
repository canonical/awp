# Workshop 1 — Scope and Security Baseline

Establishes the framework of the study, its business and technical scope, the feared events, and the security baseline. **Prerequisite for any risk assessment.** Period considered = the strategic cycle. This is the "compliance" / "defence" viewpoint (the first two pyramid levels).

## Participants
Top management; business teams; CISO; IT department / information management team. (Add anyone useful.)

## Outputs
- Framework: objectives, roles & responsibilities, timeframe.
- Business & technical scope: missions, business assets, supporting assets.
- Feared events + severity.
- Security baseline: applicable requirements, implementation status, identified gaps + justification.

## Steps
a. Define the framework of the study.
b. Define the business & technical perimeter of the studied object.
c. Identify feared events and assess severity.
d. Determine the security baseline.

Typically 1–3 half-day sessions (excluding prep/write-up).

---

## a. Frame the study
- Agree the **objective** (e.g. set up a cyber risk management process; accredit an information system; define a security level for a product certification). The objective determines the depth and which workshops to run.
- Identify participants, roles, responsibilities (a RACI / responsibility assignment matrix helps).
- **Identify who is accountable for accepting the residual risks** at the end — this is essential.
- Set the **timeframe**: durations of the operational and strategic cycles, consistent with constraints, standards, legal/regulatory frameworks. Generic accreditation defaults: strategic cycle 3 years, operational cycle 1 year.
- Address project-management aspects (workshop planning, resource constraints) as needed.

## b. Define the business & technical perimeter
Work top-down: missions → business assets → supporting assets.

**Missions** — the end purposes and major goals of the studied object (how it creates value). Usually the missions of the organisation the object belongs to.

**Business assets** — information or processes deemed important and worth protecting; what an attacker would target to achieve its objective (e.g. an online cancellation service, customer information, R&D results, a project's deployment phase, design know-how). A business asset's nature is **process or information**.
- Don't aim for exhaustiveness — keep only the essential/sensitive ones. ~**5–10 business assets** is a sufficient base. Unselected assets can inherit the protections of the selected ones.
- Group sets of information rather than isolated items; rank by security need (availability, integrity, confidentiality, traceability). Security needs can be judged "very high / notable / negligible" — seek a *relative* position, not an absolute value.

**Supporting assets** — the IS components a business asset relies on (digital, physical, or organisational): servers, networks, applications, premises, people/teams, suppliers. Use the IS mapping. At this stage list only the most important (≈1–3 per business asset); they'll be supplemented in workshop 4.

Note: business/supporting assets owned by outside entities can be picked up in workshop 3 (ecosystem mapping).

### Worked-example shape (vaccine biotech)
Mission "Identify and manufacture vaccines" → business assets: *R&D* (process), *Manufacturing vaccines* (process), *Traceability and control* (information). Each maps to supporting assets (e.g. R&D → desktop application servers internal/external, antigen production systems), with a responsible internal/external entity named.

## c. Identify feared events (FE) and assess severity
A **feared event** is attached to a business asset and represents a harmful breach of one of its security needs. For each business asset, look for harm to:
- **availability** (inaccessible info, service interruption, can't run a process phase),
- **integrity** (forgery/modification, function creep, process alteration),
- **confidentiality** (disclosure, unauthorised access, secret compromised),
- **traceability** (loss of audit trail, can't reconstruct a process chain),
- and more broadly quality of service / performance.

Describe each FE as a short expression or mini-scenario. For **availability** FEs, state the loss-of-service threshold at which the stated severity is reached (e.g. "> 2h", "> 1 week"). Identify FEs from the **organisation's viewpoint**, outside any attack scenario — they'll be re-used from the attacker's viewpoint in W3 and may be updated then.

**Severity** depends on the business asset's criticality w.r.t. missions, regulations, and the nature/intensity of direct and indirect impacts. Score on the G1–G4 scale (see SKILL.md). Consider all impact types — internal, external, direct, indirect — to surface impacts stakeholders hadn't imagined.

Record as a table: *Business asset | Feared event | Impacts | Severity*. Example impact categories used by ANSSI: impacts on missions/services, on development costs, on governance, on safety/health of persons, on image/trust, legal, financial.

## d. Determine the security baseline
Compliance approach (pyramid levels 1–2). Identify every **security reference standard** that applies:
- cyber hygiene / best practice (ANSSI guides, internal rules),
- standards (ISO 27000 family, etc.),
- current regulations.

If the object already exists, assess each standard's **implementation status** (e.g. green = applied without restriction, orange = applied with restrictions, red = not applied) and clearly identify **gaps** and their causes.

Record as a table: *Type of reference standard | Name | Implementation status | Gaps | Justification for gaps*. The gaps feed the risk assessment in later workshops; corresponding measures are defined in W5.

Note: security measures implemented as a result of *previous* risk studies are now part of the baseline and can be tested in the assessment workshops.
