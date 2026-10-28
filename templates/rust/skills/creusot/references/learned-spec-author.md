# Learned knowledge — Spec author (creusot-sl)

Append-only, Gate-S-gated requirement→Pearlite patterns the **spec author**
capitalized while running the `creusot-sl` loop (see the `creusot-sl` skill (`config/skills/creusot-sl/SKILL.md`) §11).
Each entry passed an `sl-monitoring-sl` Gate S audit by a disjoint monitor (the
coordinator) and carries provenance.

**Scope / barrier (load-bearing):** **requirement-level only.** This role is
barriered from the implementation — entries must contain **NO implementation
specifics** (no function bodies, no concrete constants from the code, no algorithmic
detail). Record only how a *kind* of requirement maps to Pearlite: `requires`/
`ensures`/`invariant` shapes, `@`/`Seq`/`Int` modelling idioms, sortedness/
permutation/bounds templates. An entry that would leak the code is a barrier breach →
REJECT. Future runs load this file at delegation time.

**Entry format:**
```
### <title>
- Kind: ignore-signal | defer-to-oracle
- Gate S: PASS | CARVE-OUT
- Arose from: <file / gap-N>
- Heuristic: <rule>
- Carve-out: <exception → requirement clause>   (if any)
```

## Entries
_(none yet)_
