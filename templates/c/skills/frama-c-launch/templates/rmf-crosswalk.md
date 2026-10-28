# NIST RMF <-> frama-c-launch crosswalk

The join table between a **NIST Risk Management Framework** assessment (the `rmf-sl` skill — SP
800-30 mechanics, SP 800-37 lifecycle, SP 800-53 controls, STRIDE engine) and the `frama-c-launch`
onboarding. It is the faithful sibling of `ebios-crosswalk.md`. It supplies the architect's
**exogenous upper bound**: the attack-surface ranking stops being "input-exposure read off the
code" (endogenous, a self-consistency signal) and becomes "RMF **risk level** = likelihood x impact
(the 800-30 risk matrix)" — an independent, threat-grounded ranking. `frama-c-launch` accepts **an
EBIOS study *or* a NIST RMF assessment *or* an equivalent exogenous risk bound**; this template is the
RMF peer of the EBIOS one. Fill one per target that has (or warrants) a risk study; it feeds Phase 0
(ranking + scope) and, after verification, the RMF **Monitor** step (ongoing authorization).

The 800-37 lifecycle's **Assess** step is exactly where a control-effectiveness check lives — the
frama-c-launch + frama-c-monitoring campaign **is** a way to assess the SI/SC/SC-5/AC-6 controls
selected in R5 against the threats found in R2 (STRIDE engine).

## Two contracts (read before filling — this is where it goes coherent-and-wrong)
- **Disjointness — keep RMF exogenous.** The bound is only independent if the RMF scenarios were
  authored **without reading the implementation**. R1-R4 (categorization, threat sources/events,
  vulnerabilities, likelihood) must come from threat intel / mission / the NIST corpus, not from the
  code; otherwise the "gold" shares the scope map's blind spot and the ranking is endogenous again (a
  fake fix). If the same actor read the code to build both, **say so** and discount the bound. R5
  legitimately names 800-53 control IDs and config tokens — that is scope/control language, not a
  loophole.
- **No-blend.** RMF likelihood/impact are **soft normative** judgments; the WP verdict is a **hard**
  machine truth. Neither substitutes for the other: a high RMF likelihood does not make a unit
  verified, and a WP `PROVED` does not zero an RMF risk — it retires **one class** (RTE / memory-
  safety) of **one** threat event on the **amenable** surface, i.e. it provides **control-effectiveness
  evidence** for one selected control. Record which plane each cell is.

## 1. Asset crosswalk  (RMF supporting asset <-> translation unit)
RMF *supporting assets* (R1/R3 — the technical components bearing the information assets) map to
frama-c-launch *translation units* (the scope map). This is the spine; everything else references it.

| RMF supporting asset (R1/R3) | Translation unit(s) | scope-map status | note |
|---|---|---|---|
| <e.g. "X.509 certificate parser" SA1> | `<file>::<fn>` ... | amenable / BLOCKED(reason) | ... |

## 2. Scenario crosswalk  (the exogenous ranking + the STRIDE->800-53->property join)
Each RMF risk scenario (R4) becomes a verification target, ranked by its risk level. **Impact comes
from the R1 categorization; likelihood from R4 — do not re-derive them here, cite them.** The STRIDE
tag (R2) selects the 800-53 control family **and** the verification property (the plan §1 join).
`priority` = the ranking key the architect uses, highest risk first.

| ID | Threat event (R2) + STRIDE | Supporting asset -> TU(s) | Impact (R1) | Likelihood (R4) | Risk level | 800-53 family (R5 CTL) | Verification property | Priority |
|----|---|---|---|---|---|---|---|---|
| RS1 | <event> · Tampering | <asset -> `file::fn`> | **Hi** | **L3** | High | SI-7 | RTE + integrity (no OOB write) on the parsing path | 1 |
| RS2 | <event> · Information Disclosure | ... | Mod | L2 | Moderate | SC-8 | no OOB read / no leak across a boundary | ... |

**The STRIDE -> 800-53 family -> verification-property join (the plan §1 table):**

