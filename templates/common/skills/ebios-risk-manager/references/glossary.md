# EBIOS RM — Glossary

Precise vocabulary, condensed from ANSSI's definitions. Use these meanings exactly; many terms are easy to confuse (business vs supporting asset; risk origin vs threat; feared event vs risk scenario; strategic vs operational scenario).

**Attack surface** — All supporting assets the studied object relies on or interacts with that could be used to attack it. More supporting assets / more exploitable vulnerabilities → larger attack surface.

**Business asset** — A component important to the organisation's mission: a service, support function, project step, or related information/know-how. It is what a risk origin wants to attack. (Was "essential asset" in EBIOS 2010.) Nature: **process or information**.

**Critical stakeholder** — An ecosystem stakeholder likely to be a privileged attack vector (privileged digital access, vulnerability, or exposure). Identified in the ecosystem digital threat mapping.

**Critical supporting asset** — A supporting asset very likely to be targeted by a risk origin reaching its target. These appear in operational scenarios.

**Denial of service (DoS)** — Attack rendering services unavailable by exploiting a software/hardware vulnerability. **DDoS** = distributed version using a network of (usually compromised) machines.

**Ecosystem** — All stakeholders interacting with the studied object in its normal operation. Risk origins are not a priori stakeholders unless they can affect the object's operation.

**Ecosystem digital threat mapping** — Visual (e.g. radar) representation of the digital threat level of ecosystem stakeholders w.r.t. the studied object.

**Elementary action** — A unitary action a risk origin performs on a supporting asset within an operational scenario (e.g. exploit a vulnerability, send a booby-trapped email, erase trails, escalate privileges).

**Elementary likelihood** — Likelihood of an elementary action; from expert judgement or scales. Confronts the RO's assumed resources/motivation against the object's security baseline and the ecosystem's vulnerability.

**Feared event (FE)** — Attached to a business asset; harms one of its security needs (e.g. service unavailability, illegitimate change of an industrial threshold, disclosure of classified data). FEs used in strategic scenarios concern an attack's impact on a business asset. Each is rated by **severity**.

**Initial risk** — A risk scenario assessed **before** applying the treatment strategy (by severity and likelihood).

**Intermediate event** — In a strategic scenario, an event the risk origin generates against an ecosystem stakeholder to ease reaching its objective (e.g. create an exfiltration channel from a provider; DoS the target's cloud supplier).

**Likelihood** — Estimated feasibility/probability that a risk occurs, on an adopted scale (e.g. rather unlikely … nearly certain).

**Mission** — Function, end purpose, reason for existence of the studied object.

**Operating mode** — The series of elementary events a risk origin will likely carry out to reach its target (terminology of operational scenarios).

**Operational scenario** — Chain of elementary actions on the supporting assets of the object or its ecosystem, planned by the risk origin to achieve an objective. Assessed by **likelihood**.

**Penetration test (pentest)** — Simulating a malicious user's attack to find which operating codes succeed; both defensive (improve protection) and offensive (attack one's own IS). Reveals risks from misconfiguration (infrastructure audit) or programming faults (product audit).

**Residual risk** — A risk scenario remaining **after** applying the treatment strategy (by severity and likelihood).

**Risk** — Possibility of a feared event occurring whose effects affect the object's missions. In EBIOS RM, a risk is expressed as a **risk scenario**.

**Risk assessment** — Processes for identifying, analysing, and evaluating risks (ISO 31000:2018). In EBIOS RM = workshops 2, 3, 4.

**Risk level** — Measure of the extent of the risk, combining **severity** and **likelihood**.

**Risk mapping** — Visual representation (radar, Farmer diagram) of the risks from the assessment.

**Risk origin (RO)** — Element, person, group, or organisation that can generate a risk; characterised by motivation, resources, skills, preferred attack methods. Examples: state services, hacktivists, competitors, vengeful employees.

**Risk scenario** — Complete scenario from risk origin to target objective, describing an attack path and its associated operational scenario. (This guide considers only **intentional** digital risk scenarios.)

**Risk treatment strategy** — Formalises acceptance thresholds and the security level to reach if not accepted; built from the initial risk mapping; decides each risk's acceptability (unacceptable / tolerable / acceptable), usually deduced from the risk level.

**Security accreditation** — An accreditation authority's validation that the achieved security level meets expectations and that residual risks are acceptable for the study.

**Security continuous improvement plan (SCIP)** — Formalises all risk-treatment measures to implement; raises the IS security maturity and enables progressive management of residual risks. Covers both the studied object and its ecosystem.

**Security measure** — Means of treating a risk, as a solution or contractual requirement. Functional, technical, or organisational; can act on a business asset, supporting asset, or stakeholder; can be reinforced along the four lines: **governance, protection, defence, resilience**.

**Security need** — Security property to guarantee for a business asset (availability, integrity, confidentiality, traceability).

**Security patch** — Code added to software to correct an identified vulnerability.

**Severity** — Estimated extent/intensity of a risk's effects; measures perceived detrimental impacts, direct or indirect (e.g. negligible … maximum).

**Social engineering** — Unfair acquisition of information/property/services by exploiting human and social weaknesses (trust, ignorance, gullibility) of the target.

**Stakeholder** — Element (person, IS, organisation, or risk origin) with direct/indirect interaction with the studied object in normal operation; internal or external. Examples: partner, provider, client, supplier, subsidiary.

**Strategic scenario** — Attack path from a risk origin to a target objective, including the ecosystem and the object's business assets. Assessed by **severity**.

**Studied object** — The organisation, information system, or product under risk assessment.

**Supporting asset** — IS component a business asset relies on; digital, physical, or organisational (e.g. server, network, gateway, technical room, a project team, administrators, the R&D department).

**Target objective (TO)** — End purpose a risk origin pursues per its motivations (e.g. steal information for spying, spread an ideology, take revenge, trigger a health crisis).

**Threat** — Any hostile intent to do harm in cyberspace; may or may not target the studied object.

**Threat level of a stakeholder** — Measure of the risk potential a stakeholder places on the object's ecosystem given its interaction, vulnerability, exposure, reliability, etc.

**Vulnerability** — A fault (malicious or careless) in a system's specification, design, build, install, or configuration, or in how it's used; can be exploited and lead to intrusion.

**Waterhole** — A booby-trap on a server/site regularly visited by targeted users; the attacker waits for the victim to connect to compromise them. The site may be legitimate or fake.
