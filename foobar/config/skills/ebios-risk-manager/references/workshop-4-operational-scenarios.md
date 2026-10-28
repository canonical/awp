# Workshop 4 — Operational Scenarios

Builds the **technical attack sequences** the risk origins could use to realise the strategic scenarios, focused on **supporting assets**, then assesses their **likelihood**. Ends with a summary of all the study's risks. Period = operational cycle.

## Participants
CISO; IT department / information management team; optionally a cybersecurity specialist.

## Outputs
- The list of **operational scenarios** and their **likelihood**.

## Steps
a. Develop the operational scenarios.
b. Assess their likelihood.

Variable length: ~1–3 half-days.

Needs: missions, business & supporting assets (W1); security baseline (W1); selected RO/TO pairs (W2); selected strategic scenarios (W3); the application and logical-infrastructure views of the IS mapping.

---

## a. Develop the operational scenarios
A successful attack usually chains several flaws of IT, organisational, or physical nature — individually minor, jointly serious. **Each strategic attack path from W3 becomes one operational scenario.**

Structure each scenario as a **typical attack sequence**. Any kill-chain-style model works; ANSSI's example uses a KNOW → ENTER → FIND → EXPLOIT progression (analogous to recon → initial access → lateral discovery → action on objective). The point is to surface the **critical supporting assets** used as entry, exploitation, or propagation vectors — W5 measures will target these (others can inherit them).

Represent as **attack graphs / diagrams** built on the IS mapping. Adjust granularity to the organisation's maturity and the depth sought: macroscopic actions (e.g. a "WannaCry"-style event) or fine-grained ones. To avoid combinatorial explosion, prioritise the **least-effort** methods for the RO and a **representative panel** of supporting assets.

A classic illustrative pattern is the **waterhole** attack for establishing an exfiltration channel: attacker compromises a third-party site the victims visit → booby-trapped iframe redirects to malware → infection + backdoor on a workstation → propagation to key internal systems (domain controller, mail, directory, file server) → drop attack tools → exfiltrate.

### Worked-example shape (vaccine biotech)
For the path "competitor exfiltrates directly from R&D's IS", the team drew an attack graph with several entry techniques: phishing the HR mail system / booby-trapping the works-council website / using a pre-existing hidden channel; corrupting an R&D employee; corrupting maintenance personnel to insert a booby-trapped USB key. Aggravating factors repeatedly noted: poor patch discipline, unpartitioned internal networks, unrestricted USB ports, unsupervised outgoing flows.

## b. Assess likelihood
For each operational scenario, assess its **overall likelihood** (probability of success / feasibility). Severity is **not** reassessed here — it equals the severity of the associated strategic scenario (set in W3).

Two ways:
1. **Detailed** — score the **elementary likelihood** of each elementary action, confronting the RO's assumed resources/motivation against the object's security baseline and the ecosystem's vulnerability (attack surface, structural/organisational weaknesses, detection/reaction capacity). Then combine into an overall likelihood (e.g. via the least-effort path).
2. **Express** — assess the overall likelihood directly from the attack methods as a whole. Faster, less precise.

Score on V1–V4 (see SKILL.md). Record: *Strategic attack path (≙ operational scenario) | Overall likelihood*.

### Worked-example shape (vaccine biotech)
Exfiltration **via the IT service provider** → **V4 (nearly certain)**: the provider has high access rights and weak IS security. **Direct** exfiltration → **V3 (very likely)** given many technical/organisational weaknesses. Via the laboratory → V2. Production interruption via equipment supplier → V2. Labelling alteration → V1.

Note: while building operational scenarios you may need to **update or supplement the strategic scenarios** of W3 (new vulnerability, new stakeholder, alternative method). W3 participants decide whether to adopt the additions. W3↔W4 iterate — but **don't exceed two iterations**.
