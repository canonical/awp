# Learned knowledge — Verifier (framac-sl)

Append-only, Gate-S-gated **formal-test** & mutation patterns the **verifier**
capitalized while running the `framac-sl` loop (see `../../framac-sl/SKILL.md` §11). Each real
entry passes an `sl-monitoring-sl` Gate S audit by a disjoint monitor (the coordinator) and
carries provenance.

**The verifier's deliverable is a *formal test*** (see `../SKILL.md` "A formal test"): an
acceptance test driver authored from the requirement/English description — broadest `requires`,
the intended property checked in the **body**, a deliberately simple `ensures \result==1` — proven
by WP over **all** inputs. The adversarial checks ARE the body; the simple postcondition is by
design (proving `\result==1` over the broad domain forces every failure branch unreachable). The
mutation probe is the *companion* that proves the formal test has teeth (a driver with no real
check proves `\result==1` vacuously → reject).

**Scope / barrier (load-bearing):** how to author formal tests (and which mutation exposes a
vacuous one of a given shape) from the requirement + surface. The verifier never reads the body or
the diff, so this file must contain **no implementation specifics** — the driver encodes *intent*,
not the code's behaviour (a driver that mirrors the implementation is endogenous → coherent-and-wrong).
An entry that would leak the implementation is a barrier breach → REJECT.

**Entry format:**
```
### <title>
- Kind: ignore-signal | defer-to-oracle
- Gate S: PASS | CARVE-OUT
- Arose from: <file / gap-N>
- Heuristic: <rule>
- Carve-out: <exception → requirement clause>   (if any)
```

## Seed entries (PROVISIONAL — confirm via Gate S on first real use)

### Author the acceptance check as a FORMAL TEST: broad requires, property in the body, ensures \result==1
- Kind: defer-to-oracle
- Gate S: PROVISIONAL (seed)
- Arose from: the formal-test framing (frama-c/SKILL.md "A formal test")
- Heuristic: to validate a *functional* property without a brittle declarative `ensures`, write a
  **test driver** `int formal_test_f(<params>)` with: (1) the **broadest** `requires` the function
  supports (wider domain = stronger claim); (2) a body that calls `function_under_test(...)` and
  **checks the intended property operationally**, `return 0` (or any non-1) on any failure; (3)
  `ensures \result == 1`. WP proving `\result==1` over the broad domain = proving every failure
  branch unreachable = the property holds for *all* inputs (WP supplies the ∀). The simple
  postcondition is **correct by design, not vacuous** — the property lives in the body. Author it
  from the requirement / the English description, **never the code** (else the test mirrors the
  implementation = endogenous). Always pair with a mutation probe (next entries): a formal test
  whose `\result==1` still proves after `function_under_test` is mutated has no teeth → reject.

### The canonical mutation set: comparator flip, off-by-one, dropped guard, loosened bound
- Kind: defer-to-oracle
- Gate S: PROVISIONAL (seed)
- Arose from: seed (Gate C non-vacuity probe)
- Heuristic: to prove a contract has teeth, mutate the *source* (not the spec) in four ways
  and require some goal to turn RED: (1) flip a comparator (`<`↔`<=`, `==`↔`!=`); (2) drop a
  `+1`/`-1`; (3) delete a runtime bounds/zero check; (4) widen a guard (`> len` → `> len+K`).
  A mutant that still proves means the spec is vacuous or too weak — gap doc.

### A goal routed through an unspecified callee is vacuous — check the stub before trusting green
- Kind: ignore-signal
- Gate S: PROVISIONAL (seed)
- Arose from: seed (ported from lace `div_ceil` / `{false}`-block finding)
- Heuristic: when a function calls a callee with NO ACSL contract in scope, WP may model the
  callee's body as unreachable / `\false`, making every downstream goal over its result
  **vacuously Valid** — a green that proves nothing (the dominant coherent-and-wrong for
  safety). Before accepting an all-green unit, confirm no goal depends on an unspecified
  call: give the callee a real stub (or expand the call to primitive ops) and re-check the
  goal still proves. A goal that flips to `Unknown` once the call is specified was vacuous.

### Confirm the proof has teeth with a negative control on every unspecced closure/resolver
- Kind: defer-to-oracle
- Gate S: PROVISIONAL (seed)
- Arose from: seed (ported from lace `Rsdp::find_table` resolver negative-control)
- Heuristic: when robustness must hold for ANY behaviour of a caller-supplied function
  pointer / resolver returning an unconstrained buffer, model its result opaquely and prove
  every access via the code's OWN runtime guard. Then run a negative control: weaken the
  guard (`> len` → `> len+K`) and confirm the access goal goes RED. A unit that STAYS green
  when you break its guard is a rubber-stamp, not a proof.

