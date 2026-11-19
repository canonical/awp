# Trusted base (parsed)

_PAUSED/IN PROGRESS — interim; not a terminus. Generated from the ledgers by `openssl-4.1.0-analysis-acsl/tools/gen-interim-report.py`; do not hand-edit. Sign-off ☐ PENDING._

Parsed heuristically from `openssl-4.1.0-analysis-acsl/trusted-base.md` (the last mention of an entry ID wins). The ledger is authoritative.

## Counts by class

| parsed status | count |
|---|---|
| IRREDUCIBLE | 10 |
| OPEN (irreducible-candidate, audit owed) | 4 |
| OPEN (reducible) | 21 |
| OPEN (unclassified) | 6 |
| OUT-OF-BOUNDARY | 1 |
| PROVEN-away | 17 |
| RETIRED | 8 |
| UNKNOWN | 8 |

Line mentions: PROVEN-away 50, IRREDUCIBLE 68, OPEN 94, REDUCIBLE 230, RETIRED 19 (over 1218 entry lines).

## Irreducible entries, with why

- **HE-2** [IRREDUCIBLE] — Status summary per agent: HE-1, HE-4b PROVEN-away; HE-2a, HE-3a, HE-4 IRREDUCIBLE (upcalls); HE-2b..d closed.
- **HE-3** [IRREDUCIBLE] — Status summary per agent: HE-1, HE-4b PROVEN-away; HE-2a, HE-3a, HE-4 IRREDUCIBLE (upcalls); HE-2b..d closed.
- **OB-zalloc_pool-c101** [IRREDUCIBLE] — OB-zalloc_pool-c101 re-scoped: inside the FIPS module, CRYPTO_zalloc is the forwarder providers/fips/fipsprov.c:1136 to the core upcall c_CRYPTO_zalloc (crypto/mem.c is not linked into libfips). The pool model therefore belongs on c_CRYPTO_zalloc, which is the module's real external boundary: the core's allocator, outside the module. It becomes IRREDUCIBLE once the forwarder is proved to pass the model through. The crypto/mem.c body attempt (22/24) is not on the FIPS path: memset writes bytes, so under Typed+cast the BIGNUM fields cannot be shown to be zero.
- **TB2** [IRREDUCIBLE] — | TB2 | Frama-C WP + Alt-Ergo/Z3 + byte memory model, machdep gcc_x86_64 | toolchain | IRREDUCIBLE | foundational base | n/a |
- **TB-memset-typed** [IRREDUCIBLE] — Trusted for these rows: the same TB-memset-typed and memcmp-faithful stubs as the KDF/kmac lanes (an IRREDUCIBLE candidate, pending AO).
- **TB-memset-typed-POLY** [IRREDUCIBLE] — **TB-memset-typed-POLY (cycle 91, wp-literals c89):** stub wp-literals/c89/stubs/memset_poly{.h,_spec.c}, redirecting only POLY* memset. It assigns exactly the n bytes and ensures every coefficient is 0. The struct diff against pristine ml_dsa_poly.h is SAME. Twin 17/17 with the stub; mutants A and B are caught definitely (admit-free Coq non-theorems, c89/coq/tm89_mut_notthm.v). Same family as TB-memset-typed and Z2-4T: IRREDUCIBLE candidate pending AO acceptance (machdep: uint32 0 is all-bits-zero). **OB-STUB-vector_zero: PROVEN-away** (the real vector_zero body is inlined).
- **Z2-4** [IRREDUCIBLE] — **TB-memset-typed-POLY (cycle 91, wp-literals c89):** stub wp-literals/c89/stubs/memset_poly{.h,_spec.c}, redirecting only POLY* memset. It assigns exactly the n bytes and ensures every coefficient is 0. The struct diff against pristine ml_dsa_poly.h is SAME. Twin 17/17 with the stub; mutants A and B are caught definitely (admit-free Coq non-theorems, c89/coq/tm89_mut_notthm.v). Same family as TB-memset-typed and Z2-4T: IRREDUCIBLE candidate pending AO acceptance (machdep: uint32 0 is all-bits-zero). **OB-STUB-vector_zero: PROVEN-away** (the real vector_zero body is inlined).
- **Z2-6** [IRREDUCIBLE] — Z2-6T (the typed _Atomic int contract) replaces the Z2-6 cast form. IRREDUCIBLE: a compiler builtin.
- **Z2-10** [IRREDUCIBLE] — `probes/wz2/d30/alloc_live2.h` is ADOPTED as the Z2-10 text (IRREDUCIBLE, allocator boundary). Its condition is met: kmac_init's only CRYPTO_malloc call (overlay line 383) has `call_CRYPTO_malloc_requires_d30_live` part1-4 all Valid (d31 runs B and D), with d28_obase 4/4 and d28_osep 4/4.
- **ZS-9** [IRREDUCIBLE] — **ZS-9** secure_zalloc freshness: WP does not implement `\fresh`. Candidate Frama-C limitation; route through no_ceiling_gate.

