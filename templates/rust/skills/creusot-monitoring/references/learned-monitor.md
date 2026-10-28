# Learned knowledge — Base-SL monitor (creusot-monitoring)

Append-only, Gate-S-gated heuristics the **base-SL monitor** capitalized while running
the `creusot-monitoring` loop (see this skill's `SKILL.md` §6–§7). Each entry passed an
`sl-monitoring-sl` Gate S audit **from a disjoint base** (the monitor may not audit its
own skills) and carries provenance.

**Scope / barrier:** how to audit `creusot-sl`'s soft outputs — which base skills tend
to over-reach, ignore-signal vs defer-to-oracle tells, which mutations/cross-unit
checks expose a guidance-wrong or globally-wrong inferred contract, when a surprise is
a real tooling gap (→ `getting-better/`) vs a bug (→ `bugs-to-report/`). Judge against
the guidance `U` and the base oracle `L` only — never a base agent's rationale. Future
runs load this file at delegation time.

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

### Trivial stubs invite fabricated proofs — fast-path them, enforce faithfulness
- Kind: ignore-signal
- Gate S: CARVE-OUT
- Arose from: batch 1 (8 of 10 sub-agents fabricated code)
- Heuristic: a `creusot-sl` sub-agent handed a 1-line no-op stub (empty body,
  struct-only, or comment-only) tends to **invent** functions/structs to match the
  filename and "prove" them — textbook coherent-and-wrong. Two defenses: (1) the
  coordinator **fast-paths** any file with no non-empty `{ ... }` body to `TRIVIAL`
  without spawning a sub-agent; (2) the monitor runs the **faithfulness gate**
  (`monitor-check.sh`: stripping all `#[...]`/`use` from the annotated file must
  reproduce the original code) and reverts + re-labels any FABRICATED result.
- Carve-out: findings (bugs/heuristics) produced *from a fabricated run* are discarded
  — their provenance is tainted (e.g. the batch-1 `>>`-division gap came from invented
  shift code and was NOT routed).

### Faithfulness gate is line-oriented — formatting-altering annotations FABRICATE
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: 100doors.rs (batch 4), bug/1312.rs (batch 5)
- Heuristic: `monitor-check.sh` strips `#[...]`/`use`/proof-macros then diffs line-by-line
  (whitespace-normalized but NOT line-joined). So two faithfulness traps recur even when
  the agent "only added annotations": (1) adding a non-`creusot_std` `use` to fix a macro
  ambiguity (`use std::vec;` for the `vec!` clash) — the strip tool does not remove it, so
  it survives as added code → FABRICATED; (2) a closure-level `#[requires]` placed before
  a closure that the original wrote on ONE line forces the closure body onto a new line, and
  the strip tool leaves the split → the diff sees a line break → FABRICATED. Defense: keep
  the `is_*` self-reported PROVED verdicts on a SHORT leash — always run the gate; when it
  FABRICATEs over pure formatting/`use`, the file is genuinely not faithfully annotatable
  in place, so downgrade to FAILED (real code, couldn't annotate without altering it),
  revert from `training-data/`, and DISCARD that run's LEARNED fields as tainted.

### Calibration: the TRIVIAL fast-path under-specifies spec-demonstration fixtures
- Kind: ignore-signal
- Gate S: CARVE-OUT
- Arose from: the 241-file annotate-vs-reference comparison (`annotate/*.txt`, 2026-06-17)
- Heuristic: the coordinator's stub fast-path treats "no operation can panic/overflow/index"
  as "nothing to verify → TRIVIAL". That is sound for *safety*, but it **systematically
  drops functional/demonstration content** in files whose whole purpose is to exercise a
  Creusot feature — the reference annotations there are `#[logic]` functions, trait laws,
  `View`/`Invariant` impls, `proof_assert!`/prophecy lemmas, and functional `#[ensures]`
  that carry no panic/overflow VC. Against the reference, these `TRIVIAL` files are the
  dominant shortfall, and a few were outright mis-classified (e.g. `bug/1030`, a logic-fn
  fixture). Carve-out → the relevance claim "no safety VC ⇒ TRIVIAL" is too broad: it
  ignores the signal "the file declares `#[logic]`/trait-law/`impl View`/`impl Invariant`
  scaffolding or a functional `#[ensures]` in the reference." When that signal is present
  (or when the file lives under `specification/`, `syntax/`, `traits/`, `type_invariants/`,
  `bitvectors/`), do NOT fast-path to TRIVIAL — route it to a `creusot-sl` sub-agent for a
  *functional* spec, and reserve TRIVIAL for genuinely empty/no-op bodies. Trade-off noted:
  this widens the sub-agent fan-out (more cost) in exchange for matching the reference's
  demonstration intent rather than only its safety obligations.
- Provenance: each per-file diff in `annotate/<name>.txt`.