### EVA "no alarm" never substitutes for a WP `Valid` (no-blend)
- Kind: ignore-signal
- Gate S: PROVISIONAL (seed)
- Arose from: seed (Gate C no-blend, two-oracle setup)
- Heuristic: **EVA is not used — not even to triage** (TCB-minimization; see `loops-design.md`
  §6.2 and `frama-c-monitoring` "No EVA"). Letting EVA discharge OR rank an obligation folds the
  whole abstract-interpretation engine into the TCB. Risk-ranking comes from the Phase-0
  architectural-audit attack-surface ranking, not an EVA sweep. Each obligation records *which*
  WP/SMT/Coq oracle closed it; a WP goal stays `Unknown` until WP proves it.

## Verified entries (Gate S — from the framac-monitoring small batch, run 1)

### A DEFINITIONAL `axiomatic` is NOT an escape hatch — carve-out to "no axiomatic"
- Kind: ignore-signal
- Gate S: CARVE-OUT
- Arose from: Nonmutating/count.c (small batch; the blanket "no axiomatic" rule over-reached)
- Heuristic: do NOT flag every `axiomatic`/`axiom` as a Gate B escape hatch. CARVE-OUT: an
  axiomatic that only DEFINES a recursive `logic`/`predicate` over a memory range (its
  base/step equations) is the standard, legitimate ACSL idiom (`count_occ`, `sorted`, …).
  Flag a Gate B HATCH only when an `axiom` asserts a *behavioral fact* about the program —
  i.e. it mentions the C function under verification or `\result`. The remaining risk of a
  definitional axiomatic is *inconsistency* (which proves everything); that is caught by the
  Gate C mutation probe, not by grep — see next entry. (Refers to [[learned-spec-author]].)

### Gate C mutation probe is the consistency/non-vacuity backstop — but generic mutations miss some shapes
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac-mutation-probe.sh over the small batch (clamp/swap)
- Heuristic: `framac-mutation-probe.sh` confirms a proof has teeth (a mutated body must break
  a goal) and thereby that any axiomatic is consistent. Limitation observed: its GENERIC
  mutations (`+`↔`-`, `++`→`--`, `<`→`<=`, `==`→`!=`) can be **behavior-preserving** (clamp's
  `<`→`<=` at the boundary → false `VACUOUS`) or **not apply at all** to a pure/store-only
  function (swap → `INCONCLUSIVE`). So treat `VACUOUS`/`INCONCLUSIVE` as **NEEDS-MANUAL**, never
  an auto-pass and never an auto-fail of a real proof: author ONE targeted mutation (swap a
  returned branch, change an assigned var) and confirm a goal goes RED. Verified clamp (10/11)
  and swap (9/10) this way.

### Mutation probe must mutate CODE, not ACSL; VACUOUS is never terminal
- Kind: ignore-signal
- Gate S: CARVE-OUT
- Arose from: Nonmutating/search.c (batch 3 — a false VACUOUS wrongly FAILED a genuine proof)
- Heuristic: two refinements to the Gate C probe, both load-bearing. (a) These units put loop
  invariants/asserts (`/*@..*/`, `//@..`) right BEFORE the code, so a "first occurrence in the
  file" mutation hits the SPEC, not the body — the proof still passes and you get a FALSE VACUOUS.
  The probe must mutate only OUTSIDE ACSL spans (search: first ` + ` was in the loop invariant).
  (b) A generic mutation set (+/-/<=/==) cannot break every correct spec — search's functional
  contract survived all generics yet a targeted `return i -> return i+1u` broke 4 goals (23/27).
  So treat probe VACUOUS/INCONCLUSIVE as **NEEDS-MANUAL**, NEVER terminal FAILED: author a targeted
  BODY mutation first. Only a postcondition trivially true for ANY execution is truly vacuous.

### Trivially-true postcondition is the real vacuous spec — relate \result to the defined predicate
- Kind: ignore-signal
- Gate S: PASS
- Arose from: Heap/is_heap.c (batch 3 — true Gate C catch)
- Heuristic: a bool-returning predicate-test whose ONLY postcondition is `ensures \result==0 ||
  \result==1` is vacuous — it holds for any return, so NO body mutation can break it and the proof
  is worthless. Tell-tale: the file DEFINES a `predicate` (e.g. `is_max_heap`) but the contract
  never USES it. The fix (a spec-author job) is `ensures \result != 0 <==> is_max_heap(a, n);`.
  When the functional half is omitted "because a callee has no contract", the honest verdict is
  PARTIAL/FAILED, not PROVED. (See [[learned-spec-author]].)

