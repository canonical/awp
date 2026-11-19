# Residuals and sign-off

_PAUSED/IN PROGRESS — interim; not a terminus. Generated from the ledgers by `openssl-4.1.0-analysis-acsl/tools/gen-interim-report.py`; do not hand-edit. Sign-off ☐ PENDING._

The campaign is **paused at the deadline/interim checkpoint, not at its terminus**.

## F5 residual register (from the study)

| RR# | names | plane | treatment |
|---|---|---|---|
| RR1 | RQ1 | validation | the Approved-functions list (SP 800-140C, SP 800-140D) is transcribed, not proven; VO1 checks reachability only; the CMVP validation and the algorithm certificates cover the list — leaves open RQ1. |
| RR2 | RQ4 | validation | the per-level requirements of ISO/IEC 19790 and the SP 800-140 series are outside the corpus; the level-4 target for a software-only module is likely not attainable as an overall level (outside knowledge); the laboratory decides the per-area levels — leaves open RQ4. |
| RR3 | RQ11 | crypto | the strength of any operator authentication mechanism (SP 800-140E) is out of formal reach; the public description documents no authentication, so RQ11 is expected to be a design gap — leaves open RQ11 FM10. |
| RR4 | RQ14 — RQ15 | crypto | the integrity technique itself is trusted; VO12 covers its ordering only; whether a keyed MAC with a public key meets the level-3+ digital-signature expectation is a design question for the laboratory — leaves open RQ15. |
| RR5 | RQ18 — RQ20 — RQ21 | ENV | process isolation and file access control belong to the operating environment (RQ18, RQ20); for RQ21 only its external dependencies stay here (the core loading MOD1 with its installed configuration, and the operating system protecting that configuration), while its internal enforcement is VO29; deployment guidance and platform hardening — leaves open RQ18 RQ20 RQ21. |
| RR6 | RQ19 | crypto | the quality of the entropy source outside the boundary (SP 800-90B, the entropy-source validation) is out of formal reach; VO14 covers only the fail-closed handling of its quantity — leaves open RQ19. |
| RR7 | RQ22 — RQ23 — RQ24 | side-channel | constant-time analysis tooling (dudect, ctgrind, binary-level timing analysis) and laboratory leakage assessment against the SP 800-140F metrics, not WP — leaves open RQ22 RQ23 RQ24. |
| RR8 | RQ32 — RQ25 — RQ26 | supply-chain | a compiler or linker may remove the clearing stores proved by VO15 and VO16; binary inspection of the clearing primitive and a reproducible build — leaves open RQ32. |
| RR9 | RQ28 | logic | the trusted-channel element is N/A for MOD1 as defined in F1 (electronic, in-process, no path off the host; UNSOURCED reading); the indicator is not channel protection; the laboratory confirms the perimeter reading, and transport of a delivered SSP off the host is the caller's (EN9) — leaves open RQ28. |
| RR10 | RQ33 — RQ34 — RQ35 — RQ36 | crypto | adequacy of the known-answer vectors and of the DRBG and entropy health-test parameters is out of formal reach; ACVP algorithm testing — leaves open RQ34 RQ36. |
| RR11 | RQ40 — RQ41 — RQ42 | logic | configuration management, delivery, guidance documents and the component pre/postcondition documentation are life-cycle evidence; the contracts produced downstream by the formal campaign are evidence toward RQ42, reviewed by the laboratory — leaves open RQ40 RQ41 RQ42. |
| RR12 | RQ43 | logic | fault-injection countermeasures are assessed by design review and fault-injection testing, not WP — leaves open RQ43. |
| RR13 | RQ44 | side-channel | padding-oracle resistance in content is reviewable, in timing it needs constant-time tooling; implicit-rejection review and timing measurement — leaves open RQ44. |
| RR14 | RQ45 | logic | per-key IV uniqueness depends on the IV-generation design and on caller behaviour; design review against the public implementation guidance — leaves open RQ45. |
| RR15 | AR6 | physical | not applicable: no physical enclosure; the level-4 physical and environmental-failure protections, if required, belong to the host platform — STANDING. |
| RR16 | AR5 | ENV | the general-purpose, modifiable operating environment is outside the module boundary; operating-system hardening — STANDING. |
| RR17 | AR7 | side-channel | constant-time tooling and leakage assessment, not WP — STANDING. |
| RR18 | STANDING | crypto | strength of the cryptographic primitives; KAT vectors and ACVP certificates — STANDING. |
| RR19 | STANDING | supply-chain | compiler correctness including removed zeroization, and the integrity of the toolchain and dependencies; SLSA and reproducible build — STANDING. |
| RR20 | STANDING | validation | the CMVP validation itself; a proof is evidence for the laboratory, not a validation; conformance "is not sufficient to ensure that a particular module is secure" (Ann. 13) — STANDING. |
| RR21 | FM5 — FM25 — FM26 | logic | the system-level obligations VO5, VO25 and VO26 (and the other system-level classes) count as treated only with a derived leaf ensures or a named TCB axiom; a ghost model with a postulated ensures is vacuous and must be rejected by the monitor's ghost-antecedent audit — leaves open FM5 FM25 FM26. |
| RR22 | FM5 | logic | vector (d) of FM5, a thread racing the ST4 transition, is out of reach of a sequential proof model; concurrency review or model checking — leaves open FM5. |
| RR23 | RQ47 — FM29 | logic | the streaming authenticated-decryption interface releases tentative plaintext before the tag check; this depends on the caller obligation EN8 and is a level-4 design-gap candidate for the laboratory; FE4 covers finalization and one-shot paths by functional evidence — leaves open RQ47 FM29. |
| RR24 | RQ48 — FM32 | logic | functional evidence FE2 (runtime-error and length contracts proved downstream, plus fuzzing); no property class expresses bounds — leaves open RQ48 FM32. |
| RR25 | RQ30 — FM31 | logic | functional evidence FE1 against the validation steps of the approved key-establishment and signature standards, plus ACVP key-validation vectors — leaves open RQ30 FM31. |
| RR26 | RQ2 — RQ46 — RQ5 | logic | functional evidence FE3; VO2 and VO28 prove the state discipline only, the thresholds come from the SP 800-140C and SP 800-131A tables the laboratory checks — leaves open RQ2 RQ46 RQ5. |
| RR27 | RQ49 — RQ27 | ENV | SSPs delivered through PO1–PO5 into caller-owned memory, including data passed to an export callback (an irreversible boundary crossing), are protected and cleared by the calling application (EN9); application guidance and review — leaves open RQ49. |
| RR28 | RQ50 | validation | per algorithm, whether an imported-key test failure is a conditional self-test that moves MOD1 to ST4 or only an import rejection is a policy decision for the laboratory — leaves open RQ50. |

