# FIPS report-format convention (PINNED) — the `bin/fips-lint.sh` contract

This is the **authoritative, fixed** format an `fips-sl` report must follow. It is the contract the
mechanical lower bound (`bin/fips-lint.sh`) parses and the study author writes to — one source of
truth, so the linter and the report cannot drift. It layers stable tags onto the vendored standard
(`./NIST.FIPS.140-3.pdf`, FIPS PUB 140-3, *Security Requirements for Cryptographic Modules*, March
22, 2019). It is the faithful sibling of `rmf-sl/references/report-format.md` (RMF `R1–R5` → FIPS
`F1–F5`) and of `ebios-sl/references/report-format.md`.

## What the source document contains (read before authoring)

The PDF has two independent numberings: the *Announcement* items 1 to 14 (pages iii–vi) and the body
sections 1 to 3 (pages 1–3). This convention writes them `Ann. n` and `Sec. n`.

| Content | Where |
|---|---|
| Four security levels, named "Level 1, Level 2, Level 3, and Level 4" | Ann. 3, the only place that names them. Sec. 1 gives the count ("four security levels"), and the Abstract says "four increasing, qualitative levels of security" |
| The requirement areas, listed after "These areas include": cryptographic module specification; cryptographic module interfaces; roles, services, and authentication; software/firmware security; operating environment; physical security; non-invasive security; sensitive security parameter management; self-tests; life-cycle assurance; and mitigation of other attacks | Abstract; Ann. 3 |
| The counts: "Four security levels were specified for each of eleven requirement areas" (about FIPS 140-1) | Sec. 1 |
| The level "must be chosen to provide a level of security appropriate for the security requirements of the application and environment", and the requirements of a level are "both the security requirements specific to that level and the security requirements that apply to all modules regardless of the level" | Ann. 7 |
| Conformant modules "shall employ Approved security functions such as cryptographic algorithms, cryptographic key management techniques, and authentication techniques" | Ann. 10 |
| Conformance "is not sufficient to ensure that a particular module is secure". The operator ensures the security is "sufficient and acceptable to the owner of the information that is being protected and that any residual risk is acknowledged and accepted"; "the responsible authority in each agency" ensures the security of the system | Ann. 13 |
| Validation goes through the CMVP and accredited CST laboratories | Ann. 3, 9, 12 |
| The technical requirements are those of ISO/IEC 19790:2012 and the test requirements those of ISO/IEC 24759:2017, modified by SP 800-140 and SP 800-140A to F | Sec. 2, Sec. 3, Table 1 |

**What the PDF does not contain:** the requirements themselves. Apart from the applicability rule of
Ann. 6, the only requirement on a module is Ann. 10. Which requirement applies in which area at
which level is in ISO/IEC 19790 and the SP 800-140 series, which the PDF names but does not
reproduce. (That the per-level requirements are in ISO/IEC 19790's clause 7 is outside knowledge,
not something the PDF says.) **The skill never presents a requirement as coming from the PDF when it
does not** — rule F3 is the mechanism, and `src:UNSOURCED` is the honest state of most requirements.

## Inherited rules (from `rmf-sl/references/report-format.md`, unchanged)

- **Its rule 0 — locality.** One artifact per markdown list item or table row, with **all of its
  tokens** (its tag and the IDs it derives from) **on that same line**. The linter detects chaining
  by line proximity; an artifact whose parent ID sits three lines away reads to the linter as
  *missing*. Locality is the price of a dependency-free linter; keep it.
