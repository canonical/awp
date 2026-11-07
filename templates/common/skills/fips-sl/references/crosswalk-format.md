# FIPS crosswalk-format reference — thin pointer + tag bindings

The crosswalk is the one document where the **code-blind** FIPS requirement study (the exogenous
upper bound `U`) meets the **code-aware** verification (the lower bound `L`). It is authored by the
*architect* (who reads the source) — that asymmetry is the whole point, and is what keeps the
upstream `fips-sl` report exogenous. The `/fips` campaign produces a `fips-crosswalk.md` (or
`<prefix>-crosswalk.md`) from it.

## The canonical schema (do NOT redefine — reference it)
**[`config/skills/frama-c-monitoring/templates/crosswalk-template.md`](../../frama-c-monitoring/templates/crosswalk-template.md)**
is the authoritative schema: the sections (the §1 unit crosswalk · the §2 obligation ranking · the
§3 coverage ledger with the cell lifecycle `UNMODELED|PROVED|TRUSTED-PENDING|TRUSTED|N/A` · the §3.2
ratchet · the verdict join · the §5 residual register · handoff), the **no-blend plane rule** (a WP
green retires one class of one obligation on the amenable surface — it never lowers a priority and
never validates the module), and the `\fuel`/`\cost`/`\resource` spine for bounded-work cells.
Author to it verbatim. Under `fips`, §3 of the generated crosswalk is the **FIPS ledger** form of
the template's §3 (below); the rest of the schema is kind-independent.

## FIPS-specific tag bindings (what fills each template slot)
The crosswalk references the report's pinned tags (see
[`report-format.md`](./report-format.md)) — it does **not** invent new ones:

| Template slot | FIPS tag binding |
|---|---|
| §1 crosswalk row | **`VO#`** — one row per F4 verification-obligation home line (the id, and the text up to the first separator as its role). Keyed on `VO#`, not on `MOD#`/`SV#`: no `VO#` line names an `SV#`, so `MOD#`/`SV#` rows would leave the unit and coverage columns empty |
| §1 module / services / roles / SSPs / interfaces / states | **`MOD#` `SV#` `RL#` `SSP#` `IF#` `ST#`** — the F1 vocabulary (module boundary, by role, never a file name) |
| §2 requirement area | **`AR#`** — one of the eleven fixed areas (`AR1`–`AR11`) |
| §2 obligation row (ranking key) | **`VO#`** — ranked by its **priority `P1`/`P2`/`P3`** (in place of `rmf-sl`'s likelihood × impact risk level), **never re-derived from code** |
| §2 failure mode | **`FM#`** ← its **`RQ#`** with its **`src:`** token (`src:PDF-ann6|7|10|13` or `src:UNSOURCED`) |
| §3 ledger row | **`VO#`** — one row per obligation; the header row is exactly `\| VO# \| AR# \| Class \| Coverage \|` and the first cell of each row is the bare `VO#` (the ratchet keys the row on that id) |
| §3 ledger columns | **`AR#`**, the **property class** (`approved-only`, `output-inhibit`, `role-gate`, `integrity-first`, `zeroize`, `no-plain-ssp-out`, `selftest-order`, `error-state`, `fsm` — from [`area-properties.md`](./area-properties.md)), and one **Coverage** cell with the shared lifecycle tokens `UNMODELED\|PROVED\|TRUSTED-PENDING\|TRUSTED\|N/A[(RR#)]` |
| §4 verdict join | overlay `verdicts.tsv` ↔ **`VO#`** — under `fips` the column the RMF/EBIOS kinds head `SA#` is headed `VO#` (read by header name, not position); `VO\d+` placeholder units are skipped |
| §5 residual register | **`RR#`** — signed off by the **owner of the protected information, or the agency's responsible authority** (Ann. 13) at the human terminus |

The §3 ledger's machine form is `PREFIX-acsl/fips-ledger.tsv`, one row
`VO#<TAB>AR#<TAB>class<TAB>cell`, which the code-aware architect fills as it fills
`stride-ledger.tsv` for the RMF/EBIOS kinds. The generated crosswalk's §3 carries the marker line
`# ledger: fips` immediately above the table, which selects the FIPS row form for
`bin/ledger-ratchet.sh`; the same §3.1 lifecycle and §3.2 ratchet rule apply unchanged (FAIL only
when a `PROVED` or `TRUSTED` cell falls back to `UNMODELED`, or when a row of the baseline is
gone).

## Load-bearing invariants (inherited from the template)
- **Asymmetry preserved** — the upstream report passed the F-C9 endogeneity tripwire (no code
  artifacts in F1–F4); only the crosswalk is code-aware. Never back-port a file/function name into
  the report.
- **No-blend** — every §3/§4/§5 cell names its plane; a green never lowers a `P1`–`P3` priority and
  never validates the module (the standing `validation` residual). Only the residual-risk owner
  closes a residual, downstream, at the F5 sign-off.
- **Ratchet** — the §3.2 baseline only moves forward; an `UNMODELED` cell on a ranked obligation is
  a ratcheted `WARN`, never a silent green. (The cross-run ratchet is `frama-c-monitoring`'s CI
  gate; `bin/fips-lint.sh` has no ledger check — the FIPS ledger is never hand-written, only
  generated and machine-checked by the generator.)

## Native generation

The crosswalk is **generated**, not hand-written: `bin/crosswalk-gen.sh --kind fips` (auto-detected
from `PREFIX-fips-report.md`, checked after the RMF and EBIOS reports) emits `PREFIX-crosswalk.md`
from this loop's code-blind report (§1/§2 the F4 `VO#` home lines with their priorities, §5 the F5
`RR#` home lines) joined with the code-aware `PREFIX-acsl/verdicts.tsv` (§4, the column headed
`VO#`) and `PREFIX-acsl/fips-ledger.tsv` (§3, with the `# ledger: fips` marker line written into
the crosswalk — the TSV itself carries no marker). The generator machine-checks that every `PROVED`
ledger cell is backed by a real verdict (a fabricated PROVED fails generation). See
`config/skills/frama-c-monitoring/references/crosswalk-generation.md` for the full contract and
`config/skills/frama-c-monitoring/templates/crosswalk-template.md` §3 for the FIPS ledger schema.