## Open items

- 918 latest-status RESIDUE(C) rows (next actions in the campaign report).
- 12 violations to remediate or adjudicate: FI-1, FI-2, FI-3, FI-4, FI-5, FI-6, FI-7, FI-8, FI-9, FI-10, FI-11, FI-14.
- 21 trusted-base entries parsed as OPEN (reducible); 4 as OPEN irreducible-candidate (audit owed).
- 114 in-scope units without a verdict row.
- formal-tests.tsv and scope-classification.tsv: not yet produced.

## Gate T, item by item

| item | check | status | evidence |
|---|---|---|---|
| 1 | ENUMERATION-COMPLETE | computed-FAIL | 319 units enumerated in unit-coverage.tsv: 216 in scope (VO#-mapped), 103 OUT-OF-SCOPE-BY-ROLE (0 without a written reason). In-scope units with no verdict row yet: 114. |
| 2 | GOAL-STATUS-COMPLETE | computed-FAIL | 918 latest-status RESIDUE(C) rows (bare class C = open goal). |
| 3 | GATE-S TCB-CLEAN | computed-FAIL (parsed) | 21 trusted-base entries whose latest parsed status is OPEN and REDUCIBLE: HG-3, HG-3', HS-3, HS-5, HS-6, OB-bn_callees-c92, OB-ob_block-c92, Z2-8, Z2-9, Z2-11, Z2-14, Z2-16, Z2-17, Z2-18, Z2-19, Z2-20, Z2-21, Z2-25, Z2-40, ZS-1, ZS-2. |
| 4 | TWO-ORACLE | computed-FAIL | openssl-4.1.0-analysis-acsl/formal-tests.tsv: not yet produced. |
| 5 | GATE-R RECONCILED | computed-PASS (this generator; byte-identical regeneration is checked by the caller) | Report regenerated from verdicts.tsv by this script; 2306 raw rows == sum of raw counts 2306; every FI cited by a VIOLATION row has a found-issues heading: yes. |
| 6 | VERDICT-PROVENANCE | NOT COMPUTABLE | Needs the coordinator's audit of delivered verifier reports; not derivable from the ledgers. |

## What the campaign did not do

- No CMVP validation, no CST laboratory testing, no ACVP algorithm testing.
- No side-channel, physical or operating-environment analysis (planes side-channel, physical, ENV).
- No concurrency proof (sequential WP model); race vectors are routed out of plane.
- No binary-level check that zeroization survives compilation (plane supply-chain).
- No differential (Oracle B) tests yet.

## Sign-off

**☐ PENDING.** The owner of the protected information, or the agency's responsible authority, has not signed. Before signing, the authority must weigh: the open violations (and whether on-demand self-test output and deferred self-tests are acceptable under the module's Security Policy), the design gaps, the open RESIDUE(C) goals, the open trusted-base entries, the standing residuals RR15–RR20, and the fact that the campaign is interim.

Study F5 line: Sign-off: ☐ PENDING — the owner of the protected information, or the agency's responsible authority, acknowledges and accepts the residual risk (Ann. 13).
