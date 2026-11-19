# Design gaps

_PAUSED/IN PROGRESS — interim; not a terminus. Generated from the ledgers by `openssl-4.1.0-analysis-acsl/tools/gen-interim-report.py`; do not hand-edit. Sign-off ☐ PENDING._

Requirements whose mechanism is absent, from the gaps file (lines mentioning a design gap) and the study's F5 (residuals naming a design gap or design-gap candidate). No FI entry is routed here: every FI cites a VO# and is in the violations file.

## RQ10, RQ11, RQ12

- **Source:** gaps: G-2 (cycle 2) — VIOLATION candidates surfaced (unconfirmed, need verifier)
- **Recorded:** 5. VO9/VO10: no roles/authentication in code — level-4 design gap (expected per RR2).
- **Requirements and obligations:** RQ10, RQ11, RQ12, VO9, VO10
  - RQ10: MOD1 supports RL1 and RL2, and every service SV1–SV14 runs only for the role(s), and with only the effects, of its row MX1–MX5 of the service-role matrix in F1; no service is reachable outside its row.
  - RQ11: every service that requires a role runs only after identity-based, multi-factor authentication of the operator assuming that role.
  - RQ12: services that change the module's configuration or approved-mode behaviour (SV14, disabling a security check, changing self-test settings) run only for an authenticated RL1.
- **How established:** as recorded above (ledger line); no further proof by the dossier.
- **Proposed treatment:** a design model of the missing mechanism, a wrapper property at the module boundary, or a test, decided by the responsible authority.
- **Consequence for a module built on this code:** the requirement cannot be met by the code as verified; the integrator or the laboratory must supply or waive the mechanism.

## RQ11

- **Source:** report F5 RR3
- **Recorded:** RQ11 — the strength of any operator authentication mechanism (SP 800-140E) is out of formal reach; the public description documents no authentication, so RQ11 is expected to be a design gap — leaves open RQ11 FM10.
- **Requirements and obligations:** RQ11
  - RQ11: every service that requires a role runs only after identity-based, multi-factor authentication of the operator assuming that role.
- **How established:** as recorded above (ledger line); no further proof by the dossier.
- **Proposed treatment:** a design model of the missing mechanism, a wrapper property at the module boundary, or a test, decided by the responsible authority.
- **Consequence for a module built on this code:** the requirement cannot be met by the code as verified; the integrator or the laboratory must supply or waive the mechanism.

## RQ47

- **Source:** report F5 RR23
- **Recorded:** RQ47 — FM29 — the streaming authenticated-decryption interface releases tentative plaintext before the tag check; this depends on the caller obligation EN8 and is a level-4 design-gap candidate for the laboratory; FE4 covers finalization and one-shot paths by functional evidence — leaves open RQ47 FM29.
- **Requirements and obligations:** RQ47
  - RQ47: authenticated-decryption output policy: finalization reports failure on any tag mismatch; one-shot paths where MOD1 holds the whole message (key unwrap, one-shot authenticated decryption) release no plaintext on failure; the public streaming interface releases tentative plaintext before the tag check, which is recorded as a caller obligation (EN8) and a level-4 design-gap candidate (RR23), not demanded as strict buffering.
- **How established:** as recorded above (ledger line); no further proof by the dossier.
- **Proposed treatment:** a design model of the missing mechanism, a wrapper property at the module boundary, or a test, decided by the responsible authority.
- **Consequence for a module built on this code:** the requirement cannot be met by the code as verified; the integrator or the laboratory must supply or waive the mechanism.
