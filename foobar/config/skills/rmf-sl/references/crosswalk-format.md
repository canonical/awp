# RMF crosswalk-format reference — thin pointer + tag bindings

The crosswalk is the one document where the **code-blind** RMF study (the exogenous upper bound `U`)
meets the **code-aware** verification (the lower bound `L`). It is authored by the *architect* (who
reads the source) — that asymmetry is the whole point, and is what keeps the upstream `rmf-sl` report
exogenous. The `/rmf` campaign produces a `rmf-crosswalk.md` (or `<prefix>-crosswalk.md`) from it.

## The canonical schema (do NOT redefine — reference it)
**[`config/skills/frama-c-monitoring/templates/crosswalk-template.md`](../../frama-c-monitoring/templates/crosswalk-template.md)**
is the authoritative schema: the six sections (asset crosswalk · scenario ranking · the §3 STRIDE
coverage ledger with the cell lifecycle `UNMODELED|PROVED|TRUSTED-PENDING|TRUSTED|N/A` · the §3.2
ratchet · the verdict join · the §5 residual register · handoff), the **no-blend plane rule** (a WP
green retires one class of one step on the amenable surface — it never lowers a risk *level*), and the
`\fuel`/`\cost`/`\resource` spine for DoS/bounded-work cells. Author to it verbatim.

## Live + archived instances
- **`s2n-tls-analysis-crosswalk.md`** (repo root) — the **current live RMF example**, seeded from a
  converged campaign (690 WP goals). Use it as the golden filled ledger (its §3.3 matrix and §5
  register are the worked shape `C9` validates against).
- **`experiments/mbedtls/ebios-crosswalk.md`** — the archived prior instance (EBIOS-flavoured).

## RMF-specific tag bindings (what fills each template slot)
The crosswalk references the report's pinned tags (see
[`report-format.md`](./report-format.md)) — it does **not** invent new ones:

| Template slot | RMF tag binding |
|---|---|
| §1 supporting asset (Categorize) | **`SA#`** — technical component (a translation unit maps to it here, code-aware) |
| §1 / §2 information asset | **`IA#`** — mission/data asset (Prepare) |
| §1 categorized element | **`IM#`** — system element + FIPS-199 impact **`Lo`/`Mod`/`Hi`** |
| §2 scenario row (ranking key) | **`RS#`** — risk scenario, ranked by its cited **risk level** `Low/Moderate/High` (= **`L1`..`L4`** likelihood × `IM#` impact), **never re-derived from code** |
| §2 threat event / source | **`TE#`** ← **`TS#`** with its **800-30 origin** `ADV`/`ACC`/`ENV` (adversarial / accidental / environmental — the three origins RMF weights, unlike EBIOS) |
| §2 / §3 vulnerability | **`VU#`** — predisposing condition |
| §3 ledger row asset | **`SA#`** (one row per supporting asset; `C9` requires a row for every Hi/High `SA#`/`IA#`) |
| §4 verdict join | overlay `verdicts.tsv` ↔ `RS#` (named plane only) |
| §5 residual register | **`RR#`** — signed off by the **Authorizing Official (AO)** at the human terminus (the ATO) |
| §3.3 / §5 control | **`CTL#`** — an 800-53 family token (`AC-6`, `SC-5`, `SI-7`, …); ATT&CK technique tags join in per [`attack-mapping.md`](./attack-mapping.md) |

## Load-bearing invariants (inherited from the template)
- **Asymmetry preserved** — the upstream report passed the C8 endogeneity tripwire (no code artifacts
  in R1–R4); only the crosswalk is code-aware. Never back-port a file/function name into the report.
- **No-blend** — every §3/§4 cell names its plane; a green never lowers an RMF risk level here. Only
  the AO lowers a risk level, downstream, at the Authorize step.
- **Ratchet** — the §3.2 baseline only moves forward; an `UNMODELED` cell on a high-value asset is a
  ratcheted `WARN`, never a silent green. (The cross-run ratchet is `frama-c-monitoring`'s CI gate;
  `rmf-lint.sh`'s `C9` only does single-file structural validation of the ledger.)

## Native generation (Move 5)

The crosswalk is **generated**, not hand-written: `./crosswalk-gen.sh PREFIX` emits
`PREFIX-crosswalk.md` from this loop's code-blind report (§1 assets, §2 scenarios, §5 residuals) joined
with the code-aware `PREFIX-acsl/verdicts.tsv` (§4) and `stride-ledger.tsv` (§3). The generator
machine-checks that every `PROVED` ledger cell is backed by a real verdict (a fabricated PROVED fails
generation). See `config/skills/frama-c-monitoring/references/crosswalk-generation.md` for the full
contract and the `stride-ledger.tsv` format. CI gate G4 (`make stride-ci`) keeps it in sync.
