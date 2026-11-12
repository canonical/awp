# Trusted base

Every proof in this dossier is relative to these assumptions. They are
contracts the verifier assumed rather than proved: a wrong one can make a
proof vacuous or unsound (see VAC-1 and the trusted-contract errors in
`other-findings.md` §4). Source: `mbedtls-analysis-acsl/trusted-base.md`
(364 lines) and `mbedtls.md` §5.

## Counts

| Class | Entries |
|---|---|
| `SL-*` entries | 46 |
| irreducible (cannot be proved in this setting) | 10 |
| reducible, still open (a proof could retire them) | 10 |
| reducible, retired by a later proof | 5 |
| no class recorded, still open | 19 |
| not applicable in the as-built configuration | 1 (SL-CIPHER-1) |
| tool and model entries (`T-*`) | 11, of which 7 irreducible |

## Irreducible entries

| ID | Assumption | Why it cannot be proved here |
|---|---|---|
| SL-STUB-1 | `explicit_bzero` behaves as its man page says | a glibc function outside the module |
| SL-ASM-1 | the empty `asm volatile` in `mbedtls_platform_zeroize` assigns nothing | compiler semantics of an empty `asm`; WP aborts without it (TOOL-3) |
| SL-LIBC, SL-LIBC-2, SL-LIBC-3 | Frama-C 32.1's libc contracts (`memset`, `free`, …) | the C library is outside the module |
| SL-PSA-3 | local input/output copies live in a ghost heap disjoint from the caller's memory | WP has no allocation freshness (TOOL-2) |
| SL-PSA-7 | contracts of the PSA abort and derivation internals | bodies too large in this setting |
| SL-PSA-16 | the free-slot index invariant `ff_ok` | needs a pool invariant over 23 slices; checked by source reading |
| SL-PSA-17 | `psa_wipe_key_slot` header contract (corrected in cycle 12) | as SL-PSA-16 |
| SL-PSA-22 | `slot->slice_index` names the slice that contains the slot | a C undefined-behaviour hypothesis the source says cannot be checked |

## Reducible entries still open

| ID | Assumption | Where the proof would come from |
|---|---|---|
| SL-MD-2 | `mbedtls_md_hmac_{starts,update,finish}` return 0 on a set-up context | `md.c` and the hash engines; OBS-1 depends on it |
| SL-MD-3 | the hash engine state behind the context is opaque and fresh | costly: an honest footprint breaks the HKDF frame proof |
| SL-MD-4 | `md_init`, `md_free`, `md_setup` contracts | `md.c:418` |
| SL-HASH-1 | `update` and `finish` of the hash engines; `sha3` | the `starts` legs are already retired |
| SL-PSA-1 | slot lookup returns a valid slot on success (partly retired) | `psa_crypto_slot_management.c` |
| SL-PSA-2 | footprint of `psa_random_internal_generate` | `psa_crypto_random.c` → `ctr_drbg` |
| SL-PSA-5 | `assigns` footprints of the SL-PSA-1/4 stubs whose bodies are in unverified files | those files |
| SL-PSA-6 | `psa_start_key_creation` / `finish` / `fail` contracts | `psa_crypto.c` (needs SL-PSA-23, an assumed pool invariant) |
| SL-PSA-8 | `psa_key_policy_algorithm_intersection` | 150 goals time out; the algorithm lattice of the policy gate is therefore not proved |
| SL-PSA-10 | `slots_link`: once the key slots are initialized, the persistent-key slice is valid (a `requires` of slot lookup, `psa_close_key`, `psa_purge_key`) | partly proved: init sets the flag only with a non-NULL slice; V-1 is where it does not hold |

## Retired by proof

SL-MD-1, SL-PSA-1b, SL-PSA-4, SL-CT-1, SL-PSA-9.

## What this means for the evidence

- The zeroization proofs rest on SL-STUB-1, SL-ASM-1 and the libc
  contracts. They also need the compiler not to remove the clearing:
  residuals RR13 and RR20 (`residuals-and-signoff.md`).
- The key-policy and export-gating proofs rest on SL-PSA-1, SL-PSA-6 and
  SL-PSA-8.
- Closing Gate T item 3 needs the ten open reducible entries retired.
