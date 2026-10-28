# Learned knowledge — Spec author (framac-sl)

Append-only, Gate-S-gated requirement→ACSL patterns the **spec author** capitalized while
running the `framac-sl` loop (see `../../framac-sl/SKILL.md` §11). Each real entry passes an
`sl-monitoring-sl` Gate S audit by the disjoint monitor (the coordinator) and carries
provenance.

**Scope / barrier (load-bearing):** requirement-level mapping patterns ONLY — how a *kind*
of requirement becomes `requires`/`ensures`/`assigns`/`loop invariant`, stub idioms,
modelling idioms. The spec author never sees the body, so this file must contain **no
implementation specifics** (no magic constants, no off-by-one read off code). An entry that
would leak the implementation to this barriered role is a barrier breach → REJECT.

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

### Always pair a write with an `assigns`; default to the tightest footprint
- Kind: defer-to-oracle
- Gate S: PROVISIONAL (seed)
- Arose from: seed (ACSL frame rule)
- Heuristic: every function/loop that writes needs an `assigns` (and `loop assigns`) clause;
  omitting it makes WP assume it may write anything (unsound frame) or, with `\nothing`,
  drops a real effect (vacuous). State the *tightest* set the requirement allows
  (`a[0 .. n-1]`, not `a[0 .. ]`). A too-loose `assigns` is the dominant coherent-and-wrong
  for stateful functions.

### Robustness precondition guards an unsigned subtraction before it underflows
- Kind: defer-to-oracle
- Gate S: PROVISIONAL (seed)
- Arose from: seed (ported from lace `e_lfanew - 64` underflow)
- Heuristic: a `requires x >= K` before an `x - K` on an unsigned/size type is the ACSL
  clause that discharges the `-wp-rte` underflow goal. For an attack-surface unit do NOT
  add it as an assumption on the input — instead require the *code* to check it (`if (x < K)
  return Err;`); if no such check exists, the undischarged underflow goal IS the bug.

### Structural safety rests on a type invariant, never an input restriction
- Kind: defer-to-oracle
- Gate S: PROVISIONAL (seed)
- Arose from: seed (ported from lace `PeRef::nth_section` invariant idiom)
- Heuristic: when a method's in-bounds safety rests on a relationship between a struct's
  fields (e.g. `hdr.len == n * 40`), encode it as a `predicate inv(struct T *)` and require
  it (`requires inv(self)`); the *constructor* must then `ensures inv(\result)` — a real,
  Gate-C-legal obligation that constrains the type, not the adversarial input. This is the
  faithful way to verify a "this access cannot overflow because the type guarantees it".

### A stub `ensures` may never exceed the documented callee guarantee
- Kind: ignore-signal
- Gate S: PROVISIONAL (seed)
- Arose from: seed (ACSL external-function stubs)
- Heuristic: an ACSL stub for an out-of-scope callee is authored from the *documented
  surface* only; a stub `ensures` stronger than the real callee proves is an escape hatch
  (Gate B violation). When the callee is later brought in scope, its proven `ensures` must
  imply the stub or the stub is REJECTED.

## Verified entries (Gate S PASS — from the framac-monitoring small batch, run 1)

### Aggregate overflow: bound every partial result with a recursive `logic` + a range `requires`
- Kind: defer-to-oracle
- Gate S: PASS (mutation-probe TEETH confirms non-vacuity)
- Arose from: Numeric/accumulate.c (small batch)
- Heuristic: for a fold/aggregate (`init = init + a[i]`), the `-wp-rte` signed-overflow goal
  is discharged by (1) a recursive `logic integer agg{L}(...) = n<=0 ? init : agg(..,n-1) + a[n-1];`
  defining the partial result, and (2) a precondition bounding EVERY partial result:
  `requires \forall integer k; 0<=k<=n ==> VALUE_TYPE_MIN <= agg(a,init,k) <= VALUE_TYPE_MAX;`.
  Carry `init == agg(a,\at(init,Pre),i)` as the loop invariant. This is the correct robustness
  contract (a reasonable library precondition) — NOT a vacuous spec and NOT an escape hatch.
  (Supersedes the earlier guess that sum/accumulate would be an irreducible PARTIAL.)

