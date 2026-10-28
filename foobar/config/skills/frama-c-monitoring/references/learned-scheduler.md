# Learned knowledge — Scheduler / graph planner (frama-c-monitoring)

Append-only, Gate-S-gated heuristics the **scheduler** capitalized while running the
`frama-c-monitoring` loop (see this skill's `SKILL.md` §7). Each entry passed an
`sl-monitoring-sl` Gate S audit by a disjoint monitor and carries provenance.

**Scope / barrier:** include/call-graph and **leaf-first** ordering heuristics — how to
build the dependency graph of a C/C++ codebase, what makes a clean topological order, when
two units are genuinely independent (parallelizable), how proven-`ensures`→stub-`requires`
propagation should flow, **and how to compute the per-unit preprocessing flags** (`-I`/`-D`/
`-machdep`/force-includes from `compile_commands.json`). Record ordering/structure/flag
knowledge only — no specs, no implementation specifics. Future runs load this file at
delegation time.

**Entry format:**
```
### <title>
- Kind: ignore-signal | defer-to-oracle
- Gate S: PASS | CARVE-OUT
- Arose from: <mission / unit / gap-N>
- Heuristic: <rule>
- Carve-out: <exception → guidance clause>   (if any)
```

## Entries

### Per-unit preprocessing flags are the scheduler's job — a parse failure is a scheduler gap, not a unit FAILED
- Kind: defer-to-oracle
- Gate S: PROVISIONAL (seed — confirm via Gate S on first real use)
- Arose from: StandardAlgorithms corpus prep (the C port differs from Creusot here)
- Heuristic: unlike a Rust crate (one `cargo metadata`), each C translation unit needs its
  own `-I`/`-D`/`-machdep` to even parse. Get them from `compile_commands.json` (`bear -- make`
  or CMake `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) and carry them in the `{file, flags}` queue
  (`framac-queue.sh`). Two recurring traps: (1) a bare `-I` is rejected by frama-c — wrap
  includes in `-cpp-extra-args="..."`; (2) when the corpus prep stripped `.acsl`/typedef
  include chains, the unit no longer sees types it needs — supply them with **force-includes**
  (`-cpp-extra-args="-include typedefs.h -include ..."`). A unit that won't parse is a
  **scheduler** gap (wrong/missing flags) to fix in the queue, NOT a base-loop FAILED.

### This corpus inlines ACSL predicate/lemma blocks per-unit — there is no `-Iframac/Logic`, so `.acsl` includes don't resolve
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: the functional-residual batch (gold uses `#include "MultisetReorder.acsl"`; framac/ flags omit -Iframac/Logic)
- Heuristic: the gold reference (`framac-gold/`) factors shared logic into `Logic/*.acsl` files pulled
  in by `#include`. The working corpus does NOT: the prescribed WP flags have no `-Iframac/Logic`, so a
  C `#include "<x>.acsl"` cannot resolve and would also be non-ACSL added text (faithfulness break).
  The corpus convention (the `push_heap.h` pattern) is to **inline** the needed predicate/`logic`/lemma
  blocks into the unit's own `.h`, built bottom-up via the unit `#include` graph — pure ACSL, so
  faithful. When the spec-author ports a gold functional spec, copy the `Logic/*.acsl` *content* inline,
  do not add an include. Also remember the per-unit **force-include** (`-include typedefs.h`, and
  `-include Stack.h` for the Stack family) — the strip removed the typedef chains, so without it WP
  reports `unexpected token 'value_type'` and silently drops the annotations.

### Leaf-first means callee-specified-first; stub `ensures` must be implied by the proven callee `ensures`
- Kind: defer-to-oracle
- Gate S: PROVISIONAL (seed)
- Arose from: seed (ported from creusot-monitoring leaf-first discipline, adapted to ACSL stubs)
- Heuristic: topo-sort so every callee is specified before its callers, and propagate the
  callee's **proven** `ensures` as the caller's stub `ensures`. The cross-unit soundness
  obligation (Gate B_top): when the callee comes into scope, its proven `ensures` must
  **imply** the stub the caller assumed — an over-promising stub is unsound and is the
  cross-unit coherent-and-wrong. Parallelize only across units that share no dependency.
