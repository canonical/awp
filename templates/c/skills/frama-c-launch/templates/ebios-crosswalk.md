# EBIOS RM ↔ frama-c-launch crosswalk

The join table between an **EBIOS Risk Manager** study (ANSSI's cyber-risk method — the
`ebios-risk-manager` skill) and the `frama-c-launch` onboarding. It supplies the architect's
**exogenous upper bound**: the attack-surface ranking stops being "input-exposure read off the
code" (endogenous, a self-consistency signal) and becomes "EBIOS **risk level** = severity ×
likelihood" — an independent, threat-grounded ranking. Fill one per target that has (or warrants) a
risk study; it feeds Phase 0 (ranking + scope) and, after verification, EBIOS workshop 5 (treatment).

EBIOS's own adaptation table lists *"Direct a security audit / pentest → W3, W4"* — the
frama-c-launch + frama-c-monitoring campaign **is** a way to discharge those W3/W4 attack scenarios.

## Two contracts (read before filling — this is where it goes coherent-and-wrong)
- **Disjointness — keep EBIOS exogenous.** The bound is only independent if the EBIOS scenarios were
  authored **without reading the implementation**. W1–W3 (missions, risk origins, strategic
  scenarios) must come from threat intel / stakeholders / mission, not from the code; otherwise the
  "gold" shares the scope map's blind spot and the ranking is endogenous again (a fake fix). If the
  same actor read the code to build both, **say so** and discount the bound. W4 legitimately touches
  technical supporting assets — that is the gradient, not a loophole.
- **No-blend.** EBIOS severity/likelihood are **soft normative** judgments; the WP verdict is a
  **hard** machine truth. Neither substitutes for the other: a high EBIOS likelihood does not make a
  unit verified, and a WP `PROVED` does not zero an EBIOS risk — it retires **one class** (RTE /
  memory-safety) of **one** attack step on the **amenable** surface. Record which plane each cell is.

## 1. Asset crosswalk  (EBIOS supporting asset ↔ translation unit)
EBIOS *supporting assets* (W3/W4 — the technical components bearing the business assets) map to
frama-c-launch *translation units* (the scope map). This is the spine; everything else references it.

| EBIOS supporting asset (W3/W4) | Translation unit(s) | scope-map status | note |
|---|---|---|---|
| <e.g. "X.509 certificate parser"> | `<file>::<fn>` … | amenable / BLOCKED(reason) | … |

## 2. Scenario crosswalk  (the exogenous ranking)
Each EBIOS operational scenario / attack path becomes a verification target, ranked by its risk
level. **Severity comes from the feared events (W1); likelihood from W4 — do not re-derive them
here, cite them.** `priority` = the ranking key the architect uses, highest risk first.

| ID | Attack path (W3) | Supporting asset → TU(s) | Feared event + **severity** (W1) | **Likelihood** (W4, pre-treatment) | **Risk level** | Verification target (property) | Priority |
|----|---|---|---|---|---|---|---|
| R1 | <path> | <asset → `file::fn`> | <feared event> · **G4** | **V3** | High | RTE-robustness on the parsing path | 1 |
| R2 | … | … | … · G2 | V2 | Moderate | … | … |

Derived rules (the architect applies these — see `../references/learned-architect.md`):
- **Ranking key = risk level (severity × likelihood)**, not raw input-exposure. Verify the High-risk
  supporting assets first.
- A supporting asset on **no** attack path → low priority (verify last / out of the security scope).
- A supporting asset on a **high-severity** path that the scope map marks **BLOCKED** (asm / crypto /
  syscall / state-machine — out of WP reach) → a **flagged residual risk**, citable to its EBIOS
  scenario ID; it does not silently disappear, it moves to §3 for non-formal treatment.

## 3. Verification feedback into EBIOS W5  (filled by the frama-c-monitoring §8e campaign-close step)
The downstream half: WP verdicts become risk-treatment evidence. Left blank during onboarding; filled
at campaign close per `../references/ebios-feedback.md` (the coordinator *proposes* the deltas; the
EBIOS risk owner *adjudicates* — the human terminus). No-blend: a verdict *informs* likelihood, never
sets it; severity is never changed by a verdict.

| EBIOS scenario | TU + verdict | Property proved | Likelihood reduction (honest, RTE/amenable only) | Residual risk | SCIP security measure |
|---|---|---|---|---|---|
| R1 | `file::fn` PROVED 99/99 | RTE-robust (no OOB/overflow/shift) on the parsing path | excludes memory-corruption *steps* on this asset → V3→V2 for R1; logic/crypto steps unchanged | crypto callee BLOCKED (out of WP scope) | "formally verified RTE-robustness of <asset>" |
| R2 | `file::fn` PARTIAL | … | partial — name the un-discharged goals | … | … |

## Worked fragment — mbedtls (illustrative; W1–W3 authored from threat model, not the code)
| ID | Attack path | Supporting asset → TU | Feared event · severity | Likelihood | Risk | Target | Priority |
|----|---|---|---|---|---|---|---|
| R1 | Malicious cert in TLS handshake → DER decode | ASN.1 length/tag decoder → `asn1parse.c::mbedtls_asn1_get_len/_get_tag` | Memory corruption / RCE parsing attacker bytes · **G4** | **V3** | **High** | RTE-robustness on the decode path | 1 |
| R2 | Forged X.509 field → field parser | X.509 field parsers → `x509.c::mbedtls_x509_get_{serial,sig,name}` | Forged certificate accepted · **G4** | **V2** | **High** | RTE-robustness on field parsing | 2 |
| R3 | Crafted TLS record → record-header math | record header → `ssl_msg.c::ssl_parse_record_header` | Record-length overflow · **G3** | **V2** | Moderate | refute the overflow | 3 |
| R4 | (crypto primitive) | AEAD/MAC → `tf-psa-crypto` (submodule) | — · G4 | — | High | **BLOCKED** (out of WP scope) → §3 residual | n/a |

Note how the mbedtls campaign's actual order (ASN.1 → X.509 field parsers → record header) falls out
of the risk ranking, and the crypto primitive (R4) lands as an **explicit residual risk**, not a
silent omission — the value the exogenous bound adds over "input-exposure read off the code."