### Recursive predicate over a memory range: define via a DEFINITIONAL `axiomatic`
- Kind: defer-to-oracle
- Gate S: PASS (mutation-probe TEETH confirms the axioms are consistent)
- Arose from: Nonmutating/count.c (small batch)
- Heuristic: a logic function that *reads an array range* (e.g. `count_occ(a,lo,hi,v)`) cannot
  always be written as a direct `logic ... = ...`; the standard ACSL idiom is an `axiomatic`
  block declaring `logic ... reads a[lo..hi-1];` plus base/step `axiom`s (empty / match /
  nomatch). This is FAITHFUL (strips clean) and SOUND when the axioms are purely definitional.
  It is NOT a Gate B escape hatch — see [[learned-verifier]] for the carve-out and the Gate C
  consistency backstop. Keep the axioms definitional only; never write an axiom mentioning the
  C function or `\result`.

### Index-returning function over a possibly-empty range: specify with complete+disjoint empty/nonempty behaviors
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/MinMax/min_element.h: top-level `0<=\result<=n` plus `behavior empty`/`behavior nonempty` with `complete behaviors; disjoint behaviors;`; consumed cleanly by selection_sort's proof. No implementation specifics. (capitalization, this batch)
- Heuristic: When a requirement is "return an index into a range that may be empty" (min/max element, find, lower/upper bound), do not cram both cases into one postcondition. Split into named behaviors: `behavior empty: assumes n == 0; ensures \result == 0;` and `behavior nonempty: assumes 0 < n; ensures 0 <= \result < n; ensures <the selection property over the range>;`, closed with `complete behaviors; disjoint behaviors;`. The complete+disjoint pair is the load-bearing part: it forces the contract to cover every input and forbids the silently-vacuous empty case, and it gives a caller two clean facts to case-split on. Keep the always-true range fact (`0 <= \result <= n`) as a top-level ensures so callers that don't case-split still get a bound.

### A rearrangement spec MUST ensure PERMUTATION, not just the target shape (sortedness is half a sort)
- Kind: ignore-signal
- Gate S: PASS
- Arose from: Sorting/{insertion,selection,bubble}_sort.c (batch 4 — sortedness-only specs accepted a zero-fill body)
- Heuristic: for any function that REARRANGES an array in place (sort, partition, rotate, reverse, make_heap), `ensures Sorted(a,0,n)` (or the analogous target-shape predicate) is only HALF the contract and is silently satisfied by overwriting the array with a constant (a zero-fill body proves a sortedness-only sort spec — verified 14/14). You MUST also ensure the output is a **permutation / multiset** of the input: define a `predicate Permutation{L1,L2}(value_type* a, integer n)` (equal multiset across the two labels, e.g. via a `count_occ`-style logic) and add `ensures MultisetUnchanged{Pre,Here}(a, n);`. A sort with RTE-safety + sortedness but no permutation is **PARTIAL, not PROVED** — the machine gates cannot catch the omission (see [[learned-verifier]] "the sorting trap"); only this clause makes the proved theorem the intended one. `insertion_sort` had NO functional ensures at all (RTE-only): also PARTIAL.

### Rearrangement-as-composition: split the postcondition into one mapped `\forall` per output segment
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Mutating/rotate_copy.h: `requires p <= n;` plus two segmented `\forall` ensures over `0..n-p-1` and `n-p..n-1`. framac/Mutating/replace_copy.h: per-element conditional map ensures with `\old`. Both PROVED, gateB clean, gateC teeth. (capitalization, this batch) (capitalization, this batch)
- Heuristic: When a requirement rearranges/maps a range into distinct CONTIGUOUS output segments (rotate, partition into two halves, concatenate transforms), do not write one tangled postcondition. Emit one mapped universal per segment, each tying that output slice to its source by an explicit index map: `ensures \forall integer k; 0 <= k < L1 ==> b[k] == a[off1 + k];` and `ensures \forall integer k; 0 <= k < L2 ==> b[base2 + k] == a[off2 + k];`. Add the structural precondition that makes the split well-formed and keeps every subtraction in range (e.g. `requires p <= n` before any `n - p`). This shape lets WP discharge each segment independently and, when the body is itself a composition of sub-operations, lets each callee's proven postcondition cover exactly one `\forall`. Per-element conditional maps follow the same rule with `\old`: `ensures \forall integer k; ... ==> b[k] == (\old(a[k]) == v ? w : \old(a[k]));`. No implementation specifics: this is purely the requirement-to-segmented-ensures mapping.

