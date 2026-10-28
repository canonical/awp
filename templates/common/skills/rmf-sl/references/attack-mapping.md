# ATT&CK + 800-53 taxonomy — the threat-intelligence evidence base (RMF)

The feared-event → **MITRE ATT&CK** technique mapping and the relevant **NIST SP 800-53** control
families. This is the *taxonomy* `macsl`'s **M-8 leaf tags join INTO**: `macsl` only **tags** a proven
leaf with an ATT&CK technique / control id — it does **not own** this taxonomy. The taxonomy lives here
(threat intelligence), the proof lives in WP, and the join is the crosswalk's §3.3 ledger ATT&CK column
(WS9). Authored code-blind from published threat doctrine, not from the implementation.

## Feared-event family → MITRE ATT&CK technique
The STRIDE coverage ledger (`crosswalk-format.md` §3.3) carries an **ATT&CK** column; these are the
techniques each family joins to. (Techniques, not tactics — the leaf-level tag a proof can carry.)

| Feared-event family | STRIDE | Representative ATT&CK technique(s) |
|---|---|---|
| Malformed input / parser over-read (record/length/cert framing) | T / I | **T1190** Exploit Public-Facing Application |
| Tampering with data in transit / state (e.g. downgrade, injection) | T | **T1565** Data Manipulation; T1557 Adversary-in-the-Middle |
| Principal-spoofing / forged identity (WS3 trust boundary) | S | T1556 Modify Authentication Process; **T1557** AiTM |
| Information disclosure / secret leak (residue, timing/padding oracle) | I | **T1552** Unsecured Credentials; **T1600** Weaken Encryption (crypto/side-channel) |
| Repudiation / missing accountability (WS4) | R | T1070 Indicator Removal (log tamper/deletion) |
| Volumetric / flooding DoS (WS6, out-of-band) | D | **T1499** Endpoint DoS; T1498 Network DoS |
| Algorithmic / bounded-work DoS (the `\fuel`-amenable slice) | D | **T1499.004** Application or System Exploitation |
| Privilege elevation above the lattice (WS7) | E | **T1068** Exploitation for Privilege Escalation |
| Weak entropy / DRBG / backend (crypto strength) | I | **T1600** Weaken Encryption |

> `macsl`'s M-8 emits the technique id on the **proven** leaf only — a green tagged `T1190` means the
> memory-safety class of that step is retired (the **named plane**), **not** that T1190 is "covered."
> ATT&CK coverage is a threat-intelligence statement; the proof retires one class of one step.

## Feared-event family → NIST SP 800-53 control family (the `CTL#` binding)
Every `RS#` chains to a `CTL#` (report `report-format.md` §C4c); the `CTL#` token is one of these
800-53 families. The control families relevant to the new workstreams:

| Need | 800-53 control | Note |
|---|---|---|
| **Least privilege** (WS7 privilege lattice) | **AC-6** Least Privilege | the lattice `macsl` proves **monotonicity over**; AC-6 is the Categorize-step baseline |
| **Resource / algorithmic DoS** | **SC-5** Denial-of-Service Protection | bounded-work slice → `\fuel` proof; the rest is rate-limiting |
| **Volumetric / boundary DoS** (WS6) | **SC-5 + SC-7** Boundary Protection | **rate-limiting / capacity** — out-of-band, **never a WP proof** |
| Parser / data integrity | **SI-7** Software, Firmware, Information Integrity; SI-10 Input Validation | the memory-safety plane WP retires |
| Transmission / identity | **SC-8** Transmission Confidentiality/Integrity; **IA-2** Identification & Authentication (WS3) | crypto identity = residual |
| Non-repudiation / audit (WS4) | **AU-10** Non-repudiation; AU-9 Protection of Audit Information | logging = logic residual |
| Cryptographic protection | **SC-12 / SC-13** Key Management / Cryptographic Protection | primitive strength = standing residual `RR#` |
| Supply-chain / compiler | **SR-3 / SA-12** Supply Chain Protection | reproducible build = standing residual `RR#` |

## What is taxonomy here vs proof there (the boundary)
- **Owned here (threat intelligence):** the family → ATT&CK technique map, the family → 800-53 control
  family map. Updated from published doctrine; code-blind.
- **Owned by WP/`macsl` (the proof):** whether the *amenable plane* of a step is actually retired.
- **The join (crosswalk §3.3/§4):** a proven leaf carries its ATT&CK + `CTL#` tag; the cell goes
  `PROVED` **for the named plane only**. A family with no amenable plane (volumetric DoS, crypto
  strength, trust decision) is named here and signed as an `RR#` residual — **never** a false `PROVED`.

See [`stride-families.md`](./stride-families.md) for the code-blind authoring of each family and
[`report-format.md`](./report-format.md) §5 for the residual register / sign-off convention.
