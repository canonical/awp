# Learned knowledge — Scheduler / graph planner (creusot-monitoring)

Append-only, Gate-S-gated heuristics the **scheduler** capitalized while running the
`creusot-monitoring` loop (see this skill's `SKILL.md` §7). Each entry passed an
`sl-monitoring-sl` Gate S audit by a disjoint monitor and carries provenance.

**Scope / barrier:** dependency-graph and **leaf-first** ordering heuristics — how to
build the module/call graph of a crate, what makes a clean topological order, when two
files are genuinely independent (parallelizable), how `#[ensures]`→`#[requires]`
propagation should flow. Record ordering/structure knowledge only — no specs, no
implementation specifics. Future runs load this file at delegation time.

**Entry format:**
```
### <title>
- Kind: ignore-signal | defer-to-oracle
- Gate S: PASS | CARVE-OUT
- Arose from: <mission / file / gap-N>
- Heuristic: <rule>
- Carve-out: <exception → guidance clause>   (if any)
```

## Entries
_(none yet)_
