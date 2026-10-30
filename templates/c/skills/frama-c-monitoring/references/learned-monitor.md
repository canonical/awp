# Learned knowledge — Base-SL monitor (frama-c-monitoring)

Append-only, Gate-S-gated heuristics the **base-SL monitor** capitalized while running
the `frama-c-monitoring` loop (see this skill's `SKILL.md` §6–§7). Each entry passed an
`sl-monitoring-sl` Gate S audit **from a disjoint base** (the monitor may not audit its
own skills) and carries provenance.

**Scope / barrier:** how to audit `framac-sl`'s output — the four base gates (faithfulness
/ Gate B / non-vacuity / gold-completeness), which base skills tend to over-reach,
ignore-signal vs defer-to-oracle tells, which mutations / cross-unit checks expose a
guidance-wrong or globally-wrong inferred contract, the SMT→Coq escalation soundness
checks, and when a surprise is a real tooling gap (→ `getting-better/`) vs a bug
(→ `bugs-to-report/`). Judge against the guidance `U` (and `framac-gold`) and the WP oracle
`L` only — never a base agent's rationale. Future runs load this file at delegation time.

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

### A definitional `axiomatic` is NOT a Gate B escape hatch — carve-out to "no behavioural axiom"
- Kind: ignore-signal
- Gate S: CARVE-OUT
- Arose from: StandardAlgorithms corpus (the blanket "flag every axiomatic" rule over-reached)
- Heuristic: do NOT flag every `axiomatic`/`axiom` as a Gate B hatch. CARVE-OUT: an
  axiomatic that only DEFINES a recursive `logic`/`predicate` by its base/step equations
  (`count_occ`, `sorted`, `gcd`) is the standard, legitimate ACSL idiom. Flag a Gate B HATCH
  only when an `axiom` asserts a *behavioural fact* about the program — i.e. it mentions the
  C function under verification or `\result`. The residual risk of a definitional axiomatic
  is *inconsistency* (proves everything), which the Gate C mutation probe catches, not grep.

### Mutation probe must mutate CODE not ACSL; VACUOUS is NEEDS-MANUAL, never terminal
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: Nonmutating/search.c, clamp/swap probes (StandardAlgorithms batches)
- Heuristic: `bin/framac-mutation-probe.sh` confirms teeth (a mutated body must break a goal),
  but two refinements are load-bearing. (a) Units put loop invariants/asserts right BEFORE
  the code, so a "first occurrence in file" mutation can hit the SPEC → false VACUOUS;
  mutate only OUTSIDE ACSL spans. (b) Generic mutations (`+`↔`-`, `<`→`<=`, `==`→`!=`) can be
  behavior-preserving (clamp boundary) or not apply (pure/store-only fn). So treat
  VACUOUS/INCONCLUSIVE as **NEEDS-MANUAL** (author ONE targeted body mutation — swap a
  returned branch, change an assigned var — and confirm a goal goes RED), never an auto-pass
  and never a terminal FAILED of a real proof.

### Mutation TEETH proves NON-VACUITY, NOT COMPLETENESS — the sorting trap (Gate C′ is editorial)
- Kind: ignore-signal
- Gate S: PASS
- Arose from: Sorting/{insertion,selection,bubble}_sort.c (passed every machine gate yet under-specified)
- Heuristic: faithful + Gate B CLEAN + mutation TEETH can ALL hold while the spec omits the
  intended property. A sort whose only postcondition is `ensures Sorted(a,0,n)` passes every
  machine gate, yet a **zero-fill body satisfies it** (sortedness ≠ permutation). The probe
  shows teeth on the *sortedness* goal but cannot see the missing permutation clause.
  Completeness is the **gold-comparison** check (Gate C′, `bin/framac-compare.sh` vs
  `framac-gold/`) — no code mutation supplies it. A unit that machine-passes but omits the
  intended property is **PARTIAL** ("RTE+X proved; intended Y unspecified"), never PROVED.
  Watch any rearrangement/aggregate where a trivial output (constant/zero/identity) could
  satisfy the written postcondition.

