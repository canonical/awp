# Module definition

Transcribed from section F1 of the requirement study
(`mbedtls-analysis-fips-report.md`). The study was written **code-blind**:
its author read the FIPS 140-3 PDF and the library's public description,
never the source. These definitions are therefore what a FIPS module built
from Mbed TLS should be, not a description of what the code does.

**Target level: 4.** It was chosen when the project was generated
(`--level 4`), not derived from the module. Level 4 is the most demanding
level; several of its requirements (physical tamper response, environmental
failure protection) belong to the hardware platform, not to a software
library (area AR6, `N/A` below).

## Module

- **MOD1**: the Mbed TLS cryptographic library module, a software module.
  Role: provider of cryptographic primitives, key management, random bit
  generation and, above them, the TLS and X.509 protocol layers. Boundary:
  the library's cryptographic and protocol code as built into one
  deliverable. The application, the operating system and the hardware are
  outside it.

## Services

| ID | Service |
|---|---|
| SV1 | symmetric encryption and decryption (block ciphers, authenticated encryption) |
| SV2 | hashing, message authentication, key derivation |
| SV3 | public-key operations (signature generation and verification, key agreement, key-pair generation and import) |
| SV4 | random bit generation (a deterministic generator seeded from an entropy source) |
| SV5 | key management (import, export, storage, destruction) |
| SV6 | TLS handshake and record protection |
| SV7 | X.509 certificate parsing and path validation |
| SV8 | show status, self-test and zeroize |

## Roles

| ID | Role |
|---|---|
| RL1 | crypto officer: initializes MOD1, configures its approved mode, may invoke zeroization and self-tests |
| RL2 | user: runs SV1–SV7 on keys it owns |

## Sensitive security parameters (SSPs)

| ID | SSP | Handled by |
|---|---|---|
| SSP1 | long-term private and secret keys (asymmetric private keys, pre-shared keys) | SV3, SV5, SV6 |
| SSP2 | session and symmetric keys (traffic, encryption, MAC keys) | SV1, SV2, SV6 |
| SSP3 | random bit generator internal state and seed material | SV4 |
| SSP4 | key-agreement ephemeral private values and intermediate secrets | SV3, SV6 |
| SSP5 | password, pre-master and derived secrets | SV2, SV6 |

## Interfaces

| ID | Interface |
|---|---|
| IF1 | the library programming interface for data input and output |
| IF2 | the control input interface (configuration, initialization, mode selection) |
| IF3 | the status output interface (return codes and error indications) |
| IF4 | the entropy-source input interface supplied by the operating environment |

## Finite state model

| ID | State |
|---|---|
| ST1 | uninitialized: MOD1 loaded, no service available |
| ST2 | pre-operational self-test: the integrity test and the self-tests run |
| ST3 | approved operational: services available in the approved mode |
| ST4 | non-approved operational: services available outside the approved mode |
| ST5 | error: a self-test or integrity failure; no data output, no service |
| ST6 | zeroized or terminated: SSPs cleared at end of life or on request |

## How the code maps to this model

From the campaign's code-aware passes (`mbedtls-analysis-fips-gaps.md`,
cycles 1–7):

- ST1 and ST3 exist: `global_data.initialized` and the three subsystem
  flags set by `psa_crypto_init`, cleared by `mbedtls_psa_crypto_free`
  (ST6 then coincides with ST1).
- **ST2 does not exist**: `psa_crypto_init` runs no integrity test and no
  self-test. The `*_self_test()` functions are separate and optional
  (`MBEDTLS_SELF_TEST`).
- **ST5 does not exist**: failures are per-call return codes; nothing
  latches an error state.
- ST3 versus ST4 is not distinguished: there is no approved-mode switch.
- RL1 versus RL2 is not distinguished: there is no operator identity. The
  only access control is the per-key usage policy
  (`psa_get_and_lock_key_slot_with_policy`).

These absences are the design gaps of `design-gaps.md`.
