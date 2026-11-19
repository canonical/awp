# Other findings

_PAUSED/IN PROGRESS — interim; not a terminus. Generated from the ledgers by `openssl-4.1.0-analysis-acsl/tools/gen-interim-report.py`; do not hand-edit. Sign-off ☐ PENDING._

## 1. Code defects without a requirement

### FI-12 — ML-KEM encapsulate/decapsulate usable after the module enters ERROR

`providers/implementations/kem/ml_kem_kem.c`: the only `ossl_prov_is_running()` check is in `ml_kem_init` (line 103). `ml_kem_encapsulate` (line 175) and decapsulate perform the KEM and output a shared secret with no state check, so a ctx initialised while RUNNING remains usable after a transition to ERROR. Class: error-state output inhibition (VO5), same pattern as FI-6. Status: source-confirmed; machine witness pending (h-gates).

- FIPS relevance (the dossier's reading): no study requirement cited.

### FI-13 — Pairwise-consistency test skipped for every key generated while the module is in SELFTEST state

`ossl_fips_self_testing()` (`providers/fips/self_test.c:275-278`) returns true whenever the process-wide `FIPS_state == FIPS_STATE_SELFTEST`, not only for the self-test's own operations. The keygen PCT is skipped on that condition in ML-DSA (`ml_dsa_kmgmt.c:67-70`, returns 1), ML-KEM (`ml_kem_kmgmt.c:97`), SLH-DSA (`slh_dsa_kmgmt.c:312`, comment "During self test, it is a waste to do this test") and DH (`dh_kmgmt.c:845`). During an on-demand POST, other threads keep service (FI-1), so any application key generated concurrently is released without its PCT (ISO/IEC 19790 7.10.3.3 / FIPS 140-3 IG 10.3.A). Status: source-confirmed by the coordinator; concurrent reproducer pending. Severity depends on FI-1 reachability.

### FI-13 addendum (cycle 20): concrete reproduction
Reproduced on a copy fips.so built outside the pristine tree (`openssl-4.1.0-analysis-acsl/h-selftest/repro13/`). The only difference from `providers/implementations/keymgmt/ml_dsa_kmgmt.c` is counter instrumentation (coordinator diff).
- **Control** (state RUNNING): pairwise test executed 1, skipped 0.
- **Mode A** (keygen from the self-test callback during an on-demand `OSSL_PROVIDER_self_test`): executed 0, skipped 1.
- **Mode B** (a second application thread generating keys during on-demand POST): about 56 keys, 1 executed, 56 skipped.

Application ML-DSA key pairs are therefore returned without the FIPS 140-3 pairwise consistency test (IG 10.3.A) while any self-test is running. Path: `ml_dsa_kmgmt.c:67-70`, `self_test.c:275-278`.

### FI-6 addendum (cycle 22): AES-CBC-CTS update ungated
`ossl_cipher_cbc_cts_block_update` (`providers/implementations/ciphers/cipher_cts.c:399-442`) has no `ossl_prov_is_running()` check, and none exists anywhere in that file. AES-128/192/256-CBC-CTS are registered in the FIPS provider (`fipsprov.c:273-275`).

Trace: an encrypt context is initialised while RUNNING (gate at `ciphercommon.c:181`), then the module enters ERROR (`ossl_set_error_state`). A subsequent update with `out != NULL` still writes ciphertext and returns 1, which contradicts FIPS 140-3 §7.10.2 (no data output in the error state).

Machine witness: macsl in-situ, ERROR-at-entry, z3 [Unknown] on 12 output-path parts (`h-gates/`).

### FI-8 / FI-9 / FI-12 witness addendum (cycle 22)
The ERROR-at-entry witnesses for `mac_get_params` (FI-8), `ecx_get_params` (FI-9) and `mlx_kem_encapsulate` (FI-12) are now DEFINITE. WP emits `Prove: false` on the success path under ERROR at entry, and the coordinator read the hypotheses in the WP output and found them consistent. They are independent path conditions, so a model exists; this is corroborated by z3 `sat` (`openssl-4.1.0-analysis-acsl/witness/sat/`).

### FI-6 addendum (cycle 23): TEST-RAND emits output in the ERROR state
- **Location:** `providers/implementations/rands/test_rng.c`, which has no `ossl_prov_is_running()` call (grep count 0). It is registered in the FIPS provider at `providers/fips/fipsprov.c:454`: `{ PROV_NAMES_TEST_RAND, FIPS_UNAPPROVED_PROPERTIES, ossl_test_rng_functions }`.
- **Trigger:**
  1. Create a TEST-RAND context while the module is RUNNING.
  2. The module enters the error state (`ossl_set_error_state`).
  3. `test_rng_generate` (lines 131-151) still copies `entropy` (or `gen_byte` output) to `out` and returns 1. `test_rng_nonce` and `test_rng_get_seed` behave the same way.
  
  The `fips_query` gate blocks only new fetches, not an existing context.
- **Requirement:** the data-output interface must be inhibited in the error state (FIPS 140-3 §7.10 / ISO 19790 7.10.1). This applies to unapproved services too.
- **Evidence:**
  - h-gates in-situ prop: the compliant run `r/ok11.trng` fails; the ERROR-at-entry run `r/we11.trng` gives [Unknown] on generate parts 2 and 4, nonce parts 2, 3, 6 and 8, and get_seed parts 1 and 2.
  - The source was confirmed by the coordinator.
- **Severity:** lower than the approved-service cases, because test data is not an SSP. It is still an output-inhibit conformance gap.

- FIPS relevance (the dossier's reading): no study requirement cited.

### FI-15 — X25519MLKEM768 is registered approved but derives with the unapproved X25519 key exchange (policy-conditional)

- **Location:**
  - `providers/fips/fipsprov.c:588` registers `X25519MLKEM768` with `FIPS_DEFAULT_PROPERTIES`.
  - `:465` registers `X25519` key exchange with `FIPS_UNAPPROVED_PROPERTIES`.
  - `providers/implementations/kem/mlx_kem.c:239-262` (encapsulate) and `:347-353` (decapsulate) run `EVP_PKEY_derive` with the X25519 key.
  - The indicator at `mlx_kem.c:128-134` reports approved for every hybrid except X448.
- **Question:** VO1 and VO19 require approved-mode key establishment to reach only SP 800-140D methods. Under SP 800-227 / IG D.R hybrid rules, a composite whose security rests on an approved component (ML-KEM) may itself be approved. Whether the module's policy accepts this is a decision for the study and the responsible authority, not for the verifier.
- **Status:** a call-graph witness (approved-cg/offending-paths.txt), source-confirmed by the coordinator. It is routed to the code-blind study via the feedback packet. The other two hybrids, SecP256r1MLKEM768 and SecP384r1MLKEM1024, use approved ECDH and are clean.

### FI-6 addendum (cycle 29): CRNG-TEST emits output in the ERROR state
`providers/implementations/rands/fips_crng_test.c` has no `ossl_prov_is_running()` call (grep count 0). It is registered at `providers/fips/fipsprov.c:447` as `PROV_NAMES_CRNG_TEST, FIPS_UNAPPROVED_PROPERTIES`.
- **Evidence:** the h-gates in-situ run with ERROR at entry (`r/we15.crng`) catches definite [Unknown] goals:
  - `crng_test_generate`: meta part 1;
  - `crng_test_get_seed`: parts 02, 05, 07, 10, 11, 13 and 15-21.
- **Observed behaviour:** an existing CRNG-TEST context keeps returning entropy or seed bytes after the module enters the error state.
- **Severity:** the same class as the TEST-RAND addendum. The approved DRBGs that consume CRNG-TEST are gated themselves, so the direct exposure is a CRNG-TEST context fetched explicitly. The source was confirmed by the coordinator.

- FIPS relevance (the dossier's reading): no study requirement cited.

### FI-16 — TDES strict-mode refusal leaves an encrypt-keyed context (approved-only / indicator bypass)

- **Where:** `providers/implementations/ciphers/cipher_tdes_common.c`, `tdes_init`.
  - It sets `ctx->enc = enc` (:114) and, after a successful key setup, `ctx->key_set = 1` (:134).
  - Only then does it call `tdes_encrypt_check_approved` (:139-141). In strict mode (`FIPS_CONFIG_TDES_ENCRYPT_DISABLED` with the indicator settable) that call refuses encryption, and `tdes_init` returns 0. It clears neither `key_set` nor `enc`.
- **EVP layer:** `evp_cipher_init_internal` returns the provider's result without invalidating `ctx->algctx`. `EVP_EncryptUpdate` (evp_enc.c:655-695) checks only `ctx->encrypt`, the cipher and `cupdate`.
- **Provider update path:** `ossl_cipher_generic_block_update` checks only `key_set` (ciphercommon.c:261).
- **Trigger:** a caller that ignores the failed `EVP_EncryptInit_ex2(TDES, key, ...)` in strict mode, then calls `EVP_EncryptUpdate` or `EVP_EncryptFinal`. It gets Triple-DES encryption, which is not approved in FIPS 140-3, even though the module refused the service.
- **Evidence:**
  - Source reading, confirmed by the coordinator.
  - WP proves the gate function itself (`tdes_encrypt_check_approved`, 1/1).
  - The keyed-after-refusal assertion `tdes_armed` timed out, so it is not definite. A dynamic reproduction is pending.
- **Severity:** P2 (approved-only / service-indicator). The module should leave no usable keyed state after a refused approved-mode service. Requires caller misuse (ignoring an error return).
- **Fix suggestion:** move the strict check before setting `enc`/`key_set`, or clear `key_set` on refusal.

### FI-16 addendum (cycle 37): definite dynamic reproduction; HKDF has the same defect
- **Repro:** `approved-cg/fi16/fi16_repro.c`, built against the build copy, never `openssl-4.1.0/`, and run against the build copy's `fips.so` with `tdes-encrypt-disabled = 1` and `hkdf-key-check = 1`. Output: `approved-cg/fi16/fi16_repro.out`, read by the coordinator.
- **TDES (DES-EDE3-ECB and -CBC):** `EVP_EncryptInit_ex2` returns 0 (refused), but `EVP_EncryptUpdate` returns 1 with 16 bytes of ciphertext.
  - ECB `d82e0510…`, CBC `87639333…`.
  - Byte-identical to the default provider's output; the approved indicator is 0.
- **HKDF:** `kdf_hkdf_set_ctx_params` stores the key (`hkdf_common_set_ctx_params`, hkdf.c:374) before `fips_hkdf_key_check_passed` (:378-380). After `set_params` rejects a 64-bit key (rc=0, "invalid key length"), `EVP_KDF_derive` returns 1 with the same output as the default provider. The indicator is 0.
- **Same store-then-check order, source reading only (not reproduced):**
  - KBKDF and SSKDF.
  - Seven RSA/EC/DSA/DH init functions. These are latent, because the EVP layer resets the operation when init fails.
- HMAC and KMAC check before storing the key (code reading).

- FIPS relevance (the dossier's reading): no study requirement cited.

### FI-17 — A refused KDF key is still used: seven FIPS KDFs derive after rejecting the key (approved-only / indicator bypass)

- **Requirement:** in strict mode (`<kdf>-key-check = 1`), a key the module rejects as non-approved must not be used for an approved service. A refusal must leave the context unable to derive.
- **Defect:** each affected KDF's `set_ctx_params` stores the key through the common setter first, then runs its FIPS key check and returns 0 on failure. The stored key stays in the context.
  - HKDF: hkdf.c:374 stores the key, :378-380 checks it. The other KDFs follow the same order.
  - `derive` does not repeat the check, so it succeeds with the rejected key, and the approved indicator reads 0.
- **Witness (definite, dynamic):** `approved-cg/c37/kdf_repro.c` and `kdf_repro.out`, run against the build copy's `fips.so` under strict config `fi16.cnf`, with a 64-bit key.

  | KDF | Key refused | Output after refusal | Indicator |
  |---|---|---|---|
  | HKDF | yes | yes | 0 |
  | KBKDF | yes | yes | 0 |
  | SSKDF | yes | yes | 0 |
  | X963KDF | yes | yes | 0 |
  | X942KDF-ASN1 | yes | yes | 0 |
  | TLS1-PRF | yes | yes | 0 |
  | SSHKDF | yes | yes | 0 |

  For HKDF, KBKDF, SSKDF, X963KDF, X942KDF-ASN1 and SSHKDF, the output equals the default provider's. Control runs with an approved key: set_params rc=1, indicator 1.
- **Clean in the same harness:** PBKDF2, HMAC and KMAC-128. TLS13-KDF is inconclusive; the harness control produced no output.
- **Impact:** a strict-mode application that ignores the `set_params` return value, or relies on the indicator after the fact, gets output derived from a key the module rejected. This is a non-approved service delivered by the FIPS module. Same class as FI-16 (TDES).
- **Fix shape (FI-16 pair):** clear the stored key on refusal, or check before storing. The TDES fix in `approved-cg/c37/fix.diff` (`key_set = 0` on refusal) removes the output dynamically (`fix_repro.out`, "no key set"), and the fixed overlay proves `refusal_disarmed` in WP (29/30, with only the function-pointer RTE goal open).
- **Status:** VIOLATION (reported). The responsible-authority sign-off is PENDING.

### FI-17 addendum (cycle 44): TLS13-KDF confirmed; an HKDF variant reports *approved* for a rejected key
- **TLS13-KDF (definite):** with the harness fixed (SHA-256, 32-byte output, `tls13 ` prefix), a 64-bit key is refused in strict mode. Derive still returns 32 bytes in both EXTRACT_ONLY and EXPAND_ONLY mode, with indicator 0 and output equal to the default provider's. The 256-bit control gives indicator 1. Evidence: `approved-cg/c42/repro42.out`.
- **HKDF malformed-salt variant (definite, more severe):** pass a 64-bit key together with a salt of the wrong type (utf8 instead of octet).
  - `hkdf_common_set_ctx_params` installs the key, then fails on the salt, so `set_ctx_params` returns 0 (hkdf.c:374-375) before the key check at :379 ever runs.
  - A following derive succeeds with **indicator = 1**: the module reports an approved service for a key it would reject.
  - HKDF-fixed-digest (:518) and TLS13 (:982) have the same shape; reproduction is owed.
- **Same store-then-check shape:** KBKDF, SSKDF, X963KDF, X942KDF-ASN1, TLS1-PRF, SSHKDF, TLS13-KDF and HKDF-fixed-digest. All but HKDF-fixed-digest are reproduced.

- FIPS relevance (the dossier's reading): no study requirement cited.

### FI-18 — DH key exchange: a refused derive init leaves the context armed (approved-only / indicator bypass)

- **Requirement:** a key the FIPS module rejects at init must not be usable for key agreement.
- **Defect:** `dh_init` stores `pdhctx->dh` (dh_exch.c:140-141) before the key check (:148, `dh_check_key`, error at :116). `EVP_PKEY_derive_init_ex` calls init (exchange.c:374) and returns early on failure (:377), skipping the operation reset at :378-380. The provider context stays armed with the rejected key.
- **Witness (definite, dynamic):** `approved-cg/c42/repro42.c` and `repro42.out`, run against the build copy's fips.so in strict config.
  - Parameters: ffdhe3072 p,q with g=4 (not a named group). `ossl_dh_check_key` rejects them: "invalid key length".
  - Result: derive_init rc=0, then set_peer rc=1 and derive succeeds. The fips provider serves it, 384 bytes, indicator 0, output equal to the default provider's.
  - Controls L=2048/N=224 and L=2048/N=256 give rc=1 and indicator 1.
- **Contrast:** for ECDH the derive init also does not reset, but set_peer re-checks the key, so it is blocked (P-192 test). RSA, RSA-KEM, ECDSA and DSA signature inits are blocked because EVP resets on init failure.
- **Status:** VIOLATION (reported). The responsible-authority sign-off is PENDING.

### FI-17 addendum (cycle 47): WP witness on the real code; malformed-parameter variant on every HKDF caller; EVP_PKEY route
- **WP witness** (faithful overlay, strip ACCEPT; `approved-cg/c44/wp/`): the real code proves 43/47, and the gate part reduces to `Prove: false` with z3 Unknown. The fixed overlay proves 33/33.
- **Variant, all three HKDF call sites:** a bad salt, a bad label or bad data, or the TLS13 EXTRACT_AND_EXPAND mode makes the parameter parser fail after the key is stored. Derive then succeeds with **indicator=1** at hkdf.c:374 (HKDF), :518 (HKDF-SHA256) and :982-1012 (TLS13-KDF). Evidence: `approved-cg/c44/repro44.out`.
- **EVP_PKEY route:** the EVP_PKEY HKDF and TLS1-PRF key-exchange wrappers (kdf_exch.c) reach the same bypass. set1 refuses a 64-bit key with rc=0, yet derive still returns output. Evidence: `repro44b.out`.

### FI-18 addendum (cycle 47)
- **WP witness** (faithful overlay, strip ACCEPT; `approved-cg/c44/wp/dh/`): dh_init proves 43/47 on the real code. Part 4 (the dh_check_key refusal) reduces to `Prove: false` with consistent hypotheses (strict mode, a valid context, the up-ref succeeded), and z3 returns Unknown. Part 5 is the dh_set_ctx_params failure path, which leaves an unchecked key in place. The fixed copy, which frees the key and sets it to NULL on both failures, proves 29/29.
- **Extent:** ecx_init (X25519/X448) stores the key before the indicator-callback veto (ecx_exch.c:91-96), and EVP does not reset. A derive the application vetoed still runs in the fips provider (`repro44b.out`). These algorithms are non-approved, so the failure is that the application's veto is bypassed.
- **Not affected:**
  - KEMs: kem.c:217-223 resets the operation on failure.
  - ECDH: set_peer re-checks the key.

### FI-18 addendum (cycle 52): ecx WP pair, plus EVP reset gaps found by source reading
- **ecx_init WP pair:**
  - The faithful overlay gives 25/27 with a definite witness: `refusal_disarmed` part5 reduces to `Prove: a_3 = key_0` with key_0 != null, and the old key is null under strict mode.
  - The fixed overlay (free the key and set it to NULL on refusal) is 11/11.
  - Evidence: approved-cg/c47/wp/ecx/.
- **Gaps found by source reading only (not WP), recorded as candidates, not as bypasses:**
  - kem.c:67-70: an authkey type mismatch returns 0 with no reset, leaving `operation` set. No algctx exists on that path.
  - signature.c:871-881: the `notsupported` path returns -2 with no reset.
  - signature.c:883-886, non-FIPS build: returns ≤0 with the provider context still live.
  - Each needs a WP reset proof or witness (queued to approved-cg).

### FI-18 addendum (cycle 57): ecdh_init has the same store-before-refusal pattern
- **WP witness:** ecdh_init `refusal_disarmed` is 6/8. Part 5/8 is `Prove: a = vecdh_0` under the strict precondition a=null. The key is stored at ecdh_exch.c:122-123 and the refusal comes at :131-134. Evidence: approved-cg/c52/wp/gates/ecdh/.
- **Exploitability NOT shown:** ecdh_set_peer re-checks the key at :170. A dynamic repro is owed before this counts as more than a WP-level defect in the refusal contract.
- **KEM (kem.c:67-70) and signature (:871-881):** not a bypass. No algctx exists on those paths, and every later call returns -2 (dynamic repro approved-cg/c52/repro/repro52.out).
- **Latent issue (not an FI):** ossl_FIPS_IND_set_approved with a negative id writes out of bounds, because ossl_assert only checks id < MAX. All callers pass constants.

### FI-9 addendum (cycle 59): EC key_to_params witness
- **v1 extract retracted.** It assumed a private key with no public point, which is unreachable: ec_backend.c:518-522 derives the public point.
- **v2 extract** (witness/ec_kt_extract54.inc, 40 lines, line-by-line mapped to ec_kmgmt.c:139-249) gives `Prove: false`, and the hypotheses are consistent. In the ERROR state, with the public key present and pub/pub_x/pub_y not requested, the private key is emitted via set_bn_pad (:243-247). Evidence: h-gates/r/we54b.ecx.w54_key_to_params_priv.log.

### FI-18 addendum (cycle 61): ecdh exploitability
A dynamic repro (approved-cg/c57/repro) uses a refused P-192 key in strict mode:
- init returns 0;
- set_peer fails ("invalid key length");
- derive fails ("missing key").

The ecdh store-then-check stays a latent defect: it is not exploitable, because of the re-check at ecdh_exch.c:170-174 and the group-match check at :138-156.

### FI-17 addendum (cycle 63): hkdf short-key refusal, now against the proven callee contract
The hkdf_common_set_ctx_params body is VERIFIED 84/84 (with RTE). On the real kdf_hkdf_set_ctx_params, refusal_disarmed and armed_safe fail (parts 3 and 5): after the short-key refusal (keylen ≤13) the key stays installed. Evidence: approved-cg/c61/wp/hkdf/real/callers.log.

The fixed copy proves all four gate properties. It still has one open goal: the new p_mode precondition at the call site, which needs a decoder contract on the complete struct type.

- FIPS relevance (the dossier's reading): no study requirement cited.

### FI-19 — `OSSL_PARAM_get_utf8_string` dereferences a NULL parameter (CWE-476; low, API misuse only)

- **Defect:** `get_string_internal` handles `p == NULL` by raising "null argument" and returning 0 (crypto/params.c:1336-1338). `OSSL_PARAM_get_utf8_string` then reads `p->data_size` (:1396) before its `if (ret == 0)` test, so a NULL `p` is dereferenced. Every sibling getter (get_int32 :395, get_uint32 :549, get_int64 :707, get_uint64 :862, get_BN :1087, get_double :1183, get_ptr_internal :1487, get_string_ptr_internal :1675) returns before touching `p`. The man page (doc/man3/OSSL_PARAM_int.pod:244-251) says nothing about NULL either way.
- **Witness (definite):**
  - WP, pure WP, EVA not used: the harness `w_null` (h-errstate/c92/w_prm.c) gives 19/20. The open goal is the mem_access at :1396; its VC reads through the null base, and its conclusion contradicts the hypotheses. The smoke run shows the `p == NULL` branch is live. The pair `w_nonnull` proves the same goal (h-errstate/c92/WN.log, WP.log).
  - Dynamic: pristine params.c built at -O0 and called with NULL gives SIGSEGV, exit 139 (h-errstate/c92/repro/run_O0.log). The -O3 analysis build does not crash: the compiler moves the load after the `ret` test (repro/disasm_*.log). That does not make the code correct; it is still undefined behaviour.
- **Reachability:** none from the FIPS provider. All 22 FIPS-object call sites test the argument for non-NULL first (listed in h-errstate/c92/deliver_c92.tsv). The bug is reachable only when an application passes NULL directly, for example the unchecked result of `OSSL_PARAM_locate`.
- **Impact:** a crash (denial of service) in a caller that misuses the API. No memory disclosure or code execution. Not a FIPS approved-service issue.
- **Fix:** move `size_t data_length = p->data_size;` after `if (ret == 0) return 0;`.
- **Status:** VIOLATION (reported), low. Suitable as a public bug report, not a security advisory. The responsible-authority sign-off is PENDING.

- FIPS relevance (the dossier's reading): no study requirement cited.

### FI-20 — Integer OSSL_PARAM getters read one byte before the caller's buffer when data_size is 0 (CWE-125; reachable from provider set_ctx_params)

- **Defect:** `is_negative(number, s)` returns `0x80 & n[s - 1]` on little-endian (crypto/params.c:94-100). `general_get_uint` / `general_get_int` call it through `unsigned_from_signed` / `signed_from_signed` (:181-188, :166-170) with `s = p->data_size`, and no getter rejects `data_size == 0`: the size switches in `OSSL_PARAM_get_uint64` (:874-883), `get_int64` (:718-728), `get_uint32` (:560-577) and `get_int32` (:405-422) have no case 0 and fall through to the general path; `get_size_t` (:1022-1027) dispatches to `get_uint64`. With an INTEGER param, data != NULL, data_size == 0, the read is `n[SIZE_MAX]`, one byte before the buffer.
- **Witness (definite):**
  - WP (pure WP, EVA not used): the mem_access goal at :99 is `Prove: valid_rd(m, shift_uint8(global(G_ob_z), 18446744073709551615), 1)` on a 1-byte object, consistent hypotheses (h-errstate/c94/ZU.log 97/98; ZI, ZS, Z32 logs alike). The same goal is Valid for data_size == 1.
  - Dynamic: with the buffer at the start of a page preceded by a PROT_NONE page, all five getters SIGSEGV at data_size 0 and succeed at 1, on pristine params.c at -O0 and on the -O3 build-copy libcrypto (h-errstate/c94/dyn/run_zt_O0_g.log, run_zt_O3lib_g.log).
  - End to end: `EVP_KDF_CTX_set_params` on PBKDF2 `"iter"` and `EVP_MAC_CTX_set_params` on KMAC128 `"size"` with such a param SIGSEGV (h-errstate/c94/dyn/run_e2e.log, default provider; the same source files are compiled into the FIPS provider).
- **Reachability:** application-supplied params reach the getters in provider set_ctx_params decoders that match by key only: pbkdf2.c:387 (`get_uint64(p.iter)`), kmac_prov.c:454 (`get_size_t(p.size)`), ciphercommon.c:654/:677 (`get_size_t`), hkdf.c:324 and drbg_ctr.c:745 (`get_int`).
- **Impact:** a one-byte out-of-bounds read of caller memory. It crashes only when the buffer starts a mapped region; otherwise the byte's top bit decides whether the call fails with "negative" or proceeds with a zero-length copy. No write, no disclosure beyond that one bit's effect on the return value. Low severity, but it is a memory-safety defect reachable through the public EVP set_params API, including in the FIPS provider.
- **Fix:** reject `data_size == 0` in the general integer path (for example in `general_get_int` / `general_get_uint`, or in `is_negative` by returning 0 for s == 0).
- **Status:** VIOLATION (reported), low. Dynamic confirmation against fips.so itself is owed (the e2e run used the default provider). The responsible-authority sign-off is PENDING.

### FI-20 addendum (cycle 97u): confirmed on the FIPS provider
- With a FIPS-only library context (h-errstate/c95/dyn/fips.cnf; `OSSL_PROVIDER_available(lc,"fips")=1`, default unavailable) and every fetch made with `"provider=fips"`, each of PBKDF2 `"iter"` (get_uint64), KMAC-128 `"size"` (get_size_t) and AES-128-CBC `"padding"` (ciphercommon.c, get_uint) is served by `"fips"` and dies with SIGSEGV at `si_addr = data - 1` for a zero-size INTEGER param on a guard page. The data_size 8 control returns 1 (h-errstate/c95/dyn/run_e2e_fips_addr.log).
- Status unchanged: VIOLATION (reported), low; it is now a confirmed out-of-bounds read inside the FIPS module boundary. The responsible-authority sign-off is PENDING.

- FIPS relevance (the dossier's reading): no study requirement cited.

### FI-21 — Pointer OSSL_PARAM getters dereference a NULL `p->data` (CWE-476; low)

- **Defect:** `get_ptr_internal_skip_checks` (crypto/params.c:1480; :1491 in the annotated copy h-errstate/c103/crypto/params.c) does `*val = *(const void **)p->data;` without checking `p->data`. Its callers `get_ptr_internal` (used by `OSSL_PARAM_get_utf8_ptr` / `OSSL_PARAM_get_octet_ptr`) and the `ref_type` arm of `get_string_ptr_internal` (used by `OSSL_PARAM_get_utf8_string_ptr` / `OSSL_PARAM_get_octet_string_ptr`) check `p` and `val` for NULL and the data type, but not `p->data`. Sibling getters such as `OSSL_PARAM_get_double` do reject `p->data == NULL`.
- **Trigger:** `p != NULL`, `val != NULL`, `p->data == NULL`, `p->data_type == OSSL_PARAM_OCTET_PTR` or `OSSL_PARAM_UTF8_PTR` (inside the Oracle-B envelope).
- **Witness (WP, fixed bytes model, EVA not used):** goal `bytes_ob_get_<getter>_assert_rte_mem_access_6` at :1491 is not proved for all four pointer getters (h-errstate/c103/X1.log); refutation witnesses `ob_w_octet_ptr_null` and `ob_w_utf8_ptr_null` (h-errstate/c103/ob_w103.c) prove `!\valid_read(...)` of the dereferenced cell, requires smoke not Doomed (h-errstate/c103/W.log, 12/12). Distinct from FI-19 (`p == NULL`).
- **Impact:** a NULL dereference (crash) for a caller passing a pointer-typed param with no data. Reachability from provider code and a dynamic reproduction are OWED.
- **Fix:** add `p->data == NULL` to the error check in `get_ptr_internal_skip_checks` (or in its callers), as `get_double` does.
- **Status:** VIOLATION (reported), low. The responsible-authority sign-off is PENDING.

- FIPS relevance (the dossier's reading): no study requirement cited.

### FI-22 — `OSSL_PARAM_get_double` negates INT64_MIN (CWE-190, signed-overflow UB; low)

- **Defect:** for an `OSSL_PARAM_INTEGER` param of size 8, `OSSL_PARAM_get_double` computes `u64 = i64 < 0 ? -i64 : i64;` (crypto/params.c:1217; :1228 in the annotated copy). With `i64 == INT64_MIN`, `-i64` is signed overflow, undefined behaviour in C.
- **Trigger:** `data_type == OSSL_PARAM_INTEGER`, `data_size == 8`, data bytes = 0x8000000000000000.
- **Witness (WP, fixed bytes model, EVA not used):** goal `bytes_ob_get_double_assert_rte_signed_overflow` not proved (h-errstate/c103/X2.log); refutation witness `ob_w_double_int64_min` (h-errstate/c103/ob_w103.c) proved by Qed, requires smoke not Doomed (W.log).
- **Impact:** undefined behaviour; with the usual wrap-around the result is still rejected as inexact, so the practical effect depends on the compiler. A sanitizer reproduction is OWED.
- **Fix:** compute the magnitude in unsigned arithmetic, e.g. `u64 = i64 < 0 ? 0 - (uint64_t)i64 : (uint64_t)i64;`.
- **Status:** VIOLATION (reported), low. The responsible-authority sign-off is PENDING.

### FI-21 addendum (cycle 97bj): reproduced, and reachable inside the FIPS provider
- Dynamic, pristine source: all four pointer getters SIGSEGV with si_addr=(nil), exit 139, when `p->data == NULL`, at -O0 and on the -O3 build-copy libcrypto; the valid-data control returns 1 (h-errstate/c104/dyn/run_zt21_O0.log, run_zt21_O3lib.log).
- End to end with a FIPS-only library context (default provider unavailable, `provider=fips`): TLS1-PRF `"digest"` (tls1_prf.c:319), SSHKDF `"type"` (sshkdf.c:276), KBKDF `"mode"` (kbkdf.c:413) through `EVP_KDF_CTX_set_params`, and ML-KEM-768 `"encoded-pub-key"` (ml_kem_kmgmt.c:682) through `EVP_PKEY_set_params`, each crash with SIGSEGV si_addr=(nil) in fips.so at `OSSL_PARAM_get_utf8_string_ptr` / `OSSL_PARAM_get_octet_string_ptr`; the TLS1-PRF control with "SHA256" returns 1 (h-errstate/c104/dyn/run_e2e21_fips.log, addr2line_fips.log). The generated decoders match by key only and do not check `data_type` or `data`.
- Same pattern, not run: x942kdf.c:600/602; provider_util.c:180/182/205/208 (from kbkdf, sskdf, hmacdrbg_kdf, tls1_prf); mlx_kmgmt.c:620; default-provider sites encode_key2any.c:1169/1171, cipher_sm4_xts.c:219, file_store.c:356, winstore_store.c:131. Guarded: tls1_prf.c:392 (data check at :389).
- Status: VIOLATION (reported), low — a NULL-dereference crash (denial of service) inside the FIPS module boundary, reachable through the public EVP set_params API by an application that forwards an untrusted parameter array; no read or write of other memory. The responsible-authority sign-off is PENDING.

### FI-22 addendum (cycle 97bj): reproduced; not reachable from providers
- UBSan on pristine params.c: `params.c:1217:34: runtime error: negation of -9223372036854775808 cannot be represented in type 'long int'`; the continuing build returns 0 and leaves `*val` unchanged (h-errstate/c104/dyn/run_zt22_ubsan_rec.log).
- No provider calls `OSSL_PARAM_get_double`; params_from_text.c:287 handles REAL params only. Reachable only by an application calling the function directly.
- Status: VIOLATION (reported), low (undefined behaviour, application-API only). The responsible-authority sign-off is PENDING.

- FIPS relevance (the dossier's reading): no study requirement cited.

### FI-23 — Signed integer OSSL_PARAM setters read one byte before `val` when data_size is 0 (CWE-125; low)

- **Defect:** `OSSL_PARAM_set_int32` and `OSSL_PARAM_set_int64` (and `OSSL_PARAM_set_int`, which calls `set_int32`) on an `OSSL_PARAM_INTEGER` param go through `general_set_int` (crypto/params.c:223) → `signed_from_signed` (:169) → `copy_integer`. With `dest_len == 0`, `check_sign_bytes` passes vacuously when every byte of `val` equals the sign pad (`val` 0 or -1). Line 155 then reads `src[dest_len - 1]` = `src[SIZE_MAX]`, the byte before `val`.
- **Trigger:** `data_type == OSSL_PARAM_INTEGER`, `data != NULL`, `data_size == 0`, `val` ∈ {0, -1}.
- **Witness:**
  - WP (pure WP, EVA not used): the precondition of the `general_set_int` call is unproved under the honest setter contract (approved-cg/c183/r/U7a.log, set_int32 152/153; U7b.log, set_int64).
  - Dynamic: AddressSanitizer on the unmodified build-tree params.c reports a 1-byte stack-buffer-underflow READ at params.c:155 for `val` 0 and -1. The `val` 1 control returns normally (approved-cg/c183/dyn/run_0.log, run_-1.log, run_1.log).
- **Reachability:** not yet assessed for provider get_ctx_params sites. The one site c179 needed, `cipher_generic_get_ctx_params_decoder` → `OSSL_PARAM_set_int(p, 1)`, is safe: `check_sign_bytes` fails on the first byte before the read. Next action: enumerate the provider call sites of the signed setters whose value can be 0 or -1.
- **Status:** VIOLATION (recorded), low. The responsible-authority sign-off is PENDING. No external report: reporting is the authority's decision.

- FIPS relevance (the dossier's reading): no study requirement cited.

### FI-24 — `OSSL_PARAM_set_int64` negates INT64_MIN on the REAL path (CWE-190, signed-overflow UB; low)

- **Defect:** for an `OSSL_PARAM_REAL` param of size 8, `OSSL_PARAM_set_int64` computes `-val` at crypto/params.c:838. With `val == INT64_MIN` this is signed overflow. It is the setter twin of FI-22.
- **Witness:** WP leaves the RTE signed_overflow goal open (approved-cg/c183/r/U7b.log, 158/160). UBSan on the build-tree params.c: `params.c:838:34: runtime error: negation of -9223372036854775808 cannot be represented in type 'long int'` (approved-cg/c183/dyn/run64.log).
- **Reachability:** not reachable from `OSSL_PARAM_set_int`, which goes through `set_int32` on this ABI. Provider callers of `set_int64` with a REAL param are not yet assessed.
- **Status:** VIOLATION (recorded), low. The responsible-authority sign-off is PENDING. No external report: reporting is the authority's decision.

### FI-23 addendum (cycle 97gl): reachable inside the FIPS provider
- Call sites: 140 signed-setter sites enumerated (approved-cg/c186/sites.tsv). 127 are compiled into the FIPS module, and 94 of those take a caller-supplied param with a value that can be 0 or -1.
  - Example: `providers/implementations/kdfs/hkdf.c:444` `OSSL_PARAM_set_int(p.mode, ctx->mode)`, where the default mode is 0.
  - Example: `rsa_kmgmt.c:428`, security category 0.
- End to end with a FIPS-only library context: `EVP_KDF_CTX_get_params` on HKDF (`provider=fips`) with an `OSSL_PARAM_INTEGER` `"mode"` of `data_size` 0 reaches the setter. It returns 0 with `return_size` 4, and the `data_size` 4 control returns 1 (approved-cg/c186/dyn/run_e2e23_fips.log).
  - fips.so is not sanitizer-built, so this run shows the path only, not the read.
- The out-of-bounds read itself is detected by ASan at unit level for the same value expressions: hkdf mode 0 and rsa seccat 0 give a 1-byte stack-buffer-underflow READ at params.c:155. The val 1 and data_size 4 controls are clean (approved-cg/c186/dyn/run_h23_*.log).
- Status: VIOLATION (recorded), low. It is a one-byte out-of-bounds read of the provider's own stack variable. It is reachable through the public EVP get_params APIs inside the FIPS module boundary, by an application that passes a zero-size integer param. Nothing is written. The responsible-authority sign-off is PENDING, and there is no external report.

### FI-24 addendum (cycle 97gl): not reachable from the FIPS provider
- On LP64, `OSSL_PARAM_set_int` goes through `set_int32`. The FIPS callers that reach `set_int64` are:
  - `set_time_t` at drbg.c:920/924, which passes reseed timestamps, never INT64_MIN;
  - the INTEGER-only template builders param_build_set.c:40 and dh_backend.c:100.
- No FIPS site can be given a REAL param together with INT64_MIN. The defect is confirmed at unit level by UBSan (approved-cg/c186/dyn/run_h24_INT64MIN.log; control run_h24_ctrl.log).
- Status: VIOLATION (recorded), low; application-API only. The responsible-authority sign-off is PENDING.

- FIPS relevance (the dossier's reading): no study requirement cited.

- (gaps, G-3 (cycle 2) — Plane H findings from h-selftest (delivered), unconfirmed) G-2 item 1 update (cycle 3): cleanup_entropy VIOLATION candidate REFUTED by w-zeroize code trace (no reachable trigger); retained as hardening note (skip-clear on lock failure). — FIPS relevance (the dossier's reading): hardening, no requirement violated.
- (gaps, G-4 (cycle 4)) Hardening (not a FIPS-module finding): `DSA_set0_key` frees the old private key with BN_free (runtime-confirmed in libcrypto; FIPS import always targets a fresh DSA). — FIPS relevance (the dossier's reading): hardening, no requirement violated.
- L64 `crypto/dsa/dsa_lib.c` DSA_set0_key — RESIDUE(C): hardening (not FIPS-reachable, G-4); not WP-run; VIOLATION candidate (runtime-confirmed in libcrypto): replacement frees old priv_key with BN_free (no clear unless BN_FLG_SECURE); trigger probes/wz2/runtime/dsa_set0.c (non-secure BN priv 0xAA.., set0 again -> freed 40B limb block holds old key). FIPS-provider reachability NOT established (ossl_dsa_key_fromdata sets into fresh DSA, old priv NULL)

## 2. Observations

- (gaps, G-3 (cycle 2) — Plane H findings from h-selftest (delivered), unconfirmed) 2. VO25 race: on-demand self-test final set_fips_state(RUNNING) (self_test.c:423) may overwrite a concurrent ossl_set_error_state(ERROR). OUT-OF-PLANE for sequential WP → route: macsl \guarded_by / \stable_check attempt first, else TLA+ / CBMC bounded check on the FIPS_state FSM.
- (gaps, G-3 (cycle 2) — Plane H findings from h-selftest (delivered), unconfirmed) G-3 update (cycle 3): item 1 → FI-1 (reported; on-demand-self-test concurrency). Not reachable at POST. Item 2 (VO25 RUNNING-overwrites-ERROR race) still open, out-of-plane for sequential WP.
- (gaps, G-4 (cycle 4)) Read-only (no proof yet): RSA/EC/DH/ML-DSA key free/set paths use BN_clear_free or secure clear-free for private parts.
- FI-6 erratum (recorded under FI-8): **FI-6 erratum (cycle 6, coordinator):** `aes_ocb_block_update` is removed from FI-6's affected list. `providers/fips/fipsprov.c` registers no OCB cipher, so OCB is outside the FIPS boundary.

## 3. Tool defects

None recorded in the ledgers read by this generator.

## 4. Errors in the campaign's own annotations, caught and fixed

- trusted base HE-3: **HE-3b:** EVP_RAND_CTX_free is 53/59. The old TCB assigns (h3b_heap only) omitted the refcount and algctx writes, so it was too narrow (a smuggled axiom), now corrected. Open: the dispatch hop, the fn-ptr RTE (\valid_function claim), terminates, and the recursive-call assigns. EVP_RAND_CTX_new is still TCB.
- trusted base HG-2: HG-2 SHA*_Final contract (h-gates digest harness) — its assigns omit the output buffer, so it is an UNSOUND frame (smuggled axiom). It must be corrected before any digest row is recorded VERIFIED. The body is in crypto/sha, which is REDUCIBLE. OPEN.
- trusted base HS-5: The HS-5c leaf frames have been corrected to include the static `kat_rand`. Proven bodies: self_test_cipher, kdf, drbg, asym_cipher and their helpers (317/317).
- trusted base HS-5: HS-5c and HS-5c-ext (h-selftest/tcb_kats.h) are UNSOUND: the 17 free contracts assigned only the ghost h_lc_heap. They have been replaced by `h-selftest/tcb_kats_honest.h`, which declares `requires zs2_reach_ok(p); assigns h_lc_heap, zs2_rgn(p,0..2)[..]`, and the constructors ensure zs2_reach_ok(\result). All 17 are REDUCIBLE (bodies in-module), so they remain OPEN.
- trusted base Z2-4: Z2-4 EVP_CIPHER_CTX_reset — the cycle-4 `assigns \nothing` was UNSOUND (smuggled axiom). It is replaced by the real byte footprint (ZS2_EVPCTX). Body RESIDUE(C): the indirect `freectx` needs a `calls` set. Every VERIFIED row that depended on the old Z2-4 must be re-proved (an audit has been tasked).
- trusted base Z2-4: Z2-4 EVP_CIPHER_CTX_reset caller footprint: TOO NARROW (omits provider-ctx write) — UNSOUND, must be widened; CMAC rows downgraded to C pending re-proof.
- trusted base Z2-10: ZS-12/ZS-13 (REDUCIBLE, corrected): the cycle-67 `assigns \result` contracts for CRYPTO_zalloc/CRYPTO_malloc and ossl_prov_is_running were too narrow (they write allocator globals, a static counter and the error queue) — a smuggled axiom, self-reported by w-zeroize. Widened to ghost cells wz_alloc_heap / wz_fips_err_heap. Rows resting on the narrow text (kdf_sshkdf_new 11/12) owe re-runs. The same narrow pattern is in w-zeroize-2's Z2-10 (zeroize2_specs.h:345) and Z2-16; flagged.
- trusted base Z2-12: Status: the corrected texts live only in probe copies. Z2-12 and Z2-13 stay REDUCIBLE, OPEN until adopted into harness/ and their bodies proved against them. New REDUCIBLE: the kmac_set_ctx_params_decoder contract (d27_dec_*), assumed by kmac_set_ctx_params 523/523.
- trusted base Z2-12: Z2-12 and Z2-13: corrected texts (probes/wz2/d28/zeroize2_specs_final.h) are PROVEN on their bodies (crypto/sha/sha3_encode.c: ossl_sp800_185_encode_string, get_encode_size, ossl_sp800_185_bytepad, 1026/1026, smoke 48/48). They move to PROVEN-away once harness/ adopts the final text and the dependent rows are re-run on it (owed, d29).
- trusted base Z2-13: Status: the corrected texts live only in probe copies. Z2-12 and Z2-13 stay REDUCIBLE, OPEN until adopted into harness/ and their bodies proved against them. New REDUCIBLE: the kmac_set_ctx_params_decoder contract (d27_dec_*), assumed by kmac_set_ctx_params 523/523.
- trusted base Z2-13: Z2-12 and Z2-13: corrected texts (probes/wz2/d28/zeroize2_specs_final.h) are PROVEN on their bodies (crypto/sha/sha3_encode.c: ossl_sp800_185_encode_string, get_encode_size, ossl_sp800_185_bytepad, 1026/1026, smoke 48/48). They move to PROVEN-away once harness/ adopts the final text and the dependent rows are re-run on it (owed, d29).
- trusted base Z2-16: ZS-12/ZS-13 (REDUCIBLE, corrected): the cycle-67 `assigns \result` contracts for CRYPTO_zalloc/CRYPTO_malloc and ossl_prov_is_running were too narrow (they write allocator globals, a static counter and the error queue) — a smuggled axiom, self-reported by w-zeroize. Widened to ghost cells wz_alloc_heap / wz_fips_err_heap. Rows resting on the narrow text (kdf_sshkdf_new 11/12) owe re-runs. The same narrow pattern is in w-zeroize-2's Z2-10 (zeroize2_specs.h:345) and Z2-16; flagged.
- trusted base Z2-22: Z2-22 provider freectx: previous `assigns \nothing` was UNSOUND (dropped the zeroizing write); corrected to assigns algctx[0..zs2_algsz). Refinement by each VERIFIED FIPS freectx argued, not mechanical — OPEN REDUCIBLE.
- trusted base ZS-2: **The EVP_CIPHER_CTX_free contract (zeroize_specs.h:57, `assigns \nothing`) is UNSOUND**: it is refuted against the body (8/13). It is superseded by `ZS2_CTXFREE` (harness/zeroize2_specs.h), whose assigns prove on the body (12/14; 2 requires open). Still REDUCIBLE and OPEN. Dependents overturned: CMAC_CTX_free, drbg_ctr_free. self_test_kats.c:166 is already C.
- trusted base ZS-6: ZS-6 ossl_prov_digest_load — contract gap fixed (requires), PROVEN-away (38/38).
- trusted base ZS-8: ZS-8 ossl_prov_ctx_get0_libctx — contract corrected (requires ctx null-or-valid), PROVEN-away (body 5/5). Caused a surgical overturn of kdf_pbkdf2_reset (now RESIDUE(C) 20/21).
- trusted base ZS-12: ZS-12/ZS-13 (REDUCIBLE, corrected): the cycle-67 `assigns \result` contracts for CRYPTO_zalloc/CRYPTO_malloc and ossl_prov_is_running were too narrow (they write allocator globals, a static counter and the error queue) — a smuggled axiom, self-reported by w-zeroize. Widened to ghost cells wz_alloc_heap / wz_fips_err_heap. Rows resting on the narrow text (kdf_sshkdf_new 11/12) owe re-runs. The same narrow pattern is in w-zeroize-2's Z2-10 (zeroize2_specs.h:345) and Z2-16; flagged.
- trusted base ZS-13: ZS-12/ZS-13 (REDUCIBLE, corrected): the cycle-67 `assigns \result` contracts for CRYPTO_zalloc/CRYPTO_malloc and ossl_prov_is_running were too narrow (they write allocator globals, a static counter and the error queue) — a smuggled axiom, self-reported by w-zeroize. Widened to ghost cells wz_alloc_heap / wz_fips_err_heap. Rows resting on the narrow text (kdf_sshkdf_new 11/12) owe re-runs. The same narrow pattern is in w-zeroize-2's Z2-10 (zeroize2_specs.h:345) and Z2-16; flagged.
- L76 `providers/implementations/kdfs/pbkdf2.c` kdf_pbkdf2_reset: cyc4 SURGICAL OVERTURN of cyc3 VERIFIED: cyc3 proof rested on ZS-8 contract whose body failed it (6/7); with corrected ZS-8 (requires null-or-valid) the init-call requires needs probe wzp_1 (proves) and wzp_2b (ctx->provctx==provctx after store, bytes-model pointer readback) remains; smoke 4/4; lever: byte-precise cleanup assigns / ghost provctx

## 5. Campaign hygiene

- (gaps, G-4 (cycle 4)) Incident: w-zeroize-2 deleted shared logs/db/*.json mid-run (regenerated byte-identical); any pbkdf2/x942kdf run that failed ~20:30Z must be re-run, never recorded.
- Supersessions in verdicts.tsv: 353 keys, 179 pure duplicates (see the campaign report).
