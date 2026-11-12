# FIPS 140-3 violations found in Mbed TLS 3.6.7

A violation here is code that contradicts a requirement of the FIPS study,
shown by a failing proof and reproduced on the real build. The campaign
found **one**, V-1, which violates two requirements. Requirements that
cannot be met because the library lacks the mechanism are not violations of
this kind; they are in `design-gaps.md`. Library defects with no FIPS
requirement attached are in `other-findings.md`.

## How to read the FIPS references

FIPS 140-3 adopts ISO/IEC 19790:2012 for its technical requirements. The
campaign's requirements (`RQ#`) are paraphrases grouped by the eleven areas
of ISO/IEC 19790 clause 7, marked `src:UNSOURCED`. The ISO/IEC 19790 clause
below is from general knowledge of the standard and was not checked against
its text; verify it before citing it in a submission.

## V-1 — `psa_close_key` / `psa_purge_key` crash outside the operational state

| | |
|---|---|
| Functions | `psa_close_key`, `psa_purge_key` (`library/psa_crypto_slot_management.c`) |
| Kind | NULL dereference, finite-state-model violation |
| Requirements | **RQ29**, **RQ30** (area AR10); obligations VO25, VO26; failure modes FM29, FM30 |
| Standard clause | ISO/IEC 19790:2012 §7.11 *Life-cycle assurance*, finite state model sub-clause (§7.11.4) |
| Effect | process crash (availability); no key disclosure shown |
| Configuration | shipped default |
| Status | VIOLATION, formally witnessed, reproduced, fix proved |

### The defect

In the default configuration, `MBEDTLS_PSA_KEY_STORE_DYNAMIC` is defined
(`include/mbedtls/mbedtls_config.h:1446`). Under it, `psa_close_key()` and
`psa_purge_key()` call `psa_get_and_lock_key_slot_in_memory()` directly.
They skip the `psa_get_key_slots_initialized()` check that
`psa_get_and_lock_key_slot()` and `psa_reserve_free_key_slot()` make. For a
persistent key ID the slot scan computes
`&global_data.key_slices[KEY_SLOT_CACHE_SLICE_INDEX][i]`. That slice is NULL
until `psa_initialize_key_slots()` allocates it, so reading `slot->state`
dereferences NULL.

### Reproduction

On the real `libmbedcrypto.a`, default configuration
(`mbedtls-analysis-acsl/repro/v1_close_purge.c`, run by `repro/run.sh`,
transcript `repro/repro-run.txt`):

```c
psa_close_key(1);                    /* before psa_crypto_init: SIGSEGV */
psa_purge_key(1);                    /* before psa_crypto_init: SIGSEGV */
psa_crypto_init(); mbedtls_psa_crypto_free();
psa_close_key(1);                    /* after free: SIGSEGV */
```

Controls, in the same states: `psa_destroy_key(1)` returns
`PSA_ERROR_BAD_STATE` (-137); a volatile ID, `psa_close_key(0x40000001)`,
returns -136.

### Formal evidence

- WP leaves exactly the `slot_lookup_after_init` goals unproved at these
  two call sites: `psa_close_key` 5/7, `psa_purge_key` 6/8.
- With the guard added, both prove completely (8/8 and 9/9): the
  `REPAIR-PROVED` row of `verdicts.tsv`.
- Independently witnessed by the Oracle-B tests and an UBSan run (cycle 7b).
- Cycle 7 enumerated the whole public surface: every other public function
  that reaches the key store goes through the init check. V-1 is the only
  unguarded path.

### The clause

The study's model of the module (`module-definition.md`) has six states.
ST1 *uninitialized* and ST6 *zeroized or terminated* allow no service.

- **RQ29**: "the transitions MOD1 allows are those of its documented finite
  state model ST1 to ST6."
- **RQ30**: "no sequence of calls reaches a state, such as a service state
  without the completed self-tests, that the finite state model does not
  contain."

ISO/IEC 19790 requires the module's operation to be specified by a finite
state model (in FIPS 140-3, part of area 11, life-cycle assurance). Every
input in every state must lead to a state the model contains. A
key-management call (service SV5) made in ST1 or ST6 must leave the module
in that state and return an error on the status interface (IF3).
`psa_destroy_key` does exactly that. `psa_close_key` and `psa_purge_key`
crash instead: the module leaves its state model, which is FM29 and FM30.

A secondary reading: the error is never reported on the status interface,
which also bears on RQ5 (area AR2, interfaces, §7.3).

### Precondition and severity

The trigger needs an application that calls these functions outside the
documented "call `psa_crypto_init` first" rule: before initialization, or
after `mbedtls_psa_crypto_free`. The effect is a crash; nothing is
disclosed. For a FIPS module the severity is the state-model breach itself:
the module must define its behaviour in every state, not rely on the caller.

### Fix

Add the `psa_get_key_slots_initialized()` check to both functions and
return `PSA_ERROR_BAD_STATE`, as their siblings do. A proposed diff is in
`mbedtls-analysis-acsl/repro/`. The fixed functions prove completely.