### Value-partition over a sorted input: specify with three contiguous comparison-class `\forall` segments plus a nesting bound, not a positional map
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/BinarySearch/equal_range.h defines predicate sorted_er, requires sorted_er(a,n), and ensures the nesting bound 0<=\result.first<=\result.second<=n plus the three comparison-class \forall segments (a[k]<v, a[k]==v, a[k]>v). PROVED. (capitalization, this batch)
- Heuristic: When a requirement classifies the elements of a SORTED range by their comparison to a query value (equal-range, partition-point on an ordered predicate, lower/upper-bound pair), the postcondition is a THREE-WAY value partition, distinct from the positional segment-map idiom: require `sorted(a,n)` as a predicate up front, then emit one `\forall` per comparison class over a contiguous index window — `ensures \forall integer k; 0 <= k < lo ==> a[k] < v;`, `ensures \forall integer k; lo <= k < hi ==> a[k] == v;`, `ensures \forall integer k; hi <= k < n ==> a[k] > v;` — and tie the boundaries together with a single nesting bound `ensures 0 <= lo <= hi <= n;`. The nesting bound is load-bearing: it is what forbids the silently-vacuous answer (e.g. lo==hi collapsing the equal segment, or returning the whole range) and lets a caller case-split cleanly. Define `sorted` once as a reusable `predicate sorted(a,n) = \forall integer i,j; 0<=i<=j<n ==> a[i]<=a[j];`. This differs from the rotate_copy positional-segment rule: there each segment is `b[k]==a[map(k)]` (a data map); here each segment is a `<`/`==`/`>` comparison class against v, sound only because the input is sorted. No implementation specifics: this is purely requirement->ACSL for 'classify a sorted range by comparison to a key'.

### Mutating op with a no-op input class: split into complete+disjoint trivial / effective behaviors, with the trivial case ensuring identity
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Mutating/rotate.h declares behavior trivial (assumes p==0||p>=n; ensures a[k]==\old(a[k])) and behavior rotated (assumes 0<p<n; ensures the two positional maps), with complete behaviors; disjoint behaviors; and a top-level ensures \result==n-p. PROVED, gateB clean, gateC teeth. (capitalization, this batch)
- Heuristic: When a rearranging/mutating function has an input region where it must do NOTHING (rotate by 0 or by the full length, reverse of length<=1, a shift by 0), do not fold the no-op case into the general functional postcondition. Specify TWO named behaviors closed with `complete behaviors; disjoint behaviors;`: `behavior trivial: assumes <degenerate guard>; ensures \forall integer k; 0<=k<n ==> a[k]==\old(a[k]);` (the array is UNCHANGED — required, otherwise the spec is silently satisfied by any output on the degenerate input) and `behavior effective: assumes <non-degenerate guard>; ensures <the functional rearrangement clauses>;`. Keep input-independent facts (the `\result` value, `assigns a[0..n-1]`) as top-level clauses outside the behaviors. The complete+disjoint pair is the teeth: completeness forces the degenerate input to be covered (so it cannot be quietly dropped) and disjointness forces the two guards to partition the inputs exactly. This mirrors the empty/nonempty index-return rule but for a MUTATION, where the trivial case's obligation is an explicit identity-on-the-array ensures, not merely a result value. No implementation specifics.

### A boolean structural-equality query specifies as a single `<==>` biconditional, with read-validity required only over the COMPARED extent
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Stack/stack_equal.h: `ensures \result != 0 <==> (s->sz==t->sz && \forall integer k; 0<=k<s->sz ==> s->data[k]==t->data[k])` with `\valid_read` required only to `sz-1` (not cap-1); framac/Nonmutating/equal.h has the same `\result != 0 <==> \forall ... ` shape. Both PROVED, gateB clean, gateC teeth. (capitalization, this batch) (capitalization, this batch)
- Heuristic: When a requirement is 'return whether two structures/ranges are equal' (sequence equal, struct equal, multiset equal), specify the result as ONE biconditional rather than two implications or a bare result-bound: `ensures \result != 0 <==> (<size/shape agreement> && \forall integer k; 0 <= k < len ==> elem_a(k) == elem_b(k));`. The `<==>` is load-bearing: a one-directional `==>` is silently satisfied by always-returning-false (or always-true), the classic vacuous boolean-query spec (confirmed on frama-c 32.1: a `==>` spec is PROVED by a `return 0;` body, the `<==>` spec FAILS it); the biconditional forces \result to track equality in BOTH directions and gives the mutation probe teeth. Require read-validity (`\valid_read`) only over the extent actually COMPARED (the logical length being equated), not over any larger allocated capacity — over-requiring validity on cells the contract never reads is an unnecessary precondition that weakens callers. Pair the size/shape conjunct with the elementwise `\forall` when the operands can differ in length (e.g. s->sz vs t->sz); omit it only when a single shared length parameter n is passed (equal.h) — either the length agreement or the elementwise `\forall` alone is half the predicate. No implementation specifics: this is purely 'equality query -> biconditional + compared-extent validity'.

