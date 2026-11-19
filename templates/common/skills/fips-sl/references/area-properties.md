# The eleven FIPS 140-3 areas → verification properties (drives frama-c-monitoring)

This table maps each of the eleven requirement areas of FIPS 140-3 to the property classes the
verification loop can discharge (`frama-c-monitoring`: WP, macsl; Creusot for Rust), and to the
planes that stay residual. **This table is the skill's design choice, not corpus text** —
the corpus names the areas (FIPS 140-3 Abstract, Ann. 3; ISO/IEC 19790 §7.2–§7.12) and says what
each requires, but not how to verify it in code; the mapping
below is `fips-sl`'s authored authority (terrain B), the counterpart of `rmf-sl`'s
STRIDE → 800-53 → property table. It is the engine that makes a code-blind requirement study rank
and aim a code-aware verification campaign.

Every `VO#` home line (pinned format, rule F4) carries one of the property-class tokens below; the
`VO#`'s priority `P1`–`P3` is the ranking the launch loop consumes.

| Area | Property class (token) | What is checked, and how | Residual (plane) |
|---|---|---|---|
| AR1 module specification | `approved-only` | in the approved mode, every service reaches only functions on the module's list of Approved security functions. A **call-graph check** (a Frama-C script over the call graph), not a WP proof | the list itself (`validation`) |
| AR2 interfaces | `output-inhibit` | no data output while the module is in an error or self-test state | — |
| AR3 roles, services, authentication | `role-gate` | each service runs only with an authenticated, authorized role | strength of the authentication mechanism (`crypto`) |
| AR4 software/firmware security | `integrity-first` | the integrity test runs, and passes, before any service | the integrity technique (`crypto`) |
| AR5 operating environment | — | — | `ENV` |
| AR6 physical security | — | — | `physical`. A software-only module marks AR6 `N/A` in F2 and still writes the standing `physical` residual in F5, with "not applicable: no physical enclosure" as its treatment |
| AR7 non-invasive security | — | — | `side-channel`: constant-time tools, not WP |
| AR8 SSP management | `zeroize`, `no-plain-ssp-out` | SSPs are zeroized after use and on every error path; no plaintext SSP leaves through a data output. The `zeroize` proof is on the source: a compiler can remove the clearing as a dead store | removed zeroization (`supply-chain`) |
| AR9 self-tests | `selftest-order`, `error-state` | the pre-operational and conditional self-tests run before first use; a failure enters the error state and stays there | the test vectors (`crypto`) |
| AR10 life-cycle assurance | `fsm` | the transitions the code allows are those of the documented finite state model | configuration management, delivery (`logic`) |
| AR11 mitigation of other attacks | — | — | `side-channel` or `logic`, per item |

## System-level classes

`output-inhibit`, `role-gate`, `integrity-first`, `selftest-order`, `error-state` and `fsm` are
properties over every path or over the order of events in the whole module. Per-function `requires`
and `ensures` cannot express them without ghost state. The `rmf-sl` warning applies to all six: they
need macsl or a whole-module invariant, and a ghost function with a postulated `ensures` does not
count as verified. Two consequences for the study:

1. **Author each such obligation as a universal, and enumerate its vectors.** An `error-state`
   obligation ("once in the error state, the module outputs nothing **by any path**") is a ranked
   head whose body is the set of ways the property can fail (every early return, every error
   branch, every asynchronous entry). The downstream proof must close **each vector** (PROVED or
   explicitly CARVED/REFUTED, none silently green), so the study must surface the vector list, not
   a one-line property.
2. **Warn the monitor of the ghost-fiat trap.** A macsl/HAPPY system property proved via a **ghost
   model function with a postulated `ensures`** is **semantically vacuous** — green while nothing
   backs the ghost. Accepting such a row as *treated* requires the monitor's ghost-antecedent audit
   (a derived leaf `ensures` or a NAMED TCB axiom), not a bare green. The **residual-risk owner**
   (the F5 sign-off) is the terminus that decides whether the universal is the intended strength.

## The standing residuals (ALWAYS named, NEVER proved)

Every report names these in F5, one `RR#` line per plane, even if no requirement surfaced them,
because they are structurally out of the formal tools' reach (pinned format, rule F4; the linter's
F-C8 enforces their presence):

- **Cryptographic primitive strength** (plane `crypto` → `STANDING`) — KAT vectors / libcrypto
  trust; out of WP's reach by design.
- **The AR5, AR6 and AR7 planes** (`ENV` → `AR5`, `physical` → `AR6`, `side-channel` → `AR7`) —
  the operating environment, the enclosure, and timing/leakage are non-formal by design;
  constant-time tooling and leakage assessment, not WP.
- **Compiler correctness, including removed zeroization, and supply chain** (plane `supply-chain` →
  `STANDING`) — a compiler may elide a clearing store; SLSA / reproducible build.
- **The CMVP validation itself** (plane `validation` → `STANDING`) — a proof is **evidence for the
  CST laboratory**, never a validation; conformance "is not sufficient to ensure that a particular
  module is secure" (Ann. 13).

`AR11` (mitigation of other attacks) routes per item: a timing side-channel to `side-channel`, a
fault/abuse-logic item to `logic`.
