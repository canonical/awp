# EBIOS report-format convention (PINNED) — the `ebios-lint.sh` contract

This is the **authoritative, fixed** format an `ebios-sl` report must follow. It is the contract the
mechanical lower bound (`ebios-lint.sh`) parses and the scenario author writes to — one source of
truth, so the linter and the report cannot drift. It layers stable tags onto the EBIOS RM method
content (the `ebios-risk-manager` skill); where that skill already fixes IDs (risk scenarios `R#`,
stakeholders client `C#` / partner `P#` / provider `F#`), this convention keeps them.

## Rule 0 — locality (load-bearing, because the linter is line-oriented)
Write **one artifact per markdown list item or table row**, and put **all of its tokens** (its tag,
its severity/likelihood, and **the IDs it derives from**) **on that same line/row**. The linter
detects severity, likelihood, and chaining by *line proximity* — an artifact whose severity sits in a
following paragraph, or whose parent ID is mentioned three lines away, reads to the linter as
*missing*. Locality is the price of a dependency-free linter; keep it.

## Rule 1 — workshop sections
Each workshop is a heading containing **`Workshop N`** (preferred) or **`WN`**, `N` ∈ 1..5:
`## Workshop 1 — Scope & Security Baseline`. The linter slices the report by these headings; W1–W3
text is what the endogeneity tripwire scans.

## Rule 2 — the tag set
Every artifact carries a stable **`TAG#`** id (tag letters + a number, e.g. `FE1`, `OS12`). Tags:

| Artifact | Tag | Required inline token(s) on its line | Workshop | Linted now |
|---|---|---|---|---|
| Business asset | `BA#` | — | W1 | C7 (count 5–10) |
| Supporting asset | `SA#` | — | W1 | (referenced by scenarios) |
| Feared event | `FE#` | **severity `G1`..`G4`** | W1 | **C3, C5** |
| Risk origin | `RO#` | — | W2 | C4 |
| Target objective | `TO#` | — | W2 | C4 |
| Combined RO/TO pair | `ROTO#` | — | W2 | C4, C7 (count 3–6) |
| Ecosystem stakeholder | `C#` / `P#` / `F#` | — | W3 | (future) |
| Strategic scenario | `SS#` | names its **RO/TO** (and its `AP#`, `FE#`) | W3 | **C4** |
| Attack path | `AP#` | — | W3 | C4b |
| Operational scenario | `OS#` | **likelihood `V1`..`V4`**; names its **`SS#`/`AP#`** (and the `FE#` it covers) | W4 | **C3b, C4b** |
| Risk scenario | `R#` | severity `G` + likelihood `V` + risk level (`Low`/`Moderate`/`High`) | W5 / summary | (future) |

Tags are **case-sensitive, no space** before the number (`FE1`, never `FE 1`). Numbers are stable
across iterations and across workshops (an `FE1` named in W3 is the same `FE1` defined in W1).

## Rule 3 — chaining (how derivation is written)
An artifact that **derives from** others **names their IDs on its own line**. This is what makes the
chain `RO/TO → SS → AP → OS` machine-checkable:
- every `SS#` line names ≥1 `RO#`/`TO#`/`ROTO#` (which RO/TO it realizes) — **C4**;
- every `OS#` line names ≥1 `SS#`/`AP#` (which path it operationalizes) — **C4b**;
- every high-severity (`G3`/`G4`) `FE#` is **named again downstream of W1** (in an `SS#`/`OS#`/`R#`
  line) — coverage, **C5**.

**Pitfall — tag each origin ONCE (or C7 double-counts).** Write a risk origin **either** as an
`RO#`/`TO#` pair **or** as a combined `ROTO#` — never both on the same line. C7's RO/TO volume count is
`set(RO#) ∪ set(ROTO#)`, so a line like `- RO1 / TO1 (ROTO1): …` counts the origin **twice** (6 real
pairs read as 12 → a spurious C7 WARN). Pick one convention; `SS#` lines may chain to whichever you
used (C4 accepts `RO#`/`TO#`/`ROTO#`). *(Hit on both the macsl flagship and the Mbed TLS study.)*

Write the references inline, e.g.: `- SS1: RO1/TO1 sends a malicious cert hitting FE1 via SA1 — severity G4 — attack path AP1`.

## Rule 4 — scales (from `ebios-risk-manager`; keep the 4/4/3 structure)
- **Severity** `G1` minor · `G2` significant · `G3` serious · `G4` critical (set on each `FE#`).
- **Likelihood** `V1` rather unlikely · `V2` likely · `V3` very likely · `V4` nearly certain (on each `OS#`).
- **Risk level** `Low` / `Moderate` / `High` (acceptability) — on each `R#` in W5/the summary.
Adapt the wording to the org, but keep the level *names* (`G1..G4`, `V1..V4`) verbatim — they are the
linter's tokens.

