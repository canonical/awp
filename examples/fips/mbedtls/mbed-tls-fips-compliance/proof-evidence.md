# Proof evidence

What the campaign proved, how, and what a proof here means. The counts come
from `mbedtls.md` §1–§3, which recomputes them from the ledgers. The ledger
date is 2026-11-10; the last cycle is 27.

## What "PROVED" means

A `PROVED` row means that Frama-C/WP (or MACSL, for system properties)
discharged the stated contract on an annotated copy of the source whose text,
with the annotations stripped, equals the pristine Mbed TLS source. It holds:

- **relative to the trusted base** (`trusted-base.md`): contracts assumed for
  callees, libc and compiler behaviour;
- **for the shipped default configuration** and the as-built preprocessor
  outcome (glibc 2.39, x86-64);
- **for the stated contract only**: a proof that a `*_free` function zeroizes
  its context says nothing about the function's other behaviour.

A proof is evidence for the laboratory, never a validation.

## Method

| | |
|---|---|
| Source | `mbedtls/` kept pristine; proofs on `mbedtls-analysis-acsl/work/` = pristine + ACSL-only patches (`patches/*.patch`) |
| Faithfulness | `faithful.sh`: annotations stripped == git `HEAD` blob; `HEAD` == the pinned baseline; tree clean |
| Plane W | Frama-C 32.1 WP, provers Alt-Ergo 2.6.4, Z3 5.1.0, Qed; memory model `typed`, with a separate `bytes` pass for whole-struct zeroization; no value analysis (EVA) |
| Plane H | MACSL in-situ system properties on the real translation units (key-export gating, init-before-service, end of life) |
| Coq | a few goals, admit-free; audited with `Print Assumptions` (only the Why3 prelude parameters, classical logic and WP's definitional axioms) |
| Replay | `verify-all.sh` re-runs every `PROVED` row with `-wp-cache none`; retracted rows are honoured |
| Non-vacuity | mutation probes (`probe7.sh` to `probe10.sh`): every new proof turns red under a seeded fault; `vacuity-sweep.sh` puts `assert \false` at each proved function's entry; `-wp-smoke-tests` |
| Differential | Oracle-B (`formal-tests.tsv`): generated tests from the contracts run against the real build, with seeded faults that must turn red; plus ASan/UBSan runs |

## Headline counts

| Quantity | Value |
|---|---|
| verdict rows | 391 |
| PROVED rows (raw) | 231 |
| RETRACTED rows | 3 (cancelling 3 PROVED keys) |
| **PROVED, effective** | **223** |
| functions with an effective PROVED row | 212 |
| library `.c` files: in tree / with a proof | 109 / 31 |
| Oracle-B entries / not plain GREEN | 95 / 17 |
| scope files classified / open (A / B / C) | 78 / 58 (1 / 12 / 45) |
| out-of-scope files | 17 |
| findings | 5 (V-1, F20-1, F24-1, F24-2, F25-1) |

Verdict rows by status: PROVED 231, OBSERVATION 90, PARTIAL 27, OPEN 21,
GAP-CANDIDATE 11, RETRACTED 3, VIOLATION-WITNESS 2, VIOLATION 1, BLOCKED 1,
PENDING 1, REPAIR-PROVED 1, TOOL-DEFECT 1, WORKAROUND 1.

Effective PROVED rows by proof kind: MACSL with the bytes model 79, MACSL 58,
typed 29, bytes 22, MACSL with residuals 8, others (Coq, partial goal sets)
27. 157 of the 223 carry a MACSL tag.

## Proved functions, by file

| File | Rows | What is proved |
|---|---|---|
| `psa_crypto.c` | 140 | key-export gating (`psa_export_key`, `psa_export_public_key`), key-policy gates of the cipher, AEAD, MAC, sign and derivation entries, init-before-service, import and generate wrappers, `psa_aead_finish` 58/59 (F20-1) |
| `psa_crypto_slot_management.c` | 17 | key-store state: slot lookup after init, slot reservation, wipe and free; `mbedtls_psa_crypto_free` end of life |
| `asn1parse.c` | 12 | the DER reader: `get_len`, `get_tag`, `get_bool`, `get_bitstring`, `get_int`, `get_enum`, `get_alg`, `get_mpi`, `traverse_sequence_of`, `find_named_data` (partial file) |
| `asn1write.c` | 9 | the DER writer: `write_len`, `write_tag`, `write_len_and_tag`, `write_bool`, `write_int`, … (partial file) |
| `ecp.c` | 9 | `ecp_point_free`, `ecp_group_free` (88/94 whole function), `ecp_keypair_free` |
| `base64.c` | 3 | constant-time character mapping, `base64_encode` (partial file) |
| `md.c`, `md5.c`, `ripemd160.c`, `sha1.c`, `sha256.c`, `sha512.c` | 1–2 each | `*_free` zeroization; `*_starts` |
| `platform_util.c` | 2 | `mbedtls_platform_zeroize` 7/7; `mbedtls_zeroize_and_free` |
| `dhm.c`, `des.c` | 2 each | `*_free` zeroization |
| `aes.c`, `aria.c`, `camellia.c`, `ccm.c`, `chacha20.c`, `chachapoly.c`, `gcm.c`, `poly1305.c`, `sha3.c`, `bignum.c`, `rsa.c`, `ecdsa.c` | 1 each | `*_free` zeroization |
| `ctr_drbg.c`, `hmac_drbg.c` | 1 each | `*_free` zeroization of the whole DRBG state (Coq) |
| `hkdf.c` | 1 | `mbedtls_hkdf_expand` 103/103, including "output untouched on error" under SL-MD-2 |
| `constant_time.c` | 1 | `mbedtls_ct_bool`, `ct_bool_not`, `ct_size_if_else_0` (values, not timing) |

## What was not covered

- **58 open files**: 45 class C (provable with more contracts), 12 class B
  (cryptographic strength or entropy, outside WP), 1 class A (a tool limit).
- **3 files never enumerated**: `entropy_poll.c` (needs `getrandom`),
  `pk.c`, `psa_crypto_storage.c` (TOOL-1).
- **Outside `library/`**: the programs, the tests, and most of the TLS stack.
- **Side channels** beyond the constant-time helpers' values.
- **Non-default configurations**: OBS-1 shows a property that holds only in
  the default one.
