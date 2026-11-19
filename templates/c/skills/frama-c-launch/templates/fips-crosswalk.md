# FIPS 140-3 ↔ frama-c-launch crosswalk

The join table between a **FIPS 140-3 requirement study** (the `fips-sl` skill — the FIPS 140-3
corpus in `specs/`, the module's public description, the manifest's target level) and the
`frama-c-launch` onboarding. It is the faithful sibling of `rmf-crosswalk.md` (and of
`ebios-crosswalk.md`). It supplies the architect's **exogenous upper bound**: the ranking stops being
"input-exposure read off the code" (endogenous, a self-consistency signal) and becomes the study's
**`VO#` priority `P1`–`P3`** — an independent, requirement-grounded ranking. `frama-c-launch` accepts
**an EBIOS study *or* a NIST RMF assessment *or* a FIPS 140-3 requirement study *or* an equivalent
exogenous bound**; this template is the FIPS peer. Fill one per target that has (or warrants) a
requirement study; it feeds Phase 0 (ranking + scope) and, after verification, the **F5 residual
acknowledgment** (the Ann. 13 terminus).

## Two contracts (read before filling — this is where it goes coherent-and-wrong)
- **Disjointness — keep the study exogenous.** The bound is only independent if the study's
  requirements and failure modes (F1–F4) were authored **without reading the implementation** — from
  the corpus, the module's public description and the target level only; otherwise the ranking is
  endogenous again (a fake fix). If the same actor read the code to build both, **say so** and
  discount the bound. Module vocabulary (`MOD#`, `SSP`, `crypto officer`, `Ann. 10`) is legitimate
  scope/standard language, not a loophole.
- **No-blend.** The study's priorities are **soft normative** judgments; the WP verdict is a **hard**
  machine truth. Neither substitutes for the other: a `P1` priority does not make a unit verified,
  and a WP `PROVED` does not validate the module — it retires **one class** (RTE / memory-safety, or
  one named property) of **one** verification obligation on the **amenable** surface. A `PROVED`
  `VO#` is **evidence for its `RQ#`**, never a CMVP validation. Record which plane each cell is.

## 1. Module crosswalk  (the module's parts <-> translation units)
The module (`MOD#`) and its services (`SV#`), roles (`RL#`), SSPs (`SSP#`), interfaces (`IF#`) and
states (`ST#`) — all named by role in F1, never by file — map to `frama-c-launch` *translation
units* (the scope map). This is the spine; everything else references it.

| FIPS element (F1) | Translation unit(s) | scope-map status | note |
|---|---|---|---|
| <e.g. "the key-establishment service" SV2> | `<file>::<fn>` ... | amenable / BLOCKED(reason) | ... |

## 2. Obligation ranking  (the exogenous ranking + the area -> property join)
Each F4 verification obligation (`VO#`) becomes a verification target, ranked by its priority.
**The priority is cited from the report — do not re-derive it here.** The property class (from
`fips-sl/references/area-properties.md`) selects what `frama-c-monitoring` verifies.

| ID | Failure mode (F3) + requirement (F2) | Area | Property class | Priority | TU(s) |
|----|---|---|---|---|---|
| VO1 | <FM1 — the SSP left in memory> · RQ5 (`zeroize`) | AR8 | zeroize | **P1** | `<file>::<fn>` ... |
| VO2 | <FM2 — data out in an error state> · RQ2 (`output-inhibit`) | AR2 | output-inhibit | P2 | ... |

Derived rules (the architect applies these):
- **Ranking key = the `VO#` priority `P1` > `P2` > `P3`**, not raw input-exposure. Verify the `P1`
  obligations first.
- An obligation whose units the scope map marks **BLOCKED** (asm / crypto primitive / syscall), and
  the areas with no property class (AR5, AR6, AR7, AR11), become a **flagged residual** (`RR#`
  in F5, citable to the obligation) — it does not silently disappear.
- The **`approved-only`** class (AR1) is a **call-graph check**, not a WP proof: verify it with a
  Frama-C script over the call graph of the approved mode's entry points, and record it as such.

## 3. Verification feedback into the F5 residual acknowledgment  (filled at campaign close)
The downstream half: WP verdicts become **requirement evidence** for the study's F5. Left blank
during onboarding; filled at campaign close per `../references/fips-feedback.md` (the coordinator
*proposes* the evidence; the **owner of the protected information, or the agency's responsible
authority** *adjudicates* — the Ann. 13 human terminus). No-blend: a verdict *informs* the evidence,
never sets the priority, and never validates the module.

| Obligation | TU + verdict | Property proved | Requirement evidence (honest, amenable only) | Residual |
|---|---|---|---|---|
| VO1 | `file::fn` PROVED 12/12 | zeroize on the error paths | RQ5 has machine evidence: the SSP is cleared on every return path (0 admits) | compiler elision — RR4 (`supply-chain`) |
| VO2 | `file::fn` PARTIAL | ... | partial — name the un-discharged goals | ... |

## Worked fragment — a crypto-library module (illustrative; F1–F4 authored from the public description, not the code)
| ID | Failure mode · requirement | Area | Class | Priority | TU(s) |
|----|---|---|---|---|---|
| VO1 | Key material readable after an error path · RQ5 | AR8 | zeroize | **P1** | the cipher free/error paths |
| VO2 | Plaintext SSP through a data output · RQ6 | AR8 | no-plain-ssp-out | **P1** | the output encoders |
| VO3 | Service runs before the self-tests · RQ7 | AR9 | selftest-order | P2 | the module init/state machine |
| VO4 | Primitive strength (e.g. a broken PRNG) · RQ3 | AR3 | — | n/a | **residual** (RR: `crypto`) — KAT vectors, not WP |

Note how the campaign order (zeroize/error paths first, then the output encoders, then the state
machine) falls out of the priorities, and the primitive-strength row lands as an **explicit
residual** (not a silent omission) — that is the value the exogenous FIPS bound adds over
"input-exposure read off the code."
