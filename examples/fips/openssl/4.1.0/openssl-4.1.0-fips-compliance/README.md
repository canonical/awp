# openssl-4.1.0 — FIPS 140-3 compliance dossier

_PAUSED/IN PROGRESS — interim; not a terminus. Generated from the ledgers by `openssl-4.1.0-analysis-acsl/tools/gen-interim-report.py`; do not hand-edit. Sign-off ☐ PENDING._

This dossier is **evidence for a CST testing laboratory, not a validation**. Only the CMVP validates a module; a proof here supports a requirement, it never certifies it. The residual-risk sign-off is **PENDING** until the owner of the protected information, or the agency's responsible authority, signs (FIPS 140-3 Ann. 13). The campaign is **paused at the deadline/interim checkpoint, not at its terminus**; the open items are listed in `residuals-and-signoff.md`.

## Target

| field | value |
|---|---|
| name | openssl-4.1.0 |
| module | MOD1 — the FIPS provider of OpenSSL 4.1.0 — a dynamically loadable software cryptographic module |
| version | 4.1.0 |
| commit | n/a — the source tree is not a git checkout; baseline = `openssl-4.1.0-analysis-acsl/pristine.sha256` (sha256 of that manifest: `ca471bd454eca7c8ae96d37910e7d83a78356bbac12c195ccb6b17e0212125e4`) |
| configuration | `./Configure enable-fips`, FIPS_MODULE compile entries (see `openssl-4.1.0-analysis-acsl/README.md`) |
| target level | 4 (config/auto-wp.json `fips_level`; study F1 `level: 4`) |
| driver | fips |
| method | PURE WP and MACSL (Frama-C/WP on the real units; macsl system properties in-situ) |
| campaign start | 2026-11-16T19:07:38Z (epoch 1794856058) |
| deadline | 2026-11-20T19:07:38Z (epoch 1795201658) |
| last wake | 2026-11-19T17:30:45Z (epoch 1795109445) |
| stop reason | none recorded — interim pause, not a terminus |

## Verdict (one paragraph, computed)

Of 51 requirement rows (50 RQ# + 1 N/A area), the matrix stands at 17 VIOLATED, 12 NOT STARTED, 17 RESIDUAL, 3 GAP, 1 PARTIAL, 1 N/A. The ledger holds 2306 verdict rows over 1685 keys, latest status 610 VERIFIED, 146 VIOLATION and 918 RESIDUE(C) (open). 24 findings are recorded (FI-1…FI-24), 12 of them violations of a study requirement. The campaign is not at its terminus: Gate T fails on the items listed in `residuals-and-signoff.md`.

## Files

- [`README.md`](README.md) — this file
- [`module-definition.md`](module-definition.md) — F1 transcribed, and how the code maps to it
- [`requirements-matrix.md`](requirements-matrix.md) — one row per RQ#, status and evidence
- [`openssl-4.1.0-found-violations.md`](openssl-4.1.0-found-violations.md) — violations of study requirements
- [`design-gaps.md`](design-gaps.md) — requirements whose mechanism is absent
- [`other-findings.md`](other-findings.md) — every other finding
- [`proof-evidence.md`](proof-evidence.md) — what PROVED means; counts
- [`trusted-base.md`](trusted-base.md) — the trusted base, parsed
- [`residuals-and-signoff.md`](residuals-and-signoff.md) — F5 residuals, open items, Gate T, sign-off PENDING

## FIPS-reference caveat

The study's requirements are mostly `src:UNSOURCED` paraphrases (rule F3): the vendored FIPS 140-3 PDF names the levels and areas but holds almost none of the per-area requirements. The ISO/IEC 19790:2012 clause of each area is given from general knowledge of that standard, which is not vendored in this project (it is a paid standard). The clause numbers are **unchecked against the standard's text**; none of them is presented as verified.

Study, F5: **UNSOURCED surfaced (rule F3):** 48 of 50 requirements are `src:UNSOURCED` — the author's reading of the area at

## Sources

- `openssl-4.1.0-analysis-fips-report.md`
- `openssl-4.1.0-analysis-fips-gaps.md`
- `openssl-4.1.0-analysis-found-issues.md`
- `openssl-4.1.0-analysis-acsl/verdicts.tsv`
- `openssl-4.1.0-analysis-acsl/trusted-base.md`
- `openssl-4.1.0-analysis-acsl/time-loop.state`
- `openssl-4.1.0-analysis-acsl/unit-coverage.tsv`
- `config/auto-wp.json`
- `openssl-4.1.0-analysis-acsl/formal-tests.tsv` — not yet produced
- `openssl-4.1.0-analysis-acsl/scope-classification.tsv` — present
- the campaign report `openssl-4.1.0.md`