### A defensive accessor with a fallback branch needs preconditions that validate EVERY branch's access, plus a per-case split postcondition
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Stack/stack_top.h requires `\valid_read(s->data + (0..s->cap-1))` and `s->cap >= 1` (so the empty-case `data[0]` read is valid) and splits the postcondition `s->sz != 0 ==> \result==data[sz-1]` / `s->sz == 0 ==> \result==data[0]`; the body framac/Stack/stack_top.c has the matching empty-fallback else branch. PROVED, gateB clean, gateC teeth. (capitalization, this batch)
- Heuristic: When a requirement is 'read/return an element, with a defined fallback on the degenerate (empty/out-of-range) input' — and the implementation is expected to have a fallback branch rather than a precondition forbidding the degenerate case — the precondition must make the FALLBACK access valid too, not just the normal one. Require read-validity over the full extent any branch may touch (e.g. validity of the slot the fallback reads) AND any structural minimum the fallback relies on (e.g. capacity >= 1 so the fallback slot exists). Then split the postcondition by the same case guard, one `ensures` per branch under an `==>` guard: `ensures <degenerate guard> ==> \result == <fallback value>;` and `ensures <normal guard> ==> \result == <normal value>;`. This differs from the empty/nonempty index-return behaviors idiom: there the empty case returns a fixed sentinel and uses named complete+disjoint behaviors; here the accessor still performs a real (defended) memory read in the degenerate case, so the load-bearing part is the validity precondition covering that fallback read — omit it and the `-wp-rte` mem-access goal on the fallback branch is undischargeable. No implementation specifics: this is 'defensive accessor with fallback -> validate-all-branches precondition + guarded per-case ensures'.

