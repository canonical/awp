# Requirements matrix

Every requirement of the study (`RQ1`–`RQ34`), with the ISO/IEC 19790:2012
clause of its area, the verification obligation (`VO#`) and its status at
the end of the campaign.

**Clause column:** the area-to-clause mapping is from general knowledge of
ISO/IEC 19790:2012 and was not checked against its text. The `RQ` wording is
the study's paraphrase (`src:UNSOURCED` except RQ1).

**Status values:**

| Status | Meaning |
|---|---|
| **VIOLATED** | code contradicts the requirement; reproduced (`mbed-tls-found-violations.md`) |
| **GAP** | the mechanism the requirement needs is absent from the library (`design-gaps.md`) |
| **PARTIAL** | properties proved on part of the code; open or partial items remain |
| **NOT STARTED** | an obligation exists but no proof was attempted (`OPEN` rows only) |
| **RESIDUAL** | outside formal reach by design; a residual `RR#` names the other treatment (`residuals-and-signoff.md`) |
| **N/A** | not applicable to a software library |

**Evidence column:** counts of rows in `verdicts.tsv` that cite the `VO`, by
status. A row may cite several `VO`s, and `PROVED` counts raw rows,
including three later retracted. "Proved" always means relative to the
trusted base (`trusted-base.md`) and the default configuration.

## AR1 — Module specification (ISO/IEC 19790 §7.2)

| RQ | Requirement | VO | Status | Evidence |
|---|---|---|---|---|
| RQ1 | in the approved mode, every service employs only Approved security functions (src: PDF Ann. 10) | VO1 (P1) | NOT STARTED | 1 OPEN. A call-graph check, not a WP proof; RR1 |
| RQ2 | in the approved mode, no non-Approved or legacy primitive is reachable | VO2 (P2) | NOT STARTED | 1 OPEN. There is no approved mode to check against (G4) |
| RQ3 | every service is documented, and no undocumented entry bypasses its service's authorization | VO3 (P2) | PARTIAL | 22 PROVED, 2 OPEN, 1 OBSERVATION: the key-policy gates of the `psa_*` cipher, AEAD, MAC, sign and export entries |

## AR2 — Interfaces (§7.3)

| RQ | Requirement | VO | Status | Evidence |
|---|---|---|---|---|
| RQ4 | no data output in an error or self-test state | VO4 (P1) | GAP | G1: no error state exists |
| RQ5 | the error state is reported on the status interface and cannot be suppressed | VO5 (P2) | GAP | G1. Related defects returning a wrong or no status: F20-1, F24-1, F25-1 (`other-findings.md`) |
| RQ6 | no plaintext SSP leaves through a data output (level ≥ 3) | VO6 (P1) | PARTIAL | 18 PROVED, 4 OPEN, 1 PARTIAL, 1 TOOL-DEFECT, 1 WORKAROUND: the export-usage gate of `psa_export_key` (MACSL, in situ). RR14 |

## AR3 — Roles, services and authentication (§7.4)

| RQ | Requirement | VO | Status | Evidence |
|---|---|---|---|---|
| RQ7 | each service runs only for an authorized role | VO7 (P1) | PARTIAL | 31 PROVED, 4 OPEN, 1 PARTIAL: scoped to the per-key usage policy, the only access control the library has (G2). RR2 |
| RQ8 | operator authentication completes before any SSP-using service (level ≥ 2) | VO8 (P2) | GAP | G2: no operator authentication |
| RQ9 | crypto-officer and user roles are separated (level 4) | VO9 (P3) | GAP | G2: no roles. RR15 |

## AR4 — Software/firmware security (§7.5)

| RQ | Requirement | VO | Status | Evidence |
|---|---|---|---|---|
| RQ10 | the integrity test runs and passes before any service | VO10 (P1) | GAP | G3: no integrity test in `psa_crypto_init`. RR3 |
| RQ11 | a failed integrity test enters the error state | VO11 (P1) | GAP | G1, G3 |
| RQ12 | the integrity test can be run on demand (level 4) | VO12 (P3) | GAP | G3 |

## AR5 — Operational environment (§7.6)

| RQ | Requirement | VO | Status | Evidence |
|---|---|---|---|---|
| RQ13 | SSP memory is not accessible to other software of the environment | — | RESIDUAL | RR4: provided by the operating system |
| RQ14 | build and run configuration documented and reproducible (level ≥ 3) | — | RESIDUAL | RR5. The campaign pinned its own profile (see `proof-evidence.md`) |

## AR6 — Physical security (§7.7)

| RQ | Requirement | VO | Status | Evidence |
|---|---|---|---|---|
| — | physical enclosure, tamper response, environmental failure protection | — | N/A | a software library has no enclosure; level 4 physical controls rest on the platform. RR17 |

## AR7 — Non-invasive security (§7.8)

| RQ | Requirement | VO | Status | Evidence |
|---|---|---|---|---|
| RQ15 | no secret-dependent branches or table indices | — | RESIDUAL | RR6, RR18: constant-time tooling and leakage assessment. Three constant-time helpers proved functionally (`constant_time.c`, `base64.c`), not their timing |
| RQ16 | non-invasive mitigations documented and tested (level 4) | — | RESIDUAL | RR7 |