## Reducible entries still open (where a proof would come from)

- **HG-3** [OPEN (reducible)] — **HG-3:** EVP_MD_get_size is proven. RSA_size is trusted and rsa_get_md_size has `assigns \nothing`, both pending body proofs.
- **HG-3'** [OPEN (reducible)] — HG-3' is back to OPEN; the i2d proof is at 60/64 and needs a freshness ensures.
- **HS-3** [OPEN (reducible)] — HS-1 tcb_atomic.h, HS-3 ossl_set_self_test_state assigns — unchanged, OPEN.
- **HS-5** [OPEN (reducible)] — HS-5c and HS-5c-ext (h-selftest/tcb_kats.h) are UNSOUND: the 17 free contracts assigned only the ghost h_lc_heap. They have been replaced by `h-selftest/tcb_kats_honest.h`, which declares `requires zs2_reach_ok(p); assigns h_lc_heap, zs2_rgn(p,0..2)[..]`, and the constructors ensure zs2_reach_ok(\result). All 17 are REDUCIBLE (bodies in-module), so they remain OPEN.
- **HS-6** [OPEN (reducible)] — HS-6 (ossl_prov_ml_dsa_new h_mdn_err) is still trusted: REDUCIBLE, OPEN.
- **OB-bn_callees-c92** [OPEN (reducible)] — OB-bn_callees-c92 OPEN, REDUCIBLE: contracts on BN_new, BN_clear, BN_free, bn_wexpand (bn_expand2, bn_expand_internal, calloc, bn_free_d, ERR_raise) and bn_correct_top, over a bn_wf predicate (wp-literals/c92/bn/c92_bn_contracts.h). The bodies are in bn_lib.c; queued.
- **OB-ob_block-c92** [OPEN (reducible)] — OB-ob_block-c92 OPEN, REDUCIBLE candidate: block-cipher abstraction for the crypto_128_unwrap_raw harness. It requires 16 readable input bytes and 16 writable output bytes (in==out allowed) and assigns out[0..15] \from in, key. It over-approximates AES_decrypt. Not covered: key-schedule readability, and that the pointer really is one of the real ciphers. Reducible by proving the real AES_decrypt (C fallback) against it, or by enumerating the FIPS-build callers' block functions.
- **Z2-8** [OPEN (reducible)] — Z2-7..14, Z2-16..21 — new trusted callee contracts (HMAC callees, sp800_185 encode/bytepad, zalloc, is_running, MD_CTX new/copy, digest_copy, indicator). In-module C bodies are REDUCIBLE and OPEN. CRYPTO_malloc via the core upcall is a libcrypto upcall (ZS-1/2 class). is_running is PROVEN by reference (HG-1).
- **Z2-9** [OPEN (reducible)] — Z2-7..14, Z2-16..21 — new trusted callee contracts (HMAC callees, sp800_185 encode/bytepad, zalloc, is_running, MD_CTX new/copy, digest_copy, indicator). In-module C bodies are REDUCIBLE and OPEN. CRYPTO_malloc via the core upcall is a libcrypto upcall (ZS-1/2 class). is_running is PROVEN by reference (HG-1).
- **Z2-11** [OPEN (reducible)] — Z2-7..14, Z2-16..21 — new trusted callee contracts (HMAC callees, sp800_185 encode/bytepad, zalloc, is_running, MD_CTX new/copy, digest_copy, indicator). In-module C bodies are REDUCIBLE and OPEN. CRYPTO_malloc via the core upcall is a libcrypto upcall (ZS-1/2 class). is_running is PROVEN by reference (HG-1).
- **Z2-14** [OPEN (reducible)] — Z2-7..14, Z2-16..21 — new trusted callee contracts (HMAC callees, sp800_185 encode/bytepad, zalloc, is_running, MD_CTX new/copy, digest_copy, indicator). In-module C bodies are REDUCIBLE and OPEN. CRYPTO_malloc via the core upcall is a libcrypto upcall (ZS-1/2 class). is_running is PROVEN by reference (HG-1).
- **Z2-16** [OPEN (reducible)] — RETIRED: Z2-16 \fresh ensures + narrow assigns, Z2-18 assigns-only text (for this scope), d38 pool/d38_zsep/d38_mcell, d39 pool/d39_kcell_res, d39_mreach "for all j" form (restated as zp_zreach, proved), d40_zreach (split: reach-sep half PROVEN via zp_zreach; reach_ok half is zp_zok), the trusted EVP_MD_CTX_new pool ensures (now PROVEN on digest.c).
- **Z2-17** [OPEN (reducible)] — Z2-10/16/17/18 + zeroize2_base.h allocator/fetch contracts widened (ghost zs2_alloc_heap / zs2_err_heap); no VERIFIED row rested on the narrow text (only RESIDUE(C) rows under -DZS2_HMAC/-DZS2_KMAC/-DZS2_KMACDUP). Regression 28/28.
- **Z2-18** [OPEN (reducible)] — RETIRED: Z2-16 \fresh ensures + narrow assigns, Z2-18 assigns-only text (for this scope), d38 pool/d38_zsep/d38_mcell, d39 pool/d39_kcell_res, d39_mreach "for all j" form (restated as zp_zreach, proved), d40_zreach (split: reach-sep half PROVEN via zp_zreach; reach_ok half is zp_zok), the trusted EVP_MD_CTX_new pool ensures (now PROVEN on digest.c).
- **Z2-19** [OPEN (reducible)] — Z2-19 EVP_MD_CTX_copy: writes *out of an opaque type, cannot be named in ACSL; named assumption, used only by kmac_dup (RESIDUE(C)).
- **Z2-20** [OPEN (reducible)] — kmac pool `d39_kcell` (uninterpreted logic function, no axiom) via CRYPTO_zalloc ensures `d39_kcell_res`: REDUCIBLE — adopt with nsep_pool.h and move onto the core `c_CRYPTO_zalloc` pool model (as 97ay), together with the Z2-16/Z2-18/Z2-20 fixes. Caveat: the harness Z2-16 zalloc assigns does not list the zeroed block; widen with the Z2-16 fix.
- **Z2-21** [OPEN (reducible)] — Z2-7..14, Z2-16..21 — new trusted callee contracts (HMAC callees, sp800_185 encode/bytepad, zalloc, is_running, MD_CTX new/copy, digest_copy, indicator). In-module C bodies are REDUCIBLE and OPEN. CRYPTO_malloc via the core upcall is a libcrypto upcall (ZS-1/2 class). is_running is PROVEN by reference (HG-1).
- **Z2-25** [OPEN (reducible)] — Z2-23 BN_free / Z2-24 BN_clear_free / Z2-25 BN_set_flags — crypto/bn bodies in FIPS: REDUCIBLE, OPEN. Z2-26 ossl_public_bn_free — PROVEN-away.
- **Z2-40** [OPEN (reducible)] — **Z2-40** ossl_provider_free: the body is under a multi-object footprint, RESIDUE(C) with at least 19 timeouts. Obstacle: a field frame across a region havoc (same as hmac h2k). Still REDUCIBLE.
- **ZS-1** [OPEN (reducible)] — ZS-6, ZS-7 — OPEN (not started). ZS-1/2/3 — unchanged.
- **ZS-2** [OPEN (reducible)] — ML-DSA key free: ossl_ml_dsa_key_reset + vector_init/free/secure_free contracts PROVEN-away (bodies in the same run, 141/141). wz_rank is a proved caller obligation, not TCB. Remaining TCB: ZS-2, ZS-3, Z2 EVP_MD_free (unchanged).