### Stateful container operation: specify via a TWO-LABEL relational predicate over (pre,post) plus a type-invariant-preserving requires/ensures pair, split into complete+disjoint capacity behaviors
- Kind: defer-to-oracle
- Gate S: CARVE-OUT
- Arose from: framac/Stack/stack_push.h, stack_pop.h, stack_init.h define StackData{S}/StackCapacity{S}/StackSize{S}, Equal{K,L}, StackInvariant (with the `\separated(s, data+(0..cap-1))` conjunct), StackValid, StackPrefix/StackEqual, and relational StackPush{S,T}/StackPop{S,T}; contracts use `requires StackValid(s); ensures StackValid(s);` with complete+disjoint full/not_full (push) and empty/not_empty (pop) behaviors whose degenerate case ensures `StackEqual{Old,Here}(s,s)`. All PROVED, gateB clean, gateC teeth. (capitalization, this batch) (capitalization, this batch)
- Heuristic: When a requirement mutates an opaque stateful object in place (push/pop/insert/clear/append on a stack, queue, ring buffer, set), do NOT phrase the postcondition as raw field equalities. Define the abstract state with labelled logic accessors `logic ... Size{S}(T*)`, `... Capacity{S}(T*)`, `... Data{S}(T*)` and a single type-invariant `predicate Inv{L}(T* x) = 0 < Capacity(x) && 0 <= Size(x) <= Capacity(x) && \valid(Data(x)+(0..Capacity(x)-1)) && \separated(x, Data(x)+(0..Capacity(x)-1));` (the \separated conjunct between the handle and its backing store is a structural well-formedness fact — handle and payload must not overlap — and is load-bearing for invariant preservation in WP's raw/Bytes memory model). Then `requires Inv(s); ensures Inv(s);` makes invariant-preservation an explicit obligation. Express the functional effect as a TWO-LABEL relational predicate `predicate Op{S,T}(T* pre, args, T* post) = <new size relates to old> && <capacity unchanged> && Prefix{S,T}(pre,post);` built from a reusable `Equal{K,L}` elementwise-over-a-range predicate, and ensure it as `ensures Op{Old,Here}(s, args, s);`. Cover the capacity edge with named `complete behaviors; disjoint behaviors;`: a degenerate behavior (full/empty) `assumes <guard>; assigns \nothing; ensures Equal{Old,Here}(s,s);` (the object is UNCHANGED — required, else the degenerate case exports no caller-visible fact) and an effective behavior with the relational ensures. Keep `assigns` to the tightest field set per behavior. This is the in-place-mutation analogue of the empty/nonempty index-return idiom, lifted to a stateful object whose correctness is a (pre,post) relation rather than a value. No implementation specifics: purely 'mutating container op -> labelled abstract state + invariant-preservation + two-label relational ensures + complete/disjoint capacity split'.
- Carve-out: the parenthetical claim that \separated is load-bearing "because WP cannot know a field write does not alias the payload" -> DEFER to the oracle/memory model: this is FALSE for WP's default Typed memory model (a write to a struct scalar field does not threaten `\valid(Data(x)+(0..))` even without the conjunct — verified by removing it and still proving), so do not justify the conjunct by that mechanism; keep \separated in the invariant as a structural well-formedness fact and confirm its load-bearingness per `-wp-model` (raw/Bytes) via WP rather than asserting it categorically.
### An algebraic-law unit (verifying op-composition identities) specifies the law as a \result/state relation to {Old}, never a standalone postcondition
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Stack/StackAxioms/axiom_size_of_push.c: ensures \result == \old(StackSize(s)) + 1; axiom_size_of_pop.c uses StackSize{Old}(s) - 1; axiom_top_of_push.c: ensures \result == v; axiom_pop_of_push.c: ensures StackEqual{Old,Here}(s,s); axiom_capacity_of_push.c: ensures \result == \old(StackCapacity(s)); axiom_size_of_init.c: ensures \result == 0 plus StackValid(s). All carry requires StackValid(s); ensures StackValid(s); and the operation's domain guard (!StackFull). All PROVED, gateB clean, gateC teeth (this batch). (capitalization, this batch)
- Heuristic: When a requirement is to VERIFY AN ALGEBRAIC LAW relating composed operations on an abstract data type (size-of-push = size+1, top-of-push = the pushed value, pop-of-push = identity, capacity-of-push = capacity-unchanged, size-of-init = 0), do not invent a fresh functional spec for the composite. The wrapper's body composes already-specified operations, so the contract is purely the LAW, phrased as a relation between \result (or the post-state) and the pre-state captured with \old(...) / a {Old} label: ensures \result == \old(AbstractAccessor(x)) + 1; (size-of-push), ensures \result == v; (top-of-push), ensures AbstractEqual{Old,Here}(x,x); (pop-of-push round-trip = identity), ensures \result == \old(AbstractCapacity(x)); (capacity invariance). Always pair the law with requires Inv(x); ensures Inv(x); (the type invariant must survive the composition) and the same domain guard the underlying operation needs (e.g. requires !Full(x) before a push-then-read law). The {Old}/\old relation is load-bearing: a law ensure that does NOT mention the pre-state (e.g. just ensures \result == 0 with no \old) is satisfiable by a body that ignores the operation, and a round-trip law MUST use the two-label relational equality AbstractEqual{Old,Here} rather than a bare same-shape claim, or a constant/no-op body proves it. This is distinct from the operation-implementation spec idiom (which states what one mutator does to the state); here the spec states an EQUATION between accessor outputs of a composition, and the underlying ops' proven contracts carry it. No implementation specifics.
### A determinism/well-definedness unit operating on TWO independent instances needs a mutual-separation precondition over both handles and both backing stores
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Stack/StackWellDefinedness/stack_pop_wd.c and stack_push_wd.c both declare predicate StackSeparated(s,t) = \separated(s, s->data+(0..s->cap-1), t, t->data+(0..t->cap-1)); require it plus StackValid(s)&&StackValid(t) and StackEqual{Here,Here}(s,t), and ensure both preserved. stack_full_not_wd.c instead requires StackCapacity(s) < StackCapacity(t) and ensures \result == false. All PROVED, gateB clean, gateC teeth (this batch). (capitalization, this batch)
- Heuristic: When a requirement is 'the operation behaves identically / preserves an equivalence on two separate instances of a stateful object' (well-definedness, determinism, congruence: f(s)≡f(t) when s≡t), and the body mutates BOTH operands, the contract needs a MUTUAL-SEPARATION precondition in addition to each instance's own type invariant: define predicate Separated(T* s, T* t) = \separated(s, Data(s)+(0..Cap(s)-1), t, t->Data+(0..Cap(t)-1)); and require it. It is load-bearing because WP cannot otherwise prove that the second instance's mutation does not alter the first (and so cannot preserve the s≡t equivalence across the two writes); omit it and the post-equivalence goal stays Unknown. Pair it with: requires Inv(s) && Inv(t); requires Equiv{Here,Here}(s,t); ensures Inv(s) && Inv(t); ensures Equiv{Here,Here}(s,t); and the tightest per-instance assigns naming only the mutated fields of both objects. For a degenerate-divergence law (the two instances are deliberately UNequal on a structural attribute and the operation must return false/diverge), the postcondition is instead a concrete result value (ensures \result == false;) backed by the structural inequality requires; do not phrase that case as an equivalence-preservation. No implementation specifics: this is purely 'two-instance determinism/congruence -> per-instance invariant + a mutual \separated over both handles+stores + equivalence-in/equivalence-out'.