## AR8 — SSP management (§7.9)

| RQ | Requirement | VO | Status | Evidence |
|---|---|---|---|---|
| RQ17 | SSPs are zeroized after use | VO13 (P1) | PARTIAL | 33 PROVED, 9 PARTIAL, 4 OPEN, 10 OBSERVATION: every `*_free` of the cipher, hash, DRBG, bignum, ECP, RSA and DHM contexts zeroizes its SSP fields. RR13: the compiler may remove the clearing |
| RQ18 | SSPs are zeroized on every error path | VO14 (P1) | PARTIAL | 10 PROVED, 1 OPEN, 1 PARTIAL, 2 RETRACTED: `hkdf_expand` 103/103. OBS-1: partial derived key left on error under non-default configurations |
| RQ19 | no plaintext SSP leaves except through documented key-output services | VO15 (P1) | PARTIAL | 13 PROVED, 3 OPEN, 7 OBSERVATION. RR8 |
| RQ20 | SSPs come from an Approved, properly seeded RBG | VO16 (P2) | NOT STARTED | 1 OPEN. RR9: entropy quality is outside the proof |
| RQ21 | SSP entry and output encrypted and integrity-protected (level ≥ 3) | VO17 (P2) | NOT STARTED | 1 OPEN. The PSA API imports and exports plaintext keys by design: an integration-level control |
| RQ22 | the operator can zeroize all plaintext SSPs (level ≥ 2) | VO18 (P2) | PARTIAL | 7 PROVED, 4 PARTIAL, 2 RETRACTED: `mbedtls_psa_crypto_free` clears the RNG state; key-slot wipe 14/15 |
| RQ23 | released SSP storage holds no residual value | VO19 (P2) | PARTIAL | 4 PROVED, 4 PARTIAL: zeroize-then-free proved; the `free()` precondition is a tool limit (TOOL-2) |

## AR9 — Self-tests (§7.10)

| RQ | Requirement | VO | Status | Evidence |
|---|---|---|---|---|
| RQ24 | pre-operational self-tests run and pass before first use | VO20 (P1) | GAP | G3; 1 BLOCKED |
| RQ25 | conditional self-tests (KAT, pairwise consistency) before use | VO21 (P1) | GAP | G3 |
| RQ26 | a failed self-test enters the error state | VO22 (P1) | GAP | G1 |
| RQ27 | the error state persists, without output, until documented recovery | VO23 (P1) | GAP | G1 |
| RQ28 | RBG and entropy health tests at start-up and continuously (level ≥ 3) | VO24 (P2) | NOT STARTED | 1 OPEN |

## AR10 — Life-cycle assurance (§7.11)

| RQ | Requirement | VO | Status | Evidence |
|---|---|---|---|---|
| RQ29 | the transitions are those of the finite state model ST1–ST6 | VO25 (P2) | **VIOLATED** | **V-1**. Besides: 24 PROVED (every other slot-reaching public function is init-gated), 6 PARTIAL, 2 OPEN, 1 REPAIR-PROVED (V-1's fix) |
| RQ30 | no call sequence reaches a state outside the model | VO26 (P2) | **VIOLATED** | **V-1**. Besides: 19 PROVED, 2 PARTIAL, 1 OPEN, 1 REPAIR-PROVED. O-4: hash entries run before init (`other-findings.md`) |
| RQ31 | configuration management, delivery and operation are controlled (level ≥ 3) | — | RESIDUAL | RR10: procedural |
| RQ32 | at end of life or reset, MOD1 returns to uninitialized with SSPs cleared | VO27 (P3) | PARTIAL | 38 PROVED, 12 PARTIAL, 4 OPEN: `mbedtls_psa_crypto_free` clears all three subsystem flags and zeroes the RNG state (Coq); `initialized == 0` as a number is a tool limit |

## AR11 — Mitigation of other attacks (§7.12)

| RQ | Requirement | VO | Status | Evidence |
|---|---|---|---|---|
| RQ33 | mitigations of fault injection and input misuse documented (level ≥ 3) | — | RESIDUAL | RR11. The input-misuse defects F20-1, F24-1, F24-2 and F25-1 bear on it (`other-findings.md`) |
| RQ34 | blinding against timing and fault attacks on secret-key operations (level 4) | — | RESIDUAL | RR12 |

## Totals

| Status | Requirements |
|---|---|
| VIOLATED | 2 (RQ29, RQ30; one defect) |
| GAP | 11 (RQ4, RQ5, RQ8–RQ12, RQ24–RQ27) |
| PARTIAL | 9 (RQ3, RQ6, RQ7, RQ17–RQ19, RQ22, RQ23, RQ32) |
| NOT STARTED | 5 (RQ1, RQ2, RQ20, RQ21, RQ28) |
| RESIDUAL | 7 (RQ13–RQ16, RQ31, RQ33, RQ34) |
| N/A | area AR6 (no RQ) |
| **Total** | **34** |

No requirement is fully met by proof: every PARTIAL one still has open
items or rests on trusted contracts.