### A goal routed through an unspecified callee, or a trivially-true postcondition, is vacuously green
- Kind: ignore-signal
- Gate S: PASS
- Arose from: Heap/is_heap.c (trivially-true catch); seed from the lace `{false}`-block finding
- Heuristic: two vacuous shapes no faithfulness/teeth check alone catches. (1) A call to a
  callee with NO ACSL contract in scope: WP may model its body as unreachable/`\false`,
  making every downstream goal **vacuously Valid**. Before trusting an all-green unit, give
  the callee a real stub (or expand to primitives) and confirm the goal still proves; a goal
  that flips to Unknown once specified was vacuous. (2) A bool-returning predicate-test whose
  ONLY postcondition is `ensures \result==0 || \result==1` holds for any return → vacuous;
  tell-tale: the file DEFINES a `predicate` (e.g. `is_max_heap`) the contract never USES. Fix
  (a spec-author job): `ensures \result != 0 <==> is_max_heap(a,n);`.

### SMT→Coq escalation is sound only if cache-clean and zero-admit — Print Assumptions is the gate
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: gcd/ flagship gate (gcd_positive/divides/greatest discharged in Coq 8.20.1)
- Heuristic: when the base loop escalates an SMT-unprovable goal (induction — the GCD
  maximality case) to Coq via the `framac-coq8` toolchain, a green is trustworthy ONLY if:
  (1) the WP replay reproduces with `-wp-cache none`/`replay` — a `[Timeout] … (Cached)` SMT
  result masking the Coq script is NOT a pass (`-wp-prover coq` plus user `Require` imports
  must go INSIDE `Proof.`, not the regenerated prelude, or WP silently discards them — see
  the `wp-interactive-coq-replay` memory); (2) `Print Assumptions wp_goal` on each `.v` shows
  ONLY the intended definitional axioms (and already-proved upstream lemmas) and **0 admits** —
  any `classic`/`admit`/smuggled behavioural axiom → REJECT; (3) a lemma WP assumes downstream
  (e.g. `gcd_greatest` relying on `gcd_positive`) is sound only if that lemma was itself proved
  — verify the chain. A Coq script that compiles is not a proof until its assumptions are audited.

### Re-verify before trusting the verdict log; a silently-dropped annotation hides both regressions and fixes
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: the psum residual cluster (verdict log stale; partial_sum_inv.c referenced a renamed logic fn)
- Heuristic: the verdict log is a CACHE, not ground truth — re-run WP before acting on a PARTIAL/PROVED.
  Two real drifts seen: (1) a later strengthening wave reformulated `partial_sum.h` (added a
  `reads`-footprint logic fn) that dissolved the inductive obligation, so three units logged PARTIAL
  actually proved 52/52, 51/51, 15/15 with SMT — the log was simply stale. (2) The reformulation renamed
  the logic function (`psum` → `AccumulateDefault`) but `partial_sum_inv.c` kept the old name, so WP
  emitted `unbound logic function psum` (a WARNING, not an error) and **silently dropped that
  `requires` clause** — the unit "verified" against a weaker spec. Audit rule: scan the WP run for
  `unbound logic function` / `dropped`/`ignoring` annotation warnings and treat any as a faithfulness-
  adjacent defect (the proved spec is not the written spec). A clean re-run (correct flags incl. the
  `-include typedefs.h` force-include) is the only trustworthy verdict.

### A "prover limitation / not addressable by Coq" verdict is a category error — REJECT it (Curry–Howard)
- Kind: ignore-signal
- Gate S: PASS
- Arose from: stack_empty_wd.c mis-labelled "not addressable by Coq, blocked by uneditable header"
- Heuristic: by Curry–Howard a proposition is provable iff true, so the monitor must REJECT any base
  verdict that blames the prover for a goal it could not close ("PARTIAL — prover/Coq limitation",
  "not addressable by Coq", "unprovable, header frozen"). Such a goal is **non-entailed** → a
  **specification defect**, and the honest verdict names the missing/weak clause, not the prover.
  Audit test: ask the base loop for the **counter-model** (a hypotheses-consistent state falsifying
  the goal). If it exists (e.g. postcondition `\result==1` while the callee only ensures `\result!=0`
  → model `\result==2`), confirm SPEC-DEFECT and require the fix (strengthen the unit's or the
  dependency's ACSL — a header's ACSL is editable; only executable C is frozen) or an honest
  "PARTIAL — spec defect in `<dep>`: `<clause>`". If NO counter-model exists and the obstruction is
  induction/a quantifier, it is SMT-incompleteness → the goal IS provable, route to Coq, never accept
  "can't". Distinct legitimate bucket: goal entailed + Coq could close it + toolchain absent →
  tooling gap (`getting-better/`), still not a "prover limitation." A red goal has exactly two honest
  classifications (SMT-incomplete→Coq, or non-entailed→spec defect); a third is always a REJECT.