- **Its rule 5 — endogeneity.** F1–F4 prose must contain **no code artifacts**, whatever the
  language of the code under study: no source filenames (`*.c`/`*.h`/`*.cpp`/`*.cc`/`*.rs`), no
  `#include`/`#define`, no `0x`-hex, no `::` or `->` (C); no `fn name(`, `impl X`, `unsafe {`,
  `#[attribute]`, `&mut`, `Vec<`/`Option<`/`Result<`/`Box<`, `macro!(` or `.unwrap()` (Rust). The
  linter **FAILs** (F-C9) on any — their presence means the author saw the source, which voids the
  exogenous bound. Name the module and its parts by their *role* ("the full-disk-encryption
  module", "the key-establishment service"), never by file, module, crate path or function. (F5 is
  not scanned by F-C9 — residual treatments may name tools and procedures freely.) **Arrow
  caution:** in F1–F4 prose use the unicode arrow `→` or the word "then", never the ASCII `->`.

## Rule F0 — home lines (load-bearing)

Each defined tag has a **home section**: `MOD SV RL SSP IF ST` in F1, `RQ` in F2, `FM` in F3, `VO`
in F4, `RR` in F5. **The `X#` line** is the one line in X's home section whose **first tag** is
`X#`. Every such id has exactly one home line. A mention of `X#` anywhere else — for example `RQ3`
named on a `VO#` line — is a **reference**: rules F2–F5 apply to home lines only, so a reference can
neither satisfy nor break them.

This closes the back-reference masking that `rmf-sl/references/report-format.md` warns about: since
every downstream line carries its full upstream chain as references *and* each upstream id has
exactly one home line, a dropped link can no longer be masked by a back-reference — the coverage
check (F-C6) runs on home lines, where the chain must actually live.

`AR1`–`AR11` are different: they are a **fixed vocabulary**, the eleven requirement areas of the
PDF, with no home line. Rule F2 and check F-C3 cover them.

## Rule F1 — the tag set

| Artifact | Tag | Required inline token(s) on its home line | Section |
|---|---|---|---|
| The module | `MOD#` | its role and its boundary | F1 |
| Service | `SV#` | — | F1 |
| Role | `RL#` | — | F1 |
| Sensitive security parameter | `SSP#` | — | F1 |
| Documented interface | `IF#` | — | F1 |
| State | `ST#` | — | F1 |
| Requirement item | `RQ#` | exactly one **`AR#`** + exactly one **`src:`** token (+ optional `min-level K`) | F2 |
| Failure mode | `FM#` | names at least one **`RQ#`** | F3 |
| Verification obligation | `VO#` | names ≥1 **`FM#`** + **the `RQ#` of each of them** + a **property class** + a **priority `P1`–`P3`** | F4 |
| Residual | `RR#` | a **plane** + a **treatment** + what it leaves open: ≥1 `FM#` or `RQ#`, or its **`AR#`**, or the token **`STANDING`** | F5 |

Tags are **case-sensitive, no space** before the number (`RQ1`, never `RQ 1`), and stay stable
across iterations. `MOD` and `SSP` are used instead of `MD` and `SP` so that `MD5` and
`SP800-140C`, which a FIPS report will mention, are not read as tags.

## Rule F2 — the five sections

Each section is a heading containing **`F1`** … **`F5`**: `## F1 — Module and target level`. The
linter slices the report by these headings; F1–F4 text is what the endogeneity tripwire scans.

