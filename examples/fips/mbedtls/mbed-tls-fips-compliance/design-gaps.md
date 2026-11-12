# Design gaps — requirements the library cannot meet as shipped

These are not code defects. They are FIPS 140-3 requirements whose
mechanism does not exist in Mbed TLS 3.6.7. There is nothing in the code to
prove the requirement on, and a ghost variable standing for the missing
mechanism would be set by nothing, so a "proof" would be vacuous. The
campaign therefore routed them out of the proof planes
(`mbedtls-analysis-fips-gaps.md`, cycles 1, 6 and 7).

The evidence is a structural reading of `psa_crypto_init`
(`library/psa_crypto.c:8611`), `mbedtls_config.h` and searches over the
library. It was not proved with WP or MACSL.

**Consequence.** A FIPS 140-3 module built on Mbed TLS needs a wrapper or
integration layer that adds these mechanisms. Once such a layer exists, its
ordering properties (no output in the error state, self-tests before
service) become provable in the same way the campaign proved
init-before-service.

## G1 — No module error state

| | |
|---|---|
| Requirements | RQ4, RQ5 (AR2, §7.3); RQ11 (AR4, §7.5); RQ26, RQ27 (AR9, §7.10) |
| Obligations | VO4, VO5, VO11, VO22, VO23 |

Failures are per-call return codes. Cycle 6 counted 223
`BAD_STATE`/`CORRUPTION`/`HARDWARE` return sites and no module-level latch:
after a failure, the next call runs normally. So there is no state ST5 in
which output is inhibited and every service refused until a documented
recovery.

Proposed treatment: a design model of the state machine ST1–ST6 (TLA+ or
Alloy) for the module definition, and, once a wrapper owns an error latch,
a MACSL property "no data-output sink while the error latch is set".

## G2 — No operator roles or authentication

| | |
|---|---|
| Requirements | RQ7, RQ8, RQ9 (AR3, §7.4) |
| Obligations | VO7, VO8, VO9 |

The library has no operator identity, no authentication, and no separation
between a crypto-officer and a user role. Its only access control is the
per-key usage policy (`psa_get_and_lock_key_slot_with_policy`). The campaign
scoped RQ7 to that policy and proved it (31 rows, see
`requirements-matrix.md`). RQ8 and RQ9 have no mechanism at all; role
separation relies on the calling application (residual RR15).

## G3 — No integrity test and no self-tests at initialization

| | |
|---|---|
| Requirements | RQ10, RQ12 (AR4, §7.5); RQ24, RQ25 (AR9, §7.10) |
| Obligations | VO10, VO12, VO20, VO21 |

`psa_crypto_init` initializes the driver wrappers, the key slots and the RNG
seeding. It runs no integrity test of the module and no known-answer or
pairwise-consistency self-test. The `*_self_test()` functions exist only
under the optional `MBEDTLS_SELF_TEST` and nothing calls them during
initialization. A search of `psa_crypto.c`, `psa_crypto_driver_wrappers.h`
and `psa_crypto_slot_management.c` for `self_test`, `selftest` or
`integrity` finds nothing.

Proposed treatment: the integrity technique is by definition outside the
code (an HMAC or signature of the binary, checked by the environment); the
ordering "integrity test and self-tests before first service" is provable
only in a wrapper that owns that state. Self-test coverage is checked by
CAVP vectors (residual RR19).

## G4 — No approved-mode distinction

| | |
|---|---|
| Requirements | RQ1, RQ2 (AR1, §7.2) |
| Obligations | VO1, VO2 |

The library has no switch between an approved and a non-approved mode
(states ST3 and ST4 of the study). Which algorithms are available is fixed
at compile time by `mbedtls_config.h`. Showing that only Approved functions
are reachable is therefore a check of the build configuration and the call
graph, not a WP proof, and it was not started (RR1).

## Not gaps: what does exist

- **Initialization and end of life (ST1, ST3, ST6).** `global_data` holds
  the initialization flags. The campaign proved init-before-service for
  every slot-reaching public function except the two of V-1, and proved
  that `mbedtls_psa_crypto_free` clears all three subsystem flags and
  zeroes the RNG state.
- **Stateless hash entry points** do not check initialization at all
  (observation O-4 in `other-findings.md`); a FIPS wrapper must gate them.
