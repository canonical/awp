# EBIOS crosswalk-format reference — thin pointer + tag bindings

The crosswalk is the one document where the **code-blind** EBIOS RM study (the exogenous upper bound
`U`) meets the **code-aware** verification (the lower bound `L`). It is authored by the *architect*
(who reads the source) — that asymmetry is the whole point, and is what keeps the upstream `ebios-sl`
report exogenous. The `/ebios` campaign produces an `ebios-crosswalk.md` (or `<prefix>-crosswalk.md`).

## The canonical schema (do NOT redefine — reference it)
**[`config/skills/frama-c-monitoring/templates/crosswalk-template.md`](../../frama-c-monitoring/templates/crosswalk-template.md)**
is the authoritative schema: the six sections (asset crosswalk · scenario ranking · the §3 STRIDE
coverage ledger with the cell lifecycle `UNMODELED|PROVED|TRUSTED-PENDING|TRUSTED|N/A` · the §3.2
ratchet · the verdict join · the §5 residual register · handoff), the **no-blend plane rule** (a WP
green retires one class of one step on the amenable surface — it never lowers a risk *level*), and the
`\fuel`/`\cost`/`\resource` spine for DoS/bounded-work cells. Author to it verbatim.

## Archived + live instances
- **`experiments/mbedtls/ebios-crosswalk.md`** — the **archived prior EBIOS instance**; the closest
  worked EBIOS-flavoured example to follow.
- **`s2n-tls-analysis-crosswalk.md`** (repo root) — the current live example (RMF-flavoured, but its
  §3.3 STRIDE matrix and §5 residual register are the same schema and the shape `C9` validates).

## EBIOS-specific tag bindings (what fills each template slot)
The crosswalk references the report's pinned tags (see
[`report-format.md`](./report-format.md)) — it does **not** invent new ones:

| Template slot | EBIOS tag binding |
|---|---|
| §1 business asset (W1) | **`BA#`** — mission/value asset |
| §1 supporting asset (W1) | **`SA#`** — technical component (a translation unit maps to it here, code-aware) |
| §1 / §2 feared event | **`FE#`** with its **severity** `G1`..`G4` (`G1` minor · `G2` significant · `G3` serious · `G4` critical) |
| §2 scenario row (ranking key) | **`SS#`** (strategic, W3) / **`OS#`** (operational, W4) ranked by its cited risk level (severity × **likelihood** `V1`..`V4`), **never re-derived from code** |
| §2 risk origin / objective | **`RO#`** / **`TO#`** (or the combined **`ROTO#`**) — EBIOS weights the **adversarial** origin (the deliberate attacker); the *accidental* race / TOCTOU feared-event enters via the doctrine families, see [`stride-families.md`](./stride-families.md) |
| §2 attack path | **`AP#`** |
| §3 ledger row asset | **`SA#`** (one row per supporting asset; `C9` requires a row for every G3/G4 `SA#`) |
| §4 verdict join | overlay `verdicts.tsv` ↔ `SS#`/`OS#` (named plane only) |
| §5 residual register | **`RR#`** — signed off by the **risk owner** at the human terminus (W5 acceptability) |
| §3.3 ATT&CK | the WS9 technique tags join in (taxonomy lives RMF-side, [`../../rmf-sl/references/attack-mapping.md`](../../rmf-sl/references/attack-mapping.md)) |

## Load-bearing invariants (inherited from the template)
- **Asymmetry preserved** — the upstream report passed the C8 endogeneity tripwire (no code artifacts
  in W1–W3); only the crosswalk is code-aware. Never back-port a file/function name into the report.
- **No-blend** — every §3/§4 cell names its plane; a green never lowers an EBIOS risk level here. Only
  the risk owner lowers a risk level, downstream, at the W5 acceptability step.
- **Ratchet** — the §3.2 baseline only moves forward; an `UNMODELED` cell on a high-value asset is a
  ratcheted `WARN`, never a silent green. (The cross-run ratchet is `frama-c-monitoring`'s CI gate;
  `bin/ebios-lint.sh`'s `C9` only does single-file structural validation of the ledger.)

## Native generation (Move 5)

The crosswalk is **generated**, not hand-written: `bin/crosswalk-gen.sh PREFIX` emits
`PREFIX-crosswalk.md` from this loop's code-blind report (§1 assets, §2 scenarios, §5 residuals) joined
with the code-aware `PREFIX-acsl/verdicts.tsv` (§4) and `stride-ledger.tsv` (§3). The generator
machine-checks that every `PROVED` ledger cell is backed by a real verdict (a fabricated PROVED fails
generation). See `config/skills/frama-c-monitoring/references/crosswalk-generation.md` for the full
contract and the `stride-ledger.tsv` format. CI gate G4 (`make stride-ci`) keeps it in sync.