## Rule 5 — endogeneity (W1–W3 are code-blind)
W1–W3 prose must contain **no code artifacts**: no source filenames (`*.c`/`*.h`/`*.cpp`/`*.rs`), no
`#include`/`#define`, no `0x`-hex, no `::` or `->`. The linter **FAILs** (C8) on any — their presence
means the author saw the source, which voids the exogenous bound. Name supporting assets by their
*role* ("X.509 certificate parser"), never by file or function. W4 may reference a supporting-asset
*interface* but still avoids implementation file/identifier specifics.

## Minimal conformant skeleton (also the linter's known-good fixture)
```markdown
# EBIOS RM report — <system>

## Workshop 1 — Scope & Security Baseline
Business assets: BA1 <…>, BA2 <…>, BA3 <…>, BA4 <…>, BA5 <…>.
Supporting assets: SA1 <role, e.g. X.509 parser>, SA2 <role>.
Feared events:
- FE1 <event> — severity G4
- FE2 <event> — severity G2

## Workshop 2 — Risk Origins
- RO1 / TO1: <origin> seeking <objective>.
- RO2 / TO2: <origin> seeking <objective>.
- RO3 / TO3: <origin> seeking <objective>.

## Workshop 3 — Strategic Scenarios
- SS1: RO1/TO1 reaches FE1 via SA1 — severity G4 — attack path AP1.
- SS2: RO2/TO2 reaches FE2 via SA2 — attack path AP2.

## Workshop 4 — Operational Scenarios
- OS1: AP1 on SA1 — <technical step> — covers FE1, SS1 — likelihood V3.
- OS2: AP2 on SA2 — <technical step> — covers SS2 — likelihood V2.
```

## What the linter enforces today vs the full contract (honesty)
`ebios-lint.sh` mechanically enforces **C1** (workshops), **C3/C3b** (severity/likelihood present),
**C4/C4b** (SS→RO/TO, OS→SS/AP chaining), **C5** (high-severity coverage), **C7** (volume, warn),
**C8** (endogeneity), and **C9** (STRIDE coverage ledger — SKIP-honest: SKIPs when the report carries
no ledger table, else validates the §3.3 matrix structure: each S/T/R/I/D/E cell holds exactly one
lifecycle token `UNMODELED|PROVED|TRUSTED-PENDING|TRUSTED|N/A[(RR#)]`, and every G3/G4 `SA#` has a row;
the cross-run *ratchet* regression is `frama-c-monitoring`'s CI gate, **not** C9). The rest of the
contract — stakeholder codes (`C#`/`P#`/`F#`), the `R#` risk-level band and severity×likelihood
consistency — is part of the **format** but not yet linted; those are checked by the human reviewer
until added. The convention is fixed regardless: author to the full contract so later checks land
without a reformat.

## Rule 6 — residual register + human-terminus sign-off (W5 acceptability)
Every threat family that is **out of WP reach by design** (crypto strength, protocol/state logic, a
trust decision, volumetric DoS, supply-chain, physical) must become a **named, signed residual** — a
listed `RR#` — never a silent drop and never a false `PROVED`. The residual register is the §5 table of
the crosswalk (schema: [`crosswalk-format.md`](./crosswalk-format.md) → the canonical template §5) and
its sign-off column is `ebios-sl`'s **human terminus**:

| Column | Meaning |
|---|---|
| **`RR#`** | stable residual id (chained from the scenario `SS#`/`OS#` it leaves open) |
| **Residual** | the out-of-model property in one phrase ("signature/cert crypto strength") |
| **Plane** | the named plane it lives on: `crypto` / `side-channel` / `logic` / `protocol` / `ENV` / `supply-chain` / `physical` |
| **Treatment (non-formal)** | the out-of-band W5 control / SCIP entry: KAT vectors, ct-verif, model-checking, rate-limiting, dependency review, reproducible build, physical control |
| **Signed (risk owner)** | `☐ PENDING` until the **risk owner** accepts the residual at the **W5 acceptability** step |

The risk owner's sign-off is the **only** actor who lowers a residual risk level — a WP green never
does (the no-blend plane rule). The accepted residuals roll into the **Security Continuous Improvement
Plan (SCIP)** as the loop-back target.

**Standing residual classes (ALWAYS named, NEVER proved).** Every campaign names these even if no
scenario surfaced them, because they are structurally out of WP reach:
- **Cryptographic primitive strength** (plane `crypto`) — KAT vectors / library trust.
- **Volumetric / distributed (flooding) DoS** (plane `ENV`, out-of-band) — rate-limiting / capacity
  carried in the SCIP; **never** a WP proof. (The *bounded-work* DoS slice is separate, `\fuel`-amenable.)
- **Compiler correctness / supply-chain** (plane `supply-chain`) — reproducible build / dependency trust.
- **Physical & social-engineering** (plane `physical`) — out-of-scope for formal verification entirely.

See [`stride-families.md`](./stride-families.md) for the code-blind families that feed these residuals.
The ATT&CK + 800-53 taxonomy each residual cites lives RMF-side:
[`../../rmf-sl/references/attack-mapping.md`](../../rmf-sl/references/attack-mapping.md).
