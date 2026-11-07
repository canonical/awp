# FIPS 140-3 requirement study — <module>

## F1 — Module and target level

level: 3

- MOD1 <module role, e.g. the full-disk-encryption module> — boundary <the documented cryptographic boundary>.
- SV1 <service> — a documented service of MOD1.
- RL1 <role> — the authenticated role entitled to run SV1.
- SSP1 <sensitive security parameter> — key material handled by SV1.
- IF1 <documented interface> — a data entry point of MOD1.
- ST1 <state> — an operating state of MOD1.

## F2 — Requirement areas

- RQ1 — AR1 — src:PDF-ann10 — in the approved mode, every service of MOD1 employs only Approved security functions.
- RQ2 — AR2 — src:UNSOURCED — no data output while MOD1 is in an error or self-test state.
- RQ3 — AR3 — src:UNSOURCED — min-level 2 — SV1 runs only for an authenticated, authorized RL1.
- RQ4 — AR4 — src:UNSOURCED — the integrity test of MOD1 runs, and passes, before any service.
- RQ5 — AR8 — src:UNSOURCED — SSP1 is zeroized after use by SV1 and on every error path.
- RQ6 — AR8 — src:UNSOURCED — no plaintext SSP leaves MOD1 through IF1.
- RQ7 — AR9 — src:UNSOURCED — the pre-operational self-tests of MOD1 run before first use of SV1.
- RQ8 — AR10 — src:UNSOURCED — the transitions MOD1 allows are those of its documented finite state model.
- AR5 N/A — operating environment out of the module boundary.
- AR6 N/A — software-only module, no physical enclosure.
- AR7 N/A — non-invasive security out of reach of the formal tools.
- AR11 N/A — no other-attack requirement surfaced at this level.

## F3 — Failure modes

- FM1 — RQ5 — SSP1 left in readable memory after an error path of SV1.
- FM2 — RQ2 — data output through IF1 while MOD1 is in an error state.
- FM3 — RQ7 — SV1 runs before the pre-operational self-tests of MOD1 have passed.

## F4 — Verification obligations

- VO1 — FM1 — RQ5 — zeroize — P1 — prove the clearing of SSP1 on every return path of SV1.
- VO2 — FM2 — RQ2 — output-inhibit — P2 — prove IF1 emits no data in an error state.
- VO3 — FM3 — RQ7 — selftest-order — P1 — prove the self-tests precede first use of SV1.

## F5 — Residuals and sign-off

- RR1 — RQ1 — plane validation — treatment: the Approved-functions list is transcribed, not proven; the CMVP validation covers it — leaves open RQ1.
- RR2 — RQ3 — plane crypto — treatment: the authentication mechanism's strength is out of formal reach; KAT vectors — leaves open RQ3.
- RR3 — RQ4 — plane crypto — treatment: the integrity technique itself is trusted; the proof covers its ordering only — leaves open RQ4.
- RR4 — RQ6 — plane supply-chain — treatment: a compiler or linker may remove or weaken the zeroization; SLSA/reproducible build — leaves open RQ6.
- RR5 — RQ8 — plane logic — treatment: configuration management and delivery of the state model — leaves open RQ8.
- RR6 — AR5 — plane ENV — treatment: the operating environment is outside the module boundary — STANDING.
- RR7 — AR6 — plane physical — treatment: not applicable: no physical enclosure; physical control at the system boundary — STANDING.
- RR8 — AR7 — plane side-channel — treatment: constant-time tooling and leakage assessment, not WP — STANDING.
- RR9 — STANDING — plane crypto — treatment: strength of the cryptographic primitives; KAT vectors — STANDING.
- RR10 — STANDING — plane supply-chain — treatment: compiler correctness including removed zeroization; SLSA/reproducible build — STANDING.
- RR11 — STANDING — plane validation — treatment: the CMVP validation itself; a proof is evidence for the laboratory, not a validation — STANDING.

Sign-off: ☐ PENDING — the owner of the protected information, or the agency's responsible authority, acknowledges and accepts the residual risk (Ann. 13).
