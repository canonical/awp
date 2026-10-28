# Squeeze table — <CAMPAIGN NAME>

The coordinator fills this **before any delegation** (paper §disjoint: the (U,L) table written
up front and pasted row-by-row into each sub-agent prompt). It is a required Phase-0 artifact of
`frama-c-monitoring`. `framac-squeeze-audit.sh` checks it for compliance (C1 distinctness; C3 —
the implementation/annotation absent from every judge's context).

Columns:
- **U (upper bound)** — the citable soft authority fixing the strongest claim the actor may make.
- **L (lower bound)** — the executable ground truth whose verdict it cannot alter.
- **Denied** — evidence that MUST be absent from this actor's fresh context (the barrier, C3).
- **Provider** — the model/provider family the actor ran on (for the disjointness ledger; the
  paper owes a cross-provider replication — record when a disjoint role actually decorrelated).

The audit requires: pairwise-distinct (U,L) pairs (C1); and every **judge** role
(property-author, verifier, completeness-oracle, monitor) lists the implementation/annotation as
**Denied** (C3). A new role is justified only by a new evidence base — two actors with identical
(U,L) are one actor.

| Actor | U (upper bound) | L (lower bound) | Denied (absent from context) | Provider |
|---|---|---|---|---|
| Coordinator | mission guidance + scope | aggregated WP verdicts + cross-unit discharge | — (judges against guidance, never a sub-agent's rationale) | <e.g. opus> |
| Property-author | the requirement / `framac-gold` spec | expressibility: each obligation clause dischargeable by some WP goal | **the implementation; any annotation; the diff** | <e.g. sonnet/other> |
| Annotator | the spec's strongest mandated claim | WP `Valid` + the standing faithfulness gate | the gold (writes ACSL from the requirement the coordinator passes, not from gold directly) | <opus> |
| Verifier | the spec's acceptance clauses + documented surface only | what WP actually proves when run | **the implementation body; the diff** (reads the WP verdict, never the code) | <opus> |
| Completeness oracle (WS2) | the requirement / `framac-gold` + the WP **goal list** | the trivial-witness probe (a constant/zero/identity artifact must NOT satisfy the spec) | **the implementation; the annotator's rationale; the proof scaffolding** | **different family if possible** |
| Probe | the design claim under test (one per probe) | the tool's actual behaviour (mutation probe / parse gate) | implementing anything | <opus> |
| Monitor (Gate S) | the mission guidance (the skill/contract must not contradict it) | the WP oracle + cross-unit discharge, as a differential comparator | **the base agents' private notes / rationale** | **different family if possible** |

## Worked example — mbedtls `library/` RTE campaign
| Actor | U | L | Denied | Provider |
|---|---|---|---|---|
| Coordinator | "RTE-robustness of untrusted-input parsers; crypto/state-machine out of scope" | WP verdicts on `library/`+`tf-psa-crypto/utilities/` | sub-agent rationales | opus |
| Property-author | the parser's documented robustness claim (no OOB/overflow for any input) | each clause → a `-wp-rte` goal | the `.c` body, the ACSL | (within-family — flag) |
| Annotator (`framac-sl`) | "no RTE under a sound, non-vacuous precondition" | `-wp-rte` Valid + `framac-monitor-check.sh` ACCEPT | — | opus |
| Verifier | the documented `(buf,end)` surface | WP `Proved goals N/N` | the body, the diff | opus |
| Completeness oracle | (for functional units) `framac-gold` `ensures` | trivial-witness probe | body, scaffolding | **owed cross-provider** |
| Monitor | mission guidance | re-run WP on merged tree + faithfulness diff | base notes | opus |

> Disjointness ledger note: in the mbedtls run the disjoint roles (completeness oracle, monitor)
> ran **within one provider family** — recorded here as a known weakness (paper §10 "shared
> priors"); a cross-provider completeness oracle is the owed decorrelation.