### Mutation TEETH proves NON-VACUITY of the written spec, NOT its COMPLETENESS (the sorting trap)
- Kind: ignore-signal
- Gate S: PASS
- Arose from: Sorting/{insertion,selection,bubble}_sort.c (batch 4 — passed all machine gates yet under-specified)
- Heuristic: all three Gate C signals (faithful + gateB CLEAN + mutation TEETH) can hold while the
  spec still omits the intended property. A sort whose only postcondition is `ensures Sorted(a,0,n)`
  passes every machine gate, yet a **zero-fill body satisfies it** (verified: 14/14) because
  sortedness alone does not require the output to be a permutation of the input. The mutation probe
  shows TEETH (mutating the code breaks the *sortedness* goal) but cannot tell that the spec is
  *incomplete*. So machine gates bound non-vacuity, NOT intended-property coverage — completeness is
  the editorial / gold-comparison check (Gate C's "the proved theorem is the intended one"), which no
  code mutation can supply. Watch for it on any rearrangement/aggregate where a trivial output
  (constant, zero, identity) could satisfy the written postcondition. Verdict for such a unit is
  PARTIAL ("RTE+property X proved; intended property Y unspecified"), never PROVED. (See
  [[learned-spec-author]] for the permutation-ensures requirement.)
### A law/determinism unit whose postcondition is preservation-only (no relation to the pre-state) is vacuous — demand a relation to \old/{Old} or a concrete divergent result
- Kind: ignore-signal
- Gate S: CARVE-OUT
- Arose from: framac/Stack/StackAxioms/* postconditions all relate \result to \old/{Old} (size==\old+1, ==v, StackEqual{Old,Here}) — none is preservation-only. The contrast stack_full_not_wd.c uses a concrete ensures \result == false; backed by requires StackCapacity(s) < StackCapacity(t). Generalizes batch-4 sorting-trap (TEETH != completeness) and the existing wrapper-overclaim entry to the law/determinism terrain (this batch). (capitalization, this batch)
- Heuristic: Watch for the vacuous-by-preservation spec on a unit whose job is to VERIFY A LAW or DETERMINISM by composing operations: a contract that ensures only that an equivalence/invariant is PRESERVED (ensures Inv(x); ensures Equiv{Here,Here}(s,t);) with no clause relating the post-state to the captured pre-state (\old/{Old}) can be silently satisfied by a body that never performs the operation under test (a no-op, or returning a constant). Preservation-only is the determinism analogue of the sorting trap: machine gates show TEETH on the surviving invariant goal yet the INTENDED law is unspecified. The non-vacuous shape requires one of: (a) a result/state relation to the pre-state, ensures \result == <function of \old(AbstractAccessor(x))>; or ensures Equiv{Old,Here}(x,x); for a round-trip identity (the {Old,Here} two-label form, NOT a single-label same-shape claim that any constant satisfies); or (b) for a deliberate-divergence case where two instances differ structurally, a concrete result value ensures \result == <false/the divergent value>; tied to the structural-inequality precondition. Targeted mutation to expose it: replace the composed operation with a no-op (or make the two operands' mutation a constant write) and confirm a goal goes RED; if everything stays green the law clause is missing. A unit with invariant-preservation + RTE-safety but no pre-state relation is PARTIAL, never PROVED. No implementation specifics.
- Carve-out: TWO-DISTINCT-OBJECT determinism / well-definedness pattern (the precondition constrains two SEPARATE objects equal+separated — e.g. requires StackEqual{Here,Here}(s,t); requires StackSeparated(s,t); — and the body applies the SAME operation to BOTH) → here the single-label ensures Equiv{Here,Here}(s,t) IS the gold-correct non-vacuous shape; do NOT demand a rewrite to {Old,Here} or a concrete value, and do NOT use the NO-OP mutation as the teeth probe (verified on framac/Stack/StackWellDefinedness/stack_pop_wd.c & stack_push_wd.c: a no-op body proves 5/5 by merely preserving the pre-equality, yet both are PROVED gold-verbatim). Establish teeth with the ASYMMETRIC mutation (perform the operation on only ONE operand: dropping stack_pop(t) flips ensures_equal to RED, 10/10→6/7 Timeout — verified) and establish completeness by gold-comparison. The "preservation-only is vacuous" rule still applies in full force to LAW/axiom units acting on a SINGLE object (StackAxioms, round-trips), where the post-state must relate to \old/{Old} or yield a concrete divergent \result.

### `-wp-model +cast` can SILENTLY VACUATE a proof — smoke-test every +cast discharge
- Kind: ignore-signal
- Gate S: REJECT (a +cast "N/N" without a passing smoke run is not a floor)
- Arose from: a struct-with-large-`char[]` unit whose whole tail collapsed to dead code under +cast, reported green
- Heuristic: `-wp-model +cast` (chosen for void*/uint8_t*/char* boundary casts) has a cast-frame soundness defect: a
  WHOLE-STRUCT `memset(&s, 0, sizeof(s))` where `s` contains a LARGE fixed `char[]` collapses the post-op memory state
  to `\false`, making every following statement DEAD CODE. WP then reports a green "N/N" that proves NOTHING — the
  recv/parse/use tail is `[Failed](Doomed)` only under `-wp-smoke-tests`. So a +cast discharge is UNTRUSTWORTHY without
  `-wp-smoke-tests`: demand `Smoke Tests: Y/Y` (all live) before trusting any count. DISCRIMINATE real vacuity from
  benign dead code: an `X<Y` smoke with `dead_code`/`dead_call` on a reachable TERMINATING statement is the vacuity
  REJECT — but cross-check against `-wp-model Typed` (sound): legit `exit`/noreturn dead-calls and stub-scoped-
  unreachable branches show the SAME dead set under Typed and are model-INDEPENDENT (NOT vacuity). Small buffers /
  `&p->data[0]` / brace-init `= {}` do NOT trigger it. Fix per-unit: move that unit to `-wp-model Typed` (or Bytes) and
  file the tool bug. For a store-bloat-walled unit that can't be smoke-run, trigger-pattern ABSENCE (no
  `memset(&struct,.,sizeof)` over a large char[]; the residue is TIMEOUT not dead_code) is a sound non-vacuity
  argument once one smoke-passing sibling validates the reasoning.

