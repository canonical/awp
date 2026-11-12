# Residuals, open items and sign-off

## Residual register

From section F5 of the requirement study. Each residual names a requirement
that formal verification of the code cannot settle, and the other technique
that must. "Leaves open" means the requirement stays open until that
technique is applied.

| RR | Requirement | Plane | Treatment |
|---|---|---|---|
| RR1 | RQ1 | validation | the Approved-functions list and the approved-mode claim, checked by call-graph review; the CMVP validation covers them |
| RR2 | RQ7 | crypto | strength of the authentication mechanism: KAT vectors and review |
| RR3 | RQ10 | crypto | the integrity technique is trusted; a proof covers ordering only |
| RR4 | RQ13 | environment | memory isolation is the operating system's; platform review |
| RR5 | RQ14 | logic | build and run configuration: documented procedure and reproducible build |
| RR6 | RQ15 | side channel | constant-time tooling and leakage assessment |
| RR7 | RQ16 | side channel | the documented mitigations, tested by leakage assessment |
| RR8 | RQ19 | supply chain | the compiler or linker may remove or weaken zeroization: SLSA and reproducible build |
| RR9 | RQ20 | crypto | entropy quality of the platform source: statistical assessment |
| RR10 | RQ31 | logic | configuration management and delivery are procedural |
| RR11 | RQ33 | logic | fault and misuse mitigations are reviewed and tested, not proved |
| RR12 | RQ34 | side channel | blinding effectiveness: leakage and fault testing |
| RR13 | RQ17 | supply chain | dead-store elimination of the clearing: build checks and binary inspection |
| RR14 | RQ6 | validation | trusted-channel strength at level 4 is judged by the laboratory |
| RR15 | RQ9 | logic | role separation relies on the calling application |
| RR16 | AR5 | environment | the operating environment is outside the module boundary (standing) |
| RR17 | AR6 | physical | no enclosure; level 4 physical controls rest on the platform (standing) |
| RR18 | AR7 | side channel | constant-time tooling and leakage assessment (standing) |
| RR19 | — | crypto | strength of the primitives: KAT vectors (standing) |
| RR20 | — | supply chain | compiler correctness, including removed zeroization (standing) |
| RR21 | — | validation | the CMVP validation itself: a proof is evidence, not a validation (standing) |

## Open items at the stop

The campaign stopped at its 96-hour deadline. That is a pause, not a
terminus.

- **58 open scope files**: 45 class C, 12 class B, 1 class A.
- **3 partially covered files**: `asn1parse.c`, `asn1write.c`, `base64.c`.
- **10 reducible trusted-base entries** still open (`trusted-base.md`).
- **Unproved verdict rows**: PARTIAL 27, OPEN 21, GAP-CANDIDATE 11,
  BLOCKED 1, TOOL-DEFECT 1, VIOLATION 1.
- **17 of 95 Oracle-B entries** are not plain GREEN.
- **3 files never enumerated**: `entropy_poll.c`, `pk.c`,
  `psa_crypto_storage.c`.
- **Pending patch**: a `base64_decode` patch takes decode from 112/132 to
  127/134 but regresses encode from 153/153 to 150/153; it is held in
  `patches-pending/`.
- **Next levers named by the campaign**: keep the base64 lemmas out of
  encode's goals, then the reducible trusted-base entries, then the 45 class
  C files.

## Gate T (the terminus checklist)

| Item | Result |
|---|---|
| 1. every library file enumerated | FAIL (57 enumerated files still unverified) |
| 2. — | needs a human judgement |
| 3. reducible trusted base retired | FAIL (10 open) |
| 4. Oracle-B harness for every Tier-1 function | FAIL (51 `psa_*` functions with a proof and no Oracle-B entry) |
| 5. report reconciled with the ledger | needs a human judgement |
| 6. verdict provenance | needs a human judgement |

## Not done by the campaign

- a disjoint completeness and realism review of the requirement study;
- the coordinator's judgement on Gate T items 2, 5 and 6;
- the residual-risk sign-off.

## Sign-off

☐ **PENDING.** The owner of the protected information, or the agency's
responsible authority, acknowledges and accepts the residual risk (FIPS
140-3 Annex 13). The campaign never signs; this dossier does not either.

Before signing, the authority should weigh:

1. the violation V-1 and its fix (`mbed-tls-found-violations.md`);
2. the design gaps G1–G4 and the wrapper that must close them
   (`design-gaps.md`);
3. the 33 requirements marked `src:UNSOURCED`, whose wording is the
   study's and not the standard's;
4. the residuals above, each needing its own technique;
5. the open items, since the campaign did not reach its terminus.