## Irreducible candidates with an open faithfulness audit

- **HS-1** [OPEN (irreducible-candidate, audit owed)] — HS-1 tcb_atomic.h, HS-3 ossl_set_self_test_state assigns — unchanged, OPEN.
- **HS-4'** [OPEN (irreducible-candidate, audit owed)] — HS-4..6 frame admits RETIRED → replaced by **HS-4' h_tcb_core_bio_{new_file,read_ex,free} stubs** (real <openssl/core.h> types, explicit assigns) + `//@ calls`. These are libcrypto core upcalls via the dispatch table: IRREDUCIBLE for the module (external boundary), assigns faithfulness audit OPEN.
- **OB-CRYPTO_memcmp-c92** [OPEN (irreducible-candidate, audit owed)] — OB-CRYPTO_memcmp-c92 OPEN, IRREDUCIBLE candidate (the FIPS-build implementation is assembly, with no C body in scope); the contract is read-only with an int result, and must be audited as an over-approximation.
- **TB1** [OPEN (irreducible-candidate, audit owed)] — | TB1 | OPENSSL_cleanse(p,n): assigns ((char*)p)[0..n-1]; ensures all bytes ==0 | harness/ossl_fips_specs.h | IRREDUCIBLE (candidate) | shipped body is x86_64 assembly (x86_64cpuid.pl), not C; review: a C mem_clr.c exists only for no-asm builds — not the shipped object | to audit (cycle 2+) |

