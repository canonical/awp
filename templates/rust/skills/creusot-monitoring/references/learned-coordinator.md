# Learned knowledge — Mission coordinator (creusot-monitoring)

Append-only, Gate-S-gated heuristics the **mission coordinator** capitalized while
running the `creusot-monitoring` loop (see this skill's `SKILL.md` §7). Each entry
passed an `sl-monitoring-sl` Gate S audit **from a disjoint base** (a cross-provider
agent or a human — the coordinator may not audit its own skills) and carries
provenance.

**Scope / barrier:** mission-decomposition and guidance-interpretation heuristics —
how to turn an `analyze crate xxx in dir yyy` + guidance into a plan; when to cut a
crate plan; how to apply guidance like *"disregard network access"* uniformly. Judge
against the guidance `U`; record no sub-agent's private rationale and no per-file
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
