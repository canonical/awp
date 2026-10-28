# RMF report-format convention (PINNED) — the `rmf-lint.sh` contract

This is the **authoritative, fixed** format an `rmf-sl` report must follow. It is the contract the
mechanical lower bound (`rmf-lint.sh`) parses and the assessment author writes to — one source of
truth, so the linter and the report cannot drift. It layers stable tags onto the NIST RMF method
content (the `nist/` corpus: SP 800-30 assessment mechanics, SP 800-37 the 7-step lifecycle, SP
800-53 the control catalog) with **STRIDE** as the threat-identification engine
(`nist/sp-800-stride-link.txt`). It is the faithful sibling of `ebios-sl/references/report-format.md`
(EBIOS `W1-W5` -> RMF `R1-R5`).

## Rule 0 — locality (load-bearing, because the linter is line-oriented)
Write **one artifact per markdown list item or table row**, and put **all of its tokens** (its tag,
its impact/likelihood, and **the IDs it derives from**) **on that same line/row**. The linter detects
impact, likelihood, and chaining by *line proximity* — an artifact whose impact sits in a following
paragraph, or whose parent ID is mentioned three lines away, reads to the linter as *missing*.
Locality is the price of a dependency-free linter; keep it.

**Corollary (chain-masking caveat, inherited from `ebios-lint`'s line model):** the chain checks
(C4/C4b/C4c) test whether an id appears *anywhere* a downstream id also appears. So a **back-reference**
— e.g. an R5 control line `- CTL2 SC-8 … (treats RS2)` that names `RS2` next to `CTL2` — can *satisfy*
C4c even if the R4 `RS2` line itself forgot its control. Write each `RS` line with its full inline
chain (`TE … VU … CTL …`) per Rule 0, and **do not** rely on an R5 back-reference to carry it; a
back-referenced id can mask a genuinely-dropped link. (Same property as `ebios-lint.sh`; not an
`rmf`-specific weakness.)

## Rule 1 — RMF sections (R1-R5)
Each RMF section is a heading containing **`Section N`** (preferred) or **`RN`**, `N` in 1..5:
`## R1 — Prepare & Categorize`. The linter slices the report by these headings; R1-R4 text is what the
endogeneity tripwire scans. The five sections mirror the EBIOS workshops via the NIST crosswalk
(`nist/README.txt`):

| Section | Title | NIST process | Source doc |
|---|---|---|---|
| **R1** | Prepare & Categorize | Prepare (800-37) + Categorize (FIPS-199-style impact Low/Mod/High) + Prepare-for-assessment (800-30) | 800-37, 800-30 |
| **R2** | Threat sources & events | Identify threat sources + threat events — **adversarial AND accidental/environmental** (the 800-30 DNA difference); STRIDE as the discovery engine | 800-30 + STRIDE |
| **R3** | Vulnerabilities & predisposing conditions | Identify vulnerabilities + predisposing conditions (supply-chain / ecosystem) | 800-30 |
| **R4** | Likelihood x Impact → Risk | Determine likelihood, impact, overall risk (the 800-30 risk matrix) | 800-30 |
| **R5** | Select & Implement controls | Select/Implement 800-53 controls via the STRIDE→800-53-family map | 800-37 + 800-53 |

**The two NIST terminals** (left out-of-band, not authored as report prose):
- **Authorize** (800-37 step 6) — the **Authorizing Official (AO)** accepts residual risk and grants
  the ATO. This is `rmf-sl`'s human terminus (= EBIOS risk owner). **R5/Authorize is left PENDING.**
- **Monitor** (800-37 step 7, ongoing authorization) — the **loop-back target**: verification
  verdicts feed it (`PREFIX-monitor-feedback-NN.md`), the AO re-adjudicates, the next cycle re-runs.

## Rule 2 — the tag set
Every artifact carries a stable **`TAG#`** id (tag letters + a number, e.g. `TS1`, `RS12`). Tags:

| Artifact | Tag | Required inline token(s) on its line | Section | Linted now |
|---|---|---|---|---|
| Mission / information asset | `IA#` | — | R1 | C7 (count 5-10) |
| Supporting asset (technical component) | `SA#` | — | R1 | (referenced by scenarios) |
| System element + categorization | `IM#` | **impact `Lo`/`Mod`/`Hi`** | R1 | **C3, C5** |
| Threat source | `TS#` | **origin class `ADV`/`ACC`/`ENV`** | R2 | **C6** (all 3 origins) |
| Threat event | `TE#` | names its **`TS#`** (and `STRIDE:` tag) | R2 | C4 |
| Vulnerability / predisposing condition | `VU#` | — | R3 | (referenced by RS) |
| Risk scenario | `RS#` | **likelihood `L1`..`L4`** + names its **`TE#`** + a **`VU#`** + a **`CTL#`** (+ the `IM#` it covers) + risk level (`Low`/`Moderate`/`High`) | R4 | **C3b, C4b, C4c, C5** |
| 800-53 control | `CTL#` | **800-53 family token** (e.g. `SI-7`, `SC-8`, `AC-6`) | R5 | **C4c** (RS->CTL) |
| Residual / BLOCKED item | `RR#` | — | R5 | (future) |

Tags are **case-sensitive, no space** before the number (`TS1`, never `TS 1`). Numbers are stable
across iterations and across sections (a `TE1` named in R4 is the same `TE1` defined in R2).

## Rule 3 — chaining (how derivation is written)
An artifact that **derives from** others **names their IDs on its own line**. This is what makes the
chain `TS -> TE -> (VU) -> RS -> CTL` machine-checkable:
- every `TE#` line names >=1 `TS#` (which threat source raises it) — **C4**;
- every `RS#` line names >=1 `TE#` **and** >=1 `VU#` **and** >=1 `CTL#` (the full risk chain:
  threat event exploiting a vulnerability, treated by a control) — **C4b / C4c**;
- every **Hi-impact** (`Hi`) `IM#` is **named again** in >=1 `RS#` line that also names a `CTL#`
  (coverage: every high-impact element has a risk scenario and a selected control) — **C5**.

**Pitfall — tag each threat source ONCE per origin class (or C6 mis-reads coverage).** Give each
`TS#` exactly one origin token (`ADV` adversarial, `ACC` accidental, `ENV` environmental). C6 requires
**all three classes present** somewhere in R2 — this is the 800-30 DNA difference from EBIOS (which
covers adversarial only). A report listing only `ADV` threat sources passes EBIOS but **WARNs** here.

Write the references inline, e.g.:
`- RS1: TS1's malicious-input TE1 exploits VU1 in the parser → memory corruption; covers IM1 — likelihood L3 — risk High — control CTL1.`

## Rule 4 — scales (from 800-30; keep the structure)
- **Impact** `Lo` low - `Mod` moderate - `Hi` high (FIPS-199 categorization, set on each `IM#`).
- **Likelihood** `L1` low - `L2` moderate - `L3` high - `L4` very high (the 800-30 likelihood scale,
  on each `RS#`).
- **Risk level** `Low` / `Moderate` / `High` (the 800-30 risk matrix = likelihood x impact) — on each
  `RS#`.
- **Origin class** `ADV` adversarial - `ACC` accidental - `ENV` environmental (on each `TS#`).
Adapt the wording to the org, but keep the level *names* (`Lo/Mod/Hi`, `L1..L4`, `ADV/ACC/ENV`)
verbatim — they are the linter's tokens.

## Rule 5 — endogeneity (R1-R4 are code-blind)
R1-R4 prose must contain **no code artifacts**: no source filenames (`*.c`/`*.h`/`*.cpp`/`*.cc`/`*.rs`),
no `#include`/`#define`, no `0x`-hex, no `::` or `->`. The linter **FAILs** (C8) on any — their
presence means the author saw the source, which voids the exogenous bound. Name supporting assets by
their *role* ("X.509 certificate parser"), never by file or function.

**Endogeneity nuance — don't over-sanitize scope language.** A 800-53 control ID (`SI-7`, `AC-6`) and
a configuration token (`CONFIG_PIPES`) are legitimate **scope/baseline/control** language in R1/R5,
**not** code artifacts — C8 only flags source artifacts (`.c`/`.h`/.../`#include`/`0x...`/`::`/`->`).
What stays banned in R1-R4: translation-unit names, function names, ACSL, WP goal counts. (R5 is *not*
scanned by C8 — control IDs and config tokens live there freely.)

**Arrow caution:** in R1-R4 prose use the unicode arrow `→` or the word "then", never the
ASCII `->` — C8 flags `->` as the C arrow operator. R5 prose may use `->` freely (not scanned).

## Minimal conformant skeleton (also the linter's known-good fixture)
~~~markdown
# NIST RMF risk assessment — <system>

## R1 — Prepare & Categorize
Information assets: IA1 <...>, IA2 <...>, IA3 <...>, IA4 <...>, IA5 <...>.
Supporting assets: SA1 <role, e.g. X.509 parser>, SA2 <role>.
System elements + categorization:
- IM1 <element> — impact Hi
- IM2 <element> — impact Mod

## R2 — Threat sources & events
- TS1 <adversary> — origin ADV
- TS2 <human error> — origin ACC
- TS3 <power loss / disaster> — origin ENV
- TE1 <threat event> — TS1 — STRIDE: Tampering
- TE2 <threat event> — TS2 — STRIDE: Information Disclosure

## R3 — Vulnerabilities & predisposing conditions
- VU1 <unvalidated length field in the parser>.
- VU2 <missing bounds check>.

## R4 — Likelihood x Impact → Risk
- RS1: TE1 exploits VU1 → corruption; covers IM1 — likelihood L3 — risk High — control CTL1.
- RS2: TE2 exploits VU2 → leak; covers IM2 — likelihood L2 — risk Moderate — control CTL2.

## R5 — Select & Implement controls (Authorize PENDING)
- CTL1 SI-7 — software/information integrity on the parsing path (treats RS1).
- CTL2 SC-8 — transmission confidentiality (treats RS2).
- RR1 — Spoofing residual: crypto/runtime, BLOCKED for formal verification -> non-formal treatment.
~~~

## What the linter enforces today vs the full contract (honesty)
`rmf-lint.sh` mechanically enforces **C1** (R1-R5 sections), **C3/C3b** (impact/likelihood present),
**C4** (TE->TS), **C4b** (RS->TE + VU), **C4c** (RS->CTL), **C5** (Hi-impact coverage -> RS + CTL),
**C6** (all three origin classes ADV/ACC/ENV present — the 800-30 DNA check, WARN), **C7** (volume,
WARN), **C8** (endogeneity), and **C9** (STRIDE coverage ledger — SKIP-honest: SKIPs when the report
carries no ledger table, else validates the §3.3 matrix structure: each S/T/R/I/D/E cell holds exactly
one lifecycle token `UNMODELED|PROVED|TRUSTED-PENDING|TRUSTED|N/A[(RR#)]`, and every Hi/High `SA#`/`IA#`
has a row; the cross-run *ratchet* regression is `frama-c-monitoring`'s CI gate, **not** C9). The rest
of the contract — the `IM#`/`RS#` impact x likelihood -> risk band consistency, the exact 800-53 family
validity — is part of the **format** but not yet linted; those are checked by the human reviewer until
added. The convention is fixed regardless: author to the full contract so later checks land without a
reformat.

## Rule 6 — residual register + human-terminus sign-off (R5 / Authorize)
Every threat family that is **out of WP reach by design** (crypto strength, protocol/state logic, a
trust decision, volumetric DoS, supply-chain, physical) must become a **named, signed residual** — a
listed `RR#` — never a silent drop and never a false `PROVED`. The residual register is the §5 table of
the crosswalk (schema: [`crosswalk-format.md`](./crosswalk-format.md) → the canonical template §5) and
its sign-off column is `rmf-sl`'s **human terminus**:

| Column | Meaning |
|---|---|
| **`RR#`** | stable residual id (chained from the `RS#` it leaves open) |
| **Residual** | the out-of-model property in one phrase ("signature/cert crypto strength") |
| **Plane** | the named plane it lives on: `crypto` / `side-channel` / `logic` / `protocol` / `ENV` / `supply-chain` / `physical` |
| **Treatment (non-formal)** | the out-of-band control: KAT vectors, ct-verif, model-checking, rate-limiting (SC-5/SC-7), dependency review, SLSA/reproducible build, physical control |
| **Signed (AO / risk owner)** | `☐ PENDING` until the **Authorizing Official** accepts it and grants the **ATO** (800-37 step 6) |

The AO sign-off is the **only** actor who lowers a residual risk level — a WP green never does (the
no-blend plane rule). `R5/Authorize` is left **PENDING** in the authored report; the AO signs at the
terminus, downstream, after the verdict join.

**Standing residual classes (ALWAYS named, NEVER proved).** Every campaign names these even if no
scenario surfaced them, because they are structurally out of WP reach:
- **Cryptographic primitive strength** (plane `crypto`) — KAT vectors / libcrypto trust; `SC-12/SC-13`.
- **Volumetric / distributed (flooding) DoS** (plane `ENV`, out-of-band) — rate-limiting / capacity,
  `SC-5/SC-7`; **never** a WP proof. (The *bounded-work* DoS slice is separate and `\fuel`-amenable.)
- **Compiler correctness / supply-chain** (plane `supply-chain`) — SLSA / reproducible build; `SR-3/SA-12`.
- **Physical & social-engineering** (plane `physical`) — out-of-scope for formal verification entirely.

See [`stride-families.md`](./stride-families.md) for the code-blind families that feed these residuals
and [`attack-mapping.md`](./attack-mapping.md) for the ATT&CK + 800-53 taxonomy each residual cites.