| Section | Title | Content |
|---|---|---|
| **F1** | Module and target level | The module (`MOD#`: its role, never a file name), its boundary, its services (`SV#`), its roles (`RL#`), its SSPs (`SSP#`), its documented interfaces (`IF#`), its states (`ST#`), and the level line of rule F6. |
| **F2** | Requirement areas | One subsection per area, `AR1` to `AR11`, in the PDF's order (the headings are for readers; the linter uses the `AR#` tokens). Each area holds requirement items (`RQ#`) or one `N/A` line (rule F3). |
| **F3** | Failure modes | For each `RQ#`, how the module would fail it (`FM#`): a service run before its self-test passed, an SSP left in memory after use, data output in an error state. |
| **F4** | Verification obligations | Each `FM#` becomes a verification obligation (`VO#`) with a property class from `area-properties.md` and a priority. |
| **F5** | Residuals and sign-off | The residual register: one `RR#` per failure mode or requirement out of reach of the formal tools, with its plane and its non-formal treatment, and the standing residuals. Sign-off `PENDING` until the terminus (the owner of the protected information, or the agency's responsible authority — Ann. 13) accepts it. |

## Rule F3 — areas and sources

**Areas.** Every `RQ#` home line names **exactly one** `AR#`. The eleven areas, in the PDF's order:
`AR1` module specification · `AR2` interfaces · `AR3` roles, services, and authentication · `AR4`
software/firmware security · `AR5` operating environment · `AR6` physical security · `AR7`
non-invasive security · `AR8` sensitive security parameter (SSP) management · `AR9` self-tests ·
`AR10` life-cycle assurance · `AR11` mitigation of other attacks. An area with no requirement has a
line in F2 holding its `AR#`, the token `N/A` and a **non-empty reason**:
`- AR6 N/A — software-only module, no physical enclosure`.

**Sources.** Every `RQ#` home line carries **exactly one** `src:` token, in ASCII:

- `src:PDF-ann6`, `src:PDF-ann7`, `src:PDF-ann10` or `src:PDF-ann13`. These are the only parts of
  the PDF with normative or scoping text (applicability, level choice, Approved security functions,
  conformance and residual risk). Any other section on an `RQ#` line fails the linter (F-C5);
- `src:UNSOURCED`: the author's reading of the area at the target level, with no text in the corpus
  behind it.

`UNSOURCED` is allowed: given §0, it is the honest state of most requirements. It is **never
hidden**: every `UNSOURCED` requirement appears in the reviewer's critique and in the F5 sign-off.
Whether a `src:PDF-…` requirement really says what the cited section says is a **content check**; it
stays with the reviewer, not the linter.

Other text may cite the PDF with the **full token set** (`src:PDF-abs`, `src:PDF-ann1` to
`src:PDF-ann14`, `src:PDF-sec1`, `src:PDF-sec2`, `src:PDF-sec3`, `src:PDF-sec3.1` to
`src:PDF-sec3.4`, `src:PDF-tab1`) — for example an F1 line on the level choice.

## Rule F4 — chaining

An artifact that **derives from** others **names their IDs on its own line** (home lines only):

- every `FM#` line names **≥1 `RQ#`** (which requirement it would fail);
- every `VO#` line names **≥1 `FM#`** + **the `RQ#` of each of them** + a **property class** + a
  **priority `P1`–`P3`**. Across home lines, the set of `RQ#` on a `VO#` line **equals** the union
  of the `RQ#` named by its `FM#` home lines: none missing, none extra (F-C6). Because `VO#` lines
  carry their `RQ#`, the coverage check "every `RQ#` is named on at least one `VO#` or `RR#` home
  line" stays line-local;
- every `RR#` line names a **plane**, a **treatment**, and **what it leaves open**: at least one
  `FM#` or `RQ#`, or, for a standing residual that no requirement surfaced, its **`AR#`** or the
  token **`STANDING`** (`physical` → `AR6`, `ENV` → `AR5`, `side-channel` → `AR7`; `crypto`,
  `supply-chain`, `validation` → `STANDING`). The token is upper case and matched case-sensitively,
  so prose such as "long-standing" never satisfies it.

Write the references inline, e.g.:
`- VO1 — FM1 — RQ5 — zeroize — P1 — the module must not retain the key after use.`

## Rule F5 — level applicability

An `RQ#` may carry **`min-level K`** (K in 1..4). `K` must not exceed the target level, or the item
does not belong in the report (F-C7). Since §0: every `min-level` choice is `UNSOURCED` unless the
corpus grows; the reviewer checks **monotonicity only** — a requirement marked `min-level 3` must
not be weaker than one marked `min-level 2` in the same area.

## Rule F6 — the level line

F1 contains **exactly one** line matching `^level: [1-4]$` — a bare paragraph line, not a list item
(`- level: 3` does not match). No other line in the report may match it. `min-level K` does not
match, since it does not start the line. The linter checks it against `config/auto-wp.json`'s
`fips_level` (F-C2).

## Rule F7 — scales (keep the names verbatim — they are the linter's tokens)

- **Priority** `P1` high – `P2` medium – `P3` low (on each `VO#`; the ranking the launch loop
  consumes, in place of `rmf-sl`'s likelihood × impact).
- **Property class** — a token from [`area-properties.md`](./area-properties.md): `approved-only`,
  `output-inhibit`, `role-gate`, `integrity-first`, `zeroize`, `no-plain-ssp-out`, `selftest-order`,
  `error-state`, `fsm` (on each `VO#`).
- **Plane** — one of `crypto`, `ENV`, `physical`, `side-channel`, `supply-chain`, `logic`,
  `validation` (on each `RR#`).
- **Level** — the target security level, `1`–`4`, one `level: N` line in F1 (rule F6).

## The residual register + human-terminus sign-off (F5)

Every requirement or failure mode **out of reach of the formal tools** must become a **named, signed
residual** — a listed `RR#` — never a silent drop and never a false `PROVED`. The register is the
§5 table of the crosswalk (schema:
[`crosswalk-format.md`](./crosswalk-format.md) → the canonical template §5) and its sign-off column
is `fips-sl`'s **human terminus**:

| Column | Meaning |
|---|---|
| **`RR#`** | stable residual id (chained from the `FM#`/`RQ#` it leaves open) |
| **Residual** | the out-of-model property in one phrase ("SSP zeroization after error paths") |
| **Plane** | the named plane it lives on: `crypto` / `ENV` / `physical` / `side-channel` / `supply-chain` / `logic` / `validation` |
| **Treatment (non-formal)** | the out-of-band control: KAT vectors, constant-time tooling, model-checking, dependency review, SLSA/reproducible build, the CMVP validation itself |
| **Signed (owner / responsible authority)** | `☐ PENDING` until the **owner of the protected information, or the agency's responsible authority** acknowledges and accepts the residual risk (Ann. 13) |

The owner's sign-off is the **only** actor who closes a residual — a WP green never does (the
no-blend plane rule). The F5 sign-off is left **PENDING** in the authored report; the owner signs at
the terminus, downstream, after the verdict join. **Standing residual planes (ALWAYS named, NEVER
proved):** `crypto`, `ENV`, `physical`, `side-channel`, `supply-chain`, `validation` — one `RR#`
line each, even when no requirement surfaced them (F-C8). See
[`area-properties.md`](./area-properties.md) for the per-area planes.

## Minimal conformant skeleton (also the linter's known-good fixture)

The fixture lives in [`skeleton.md`](./skeleton.md) so a test can read it without parsing this file;
it is reproduced here for the author:

~~~markdown
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
~~~

## What the linter enforces today vs the full contract (honesty)

`bin/fips-lint.sh` mechanically enforces **F-C1** (F1–F5 sections, a precondition), **F-C0** (one
home line per defined id), **F-C2** (the level line, equal to the manifest's `fips_level`),
**F-C3** (every area covered), **F-C4** (one `AR#` + one `src:` per `RQ#`), **F-C5** (the allowed
source-token set), **F-C6** (chaining + the `VO#`↔`FM#` set equality + `RQ#` coverage),
**F-C7** (`min-level` applicability), **F-C8** (the six standing planes), **F-C9** (endogeneity),
plus **F-C10** (volume, WARN) and **F-C11** (the `src:UNSOURCED` count, INFO). The rest of the
contract — whether a `src:PDF-…` requirement really says what the cited section says, and the
`min-level` monotonicity within an area — is part of the **format** but is a **content check**; it
stays with the human reviewer. The convention is fixed regardless: author to the full contract so
later checks land without a reformat.
