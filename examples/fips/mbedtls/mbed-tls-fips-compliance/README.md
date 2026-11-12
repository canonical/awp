# Mbed TLS 3.6.7 — FIPS 140-3 compliance dossier

This dossier gathers what the auto-wp FIPS campaign established about Mbed
TLS 3.6.7 against FIPS 140-3, security level 4. It is **evidence for a
reviewer and a testing laboratory, not a validation**. Validation is the job
of an accredited CST laboratory and the CMVP. The residual-risk sign-off
(Ann. 13 of FIPS 140-3) is **PENDING**: no human has accepted the residual
risk.

## The campaign

| | |
|---|---|
| Target | Mbed TLS `mbedtls-3.6.7`, commit `068ff080b369adfac81509f9b57b2afabaf82dc5`, library sources only (`library/`) |
| Configuration | the shipped default `include/mbedtls/mbedtls_config.h`; CMake Release, no tests, no programs, static library; gcc 13.3, glibc 2.39, x86-64 |
| Target level | FIPS 140-3 level 4 (`auto-wp.py --driver fips --level 4`) |
| Method | a code-blind requirement study (`fips-sl`), then Frama-C 32.1 / WP proofs (no value analysis) and in-situ MACSL system properties; Coq for a few goals, admit-free |
| Duration | 96 hours, 2026-11-06 15:18 UTC to 2026-11-10 15:22 UTC, 27 cycles; stopped at the deadline (a pause, not a terminus) |
| Where it ran | LXD container `autowp-c-mbedtls-20261106-151748`, project `/home/ubuntu/mbedtls-analyze` |

## Verdict in one paragraph

One FIPS violation was found and reproduced: **V-1**, a crash of
`psa_close_key` and `psa_purge_key` outside the operational state, against
the finite-state-model requirements (ISO/IEC 19790 §7.11). Beyond that, the
library **as shipped lacks the mechanisms** that several FIPS 140-3 areas
require: no module error state, no integrity test, no pre-operational or
conditional self-tests run by `psa_crypto_init`, and no operator roles or
authentication (see `design-gaps.md`). A FIPS 140-3 module built on Mbed TLS
therefore needs a wrapper or integration layer that provides them. On the
code that exists, the campaign proved 223 properties over 212 functions in
31 of the 109 library files, mostly zeroization, key-export gating and
key-store state, relative to a documented trusted base. 58 files remain open.

## Contents

| File | What it holds |
|---|---|
| [`module-definition.md`](module-definition.md) | the module as the study defines it: boundary, services, roles, SSPs, interfaces, states |
| [`requirements-matrix.md`](requirements-matrix.md) | every requirement `RQ1`–`RQ34`, its ISO/IEC 19790 area, its obligation, and its status with evidence |
| [`mbed-tls-found-violations.md`](mbed-tls-found-violations.md) | the code that violates a FIPS requirement, with the clause explained |
| [`design-gaps.md`](design-gaps.md) | requirements the library cannot meet because the mechanism is absent |
| [`other-findings.md`](other-findings.md) | every other finding: library defects outside FIPS, observations, tool defects, errors in the campaign's own annotations |
| [`proof-evidence.md`](proof-evidence.md) | what was proved, how, and how far to trust it |
| [`trusted-base.md`](trusted-base.md) | the assumptions every proof rests on |
| [`residuals-and-signoff.md`](residuals-and-signoff.md) | what formal methods cannot cover, what is still open, and the pending sign-off |

## How to read the FIPS references

FIPS 140-3 adopts ISO/IEC 19790:2012 for the technical requirements and
ISO/IEC 24759:2017 for the test requirements, modified by NIST SP 800-140
and SP 800-140A to F. The FIPS 140-3 PDF names the four levels and the
eleven areas but does not reproduce the requirements. So:

- The study's requirements `RQ#` are its own paraphrases. All but RQ1 are
  marked `src:UNSOURCED`; RQ1 cites Annex 10 of the PDF.
- The ISO/IEC 19790 clause given for each area (§7.2 to §7.12) is a mapping
  from general knowledge of that standard. It was **not checked against the
  standard's text**, which is not freely available. Check it before citing
  it in a submission.

## Source files

Everything here is derived from these campaign files, in the container under
`/home/ubuntu/mbedtls-analyze/`:

- `mbedtls-analysis-fips-report.md`: the code-blind requirement study
  (F1–F5);
- `mbedtls-analysis-fips-gaps.md`: requirements without a code mechanism;
- `mbedtls-analysis-found-issues.md`: findings, cycle by cycle;
- `mbedtls.md`: the interim report generated from the ledgers;
- `mbedtls-analysis-acsl/verdicts.tsv`: the verdict ledger (391 rows);
- `mbedtls-analysis-acsl/trusted-base.md`: the trusted base;
- `mbedtls-analysis-acsl/formal-tests.tsv`: the Oracle-B test ledger;
- `mbedtls-analysis-acsl/scope-classification.tsv`: the per-file scope.

The reproducers (`mbedtls-analysis-acsl/repro/`, `scratch/c20`–`c26/`) are in
the same place.