### Calibrate triage against gold — "no safety VC ⇒ done" systematically under-specifies
- Kind: ignore-signal
- Gate S: CARVE-OUT
- Arose from: the framac-gold comparison over StandardAlgorithms (PARTIAL-vs-PROVED gap, then closed by strengthening waves)
- Heuristic: the coordinator's fast-path treats "no operation can overflow/index/div0" as
  "nothing to verify". Sound for *safety*, but it systematically drops **functional** content
  in units whose purpose is to demonstrate a property — where the gold annotates a functional
  `ensures`, a `predicate` relation, or a lemma carrying no RTE VC. Against `framac-gold/`
  these look done-or-trivial but are the dominant shortfall. Carve-out: the relevance claim
  "no safety VC ⇒ done" is too broad — when the gold (or the file's own defined-but-unused
  `predicate`) signals a functional obligation, route the unit for a *functional* spec and
  record PARTIAL until it relates `\result`/state to the defined property. Ground-truth
  comparison (`bin/framac-compare.sh`) is the calibration that catches an over-broad triage;
  without it, a fast-path that silently drops a category *looks like clean progress*.
- Provenance: the per-unit verdict log (`framac/.verdicts.tsv`) and the gold diff.

### Terminus needs a MECHANICAL function-enumeration cross-check — triage-invisible functions slip every plane
- Kind: ignore-signal
- Gate S: REJECT (a "converged" claim without the empty-gap cross-check is premature)
- Arose from: a logging function (not a parser, not a gate, not obviously attacker-facing) covered by nothing until a
  `{all in-scope C functions} ∖ {functions named in the coverage ledger}` cross-check found it — carrying a real finding
- Heuristic: "no finding-bearing class-C left" is NOT the terminus. Before DONE, run the mechanical set difference
  `{every in-scope C function} ∖ {functions named in the coverage/gaps ledger} == ∅`. Functions that are NEITHER a
  Tier-1 parser NOR an authorization gate NOR obviously attacker-facing (loggers, small helpers, orchestration
  `main`s) slip every risk-ranked triage and every plane — the enumeration is the only gate that catches them. An
  empty gap set is evidence; an asserted "the rest is plumbing" is NOT — examine each claimed-plumbing fn for
  buffer/privilege ops before declaring it out-of-scope (evidence-based boundary, not assertion). This gate fired
  repeatedly AFTER apparent convergence and each time surfaced real work (a missed authorization gate, a missed
  attacker-adjacent buffer, a tool-soundness bug, a truncation finding). A recurring low-severity finding it catches:
  `snprintf` truncation checked with `r == sizeof(buf)` instead of `r >= sizeof(buf)` (snprintf returns the WOULD-BE
  length; `r > size` slips through → silently-truncated output accepted as success).

### Add `-wp-smoke-tests` to the monitor gate for every +cast discharge (silent-vacuity catch)
- Kind: ignore-signal
- Gate S: REJECT
- Arose from: a +cast "PROVEN" whose entire post-memset tail was dead code (see [[learned-verifier]] +cast vacuity)
- Heuristic: a green `-wp -wp-model +cast` count is NOT a floor without `-wp-smoke-tests: Y/Y all live`. The +cast
  cast-frame can collapse the post-`memset` state to `\false` and silently vacuate the proof (green "N/N" over dead
  code). The monitor MUST demand the smoke line for every +cast discharge, and cross-check any `X<Y` smoke against
  `-wp-model Typed` to separate real vacuity (`dead_code`, model-DEPENDENT — REJECT) from benign dead code
  (noreturn/stub, model-INDEPENDENT — accept). Non-vacuity via smoke is a monitor floor exactly like faithfulness; a
  campaign that ran +cast throughout must smoke-audit EVERY unit (store-bloat-walled units that can't smoke-run are
  cleared by trigger-pattern absence, not waved through).