## Other open / unclassified

- **OB-bn_frame-c98** [OPEN (unclassified)] — The OB-bn_frame-c98 caller side is now closed: the client TUs use epoch- and cursor-indexed predicates whose eight axioms each have a text-identical PROVED lemma in the bn_lib TU (checked by the coordinator). The client texts of BN_new and BN_bin2bn are proved on wrappers in the bn_lib TU (31/31).
- **OB-vb** [UNKNOWN] — **OB-vb (NEW, REDUCIBLE):** the provider core passes freectx/reset only pointers from newctx/dupctx. The newctx side is shown for sshkdf; the dupctx side is not.
- **Z2-41** [UNKNOWN] — **Z2-41 CRYPTO_FREE_REF:** PROVEN (empty in the atomics build).
- **Z2-42** [UNKNOWN] — Z2-42 EVP_PKEY_CTX_free;
- **Z2-43** [UNKNOWN] — **Z2-43 / Z2-45 (stack bodies):** every contract clause is proven on the bodies (62/64 typed). The only open goals are 2 rte_function_pointer goals, the `\valid_function` → False obstacle (16 ledger rows; a status-3 candidate, now being driven).
- **Z2-44** [UNKNOWN] — **Z2-44** (provider teardown pointer): reduced to fips_intern_teardown, which is VERIFIED 6/6. The `calls` binding {NULL, &zs2_ga_provider_teardown} still needs its call-graph justification.
- **Z2-45** [UNKNOWN] — **Z2-43 / Z2-45 (stack bodies):** every contract clause is proven on the bodies (62/64 typed). The only open goals are 2 rte_function_pointer goals, the `\valid_function` → False obstacle (16 ledger rows; a status-3 candidate, now being driven).
- **Z2-46** [UNKNOWN] — **Z2-46** ossl_prov_ctx_free: PROVEN 5/5.
- **ZS-3** [OPEN (unclassified)] — ML-DSA key free: ossl_ml_dsa_key_reset + vector_init/free/secure_free contracts PROVEN-away (bodies in the same run, 141/141). wz_rank is a proved caller obligation, not TCB. Remaining TCB: ZS-2, ZS-3, Z2 EVP_MD_free (unchanged).
- **ZS-4** [OPEN (unclassified)] — **ZS-4 (EVP_MD_fetch):** the assigns is widened to the ghost cell wz_fetch_cache_heap, and pbkdf2 90/90 and provider_util 62/62 re-proved under it. The too-narrow-assigns smuggle is removed.
- **ZS-6** [OPEN (unclassified)] — ZS-6/7/8: these bodies were proven under the old unsound free contracts. They need re-checking and are back to OPEN.
- **ZS-7** [OPEN (unclassified)] — ZS-6/7/8: these bodies were proven under the old unsound free contracts. They need re-checking and are back to OPEN.
- **ZS-8** [OPEN (unclassified)] — ZS-6/7/8: these bodies were proven under the old unsound free contracts. They need re-checking and are back to OPEN.
- **ZS-14** [UNKNOWN] — **ZS-12 CRYPTO_zalloc and ZS-13 ossl_prov_is_running (REDUCIBLE):** their C bodies are trusted in the w-zeroize harness. **ZS-14 CRYPTO_FREE_REF:** proved.

