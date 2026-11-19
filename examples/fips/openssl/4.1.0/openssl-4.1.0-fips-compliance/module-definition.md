# Module definition (F1 transcribed)

_PAUSED/IN PROGRESS — interim; not a terminus. Generated from the ledgers by `openssl-4.1.0-analysis-acsl/tools/gen-interim-report.py`; do not hand-edit. Sign-off ☐ PENDING._

Target level: **4** (F1 `level:` line; manifest `fips_level` = 4).

## Module

- **MOD1** the FIPS provider of OpenSSL 4.1.0 — a dynamically loadable software cryptographic module; boundary: the provider image as loaded into the calling process together with its installed integrity-check configuration data; the general-purpose crypto library core that loads it, the TLS library, the command-line tools, the other (default, legacy, base) providers, the operating system and its entropy source are outside the boundary.

## Services

- **SV1** symmetric encryption and decryption — block-cipher modes including authenticated-encryption modes and key wrapping.
- **SV2** message digest — the SHA-2 and SHA-3 families and the extendable-output functions.
- **SV3** message authentication — keyed-hash, cipher-based and Galois MACs and the Keccak-based MAC.
- **SV4** key derivation — the HKDF, TLS 1.2 and TLS 1.3 key schedules, single-step and X9.63 KDFs, counter/feedback KBKDF, SSH KDF and password-based PBKDF2.
- **SV5** random bit generation — deterministic random bit generators (counter, hash and HMAC based) seeded through the core from an entropy source outside the boundary.
- **SV6** key and key-pair generation — symmetric keys and RSA, finite-field, elliptic-curve, Edwards-curve and post-quantum lattice/hash-based key pairs where provided.
- **SV7** digital signature generation and verification.
- **SV8** key agreement and key encapsulation — finite-field and elliptic-curve Diffie-Hellman, X25519/X448, RSA and lattice-based KEMs.
- **SV9** asymmetric key transport — RSA encryption and decryption with OAEP.
- **SV10** key-object management — import, export, duplicate, compare and validate key objects and domain parameters.
- **SV11** self-test on demand — re-running the pre-operational self-tests.
- **SV12** show status — module name, version, operational status and the approved-service indicator.
- **SV13** zeroization — freeing key, context and DRBG objects, and module unload.
- **SV14** installation and configuration — the crypto-officer step that records the integrity-check value, the self-test status and the approved-mode security-check settings in the installed configuration.

## Roles

- **RL1** crypto officer — installs and configures MOD1 (SV14) and may run SV11.
- **RL2** user — invokes the cryptographic services SV1–SV13; the public Security Policies of earlier FIPS-provider validations assume the role implicitly, with no operator authentication.

## Sensitive security parameters

- **SSP1** secret symmetric keys and MAC keys (CSPs) held in key and context objects.
- **SSP2** private asymmetric keys (CSPs).
- **SSP3** public keys and domain parameters (PSPs).
- **SSP4** DRBG internal state, seeds, nonces and entropy input (CSPs).
- **SSP5** shared secrets from key agreement and key encapsulation (CSPs).
- **SSP6** derived keying material and KDF secret inputs, including passwords and intermediate PRF values (CSPs).
- **SSP7** per-operation secret intermediates — signature per-message secrets, ephemeral private keys, decrypted padding buffers (CSPs).
- **SSP8** the integrity-test key and the stored integrity-check value (public by policy; their integrity, not their secrecy, matters).

## Interfaces

- **IF1** data input — plaintext, ciphertext, messages, peer public keys and key material passed into a service.
- **IF2** data output — ciphertext, plaintext, digests, MACs, signatures, generated or exported keys and random output.
- **IF3** control input — algorithm selection, property queries, operation parameters, security-check settings and the installed configuration.
- **IF4** status output — return status, error-queue entries, the approved-service indicator and self-test event notifications.
- **IF5** control output — control signals MOD1 emits to the core (the upcalls requesting entropy and nonces, reporting errors, signalling self-test events).

## States

- **ST1** unloaded — MOD1 not in memory, or unloaded after use; no SSP present.
- **ST2** pre-operational — MOD1 loaded and running its integrity test and pre-operational self-tests; no service available.
- **ST3** operational — self-tests passed; approved and documented non-approved services available, the indicator distinguishing them.
- **ST4** error — a self-test, conditional test or integrity failure occurred; no cryptographic service and no data output until unload and reload.
- **ST5** self-test in progress — an on-demand self-test (SV11) or a conditional test (pairwise consistency, DRBG health) is running; its data output is inhibited.

## Service-role matrix

- **MX1** SV1, SV2, SV3, SV4, SV5, SV6, SV7, SV8, SV9, SV10 — roles RL2 and RL1 — authenticated per RQ11 at the level-4 target; may create, use and deliver SSPs only as the permitted outputs below allow.
- **MX2** SV14 — role RL1 only — may write the installed configuration (integrity-check value, self-test status, security-check settings); no other role and no unauthenticated caller.
- **MX3** SV11 — none — permitted effects: run the self-tests, use the module's own test vectors and test keys, move MOD1 to ST5 and back to ST3, or to ST4 on failure; no access to any operator SSP (SSP1–SSP7).
- **MX4** SV12 — none — permitted effects: read module name, version, operational state and indicator values; no SSP read, write or output.
- **MX5** SV13 — none — permitted effects: zeroization is expressly permitted without authentication; it may destroy (clear and free) any SSP object handed to it and, on unload, the module-global SSPs; it never discloses, copies or substitutes an SSP.

## How the code maps to the model (derived from the ledgers)

This section quotes the code-aware ledgers; it adds no verdict.

### States

- 189 latest verdict rows concern the module-state machinery (FIPS_state writers, the running gate, the error state): 45 VERIFIED, 120 RESIDUE(C).
- FI-1: VO5/VO32 output-inhibit: services produce output while the module is in SELFTEST during an on-demand self-test
- FI-3: VO22/RQ34 selftest-order: with defer-tests configured, the module becomes operational before its KATs run (configuration-dependent)
- FI-4: VO27/VO25 error-state: keygen pairwise-consistency-test failures never enter the module error state
- FI-5: VO25/VO27 error-state: CRNG continuous-test failure sets only a local, non-absorbing state
- FI-6: VO5/VO8 output-inhibit: cipher update paths produce ciphertext after ERROR (gate only at ctx creation)
- FI-7: VO5/VO7 output-inhibit: ECDH derive yields a shared secret after ERROR
- FI-10: VO25 error-state absorbing: a successful on-demand POST overwrites an ERROR raised during it
- FI-13: Pairwise-consistency test skipped for every key generated while the module is in SELFTEST state

### Roles and authentication

- gaps (G-2 (cycle 2) — VIOLATION candidates surfaced (unconfirmed, need verifier)): VO9/VO10: no roles/authentication in code — level-4 design gap (expected per RR2).

### Mechanisms with proof evidence

- VO4 (approved-only): 14 VERIFIED latest rows
- VO5 (output-inhibit): 74 VERIFIED latest rows
- VO6 (output-inhibit): 1 VERIFIED latest rows
- VO8 (output-inhibit): 48 VERIFIED latest rows
- VO15 (zeroize): 47 VERIFIED latest rows
- VO20 (zeroize): 6 VERIFIED latest rows
- VO25 (error-state): 69 VERIFIED latest rows
- VO27 (error-state): 1 VERIFIED latest rows
