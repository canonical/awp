# openssl-4.1.0 — found violations

_PAUSED/IN PROGRESS — interim; not a terminus. Generated from the ledgers by `openssl-4.1.0-analysis-acsl/tools/gen-interim-report.py`; do not hand-edit. Sign-off ☐ PENDING._

12 findings violate a study requirement (every FI whose heading cites a VO#). Severity: the ledgers assign none and the dossier adds none; the obligation priority is shown instead. The ISO/IEC 19790:2012 clause of each area is given from general knowledge of that standard, which is not vendored in this project (it is a paid standard). The clause numbers are **unchecked against the standard's text**; none of them is presented as verified.

## FI-1 — VO5/VO32 output-inhibit: services produce output while the module is in SELFTEST during an on-demand self-test

| field | value |
|---|---|
| functions (verdict rows) | ossl_prov_is_running (`providers/fips/self_test.c`, L47, RESIDUE(C) 0/1) |
| VO# / priority | VO5 P1 (output-inhibit), VO32 P1 (selftest-order) |
| RQ# | RQ6, RQ38 |
| FM# | FM5, FM34 |
| area / ISO/IEC 19790 clause (unchecked) | AR2 §7.3, AR9 §7.10 |

### Defect, reproduction, evidence (found-issues, verbatim)

- **Obligation:** VO5 (output-inhibit, P1) — no data output in pre-operational or error state by any path; VO32.
- **Evidence (delivered, h-selftest cycle 3):** macsl in-situ on `providers/fips/self_test.c`: the literal policy "gate ⇒ RUNNING only" on `ossl_prov_is_running` is [Unknown]; the gate returns true for `RUNNING || SELFTEST` (the weaker policy proves 1/1, attack A3 discriminates).
- **Trigger (call trace):** Thread A: `OSSL_PROVIDER_self_test` → `ossl_provider_self_test` (crypto/provider_core.c:1858) → `fips_self_test` (providers/fips/fipsprov.c:191) → `SELF_TEST_post(...,1)` sets RUNNING→SELFTEST (self_test.c:321) and runs the KATs holding `self_test_lock` + the deferred lock. Concurrent thread B on the same libctx: `EVP_Digest*` → digest newctx/init/final (providers/implementations/include/prov/digestcommon.h:60/71/78/100/136) each gated only by `ossl_prov_is_running()` (true in SELFTEST); no service path takes `self_test_lock`. B obtains digest output during A's self-test.
- **Not reachable at POST (module load):** the dispatch table is published (fipsprov.c:1016) only after POST passes.
- **Status:** VIOLATION of the report's VO5 as worded. Whether FIPS 140-3 permits service output during an on-demand (non-pre-operational) self-test is a policy question for the responsible authority (F5); recorded, not waived.

### The clause explained

- **RQ6 demands** (src:UNSOURCED): no data output on IF2 while MOD1 is in ST2 or ST4, by any service and any path.
- **RQ38 demands** (src:UNSOURCED): trigger 4, on-demand self-test: SV11 re-runs the pre-operational test and the cryptographic algorithm self-tests, with services inhibited while it runs; its failure has the effect of RQ37.
- **VO5 obliges:** once MOD1 is in ST2 or ST4, no service by any path writes data output; close each vector (a)–(e) of FM5 separately.
- **VO32 obliges:** trigger 4, on-demand: SV11 runs every pre-operational and algorithm self-test, and no service produces output while it runs.
- **Why the code contradicts it:** VO5/VO32 output-inhibit: services produce output while the module is in SELFTEST during an on-demand self-test (see the trigger above).

### Precondition, severity, fix

- Precondition/configuration: as stated in the evidence above.
- Severity: not assigned by the ledgers; obligation priority P1, P1.
- Fix: none recorded in the ledgers.

## FI-2 — VO15/VO16 zeroize: KMAC key replacement leaves old key bytes; encoded-key stack temp not cleansed

| field | value |
|---|---|
| functions (verdict rows) | kmac_free (`providers/implementations/macs/kmac_prov.c`, L58, RESIDUE(C) 18/18); kmac_setkey (`providers/implementations/macs/kmac_prov.c`, L59, RESIDUE(C) -); kmac_setkey (`providers/implementations/macs/kmac_prov.c`, L111, RESIDUE(C) -) |
| VO# / priority | VO15 P1 (zeroize), VO16 P1 (zeroize) |
| RQ# | RQ25, RQ26 |
| FM# | FM15, FM16 |
| area / ISO/IEC 19790 clause (unchecked) | AR8 §7.9 |

### Defect, reproduction, evidence (found-issues, verbatim)

- **Evidence (delivered, w-zeroize-2 cycle 4):** WP probe "byte key[key_len] survives kmac_free" is Valid on the real `providers/implementations/macs/kmac_prov.c`; `kmac_free` clears only `key[0..key_len)` of a fixed-size buffer and `kmac_setkey` overwrites only the prefix.
- **Trigger:** `openssl-4.1.0-analysis-acsl/probes/wz2/runtime/kmac_residue.c` — init with a 512-byte key, re-init with a 16-byte key, free: the freed 1256-byte context still holds ≥64 bytes of the first key (control without replacement: none). Runtime run against the non-FIPS libcrypto build; the same source is compiled into the FIPS module.
- **VO16 (code reading):** stack buffer `tmp` in `kmac_bytepad_encode_key` holds the encoded key and is never cleansed.

### The clause explained

- **RQ25 demands** (src:UNSOURCED): every SSP in provider-owned memory is zeroized when no longer referenced: on free (SV13); on replacement (a key or parameter set over an existing one); on successful and failed import and set; on every temporary copy made for get or export, on success, failure and callback rejection or cancellation; on successful duplication when the copy is later freed, and on a failed duplication for the partial copy; and on every error path of the service that created or loaded it.
- **RQ26 demands** (src:UNSOURCED): provider-owned intermediate secrets (SSP4 during reseed and uninstantiate, SSP5 before delivery, SSP6, SSP7, decoding and encoding buffers of import and export) are zeroized as soon as they are no longer needed, on success and on failure.
- **VO15 obliges:** every SSP in provider-owned memory is cleared on each vector (a)–(j) of FM15: free, replacement, import and set on success and failure, get and export temporaries on success, failure and callback rejection or cancellation, duplication, re-initialization, key-generation early returns.
- **VO16 obliges:** every provider-owned intermediate secret named in FM16 is cleared before the service returns, on success and on failure.
- **Why the code contradicts it:** VO15/VO16 zeroize: KMAC key replacement leaves old key bytes; encoded-key stack temp not cleansed (see the trigger above).

### Precondition, severity, fix

- Precondition/configuration: as stated in the evidence above.
- Severity: not assigned by the ledgers; obligation priority P1, P1.
- Fix: none recorded in the ledgers.

## FI-3 — VO22/RQ34 selftest-order: with defer-tests configured, the module becomes operational before its KATs run (configuration-dependent)

> **Configuration-dependent** (see the evidence below for the triggering configuration).

| field | value |
|---|---|
| functions (verdict rows) | SELF_TEST_kats (`providers/fips/self_test_kats.c`, L65, RESIDUE(C) 40/53) |
| VO# / priority | VO22 P1 (selftest-order) |
| RQ# | RQ34 (cited: RQ34) |
| FM# | FM22 |
| area / ISO/IEC 19790 clause (unchecked) | AR9 §7.10 |

### Defect, reproduction, evidence (found-issues, verbatim)

- **Evidence (h-errstate cycle 4):** WP witness on `SELF_TEST_kats` (all tests DEFER at entry ⇒ no KAT runs, all still DEFER) Valid.
- **Trace:** `SELF_TEST_post` marks INIT tests DEFER (self_test.c:366-374) → `SELF_TEST_kats` runs only INIT tests (self_test_kats.c:1317) → RUNNING (self_test.c:419); each KAT then runs at first use (e.g. AES-256-GCM newctx → CIPHER_PROV_CHECK → ossl_deferred_self_test → FIPS_kat_deferred → SELF_TEST_kats_execute). Each service still self-tests before its own output; the breach is operational-before-KATs, which RQ34 rev2 does not admit.
- **Default `defer_tests=0` is compliant.** Note: `fipsinstall -pedantic -defer_tests` is accepted (apps/fipsinstall.c:778 lacks the `check_non_pedantic_fips` guard other options have).
- Policy: deferral acceptability is for the responsible authority (F5) against the module's Security Policy.

### The clause explained

- **RQ34 demands** (src:UNSOURCED): trigger 1, startup known-answer tests: the cryptographic algorithm self-test of every Approved security function completes with a pass before MOD1 enters ST3 and any service becomes available; deferral of a test to first use is not admitted, because this study cites no pinned public documentation of the target version that permits it; if a later cycle cites such documentation, the deferral must be recorded per algorithm in F2 and F5.
- **VO22 obliges:** trigger 1, startup KATs: on every path from load, every Approved security function's known-answer test has completed with a pass before MOD1 enters ST3; any deferral to first use is reported as a violation of RQ34 unless recorded under its cited documentation.
- **Why the code contradicts it:** VO22/RQ34 selftest-order: with defer-tests configured, the module becomes operational before its KATs run (configuration-dependent) (see the trigger above).

### Precondition, severity, fix

- Precondition/configuration: as stated in the evidence above.
- Severity: not assigned by the ledgers; obligation priority P1.
- Fix: none recorded in the ledgers.

## FI-4 — VO27/VO25 error-state: keygen pairwise-consistency-test failures never enter the module error state

| field | value |
|---|---|
| functions (verdict rows) | rsa_keygen_pairwise_test (`crypto/rsa/rsa_gen.c`, L66, RESIDUE(C) 1/2); ml_dsa_gen (PCT) (`providers/implementations/keymgmt/ml_dsa_kmgmt.c`, L210, RESIDUE(C) 3/9); ml_dsa_gen (PCT-fail=>ERROR) (`providers/implementations/keymgmt/ml_dsa_kmgmt.c`, L316, RESIDUE(C) 1/2); PCT branch of ossl_set_error_state (self_test.c:454-458) (`providers/fips/self_test.c`, L324, RESIDUE(C) -); rsa_keygen_pairwise_test (C3 compliant copy and real code, gate when check==1) (`crypto/rsa/rsa_gen.c`, L326, RESIDUE(C) 0/1); ml_dsa_gen (PCT-fail=>ERROR) (`providers/implementations/keymgmt/ml_dsa_kmgmt.c`, L342, RESIDUE(C) 0/1); rsa_keygen_pairwise_test (real gate, re-run with faithful memcmp) (`crypto/rsa/rsa_gen.c`, L869, RESIDUE(C) 3/5); rsa_keygen_pairwise_test (attack C3 compliant, re-run with faithful memcmp) (`crypto/rsa/rsa_gen.c`, L898, RESIDUE(C) 39/40); rsa_keygen_pairwise_test (real gate, re-run with faithful memcmp) (`crypto/rsa/rsa_gen.c`, L899, RESIDUE(C) 36/37); rsa_keygen_pairwise_test (real gate, re-run with faithful memcmp) (`crypto/rsa/rsa_gen.c`, L941, RESIDUE(C) -) |
| VO# / priority | VO25 P1 (error-state), VO27 P1 (error-state) |
| RQ# | RQ35, RQ37, RQ38, RQ50 |
| FM# | FM23, FM25, FM30 |
| area / ISO/IEC 19790 clause (unchecked) | AR9 §7.10 |

### Defect, reproduction, evidence (found-issues, verbatim)

- **Evidence (h-errstate cycle 4):** WP witness "rsa_keygen_pairwise_test never enters error state" Valid on the real `crypto/rsa/rsa_gen.c`; on a fixed copy calling `ossl_set_error_state(PCT)`, PCT⇒error is Valid.
- **Trace:** tree-wide, `ossl_set_error_state` is called only from self_test.c (POST), fipsprov.c (deferred KAT) and the jitter source (disabled in this build). RSA/EC/DSA/ECX/ML-DSA/ML-KEM PCT failure paths only clear/free the key and return 0/NULL. Consequence: the PCT branch of `ossl_set_error_state` is dead, and `conditional_error_check` (fipsprov.c:996) has no effect.
- **Trigger:** any PCT failure, e.g. corrupt the RSA PCT through the `oncorrupt` self-test callback; the module stays RUNNING.

### The clause explained

- **RQ35 demands** (src:UNSOURCED): trigger 2, generated-key pairwise consistency test: a pairwise consistency test runs on each generated asymmetric key pair (RSA, ECDSA, EdDSA, finite-field and elliptic-curve key-agreement keys, lattice- and hash-based signature and KEM keys) before the key is used or output; a failure moves MOD1 to ST4.
- **RQ37 demands** (src:UNSOURCED): any self-test failure moves MOD1 to ST4 persistently: every service then returns an error with no data output until the module is unloaded and reloaded.
- **RQ38 demands** (src:UNSOURCED): trigger 4, on-demand self-test: SV11 re-runs the pre-operational test and the cryptographic algorithm self-tests, with services inhibited while it runs; its failure has the effect of RQ37.
- **RQ50 demands** (src:UNSOURCED): trigger 3, imported-key consistency test: when a key pair is imported or both its parts are set (RSA, ECDSA, EdDSA, finite-field and elliptic-curve key-agreement keys, lattice-based keys), a pairwise consistency test or the prescribed key-pair validation runs before first use; on failure the import fails and no usable key object results; whether the failure also moves MOD1 to ST4 is per algorithm per the documented policy (open item RR28); N/A to symmetric keys and public-only imports.
- **VO25 obliges:** once any self-test (pre-operational, conditional or on demand) fails, MOD1 is in ST4 and stays there: every subsequent service call fails with no output until reload.
- **VO27 obliges:** a failed generated-key pairwise consistency test moves MOD1 to ST4 for every algorithm listed in RQ35; a failed imported-key test for an algorithm listed in RQ50 fails the import with no usable key object and, where the documented policy classifies it as a conditional self-test, moves MOD1 to ST4; N/A to symmetric keys and public-only imports.
- **Why the code contradicts it:** VO27/VO25 error-state: keygen pairwise-consistency-test failures never enter the module error state (see the trigger above).

### Precondition, severity, fix

- Precondition/configuration: as stated in the evidence above.
- Severity: not assigned by the ledgers; obligation priority P1, P1.
- Fix: none recorded in the ledgers.

## FI-5 — VO25/VO27 error-state: CRNG continuous-test failure sets only a local, non-absorbing state

| field | value |
|---|---|
| functions (verdict rows) | crng_test (`providers/implementations/rands/fips_crng_test.c`, L67, RESIDUE(C) 2/3); crng_test_get_seed (`providers/implementations/rands/fips_crng_test.c`, L68, RESIDUE(C) 0/2); crng_test (real) (`providers/implementations/rands/fips_crng_test.c`, L371, RESIDUE(C) 0/1); crng_test (attack C1, compliant copy, -wp-literals) (`providers/implementations/rands/fips_crng_test.c`, L383, VERIFIED 1/1) |
| VO# / priority | VO25 P1 (error-state), VO27 P1 (error-state) |
| RQ# | RQ35, RQ37, RQ38, RQ50 |
| FM# | FM23, FM25, FM30 |
| area / ISO/IEC 19790 clause (unchecked) | AR9 §7.10 |

### Defect, reproduction, evidence (found-issues, verbatim)

- **Evidence (h-errstate cycle 4):** WP witness "crng_test never enters module error" Valid on the real `providers/implementations/rands/fips_crng_test.c`.
- **Trace:** `crng_test` sets only the local `EVP_RAND_STATE_ERROR`; `crng_test_get_seed`/`crng_test_generate` never check it; `instantiate` resets it to READY.
- **Trigger:** an RCT/APT failure on one call, then fresh entropy on the next call returns seed output.

### The clause explained

- **RQ35 demands** (src:UNSOURCED): trigger 2, generated-key pairwise consistency test: a pairwise consistency test runs on each generated asymmetric key pair (RSA, ECDSA, EdDSA, finite-field and elliptic-curve key-agreement keys, lattice- and hash-based signature and KEM keys) before the key is used or output; a failure moves MOD1 to ST4.
- **RQ37 demands** (src:UNSOURCED): any self-test failure moves MOD1 to ST4 persistently: every service then returns an error with no data output until the module is unloaded and reloaded.
- **RQ38 demands** (src:UNSOURCED): trigger 4, on-demand self-test: SV11 re-runs the pre-operational test and the cryptographic algorithm self-tests, with services inhibited while it runs; its failure has the effect of RQ37.
- **RQ50 demands** (src:UNSOURCED): trigger 3, imported-key consistency test: when a key pair is imported or both its parts are set (RSA, ECDSA, EdDSA, finite-field and elliptic-curve key-agreement keys, lattice-based keys), a pairwise consistency test or the prescribed key-pair validation runs before first use; on failure the import fails and no usable key object results; whether the failure also moves MOD1 to ST4 is per algorithm per the documented policy (open item RR28); N/A to symmetric keys and public-only imports.
- **VO25 obliges:** once any self-test (pre-operational, conditional or on demand) fails, MOD1 is in ST4 and stays there: every subsequent service call fails with no output until reload.
- **VO27 obliges:** a failed generated-key pairwise consistency test moves MOD1 to ST4 for every algorithm listed in RQ35; a failed imported-key test for an algorithm listed in RQ50 fails the import with no usable key object and, where the documented policy classifies it as a conditional self-test, moves MOD1 to ST4; N/A to symmetric keys and public-only imports.
- **Why the code contradicts it:** VO25/VO27 error-state: CRNG continuous-test failure sets only a local, non-absorbing state (see the trigger above).

### Precondition, severity, fix

- Precondition/configuration: as stated in the evidence above.
- Severity: not assigned by the ledgers; obligation priority P1, P1.
- Fix: none recorded in the ledgers.

## FI-6 — VO5/VO8 output-inhibit: cipher update paths produce ciphertext after ERROR (gate only at ctx creation)

> **Caveat: trace-confirmed; witness owed.** Kept as a violation; the machine witness is not yet produced.

| field | value |
|---|---|
| functions (verdict rows) | ossl_cipher_generic_stream_update (`providers/implementations/ciphers/ciphercommon.c`, L98, RESIDUE(C) 0/1); ml_kem_encapsulate/decapsulate (`providers/implementations/kem/ml_kem_kem.c`, L165, RESIDUE(C) -); ossl_cipher_cbc_cts_block_update (`providers/implementations/ciphers/cipher_cts.c`, L272, RESIDUE(C) 8/20); test_rng_generate,test_rng_nonce,test_rng_get_seed (`providers/implementations/rands/test_rng.c`, L302, RESIDUE(C) 4/14); crng_test_generate,crng_test_get_seed (`providers/implementations/rands/fips_crng_test.c`, L339, RESIDUE(C) -) |
| VO# / priority | VO5 P1 (output-inhibit), VO8 P1 (output-inhibit) |
| RQ# | RQ6, RQ9 |
| FM# | FM5, FM8 |
| area / ISO/IEC 19790 clause (unchecked) | AR2 §7.3 |

### Defect, reproduction, evidence (found-issues, verbatim)

- **Evidence (h-gates cycle 6):** the in-situ macsl ghost-counter prop `g_succ' != g_succ ⇒ \old(state) ∈ {RUNNING,SELFTEST}` FAILS (z3 definite) on the real `ossl_cipher_generic_stream_update`; the coordinator checked the source at `ciphercommon.c:465-475`: only `ctx->key_set` is tested.
- **Affected:** `ossl_cipher_generic_{block,stream}_update`, `cbc_cts_block_update/final`, `aes_ocb_block_update`, `gcm_stream_update`, `ccm_stream_update` (the GCM internal gate is reached only on the TLS path).
- **Trigger:** init an AES-CTR ctx while RUNNING; drive the module to ERROR (a deferred self-test failure via `deferred_test_error`, or a failed on-demand `SELF_TEST_post`); `EVP_EncryptUpdate` still returns ciphertext.
- **Status:** trace-confirmed; a machine trace-witness driver is owed.

- **Erratum (recorded under FI-8):** **FI-6 erratum (cycle 6, coordinator):** `aes_ocb_block_update` is removed from FI-6's affected list. `providers/fips/fipsprov.c` registers no OCB cipher, so OCB is outside the FIPS boundary.

### The clause explained

- **RQ6 demands** (src:UNSOURCED): no data output on IF2 while MOD1 is in ST2 or ST4, by any service and any path.
- **RQ9 demands** (src:UNSOURCED): module-state output inhibition for operations in flight: when MOD1 enters ST4 or ST5 while an operation is in progress (a conditional test failing during it, a concurrent self-test failure), that operation releases no further data output and reports failure, even if it had already computed its result.
- **VO5 obliges:** once MOD1 is in ST2 or ST4, no service by any path writes data output; close each vector (a)–(e) of FM5 separately.
- **VO8 obliges:** an operation in flight when MOD1 enters ST4 or ST5 releases no further data output and reports failure; close vectors (a)–(c) of FM8.
- **Why the code contradicts it:** VO5/VO8 output-inhibit: cipher update paths produce ciphertext after ERROR (gate only at ctx creation) (see the trigger above).

### Precondition, severity, fix

- Precondition/configuration: as stated in the evidence above.
- Severity: not assigned by the ledgers; obligation priority P1, P1.
- Fix: none recorded in the ledgers.

## FI-7 — VO5/VO7 output-inhibit: ECDH derive yields a shared secret after ERROR

> **Caveat: trace-confirmed; witness owed.** Kept as a violation; the machine witness is not yet produced.

| field | value |
|---|---|
| functions (verdict rows) | ecdh_derive/ecdh_derive_skey (`providers/implementations/exchange/ecdh_exch.c`, L99, RESIDUE(C) -); ecdh_derive (`providers/implementations/exchange/ecdh_exch.c`, L125, RESIDUE(C) 1/3); ecx_derive (`providers/implementations/exchange/ecx_exch.c`, L189, RESIDUE(C) 2/2) |
| VO# / priority | VO5 P1 (output-inhibit), VO7 P1 (no-plain-ssp-out) |
| RQ# | RQ6, RQ8 |
| FM# | FM5, FM7 |
| area / ISO/IEC 19790 clause (unchecked) | AR2 §7.3 |

### Defect, reproduction, evidence (found-issues, verbatim)

- **Evidence:** `ecdh_derive`/`ecdh_derive_skey` (ecdh_exch.c:573ff) and `ecdh_plain_derive`/`ecdh_X9_63_kdf_derive` contain no `ossl_prov_is_running()`; the only gates are newctx/init/set_peer (lines 91/116/164/202). By contrast, `dh_derive` and `ecx_derive` re-check.
- **Trigger:** init and set_peer while RUNNING → ERROR → derive returns the secret (an SSP).
- **Status:** trace-confirmed; WP witness owed.

### The clause explained

- **RQ6 demands** (src:UNSOURCED): no data output on IF2 while MOD1 is in ST2 or ST4, by any service and any path.
- **RQ8 demands** (src:UNSOURCED): status output (IF4) and control output (IF5) carry only status, error codes and indicator values, never SSP bytes.
- **VO5 obliges:** once MOD1 is in ST2 or ST4, no service by any path writes data output; close each vector (a)–(e) of FM5 separately.
- **VO7 obliges:** no status, error or control output path carries bytes of any SSP1–SSP7.
- **Why the code contradicts it:** VO5/VO7 output-inhibit: ECDH derive yields a shared secret after ERROR (see the trigger above).

### Precondition, severity, fix

- Precondition/configuration: as stated in the evidence above.
- Severity: not assigned by the ledgers; obligation priority P1, P1.
- Fix: none recorded in the ledgers.

## FI-8 — VO7/VO17/VO5 no-plain-ssp-out: HMAC/CMAC legacy keymgmt get_params returns the raw private key, ungated

> **Caveat: trace-confirmed; witness owed.** Kept as a violation; the machine witness is not yet produced.

| field | value |
|---|---|
| functions (verdict rows) | mac_get_params/cmac_get_params (`providers/implementations/keymgmt/mac_legacy_kmgmt.c`, L100, RESIDUE(C) -); mac_get_params/cmac_get_params (`providers/implementations/keymgmt/mac_legacy_kmgmt.c`, L126, RESIDUE(C) 0/2); mac_get_params/cmac_get_params (`providers/implementations/keymgmt/mac_legacy_kmgmt.c`, L159, RESIDUE(C) 2/6); mac_get_params/cmac_get_params (`providers/implementations/keymgmt/mac_legacy_kmgmt.c`, L192, RESIDUE(C) 1/3); mac_get_params/cmac_get_params (`providers/implementations/keymgmt/mac_legacy_kmgmt.c`, L222, RESIDUE(C) 9/13); mac_get_params (FI-8 witness) (`providers/implementations/keymgmt/mac_legacy_kmgmt.c`, L269, RESIDUE(C) -) |
| VO# / priority | VO5 P1 (output-inhibit), VO7 P1 (no-plain-ssp-out), VO17 P1 (no-plain-ssp-out) |
| RQ# | RQ6, RQ8, RQ27 |
| FM# | FM5, FM7, FM17 |
| area / ISO/IEC 19790 clause (unchecked) | AR2 §7.3, AR8 §7.9 |

### Defect, reproduction, evidence (found-issues, verbatim)

- **Evidence:** `mac_get_params`/`cmac_get_params` (mac_legacy_kmgmt.c:330-354) → `key_to_params` emits `OSSL_PKEY_PARAM_PRIV_KEY` = `key->priv_key` in plaintext, with no `ossl_prov_is_running()` gate (`mac_export` is gated; get_params is not).
- **Impact:** (a) plaintext SSP output (level-4 VO17 concern, any state); (b) output in the ERROR state.
- **Status:** trace-confirmed by coordinator source read; WP witness owed.
- **FI-6 erratum (cycle 6, coordinator):** `aes_ocb_block_update` is removed from FI-6's affected list. `providers/fips/fipsprov.c` registers no OCB cipher, so OCB is outside the FIPS boundary.

### The clause explained

- **RQ6 demands** (src:UNSOURCED): no data output on IF2 while MOD1 is in ST2 or ST4, by any service and any path.
- **RQ8 demands** (src:UNSOURCED): status output (IF4) and control output (IF5) carry only status, error codes and indicator values, never SSP bytes.
- **RQ27 demands** (src:UNSOURCED): no unintended disclosure: SSP bytes leave MOD1 only through the permitted outputs PO1–PO7 under their conditions; key getters return a private component only for a request naming it (PO4); a public-only selection, by getter or export, returns no private byte (PO6); the export callback receives the private part only when the selection includes it (PO5), and a rejecting callback causes failure with no further delivery; context getters, provider getters, status and control output return no SSP byte (PO8).
- **VO5 obliges:** once MOD1 is in ST2 or ST4, no service by any path writes data output; close each vector (a)–(e) of FM5 separately.
- **VO7 obliges:** no status, error or control output path carries bytes of any SSP1–SSP7.
- **VO17 obliges:** SSP bytes reach a data output only through PO1–PO7: close vectors (a)–(g) of FM17, covering key, context and provider parameter getters, private-key retrieval versus export, public-only selections, export-callback delivery and callback rejection.
- **Why the code contradicts it:** VO7/VO17/VO5 no-plain-ssp-out: HMAC/CMAC legacy keymgmt get_params returns the raw private key, ungated (see the trigger above).

### Precondition, severity, fix

- Precondition/configuration: as stated in the evidence above.
- Severity: not assigned by the ledgers; obligation priority P1, P1, P1.
- Fix: none recorded in the ledgers.

## FI-9 — VO7/VO17/VO5 no-plain-ssp-out: keymgmt get_params returns plaintext private keys, ungated (DH, ML-DSA; SLH-DSA, RSA to confirm)

> **Caveat: trace-confirmed; witness owed.** Kept as a violation; the machine witness is not yet produced.

| field | value |
|---|---|
| functions (verdict rows) | dh_get_params (`providers/implementations/keymgmt/dh_kmgmt.c`, L127, RESIDUE(C) -); ml_dsa_get_params (`providers/implementations/keymgmt/ml_dsa_kmgmt.c`, L128, RESIDUE(C) -); dh_get_params (`providers/implementations/keymgmt/dh_kmgmt.c`, L160, RESIDUE(C) -); slh_dsa_get_params (`providers/implementations/keymgmt/slh_dsa_kmgmt.c`, L162, RESIDUE(C) -); rsa_get_params (`providers/implementations/keymgmt/rsa_kmgmt.c`, L163, RESIDUE(C) -); dsa_get_params (`providers/implementations/keymgmt/dsa_kmgmt.c`, L164, RESIDUE(C) -); ec_get_params/common_get_params (`providers/implementations/keymgmt/ec_kmgmt.c`, L193, RESIDUE(C) -); ecx_get_params (`providers/implementations/keymgmt/ecx_kmgmt.c`, L194, RESIDUE(C) -); ml_kem_get_params (`providers/implementations/keymgmt/ml_kem_kmgmt.c`, L195, RESIDUE(C) -); mlx_kem_get_params (`providers/implementations/keymgmt/mlx_kmgmt.c`, L196, RESIDUE(C) -); ecx_get_params (`providers/implementations/keymgmt/ecx_kmgmt.c`, L223, RESIDUE(C) 1/9); dh_get_params (`providers/implementations/keymgmt/dh_kmgmt.c`, L224, RESIDUE(C) -); dh_get_params (FI-9 witness) (`providers/implementations/keymgmt/dh_kmgmt.c`, L268, RESIDUE(C) -); ecx_get_params (FI-9 witness) (`providers/implementations/keymgmt/ecx_kmgmt.c`, L270, RESIDUE(C) -); dh_get_params (`providers/implementations/keymgmt/dh_kmgmt.c`, L303, RESIDUE(C) -); dsa_key_todata (FI-9 witness) (`providers/implementations/keymgmt/dsa_kmgmt.c`, L454, RESIDUE(C) -); dsa_key_todata (via dsa_get_params, FI-9) (`providers/implementations/keymgmt/dsa_kmgmt.c`, L512, RESIDUE(C) -); key_to_params priv-emit path (via ec_get_params :789 -> common_get_params :779, FI-9) (`providers/implementations/keymgmt/ec_kmgmt.c`, L597, RESIDUE(C) 0/1) |
| VO# / priority | VO5 P1 (output-inhibit), VO7 P1 (no-plain-ssp-out), VO17 P1 (no-plain-ssp-out) |
| RQ# | RQ6, RQ8, RQ27 |
| FM# | FM5, FM7, FM17 |
| area / ISO/IEC 19790 clause (unchecked) | AR2 §7.3, AR8 §7.9 |

### Defect, reproduction, evidence (found-issues, verbatim)

- **Evidence (h-gates cycle 7 + coordinator source check):**
  - `dh_get_params` ends with `ossl_dh_key_todata(dh, NULL, p.pubkey, p.privkey, 1)` (dh_kmgmt.c:447), which copies the private BIGNUM into the caller's OSSL_PARAM.
  - `ml_dsa_get_params` sets `p.privkey` to `ossl_ml_dsa_key_get_priv` (ml_dsa_kmgmt.c:394-398).
  - Neither function calls `ossl_prov_is_running()`.
- **Impact:** at level 4, an SSP leaves the module in plaintext through a parameter getter, in any state including ERROR. This is the same class as FI-8. SLH-DSA and RSA/RSA-PSS (`include_private=1`) are reported by the verifier but not yet confirmed by the coordinator. EC and ECX return public data only.
- **Status:** trace-confirmed; WP witness owed.

### The clause explained

- **RQ6 demands** (src:UNSOURCED): no data output on IF2 while MOD1 is in ST2 or ST4, by any service and any path.
- **RQ8 demands** (src:UNSOURCED): status output (IF4) and control output (IF5) carry only status, error codes and indicator values, never SSP bytes.
- **RQ27 demands** (src:UNSOURCED): no unintended disclosure: SSP bytes leave MOD1 only through the permitted outputs PO1–PO7 under their conditions; key getters return a private component only for a request naming it (PO4); a public-only selection, by getter or export, returns no private byte (PO6); the export callback receives the private part only when the selection includes it (PO5), and a rejecting callback causes failure with no further delivery; context getters, provider getters, status and control output return no SSP byte (PO8).
- **VO5 obliges:** once MOD1 is in ST2 or ST4, no service by any path writes data output; close each vector (a)–(e) of FM5 separately.
- **VO7 obliges:** no status, error or control output path carries bytes of any SSP1–SSP7.
- **VO17 obliges:** SSP bytes reach a data output only through PO1–PO7: close vectors (a)–(g) of FM17, covering key, context and provider parameter getters, private-key retrieval versus export, public-only selections, export-callback delivery and callback rejection.
- **Why the code contradicts it:** VO7/VO17/VO5 no-plain-ssp-out: keymgmt get_params returns plaintext private keys, ungated (DH, ML-DSA; SLH-DSA, RSA to confirm) (see the trigger above).

### Precondition, severity, fix

- Precondition/configuration: as stated in the evidence above.
- Severity: not assigned by the ledgers; obligation priority P1, P1, P1.
- Fix: none recorded in the ledgers.

## FI-10 — VO25 error-state absorbing: a successful on-demand POST overwrites an ERROR raised during it

| field | value |
|---|---|
| functions (verdict rows) | SELF_TEST_post (`providers/fips/self_test.c`, L146, RESIDUE(C) -); SELF_TEST_post (`providers/fips/self_test.c`, L174, RESIDUE(C) -) |
| VO# / priority | VO25 P1 (error-state) |
| RQ# | RQ37, RQ38 |
| FM# | FM25 |
| area / ISO/IEC 19790 clause (unchecked) | AR9 §7.10 |

### Defect, reproduction, evidence (found-issues, verbatim)

- **Evidence (h-selftest cycle 6, coordinator source check):** at `self_test.c:422-423`, `if (ok) set_fips_state(FIPS_STATE_RUNNING);` runs without checking the current state. Under faithful contracts that let in-module callees re-enter and set ERROR, the `vo25_req` property (ERROR is absorbing) is unprovable.
- **Triggers while FIPS_state==SELFTEST, i.e. during on-demand `SELF_TEST_post`:**
  - a jitter seed-source failure (`seed_src_jitter.c:117/160` → `ossl_set_error_state(CRNG)`, when jitter is configured);
  - an application `OSSL_CALLBACK` invoked from `OSSL_SELF_TEST_on*` that drives a failing service;
  - a deferred-test failure (`fipsprov.c:1399`).
  
  The KATs then pass and the state returns to RUNNING without a reload.
- **Distinct from:** the concurrent-race candidate (out-of-plane), and FI-1 (output during SELFTEST).
- **Status:** trace-confirmed; a fault-injection reproducer is owed.

### The clause explained

- **RQ37 demands** (src:UNSOURCED): any self-test failure moves MOD1 to ST4 persistently: every service then returns an error with no data output until the module is unloaded and reloaded.
- **RQ38 demands** (src:UNSOURCED): trigger 4, on-demand self-test: SV11 re-runs the pre-operational test and the cryptographic algorithm self-tests, with services inhibited while it runs; its failure has the effect of RQ37.
- **VO25 obliges:** once any self-test (pre-operational, conditional or on demand) fails, MOD1 is in ST4 and stays there: every subsequent service call fails with no output until reload.
- **Why the code contradicts it:** VO25 error-state absorbing: a successful on-demand POST overwrites an ERROR raised during it (see the trigger above).

### Precondition, severity, fix

- Precondition/configuration: as stated in the evidence above.
- Severity: not assigned by the ledgers; obligation priority P1.
- Fix: none recorded in the ledgers.

## FI-11 — VO15 zeroize: DSA_set0_key releases a replaced private key with BN_free (conditional)

| field | value |
|---|---|
| functions (verdict rows) | DSA_set0_key (`crypto/dsa/dsa_lib.c`, L141, RESIDUE(C) 18/19); BN_free (`crypto/bn/bn_lib.c`, L176, VERIFIED 20/20); BN_free (`crypto/bn/bn_lib.c`, L806, RESIDUE(C) -); DSA_set0_key (`crypto/dsa/dsa_lib.c (probes/wz2/keys/dsa_lib.c)`, L850, RESIDUE(C) 26/27); BN_free (`crypto/bn/bn_lib.c`, L855, VERIFIED 51/51); DSA_set0_key (`crypto/dsa/dsa_lib.c (probes/wz2/keys/dsa_lib.c)`, L924, RESIDUE(C) -) |
| VO# / priority | VO15 P1 (zeroize) |
| RQ# | RQ25 |
| FM# | FM15 |
| area / ISO/IEC 19790 clause (unchecked) | AR8 §7.9 |

### Defect, reproduction, evidence (found-issues, verbatim)

- **Evidence (w-zeroize-2 cycle 8):** the WP red is exactly on `BN_free(d->priv_key)` (dsa_lib.c:299), 18/19. The analogous DH and RSA set0 paths are proven to use `BN_clear_free`.
- **Condition:** `bn_free_d` (bn_lib.c:199) cleanses only when `BN_FLG_SECURE` is set. A caller-supplied private BIGNUM that is not secure-heap is freed without cleansing.
- **Status:** VIOLATION (conditional on non-secure private BIGNUM); hardening fix: `BN_clear_free`.

### The clause explained

- **RQ25 demands** (src:UNSOURCED): every SSP in provider-owned memory is zeroized when no longer referenced: on free (SV13); on replacement (a key or parameter set over an existing one); on successful and failed import and set; on every temporary copy made for get or export, on success, failure and callback rejection or cancellation; on successful duplication when the copy is later freed, and on a failed duplication for the partial copy; and on every error path of the service that created or loaded it.
- **VO15 obliges:** every SSP in provider-owned memory is cleared on each vector (a)–(j) of FM15: free, replacement, import and set on success and failure, get and export temporaries on success, failure and callback rejection or cancellation, duplication, re-initialization, key-generation early returns.
- **Why the code contradicts it:** VO15 zeroize: DSA_set0_key releases a replaced private key with BN_free (conditional) (see the trigger above).

### Precondition, severity, fix

- Precondition/configuration: as stated in the evidence above.
- Severity: not assigned by the ledgers; obligation priority P1.
- Fix: none recorded in the ledgers.

## FI-14 — Self-test can leave the deterministic TEST-RAND installed as the thread's private DRBG (latent)

| field | value |
|---|---|
| functions (verdict rows) | SSP generation randomness from the approved DRBG only (`providers/fips/fipsprov.c (call graph)`, L320, RESIDUE(C) -); SELF_TEST_kats_execute (`providers/fips/self_test_kats.c`, L362, RESIDUE(C) 3/5); (50 unresolved EVP_*_fetch sites) (`approved-cg/vo18-fetch-classification.tsv`, L366, RESIDUE(C) -); 50 unresolved EVP_*_fetch sites (`approved-cg/vo18-fetch-classification.tsv`, L396, RESIDUE(C) -) |
| VO# / priority |  |
| RQ# |  (cited: RQ29) |
| FM# |  |
| area / ISO/IEC 19790 clause (unchecked) |  |

### Defect, reproduction, evidence (found-issues, verbatim)

- **Location:** `providers/fips/self_test_kats.c`.
  1. With `switch_rand` set, lines 1220-1232 save the current private DRBG and install the KAT `main_rand` (TEST-RAND) through `RAND_set0_private`.
  2. Line 1237: `if (!ossl_set_self_test_state(id, SELF_TEST_STATE_IN_PROGRESS)) return 0;` returns early. That skips the restore at lines 1285-1289 (`RAND_set0_private(libctx, saved_rand)`).
- **Reachability:** `ossl_set_self_test_state` calls `CRYPTO_atomic_store_int` (`crypto/threads_pthread.c:1227-1247`). That function fails only on the lock fallback, when the atomic is not lock-free, `lock == NULL`, or `write_lock` fails. This cannot happen on x86_64 with GCC atomics, but it can on lock-fallback platforms.
- **Impact if reached:** later private random draws on that thread, which include key and nonce generation, come from the deterministic KAT RNG. This violates RQ29/VO18 (SSP generation must use the approved DRBG).
- **Evidence:** the approved-cg sweep (cycle 26), source-confirmed by the coordinator. A WP witness is owed.
- **Severity:** latent, and platform-dependent.

### The clause explained

- **Why the code contradicts it:** Self-test can leave the deterministic TEST-RAND installed as the thread's private DRBG (latent) (see the trigger above).

### Precondition, severity, fix

- Precondition/configuration: as stated in the evidence above.
- Severity: not assigned by the ledgers; obligation priority -.
- Fix: none recorded in the ledgers.
