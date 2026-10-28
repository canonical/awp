# Workshop 3 — Strategic Scenarios

Gets a clear view of the **ecosystem** (partners, subcontractors, subsidiaries, suppliers, clients…) to find the most vulnerable stakeholders, then builds **high-level attack paths** ("strategic scenarios") a risk origin could take to reach a selected RO/TO pair. Treated as a *preliminary risk study*; also yields ecosystem security measures. Period = strategic cycle.

Why the ecosystem matters: attackers increasingly exploit the weakest link around the target (e.g. hitting a cloud provider's availability, booby-trapping a server supply chain to exfiltrate data).

## Participants
Business teams; functional architects; CISO; optionally a cybersecurity specialist.

## Outputs
- **Ecosystem digital threat mapping** + critical stakeholders.
- **Strategic scenarios** (with severity).
- **Security measures** chosen for the ecosystem.

## Steps
a. Build the ecosystem digital threat mapping; select critical stakeholders.
b. Develop strategic scenarios.
c. Define ecosystem security measures.

Variable length: ~1–3 half-days.

Needs: missions & business assets (W1); feared events & severity (W1); selected RO/TO pairs (W2); the IS mapping, especially its ecosystem view.

---

## a. Ecosystem digital threat mapping & critical stakeholders
A stakeholder is **critical** when it's a relevant attack vector — privileged digital access to the object, its own vulnerability, or exposure. A well-informed RO follows least effort and hits the "weakest link."

Assess each stakeholder's **threat level** on the object using criteria rather than pure expert judgement. ANSSI's simple model uses two axes:
- **Exposure** = dependency × penetration (how much the object relies on it × how deep its access is),
- **Cyber reliability** = maturity × trust.

Plot stakeholders on the mapping (often a radar) and select critical ones using risk-acceptance thresholds, conventionally three zones: **watch zone**, **control zone**, **danger zone** (increasing threshold). Selection is a governance decision — management may keep or drop a stakeholder for contextual/policy reasons even against the raw score.

Categorise stakeholders for cross-reference, e.g. Clients C1…, Partners P1…, Service providers F1….

### Worked-example shape (vaccine biotech)
Stakeholders included clients (healthcare institutions, pharmacies, distributors), partners (universities, regulators, laboratories), providers (chemical suppliers, equipment suppliers, IT service provider). Critical stakeholders retained: **F3 IT service provider**, **F2 equipment supplier**, **P3 laboratories**.

## b. Develop strategic scenarios
Imagine realistic high-level attack paths. For each selected RO/TO pair, ask, from the attacker's standpoint:
- Which business asset(s) must I hit to reach my target?
- To enable/ease the attack, would I attack a critical stakeholder with privileged access to those assets?

Then describe the **sequence of events** the RO generates to reach the target. Events that hit business assets are **feared events** (reuse the W1 list, now from the attacker's viewpoint — update if needed); events on the ecosystem are **intermediate events**.

Example events: create an exfiltration channel from a provider's infrastructure; modify a critical industrial parameter (e.g. a high-temperature threshold); DoS the cloud supplier; delete/alter a database; impersonate a support service.

Represent as **attack graphs** or overlay attack path(s) on the ecosystem view. Then assess each scenario's **severity** from the feared events it touches (this severity is shared by all its attack paths). Guidance: **1–3 attack paths per RO/TO pair**; favour variety (different critical stakeholders, different business-asset categories); avoid excessive detail.

### Worked-example shape (vaccine biotech)
- *Competitor steals R&D* (severity 3, Serious) via 3 paths: (1) direct exfiltration from R&D's IS; (2) exfiltration via the laboratory P3 (holds part of the work); (3) exfiltration via the IT service provider F3.
- *Hacktivist sabotages the campaign* (severity 4, Critical — worst case during epidemic peak, > 1 week) via 2 paths: (1) interrupt production by compromising equipment supplier F2's maintenance equipment; (2) alter vaccine labelling.

Summarise as: *Risk origins | Target objectives | Strategic attack paths | Severity*.

## c. Ecosystem security measures
Reduce the structural vulnerabilities the work exposed (including scenarios where you're hit collaterally via a partner). Measures aim to **lower a critical stakeholder's intrinsic threat level** (e.g. reduce dependency on a subcontractor) or disrupt the scenario.

Track per stakeholder: *Stakeholder | Strategic attack path | Security measures | Initial threat → Residual threat*. Produce an **initial vs residual** ecosystem threat mapping to show the expected reduction over a stated horizon (e.g. 9–12 months). These measures may affect governance — management decision is needed.