| STRIDE | Property | 800-53 family | What frama-c-monitoring verifies |
|---|---|---|---|
| Tampering | Integrity | SI-7 / SC / CM | RTE + functional integrity (no OOB write, invariant preserved) |
| Information Disclosure | Confidentiality | SC-8 / AC / MP | no OOB read / no leak across a boundary; separation |
| Denial of Service | Availability | SC-5 / CP | termination / bounded resource (loop variants, `terminates`) |
| Elevation of Privilege | Authorization | AC-6 / IA | privilege/permission invariants (HAPPY/MAcsl system props) |
| Spoofing | Authentication | IA / AC | (often BLOCKED — crypto/runtime; residual RR#) |
| Repudiation | Non-repudiation | AU | (BLOCKED — audit/logging; residual RR#) |

Derived rules (the architect applies these):
- **Ranking key = risk level (likelihood x impact, the 800-30 matrix)**, not raw input-exposure.
  Verify the High-risk supporting assets first.
- A supporting asset on **no** risk scenario -> low priority (verify last / out of the security scope).
- A supporting asset on a **Hi-impact** scenario that the scope map marks **BLOCKED** (asm / crypto /
  syscall / state-machine — out of WP reach), and the **accidental/environmental** origins (ACC/ENV)
  whose controls are CP/PE not SI/SC -> a **flagged residual risk** (`RR#`), citable to its RMF
  scenario ID; it does not silently disappear, it moves to §3 for non-formal treatment.

## 3. Verification feedback into the RMF Monitor step  (filled by the frama-c-monitoring §8e close)
The downstream half: WP verdicts become control-effectiveness evidence + POA&M entries for the 800-37
**Monitor** step (ongoing authorization). Left blank during onboarding; filled at campaign close per
`../references/rmf-feedback.md` (the coordinator *proposes* the deltas; the **Authorizing Official**
*adjudicates* ongoing authorization — the human terminus). No-blend: a verdict *informs* likelihood /
control-effectiveness, never sets it; impact (R1 categorization) is never changed by a verdict.

| RMF scenario | TU + verdict | Property proved | Control-effectiveness / likelihood reduction (honest, RTE/amenable only) | Residual risk | 800-53 control assessed |
|---|---|---|---|---|---|
| RS1 | `file::fn` PROVED 99/99 | RTE-robust (no OOB/overflow/shift) on the parsing path | SI-7 effective for memory-corruption *steps* on this asset -> L3->L2 for RS1; logic/crypto steps unchanged | crypto callee BLOCKED (out of WP scope) | CTL1 SI-7 |
| RS2 | `file::fn` PARTIAL | ... | partial — name the un-discharged goals | ... | CTL2 SC-8 |

## Worked fragment — mbedtls-style (illustrative; R1-R4 authored from threat model, not the code)
| ID | Threat event · STRIDE | Supporting asset -> TU | Impact | Likelihood | Risk | 800-53 | Property | Priority |
|----|---|---|---|---|---|---|---|---|
| RS1 | Malicious cert -> DER decode · Tampering | ASN.1 length/tag decoder -> `asn1parse.c::mbedtls_asn1_get_len/_get_tag` | **Hi** | **L3** | **High** | SI-7 | RTE + integrity on the decode path | 1 |
| RS2 | Forged X.509 field -> field parser · Tampering | X.509 field parsers -> `x509.c::mbedtls_x509_get_{serial,sig,name}` | **Hi** | **L2** | **High** | SI-7 | RTE-robustness on field parsing | 2 |
| RS3 | Crafted TLS record -> record-header math · Tampering | record header -> `ssl_msg.c::ssl_parse_record_header` | Mod | L2 | Moderate | SI-7 | refute the overflow | 3 |
| RS4 | (crypto primitive) · Spoofing | AEAD/MAC -> `tf-psa-crypto` (submodule) | Hi | — | High | IA | **BLOCKED** (out of WP scope) -> §3 residual RR1 | n/a |
| RS5 | Operator misconfiguration · (ACC origin) | config store -> n/a | Mod | L2 | Moderate | CM-6 | **non-formal** (config baseline) -> residual RR2 | n/a |

Note how the campaign order (ASN.1 -> X.509 field parsers -> record header) falls out of the risk
ranking, the crypto primitive (RS4, Spoofing) lands as an **explicit residual** (not a silent
omission), and the **accidental origin** (RS5, ACC) is captured as a non-formal residual — the 800-30
DNA difference EBIOS would not surface. That is the value the exogenous RMF bound adds over
"input-exposure read off the code."