### macsl/WP full-TU parse wall is NOT terminal — extract a verbatim subset overlay + faithful stubs
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: an authorization gate in a TU that won't parse (framework headers absent, 70+ unresolved symbols)
- Heuristic: when the real TU won't parse (heavy framework/GObject/GDBus/GLib headers absent) so macsl/WP cannot
  instrument it in-situ, that is the full-TU wall — but `no_ceiling_gate` REJECTs treating it as a TERMINAL ceiling,
  because the lever exists: lift the target function BODY-VERBATIM into a new `units/<fn>.c` subset overlay with
  faithful stubs for its callees (`ensures`/`assigns` over-approximations; syscall FAILURE branch NOT modeled away —
  that is what keeps a non-vacuity attack able to flip). Drive the `\prop`/RTE on the real body there. Faithfulness =
  `strip(//@)` of the extracted body byte-identical to pristine (the stubs + header comment are scaffold, not claimed
  pristine — so a whole-file `strip==pristine` is the WRONG check; compare the extracted FUNCTION BODY). The witness is
  in-situ (the real body), not a driver abstraction. The `macsl.cmxs` must ABI-match the frama-c build — a stale module
  from another opam switch fails to load with an `undefined symbol` Dynlink error; read the working path from `verify.sh`.

### Whole-function store-bloat: the per-goal split does NOT help; the levers are preconditions + tight loop-assigns
- Kind: ignore-signal
- Gate S: PASS
- Arose from: two orchestration `main`s walling at partial counts; a per-goal-split lever that returned +0 proven
- Heuristic: when a whole-function proof walls with the store-bloat SIGNATURE (Qed CHEAP + Alt-Ergo "Stronger"
  TIMEOUT — NOT `dead_code`), the instinct to "split to one goal so it pays the frame cost once" FAILS empirically
  (+0 proven): a single-goal scope gives the SAME per-goal prover budget, and the bloated hypothesis CONTEXT is the
  wall, not VC generation. What actually raises the count: (1) a MISSING PRECONDITION the function never had (an
  argv/`\valid` contract — often the single biggest lever), and (2) a TIGHT `loop assigns` naming the loop's EXACT
  store footprint (bounds the havoc'd region so unrelated goals stay lean). THREE store-bloat roots that NO
  `loop assigns` can cure (→ status-3, file the reproducer): a fn-ptr call inside a loop (`\valid_function`
  unimplemented), an unspecced variadic call inside a loop, an un-boundable dynamic linked-ring mutation. Discriminate
  store-bloat (class-C, closeable-in-principle) from the fn-ptr/variadic status-3 by ISOLATION: a sibling WITHOUT the
  ring but WITH the fn-ptr still walls the fn-ptr goals → those are status-3, not the ring's class-C.
