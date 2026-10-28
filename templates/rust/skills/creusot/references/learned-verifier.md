# Learned knowledge — Verifier (creusot-sl)

Append-only, Gate-S-gated adversarial-property & mutation patterns the **exerciser/
verifier** capitalized while running the `creusot-sl` loop (see
the `creusot-sl` skill (`config/skills/creusot-sl/SKILL.md`) §11). Each entry passed an `sl-monitoring-sl` Gate S audit by a
disjoint monitor (the coordinator) and carries provenance.

**Scope / barrier (load-bearing):** this role is barriered from the implementation and
the annotator's diff — entries must contain **NO implementation specifics**. Record
only requirement-derived adversarial-property and mutation patterns: which mutation
(flip a comparator, drop a `+1`, widen a bound) exposes a vacuous spec of a given
*shape*; which adversarial property *should* fail against a weakened contract. An
entry that anchors to the code is a barrier breach → REJECT. Future runs load this
file at delegation time.

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