## Retired, proven away or out of boundary

- **HE-1** [PROVEN-away] — Status summary per agent: HE-1, HE-4b PROVEN-away; HE-2a, HE-3a, HE-4 IRREDUCIBLE (upcalls); HE-2b..d closed.
- **HE-4** [PROVEN-away] — Status summary per agent: HE-1, HE-4b PROVEN-away; HE-2a, HE-3a, HE-4 IRREDUCIBLE (upcalls); HE-2b..d closed.
- **HG-1** [PROVEN-away] — HG-1 (h-gates/tcb_gate.h) ossl_prov_is_running contract — imported from VERIFIED vo5_gate_admits_running_or_selftest: PROVEN-away by reference.
- **HG-2** [PROVEN-away] — HG-2: SHA1_Final and SHA256_Final are PROVEN (rows recorded cycle 97ar); SHA224_Final was already proven. HG-2 is back to PROVEN for SHA1/SHA224/SHA256.
- **HS-2** [RETIRED] — HS-2 verify_integrity ghost contract — RETIRED (replaced by body proof, 22/25, residue C).
- **HS-4** [RETIRED] — HS-4 BIO callbacks (fn-ptr): named TCB residual; lever: \valid_function + calls binding.
- **OB-BN_bin2bn-c91** [PROVEN-away] — OB-BN_bin2bn-c91: the body is PROVEN against the c97 contract (bin2bn 819/819, BN_bin2bn 15/15, smoke clean). The c91 harness text itself is a CONTRACT FINDING: it is too weak to be true on the body (it omits ret == NULL || bn_wf(ret) and the separation of s from *ret / ret->d, and its \from omits the allocator). So OB-BN_bin2bn-c91 is NOT PROVEN-away yet: it is replaced by the c97 text, whose requires must be discharged at asn1_dsa.c:211 (open, tracked by the new asn1_dsa composition row). REDUCIBLE, OPEN.
- **OB-STUB** [PROVEN-away] — **TB-memset-typed-POLY (cycle 91, wp-literals c89):** stub wp-literals/c89/stubs/memset_poly{.h,_spec.c}, redirecting only POLY* memset. It assigns exactly the n bytes and ensures every coefficient is 0. The struct diff against pristine ml_dsa_poly.h is SAME. Twin 17/17 with the stub; mutants A and B are caught definitely (admit-free Coq non-theorems, c89/coq/tm89_mut_notthm.v). Same family as TB-memset-typed and Z2-4T: IRREDUCIBLE candidate pending AO acceptance (machdep: uint32 0 is all-bits-zero). **OB-STUB-vector_zero: PROVEN-away** (the real vector_zero body is inlined).
- **OB-bn_pool-c97** [RETIRED] — OB-bn_pool-c97, object half: the BN_new allocator contract (it returns cell(cursor), advances the cursor, assigns only cells at or above it) is now PROVEN on the real BN_new body (bn_lib.c:237-246), 19/19 with 0 Doomed. It is proved against the c99 contract plus a ghost `c101_zheap` (allocator internal state and error queue); probe p2 shows the c99 assigns without that ghost is not provable.
- **Z2-1** [PROVEN-away] — **Z2-1** cipher/digest reset: re-VERIFIED 28/28 under the flag.
- **Z2-2** [RETIRED] — Z2-2 CMAC_CTX_free, ZS2_ECKEY EC_GROUP_free/EC_POINT_free, and the abstract ZS2_BN BN_free (superseded by the proven ZS2_BNC).
- **Z2-3** [PROVEN-away] — (w-zeroize-2, harness/zeroize2_specs.h) **Z2-1 ossl_prov_cipher_reset** (C, provider_util.c:20) REDUCIBLE OPEN · **Z2-2 CMAC_CTX_free assigns \nothing** (C cmac.c:85) REDUCIBLE OPEN · **Z2-3 ossl_cipher_generic_reset_ctx** PROVEN-away (15/15) · **Z2-4 EVP_CIPHER_CTX_reset assigns \nothing** (C evp_enc.c) REDUCIBLE OPEN · **Z2-5 CRYPTO_ocb128_cleanup assigns *ctx** (C ocb128.c) REDUCIBLE OPEN.
- **Z2-5** [OUT-OF-BOUNDARY] — Z2-5 CRYPTO_ocb128_cleanup — OUT OF FIPS BOUNDARY (no OCB in fipsprov.c). Not a FIPS TCB entry.
- **Z2-7** [PROVEN-away] — Z2-7 PROVEN-away: ossl_mac_check_key_size (assigns \nothing) proved on its body, 10/10 with smoke; ossl_kdf_check_key_size's new assigns-\nothing contract proved in the same run.
- **Z2-12** [PROVEN-away] — Z2-12 / Z2-13 (cycle 97w): PROVEN-away. harness/zeroize2_specs.h now carries the texts proved on the sha3_encode.c bodies (1026/1026); dependent kmac rows re-run on it (173/173).
- **Z2-13** [PROVEN-away] — Z2-12 / Z2-13 (cycle 97w): PROVEN-away. harness/zeroize2_specs.h now carries the texts proved on the sha3_encode.c bodies (1026/1026); dependent kmac rows re-run on it (173/173).
- **Z2-15** [PROVEN-away] — Z2-15 CRYPTO_DOWN_REF — PROVEN-away.
- **Z2-22** [PROVEN-away] — Z2-22: PROVEN-away by refinement — each of 6 FIPS freectx proven 7/7 against the Z2-22 contract.
- **Z2-23** [RETIRED] — The BN_clear_free/BN_free contracts are now NULL-guarded and still PROVEN (51/51), so Z2-23/24 stay retired.
- **Z2-24** [RETIRED] — The BN_clear_free/BN_free contracts are now NULL-guarded and still PROVEN (51/51), so Z2-23/24 stay retired.
- **Z2-26** [PROVEN-away] — Z2-23 BN_free / Z2-24 BN_clear_free / Z2-25 BN_set_flags — crypto/bn bodies in FIPS: REDUCIBLE, OPEN. Z2-26 ossl_public_bn_free — PROVEN-away.
- **ZS-5** [PROVEN-away] — **ZS-5:** made exact. ZS-11 now requires pd->alloc_md == NULL, so EVP_MD_free writes nothing; callers must prove it (pbkdf2 init does).
- **ZS-10** [PROVEN-away] — ZS-10 ossl_FIPS_IND_init: PROVEN-away (27/27).
- **ZS-11** [PROVEN-away] — **ZS-5:** made exact. ZS-11 now requires pd->alloc_md == NULL, so EVP_MD_free writes nothing; callers must prove it (pbkdf2 init does).
- **ZS-12** [RETIRED] — ZS-12 CRYPTO_zalloc body: 12/16, REDUCIBLE; blockers \fresh (status-3 bundle) and TB-cast (char vs unsigned char memset view).
- **ZS-13** [RETIRED] — ZS-12/13 narrow-assigns axiom retired for kdf_sshkdf_new (re-run under widened contracts, 11/12).

