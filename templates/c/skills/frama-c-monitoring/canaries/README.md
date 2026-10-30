# Seeded coherent-and-wrong canaries

Run once per campaign by `bin/framac-canary.sh` (repo root). These are *consistency checks that the
wiring fires* (paper §synthesis: catchability made measurable via seeded falsifications —
mutation-testing the verifier itself), **not** efficacy measurements. They institutionalize the
natural `ssl_ticket_parse` catch as a repeatable, self-contained check that does not depend on the
mbedtls / StandardAlgorithms corpus.

Each campaign report must open with the canary table: each seed, its expected catch site, and
fired = yes/no. A campaign whose **soft** canary is caught only by re-running WP (not by a disjoint
actor / the trivial-witness probe) is flagged as not exercising disjointness.

| Canary | Seeded coherent-and-wrong | Expected catch site | Must fire by |
|---|---|---|---|
| **faithfulness** (`faithfulness/inc.c`) | a *fabricated proof*: executable C edited (`x+1u`→`x`) so WP discharges a false `ensures` | the **faithfulness gate** (strip-ACSL == pristine) | structural, mechanical — WP is green, the gate reverts |
| **soft-side** (`soft/sort2.c` + `sort2_trivial.c`) | a *valid-but-wrong-question* spec: `ensures ordered` only (no permutation); a zero-fill trivial witness also satisfies it | **Gate C′ / the disjoint completeness oracle** (trivial-witness probe) | a code-blind actor — WP is green on **both** bodies and cannot tell |
| **macsl-contexts-sync** (`macsl-contexts-sync.sh`) | *capability drift*: the tool gains a `\context` (e.g. `\authorized`) the skills never learn, so campaigns default to `\writing`/`\total` and hand-roll the rest | the **catalog↔tool diff** (`-macsl-list-contexts` vs `frama-c-api/references/macsl-contexts.md`) | mechanical — exit 1 on set mismatch; exit 2 if macsl unbuilt |

The soft canary is the important one: it is the only canary that exercises the half the review
calls more dangerous (an artifact that *satisfies* WP while betraying intent). WP being green on
both the real and the trivial-witness body is the mechanical signature that the spec is too weak —
the catch belongs to the disjoint oracle, never to WP.
