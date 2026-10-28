# Native crosswalk generation (`crosswalk-gen.sh`) — Move 5

The threat↔verification crosswalk is **generated**, not hand-written. `crosswalk-gen.sh PREFIX`
emits `PREFIX-crosswalk.md` (conforming to `templates/crosswalk-template.md`) by joining a campaign's
existing artifacts. A hand-built join drifts from the verdicts it summarizes; a generated one cannot.

## The seating (load-bearing — keep each half in its own evidence base)

| Crosswalk section | Source | Owner loop |
|---|---|---|
| §1 assets, §2 scenarios, §5 residuals | the **code-blind** `PREFIX-{rmf,ebios}-report.md` (SA#/RS#/SS#/FE# tags, severity, likelihood, RR#) | `rmf-sl` / `ebios-sl` |
| §1 translation units, §4 verdict join | `PREFIX-acsl/verdicts.tsv` (the code-aware proof record) | `frama-c-monitoring` |
| §3 STRIDE coverage ledger | `PREFIX-acsl/stride-ledger.tsv` (the architect's coverage assessment) | `frama-c-monitoring` (architect) |

The §1–§2/§5 emission reads only the code-blind report, so the crosswalk does not make the upstream
study endogenous. Do **not** let the code-aware step backfill the asset/scenario half.

## Why §3 is a separate input (and not derived from verdicts)

The STRIDE ledger is the architect's **coverage assessment** — necessarily *broader* than the
verdicts: it carries `UNMODELED` / `TRUSTED` / `TRUSTED-PENDING` / `N/A` cells that **no proof backs**
(a family nobody modelled, a residual signed out of scope). It cannot be derived from `verdicts.tsv`.
So it is a structured TSV the architect fills — but the generator **machine-checks** it:

> **Faithfulness invariant (enforced):** every `PROVED` cell must be backed by a non-vacuous
> `Valid`/`PROVED`/`GREEN` verdict for that SA in `verdicts.tsv`. A `PROVED` claim with no proof
> **FAILS generation** (exit 1). This is the no-blend rule made executable — a green cell can never be
> fabricated.

## `stride-ledger.tsv` format

One row per supporting asset; tab-separated; tokens per family:

```
SA   S   T   R   I   D   E   attack
SA1  N/A PROVED N/A PROVED TRUSTED-PENDING N/A T1190
```

Tokens (template §3.1): `UNMODELED` · `PROVED` · `TRUSTED-PENDING` · `TRUSTED` · `N/A`, optionally with
a parenthetical residual ref (`TRUSTED (RR2)`). The ATT&CK column carries the WS9 technique tags.

## `verdicts.tsv` (the proof record — already produced by the campaign)

Header row with at least `SA#`, `verdict`, and one of `function`/`unit`; `goals`/`notes` optional.
Comment rows (`# …`) and `SA#`-placeholder unit values (used by BLOCKED rows) are ignored by the
generator. A `Valid`/`PROVED`/`GREEN` verdict marks its SA provable (backs §3 PROVED cells + §4).

## Usage

```sh
./crosswalk-gen.sh s2n-tls-analysis                    # emit (auto-detect rmf/ebios)
./crosswalk-gen.sh wolfssl --kind ebios                # force the EBIOS variant
./crosswalk-gen.sh s2n-tls-analysis --check            # CI drift gate: fail if out of sync
```

`--check` regenerates to a temp file and diffs against the committed crosswalk — exit 1 on drift.
It is **G4** of `ci/stride-coverage-check.sh` (`make stride-ci`), so a crosswalk can never silently
fall out of sync with its report/verdicts, and a fabricated `PROVED` can never be committed.

## In the `/rmf` and `/ebios` campaigns

After Phase 2 produces `PREFIX-acsl/verdicts.tsv` and the architect fills
`PREFIX-acsl/stride-ledger.tsv`, run `./crosswalk-gen.sh PREFIX` to emit `PREFIX-crosswalk.md` as a
first-class campaign deliverable (alongside the report, found-issues, gaps, and the monitor packet).
The first run also bootstraps the `ledger-ratchet.sh` baseline; subsequent runs keep it forward-only.