## Which proofs rest on which entries

| row | VERIFIED function | entries named in its notes |
|---|---|---|
| L783 | aes_freectx | Z2-22 |
| L1005 | CMAC_CTX_cleanup | TB-memset-typed, Z2-4 |
| L1005 | CMAC_CTX_free | TB-memset-typed, Z2-4 |
| L864 | ossl_ecx_key_free | Z2-6, ZS-14 |
| L807 | ossl_rand_drbg_free | ZS-5 |
| L931 | ossl_prov_digest_reset | Z2-10, Z2-16, Z2-17 |
| L931 | ossl_prov_cipher_reset | Z2-10, Z2-16, Z2-17 |
| L1413 | kmac_new | OB-vb, TB-memset-typed |
| L170 | SELF_TEST_lock_deferred | HS-5 |
| L171 | SELF_TEST_unlock_deferred | HS-5 |
| L946 | ossl_ml_dsa_key_reset | ZS-2, ZS-3 |
| L200 | Z2-22 refinement (6 FIPS freectx) | Z2-22 |
| L858 | ossl_slh_dsa_key_free | TB1 |
| L858 | slh_dsa_key_hash_cleanup | TB1 |
| L1468 | ossl_FIPS_IND_init | ZS-10 |
| L1468 | ossl_FIPS_IND_set_approved | ZS-10 |
| L264 | EVP_MD_get_size | HG-3 |
| L265 | DSA_size | HG-3' |
| L1073 | test_rng_set_ctx_params_decoder | TB-memset-typed |
| L495 | CRYPTO_THREAD_lock_free | HE-3 |
| L571 | set_kat_drbg :1032 (he3b_inst, probe copy) | HE-3 |
| L613 | EVP_RAND_free | HE-3 |
| L820 | ossl_prov_digest_fetch+ossl_prov_digest_load (ZS-11 body) | ZS-11 |
| L1471 | kmac_final | OB-vb |
| L613 | evp_rand_free | HE-3 |
| L613 | CRYPTO_DOWN_REF | HE-3 |
| L613 | CRYPTO_FREE_REF | HE-3 |
| L766 | dsa_verify_directly | HG-3 |
| L789 | CRYPTO_DOWN_REF | Z2-6 |
| L789 | CRYPTO_FREE_REF | Z2-6 |
| L842 | DH_set0_key | ZS-2 |
| L859 | CRYPTO_FREE_REF | Z2-6, ZS-14 |
| L946 | ossl_ml_dsa_key_free | ZS-2, ZS-3 |
| L946 | vector_init | ZS-2, ZS-3 |
| L946 | vector_free | ZS-2, ZS-3 |
| L946 | vector_secure_free | ZS-2, ZS-3 |
| L942 | rsa_keygen (caller obligation he4_k) | HE-4 |
| L1011 | hkdf_set_ctx_params_decoder (listed props gw_scan/gw_ok/dec_pure/dec_end/dec_keys/dec_frame/dec_rng/dec_ninfo/dec_inv_mode/dec_mode + tm_valid/tm_zero/tm_size call requires; c88 //@-only hkdf.inc overlay; TB-memset-typed stub c87/stubs/memset_typed.h + memset_typed_spec.c, unmodified) | TB-memset-typed |
| L1019 | hint_bits_decode (Oracle-B hint, stub-free annot7 + TB-memset-typed-POLY) | OB-STUB, TB-memset-typed, TB-memset-typed-POLY, Z2-4 |
| L1079 | ossl_sp800_185_encode_string,get_encode_size (Z2-12 + nowrap + object_pointer(in) + separated(out,in) + assigns zs2_err_heap) | Z2-12 |
| L1082 | ossl_sp800_185_bytepad (Z2-13 + requires in1 != NULL && object_pointer(in1)) | Z2-13 |
| L1084 | ossl_mac_check_key_size (exact Z2-7 text: assigns \nothing) + ossl_kdf_check_key_size (new contract assigns \nothing, proved) | Z2-7 |
| L1108 | kmac_set_ctx_params (whole, RTE, own contract, smoke) | Z2-12, Z2-13 |
| L1132 | ossl_sp800_185_encode_string,get_encode_size,ossl_sp800_185_bytepad (whole, RTE, own contracts, smoke) | Z2-12, Z2-13 |
| L1135 | kmac_set_ctx_params_decoder (whole, RTE, by groups + ALL/smoke) | TB-memset-typed |
| L1143 | ossl_sp800_185_encode_string,ossl_sp800_185_bytepad (contract texts) | Z2-12, Z2-13 |
| L1385 | kmac_set_ctx_params (whole, RTE, own contracts, smoke) | TB-memset-typed |
| L1178 | BN_bin2bn | OB-bn_callees-c92, OB-bn_pool-c97 |
| L1179 | bin2bn (static) | OB-bn_callees-c92, OB-bn_pool-c97 |
| L1194 | BN_bin2bn (c98 restatement of the c97 contract via shared predicates) | OB-bn_callees-c92, OB-bn_pool-c97 |
| L1256 | d2i_ECDSA_SIG | OB-bn_pool-c97 |
| L1229 | BN_bin2bn (c99 contract: c98 text + assigns bn99_cur, ensures cur_mono, frame_wf, frame_sep, frame_fresh on every OTHER BIGNUM b with old bn_old(b) && bn_other(b, ret)) | OB-bn_callees-c92, OB-bn_pool-c97 |
| L1255 | d2i_DSA_SIG | OB-bn_pool-c97 |
| L1249 | lemmas bn_sep_sub_at, bn_pool_sep_sub, bn_fresh_wf_at, bn_fresh_sep_at, bn_cell_old, bn_cell_other, bn_fresh_other, bn_new_fresh | OB-bn_pool-c97 |
| L1250 | c100_BN_new, c100_BN_bin2bn (wrappers carrying the CLIENT texts c100/spec/bn_new.acsl, c100/spec/bn_bin2bn.acsl) | OB-bn_callees-c92, OB-bn_pool-c97 |
| L1252 | ossl_decode_der_integer (callee contract: + assigns bn99_cur, bn100_ep; ensures cur_mono, sep_carry and frame_wf for every other BIGNUM b with old bn_old_at(b, cur) && bn_other_at(b, n, ep)) | OB-bn_pool-c97 |
| L1253 | ossl_decode_der_dsa_sig (direct; + requires s_old: bn_old_at(s, bn99_cur), s_other: bn_other_at(s, r, bn100_ep); assigns *ppin, bn99_cur, bn100_ep) | OB-bn_pool-c97 |
| L1254 | ob_der_dsa_sig (harness, decoder inlined; entry requires + s_old/s_other) | OB-bn_pool-c97 |
| L1326 | BN_new (real body bn_lib.c:237-246) against the c99 allocator contract + c101_zheap, from the c101 pool CRYPTO_zalloc model | OB-zalloc_pool-c101 |
| L1357 | kmac_init (whole, RTE, own contracts; callees by contract) | OB-vb |
| L1397 | kmac_set_ctx_params_decoder (whole, RTE, own contracts, smoke) | TB-memset-typed, Z2-16, Z2-18 |
| L1413 | kmac_free | OB-vb, TB-memset-typed |
| L1416 | bn_expand_internal (bn_lib.c:259) WITHOUT csrc/csep/lsep: requires only bwf: bn_wf, bcv: bn_cv, wtop; ensures x_cell with the char view \valid((char *)\result + (0 .. words*sizeof(BN_ULONG)-1)) and cursor + words*sizeof(BN_ULONG) | OB-bn_pool-c97 |
| L1457 | OSSL_provider_init_int (fipsprov.c:814), set_func loop (fipsprov.c:827-930): bind c_CRYPTO_zalloc == &c103_core_CRYPTO_zalloc at loop exit (assert bind_est) | TB-memset-typed |
| L1467 | EVP_MD_up_ref,evp_md_up_ref (whole, RTE, smoke) | Z2-20 |
| L1509 | cmac_new (whole, RTE, smoke) | Z2-16 |
| L1556 | (whole-function smoke re-check of verdicts.tsv line 690) gcm_tls_cipher | TB1 |
| L1557 | (whole-function smoke re-check of verdicts.tsv line 700) ml_dsa_verify_msg_final | TB1 |
| L1560 | (whole-function smoke re-check of verdicts.tsv line 605) self_test_kdf | TB1 |
| L1563 | mlx_kem_export | TB-memset-typed |
| L1589 | (whole-function smoke re-check of verdicts.tsv line 217) slh_dsa_sign | TB1 |
| L1594 | (whole-function smoke re-check of verdicts.tsv line 187) ml_dsa_sign | TB1 |
| L1623 | evp_mac_new, CRYPTO_NEW_REF (whole, RTE, smoke) | TB-memset-typed |
| L1643 | evp_mac_free, CRYPTO_DOWN_REF, CRYPTO_FREE_REF (whole, RTE, smoke) | ZS-3 |
| L1700 | kmac_new, kmac_dup (whole, RTE, smoke) | Z2-17 |
| L2146 | sshkdf_set_ctx_params_decoder | TB-memset-typed |
| L2179 | kbkdf_set_ctx_params_decoder | TB-memset-typed |
| L2185 | sshkdf_set_ctx_params_decoder | TB-memset-typed |
| L2196 | (Oracle-B modular harness) sskdf_set_ctx_params_decoder | OB-PARAM |
| L2235 | (Oracle-B modular harness) test_rng_set_ctx_params_decoder | HE-3 |
| L2243 | hmac_set_ctx_params_decoder | TB-memset-typed |
| L2251 | pbkdf2_set_ctx_params_decoder | TB-memset-typed |
| L2252 | gmac_set_ctx_params_decoder | TB-memset-typed |

Every VERIFIED row also rests on TB2 (the toolchain).
