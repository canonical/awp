# Learned knowledge — Annotator (framac-sl)

Append-only, Gate-S-gated proof-scaffolding patterns the **annotator** capitalized while
running the `framac-sl` loop (see `../../framac-sl/SKILL.md` §11). Each real entry passes an
`sl-monitoring-sl` Gate S audit by a disjoint monitor (the coordinator) and carries
provenance.

**Scope / barrier:** proof-scaffolding *patterns* that make WP discharge — loop-invariant
templates per loop shape, ghost idioms, `loop variant` choices, intermediate `//@ assert`
placements, prover/timeout tips. **Generalize to a pattern — never a verbatim copy of one
program**, and never weaken a contract or record an escape hatch (`Admitted`, an axiom, a
trusted stub) as a "fix". Future runs load this file at delegation time.

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

### Counting-loop invariant template: bound + property-so-far + `loop assigns` + variant
- Kind: defer-to-oracle
- Gate S: PROVISIONAL (seed)
- Arose from: seed (pilot abs / standard WP loop idiom)
- Heuristic: for `for (i = 0; i < n; i++)`, the discharging quartet is
  `loop invariant 0 <= i <= n;` (the index bound), `loop invariant <property holds for
  0..i>;` (the accumulated fact), `loop assigns i, <written cells>;` (the frame — REQUIRED,
  WP cannot frame the loop without it), and `loop variant n - i;` (termination). Missing
  `loop assigns` is the most common reason an otherwise-correct invariant fails to close.

### A raw `base + i*stride` index needs the table-fits invariant + a mul-monotonicity assert
- Kind: defer-to-oracle
- Gate S: PROVISIONAL (seed)
- Arose from: seed (ported from lace elf64 `for_each_phdr`)
- Heuristic: a loop walking `off = base + i*stride` (no checked op, `i` in `0..n`) discharges
  its bounds goal from (1) a loop invariant `base + i*stride <= len` carried from a pre-loop
  "table fits" fact, and (2) an explicit `//@ assert i*stride <= n*stride;` — SMT solvers do
  NOT derive monotonic multiply automatically, so state it (prove it as a `lemma
  mul_mono` if reused). Do not reach for a guard the code does not have.

### Pin `-machdep` before trusting any overflow goal
- Kind: ignore-signal
- Gate S: PROVISIONAL (seed)
- Arose from: seed (Frama-C invocation)
- Heuristic: signed/unsigned overflow RTE goals depend on integer widths, which come from
  `-machdep` (e.g. `gcc_x86_64`). Running WP without a fixed `-machdep` (or changing it
  between the local run and the verifier re-run) can flip a goal between `Valid` and
  `Unknown` and breaks the determinism re-run. Always pass an explicit `-machdep`.

### `//@ check` vs `//@ assert`: use `check` for a diagnostic that is NOT a hypothesis
- Kind: defer-to-oracle
- Gate S: PROVISIONAL (seed)
- Arose from: seed (ACSL semantics)
- Heuristic: `//@ assert P;` is proved AND then assumed downstream; `//@ check P;` is proved
  but NOT added as a hypothesis. When probing *why* a later goal fails, insert a `check` so
  the experiment cannot accidentally strengthen the context and mask the real gap. Both
  strip clean (annotation-only), so they are faithful additions.

### Adding `#include` or editing a `#define` to make WP parse is a FABRICATION — do not
- Kind: ignore-signal
- Gate S: PROVISIONAL (seed)
- Arose from: seed (ported from the Creusot `use`-fabrication carve-out)
- Heuristic: if WP fails to parse for want of a macro/type, the fix is a *preprocessing
  flag* (`-I`/`-D` in the unit's queue entry), NEVER an added `#include`/`#define` in the
  source — the faithfulness gate strips only ACSL comments, so any added C token counts as
  altering executable code and `bin/framac-monitor-check.sh` flags FABRICATED. A unit that
  cannot preprocess from its flags is a `gap` (fix the queue), not a proof failure.

### Sort-loop invariant needs the cross-boundary partition fact, not just prefix-sortedness
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Sorting/selection_sort.c invariants `sorted: Sorted(a,0,i)` + `part: \forall p,q; 0<=p<i<=q<n ==> a[p]<=a[q]`; framac/Sorting/bubble_sort.c carries the dual partition invariants over `n-i+1..n-1` and `0..n-i+1`. Both PROVED (gateB clean, gateC teeth). (capitalization, this batch)
- Heuristic: For an in-place selection/bubble-style sort whose outer loop grows a sorted region, the discharging invariant set is a PAIR, not just internal sortedness: (1) Sorted(a, 0, i) (the grown region is internally ordered) AND (2) the cross-boundary partition fact `\forall integer p,q; 0 <= p < i <= q < n ==> a[p] <= a[q]` (every settled element dominates-below every unsettled one). WP cannot re-derive (1)'s preservation across an iteration from (1) alone — placing the next element into the prefix is only sorted-preserving because of (2). For a bubble pass that settles the suffix instead, mirror it as the two regions `0..n-i` and `n-i+1..n-1` with the same boundary-crossing `<=`. Always pair this with `loop assigns i, a[0..n-1]` (full array footprint) and `loop variant n - i`.

### Filter/compaction loop: carry the lagging write-index bound `0<=k<=i` as a separate invariant
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Mutating/remove_copy.c uses `0<=i<=n` + `0<=k<=i` + `\forall j; 0<=j<k ==> b[j]!=v` + `loop assigns i,k,b[0..n-1]`; mirrors reverse_copy.c's positional-map invariant `b[k]==a[n-1-k]`. PROVED, gateC teeth. (capitalization, this batch)
- Heuristic: Generalizes the counting-loop seed to a two-cursor compaction (`if (pred(a[i])) b[k++] = a[i];`): the read cursor `i` and the write cursor `k` advance at different rates, so WP needs BOTH `loop invariant 0 <= i <= n;` (read bound) AND a distinct `loop invariant 0 <= k <= i;` (write cursor never outruns the read cursor) to discharge `\valid(b + k)` on the store. Add the accumulated-property invariant over the WRITTEN prefix only (`\forall integer j; 0 <= j < k ==> P(b[j])`), and frame with `loop assigns i, k, b[0 .. n-1];` covering the whole output footprint (k's reachable max is n, not the current k).

### Descending counting-loop: phrase the invariant over the UNPROCESSED suffix and use `i` (not `n-i`) as the variant
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Mutating/copy_backward.c: `for (size_type i = n; i > 0u; --i) { b[i-1u]=a[i-1u]; }` with `loop invariant \forall integer k; i <= k < n ==> b[k]==a[k];` and `loop variant i;`. PROVED, gateB clean, gateC teeth. (capitalization, this batch) (capitalization, this batch)
- Heuristic: The counting-loop quartet seed assumes an ascending `for(i=0;i<n;++i)`. For a DESCENDING loop `for(i=n; i>0; --i){ b[i-1]=...; }` the discharging set inverts: keep `loop invariant 0 <= i <= n;` but state the accumulated fact over the SUFFIX already written, `loop invariant \forall integer k; i <= k < n ==> P(b[k]);` (NOT `0..i`), and use `loop variant i;` directly — the counter itself decreases to 0, so `n - i` is wrong here (it increases as i falls and fails the variant-decrease goal). Frame as usual with `loop assigns i, b[0 .. n-1];` over the whole footprint even though each iteration touches one cell. Tell-tale that you are in this case: the loop body indexes with `i-1`/`i-1u` and the guard is `i > 0`.

### In-place dual-array mutation: use `\at(x,Pre)` quadrant invariants (processed×unprocessed × both arrays), never `\old` inside the loop
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Mutating/swap_ranges.c carries all four `\at(...,Pre)` invariants over `0..i` and `i..n` for both `a` and `b`; header uses `\old`. framac/Mutating/swap_ranges.h. PROVED, gateB clean, gateC teeth. (capitalization, this batch) (capitalization, this batch)
- Heuristic: When a loop mutates two (or more) ranges in place — e.g. element-wise swap `for(i){ swap(a+i,b+i); }` — a single property-so-far invariant is insufficient and `\old(...)` is NOT usable inside a loop annotation. The discharging set is FOUR invariants partitioning by processed-vs-unprocessed × each array, all anchored to the `Pre` label: `\forall k; 0<=k<i ==> a[k]==\at(b[k],Pre);` and `... b[k]==\at(a[k],Pre);` (the two settled/crossed prefixes) PLUS `\forall k; i<=k<n ==> a[k]==\at(a[k],Pre);` and `... b[k]==\at(b[k],Pre);` (the two still-pristine suffixes — REQUIRED, WP cannot otherwise know the untouched tail still matches Pre). Frame with `loop assigns i, a[0..n-1], b[0..n-1];`. The header uses `\old`, but the loop body must use `\at(...,Pre)` for the same facts.

### A universally-quantified 'no earlier occurrence' postcondition needs a definitional predicate + an inductive-extension lemma + in-loop witness asserts
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Nonmutating/search_n.h: `predicate all_equal_v`, `predicate no_run_upto`, `lemma extend_no_run`, `lemma not_all_equal_witness`. framac/Nonmutating/search_n.c carries `no_run_upto(a, i-p, p, v)` invariant plus `witness:`/`point:` asserts under `(integer)i+1-p >= 0 ==>` guards. PROVED, gateB clean, gateC teeth. (capitalization, this batch) (capitalization, this batch)
- Heuristic: When the postcondition is 'for ALL earlier positions, property P fails' (no earlier run, no earlier match-window, first-of-kind), the prefix invariant alone rarely discharges it because WP cannot induct over the quantifier. The discharging scaffold is: (1) a `predicate P_window(a, s, ...)` for the local property and a `predicate none_upto(a, m, ...) = \forall s; 0<=s<=m ==> !P_window(a,s,...);` for the accumulated negative fact; (2) a `lemma extend(...): none_upto(a,m,...) && !P_window(a,m+1,...) ==> none_upto(a,m+1,...);` so WP can step the universal forward by one; (3) carry `none_upto(a, i - window, ...)` as a loop invariant; (4) at the branch that advances the run/window, place a `//@ assert` (often a `witness:` assert naming the concrete failing position, e.g. `a[start-1] != v`) that proves `!P_window(a, i+1-window, ...)` so the lemma's hypothesis is in context. The witness asserts under a `... >= 0 ==>` guard avoid underflow on the integer index expression.

### Composition of in-place mutations: bridge each callee call with positional `\at(...,Pre)` asserts naming the running permutation
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Mutating/rotate.c implements rotate via reverse(a,p); reverse(a+p,n-p); reverse(a,n); and carries six intermediate asserts (s1,s1b,s2,s2b,s2lo,s2hi) all anchored to \at(...,Pre) partitioning indices into 0..p-1 / p..n-1 and 0..n-p-1 / n-p..n-1; rotate.h's behavior 'rotated' ensures a[k]==\old(a[k+p]) etc. PROVED, gateB clean, gateC teeth. (capitalization, this batch)
- Heuristic: When a mutating function is implemented as a SEQUENCE of in-place sub-operation calls (rotate-as-three-reverses, partition-then-merge, block-swap chains) and the final postcondition is a positional map back to `\old`/`\at(...,Pre)`, WP usually cannot chain the callees' contracts across the intermediate states on its own. The discharging scaffold is a CHAIN of `//@ assert` statements placed BETWEEN consecutive calls, each one (a) anchored to the `Pre` label via `\at(a[expr], Pre)` (NOT `\old`, which is illegal mid-body), and (b) partitioned over the same processed-vs-untouched index regions the callee just rewrote: e.g. `//@ assert \forall integer i; 0<=i<L ==> a[i]==\at(a[map(i)],Pre);` for the slice the last call touched PLUS a companion `... ==> a[i]==\at(a[i],Pre);` asserting the still-pristine remainder is unchanged. Each assert restates the just-finished callee's effect as a concrete index-to-source map so the NEXT call's precondition/postcondition can be matched against it; the final positional postcondition then follows by transitivity. Tell-tale you are in this case: a short body that is only calls to other proven mutators, a postcondition phrased as `a[k]==\old(a[f(k)])`, and WP leaving the function-level ensures `Unknown` despite every callee being green. Pair with the existing dual-array `\at(...,Pre)` quadrant rule when more than one range is in play.

### A pure delegating wrapper needs NO loop/ghost scaffolding — the only requirement is the callee contract in scope
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Nonmutating/find4.c is `return find3(a,n,v);` with an identical contract to framac/Nonmutating/find3.h; framac/Stack/stack_empty.c is `return stack_size(s)==0u;` riding framac/Stack/stack_size.h's `ensures \result==s->sz`; framac/Stack/stack_full.c, stack_capacity.c similar. All PROVED, gateB clean, gateC teeth, with zero loop/ghost annotations in the body. (capitalization, this batch) (capitalization, this batch)
- Heuristic: When the body is a one-line forward to another function (`return g(args);`) or a direct struct-field read, do NOT reach for loop invariants, ghost state, or intermediate asserts — there is no loop and no state to track. WP discharges the wrapper's `ensures` purely by instantiating the callee's proven `ensures` at the call site, so the entire annotator job is ensuring the callee's contract is VISIBLE to WP (its header `#include`d, contract parsed) and that the wrapper's postcondition is implied by the callee's. Tell-tale: a body of one `return` whose RHS is a single call or a single `s->field`. If such a wrapper's goal stays `Unknown`, the cause is almost always a callee whose contract is out of scope (WP then models the call with a default generated spec — assigns-everything, no functional ensures — so the postcondition cannot be discharged) — fix the include/queue, never add scaffolding. This is the no-op end of the counting-loop/ghost-idiom spectrum: recognize it and stop.

### An extremum/argmax counting loop needs a BOUND invariant on the running result variable itself, plus a dual dominance pair
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/MinMax/max_element2.c carries `loop invariant max < n;`, `loop invariant \forall integer k; 0<=k<i ==> a[k] <= a[max];`, `loop invariant \forall integer k; 0<=k<max ==> a[k] < a[max];`, `loop assigns i, max;`, `loop variant n - i;`; header ensures the dual non-strict/strict selection postconditions. PROVED, gateB clean, gateC teeth. (capitalization, this batch) (capitalization, this batch)
- Heuristic: When a for(i=0;i<n;i++) loop maintains a running index/value answer r in a separate variable updated by `if (better(a[i], a[r])) r = i;` (max-element, min-element, argmax, running-best), the counting-loop quartet is not enough: WP also needs an explicit `loop invariant r < n;` (or `0 <= r < n;`) because the body indexes a[r] every iteration and WP cannot otherwise re-establish valid_read(a+r) on the comparison. Pair it with TWO accumulated facts, not one: a non-strict dominance over the scanned prefix `\forall integer k; 0<=k<i ==> a[k] <= a[r];` (every seen element is dominated by the current best) AND a strict dominance over the prefix strictly before the best `\forall integer k; 0<=k<r ==> a[k] < a[r];` (the best is the FIRST such extremum, which pins a unique returned index and gives the selection postcondition teeth). Frame with `loop assigns i, r;` and `loop variant n - i;`. Tell-tale: a scalar result variable conditionally reassigned to the loop index inside the body.

### An identity / no-op mutation loop proves UNCHANGED via a WHOLE-RANGE (0..n) Pre-equality invariant, not a 0..i prefix invariant
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Mutating/rewrite_array_nothing.c and rewrite_array_unchanged.c are both `for(i=0;i<n;i++){ a[i]=a[i]; }` carrying `loop invariant \forall integer k; 0<=k<n ==> a[k]==\at(a[k],Pre);` with `loop assigns i, a[0..n-1];`; the header ensures `\forall integer k; 0<=k<n ==> a[k]==\old(a[k]);`. PROVED, gateB clean, gateC teeth. (capitalization, this batch) (capitalization, this batch)
- Heuristic: When a loop's net effect is that the array is unchanged (self-assign a[i]=a[i]; or a per-element transform that is provably identity) yet the header still declares `assigns a[0..n-1]`, the discharging invariant is NOT the usual prefix property over 0..i. Carry `loop invariant \forall integer k; 0 <= k < n ==> a[k] == \at(a[k], Pre);` over the FULL range 0..n for the WHOLE loop, anchored to the Pre label (not \old, which is illegal mid-body). This is sound because each iteration writes a[i] back to its own current value, so the global Pre-equality is preserved at every step; a 0..i prefix invariant would fail to discharge the function-level `ensures a[k]==\old(a[k])` for the untouched tail. Keep the standard `loop invariant 0<=i<=n;`, `loop assigns i, a[0..n-1];` (the declared footprint, even though the net change is nil), and `loop variant n-i;`. Tell-tale: the postcondition asserts the array equals its \old value across the entire range while assigns still names the array.

### Give an internal static helper its OWN full contract so the public function's postcondition discharges modularly
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Mutating/random_number.c gives static `my_lrand48` its own contract (`requires \valid(seed+(0..2)); assigns seed[0..2]; ensures 0 <= \result < 2147483648;`) and `random_number` is `return my_lrand48(state) % n;`; header random_number.h requires n>0 and ensures 0<=\result<n, discharged from the helper's range ensures. PROVED, gateB clean, gateC teeth. (capitalization, this batch)
- Heuristic: When a public function's body is a thin expression over a call to a file-local `static` helper (e.g. `return helper(state) % n;`), do not try to verify the public postcondition by inlining/unfolding the helper's body through WP. Author a standalone contract on the static helper itself (requires/assigns/ensures, e.g. a result-range ensures `0 <= \result < BOUND;`), exactly as you would for an exported function. WP then discharges the caller's postcondition modularly from the helper's ensures at the call site, and a result-range bound on the helper combined with a `% n` (under `requires n > 0`) yields the public `0 <= \result < n` cleanly. This keeps each function's proof local and avoids the helper's (often bit-twiddling / non-linear) body bloating the caller's VC. Tell-tale: a one-line public body whose only nontrivial term is a call to a static function defined in the same translation unit.

### Contracting-interval (binary-search) loop: carry a TWO-SIDED settled invariant on the shrinking endpoints, with variant = high - low
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/BinarySearch/equal_range2.c: invariants bounds `0<=first<=last<=n`, midb `middle<=n`, left `StrictUpperBound_er(a,0,first,v)`, right `StrictLowerBound_er(a,last,n,v)`, `loop assigns first,last,middle`, `loop variant last-first`; plus per-branch sorted_lo/sorted_hi asserts lifting `a[middle]<v` to a segment bound and shift_eq/slice_le asserts to match lower_bound/upper_bound on `a+first`/`a+middle`. equal_range2.h carries the SUB_merge/SLB_merge/shift_eq lemmas. PROVED, gateB clean, gateC teeth. (capitalization, this batch) (capitalization, this batch)
- Heuristic: For a divide-and-conquer loop that shrinks an interval toward a target — `while (last > first) { mid = first + (last-first)/2; if (...) first = mid+1; else if (...) last = mid; else break; }` (binary search, lower/upper bound, equal-range, partition-point) — the counting-loop quartet does not apply: there is no monotonic 0..i index. The discharging set is (1) the nesting bound `loop invariant 0 <= first <= last <= n;` (plus a bound on any auxiliary cursor like `middle <= n;`); (2) a PAIR of settled-region facts, one per side, stating what has been proved about everything OUTSIDE the live window — e.g. `loop invariant <property> holds on [0, first)` AND `loop invariant <dual property> holds on [last, n)` (for equal-range these are StrictUpperBound on the left prefix and StrictLowerBound on the right suffix); (3) `loop assigns first, last, <aux>;`; (4) `loop variant last - first;` (the window WIDTH decreases — NOT n-i; verified: substituting `n - first` fails the variant-decrease goal). Two further scaffolding needs are typical: at each branch, an explicit `//@ assert` that lifts the single comparison `a[mid] REL v` to a whole-half bound using the input's sortedness (`\forall i; 0<=i<=mid ==> a[i]<=a[mid]`), because WP will not reliably derive the segment fact from sortedness + one point alone; and when the body calls a sub-search on an offset slice `a + first`, add `shift`/`(a+b)[k]==a[b+k]` rewriting asserts plus per-slice sorted-ness asserts so the callee precondition matches. Tell-tale: a `while` whose guard compares two cursors that converge, with `mid` computed between them and exactly one of the two cursors moved per branch.

### Coupled counters advancing at different rates: carry the arithmetic RELATION between them as an invariant, not just two independent bounds
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: framac/Heap/is_heap_until.c: `loop invariant parent == HeapParent(child)` alongside `0<=parent<child<=n+1`, `Heap(a,child)`, and the guarded not_heap invariant `a[parent]<a[child] ==> \forall i; child<i<=n ==> !Heap(a,i)`; `loop assigns parent,child; loop variant n-child`. is_heap_until.h supplies HeapParent/HeapLeft/HeapRight logic + the Heap_ParentLeft/Right/Bounds/Heap_Shrink lemmas. PROVED, gateB clean, gateC teeth. (capitalization, this batch) (capitalization, this batch)
- Heuristic: When a loop drives two counters that step at coupled-but-unequal rates — a fast cursor incremented every iteration and a slow cursor advanced conditionally so that they stay in a fixed arithmetic relation (heap parent/child: `parent == (child-1)/2`, advanced only on even child; stride/block walkers; chunk indices) — bounds alone (`0<=parent<child<=n+1`) do not discharge the body, because the body indexes BOTH cursors and WP cannot re-establish the link from the bounds. Carry the RELATION itself as a loop invariant: `loop invariant slow == f(fast);` (e.g. `parent == HeapParent(child)`), backed by small definitional lemmas about `f` (`HeapParent(HeapLeft p)==p`, `0<=HeapParent(c)<c`, etc.) so WP can step the relation across the conditional advance. Pair it with the structural property accumulated over the processed region (`Heap(a, child)`) AND, when the function returns the first failing position, a guarded NEGATIVE invariant naming the consequence of an early exit (`a[parent] < a[child] ==> \forall i; child < i <= n ==> !Heap(a,i)`). Frame `loop assigns slow, fast;` and use the natural `loop variant n - fast;`. This is the functional-relation generalization of the two-cursor-bounds compaction rule: there the cursors only needed `0<=k<=i`; here the proof needs the exact closed-form tie between them.

### An object-extent precondition on a leaf parser is a PROPAGATING obligation: strengthen the leaf, then discharge it up the call tree
- Kind: defer-to-oracle
- Gate S: field-derived (Mbed TLS 4.1.0 RTE campaign); pending disjoint audit
- Arose from: closing the entailed `asn1_*_requires_3` cast-residuals on the pkcs7/x509 decode path — added the real C object-extent bound `requires end - *p <= SIZE_MAX` (`+ ensures` for the consumers) to `mbedtls_asn1_get_tag`/`get_len`, mirroring what closed `get_bitstring_null`. asn1 109→112/112, pkcs7 leaf set →201/201, x509 leaf →229/229, crl 129/130→153/154; 0 disproved.
- Heuristic: the WP Typed model hides a real fact — a live object's byte-extent fits in `size_t` — so a leaf byte-parser cannot prove an in-bounds span computation without it; add it as a `requires` on the leaf. BUT it is a **propagating** obligation: every caller must now discharge `end - *p <= SIZE_MAX` at the call site. Top-level entry points already holding a `size_t buflen` get it for free; intermediate `(ptr, end)` helpers on the path must carry the *same* `requires` so the chain composes. So plan the strengthening as a **sweep up the parser tree**, not a one-line local fix — and add it ONLY to helpers actually on the path (adding it where it isn't needed creates helper-isolation residuals — the CSR helpers showed this, and were reverted). This is what converts an entailed `+cast`/cast-residual (which otherwise reads as a tooling `[Timeout]`) into a discharged goal.

### `//@ calls` binds only to a whole-RHS / bare-call statement — not nested-in-expression, not local-def init
- Kind: defer-to-oracle
- Gate S: field-derived (linux-7.1.3 LSM campaign cycle-443, SELinux `hashtab_search`); pending disjoint audit
- Arose from: a faithful in-place proof dispatching through two function pointers stalled at 20/33 — the `//@ calls` statement annotation is silently IGNORED when the indirect call is a sub-expression (`v = fp(k) & mask;`) or a local-def initializer (`int c = fp(a,b);`); WP then assumes the pointer may call the *enclosing* function → the whole downstream region havocs/degenerates.
- Heuristic: WP resolves an indirect call ONLY when `//@ calls f;` binds to its statement, and it binds ONLY to a plain whole-RHS assignment or a bare call statement. If the pristine body positions the call as an expression sub-term or a local-def initializer, the clause does not attach (over a local definition it errors: `Statement contract and ACSL pragmas over a local definition are not implemented`). The obvious fix — split the call into its own assignment — EDITS the body and breaks `strip(//@)==pristine`, so it is unavailable for an in-place proof. Consequences: (1) a `requires fp==&stub` pin alone does NOT devirtualize, and `-wp-dynamic` is obsolete/no-op; (2) treat such a target as **status-3-BLOCKED** for a faithful proof — record the block, do NOT count it WITNESSED, do NOT edit the body — and prefer non-`fn-ptr-in-expression` targets for clean witnesses. This is the `calls`-does-not-ATTACH gap; distinct from the residual `\valid_function`-RTE-unimplemented gap that remains even after `calls` DOES attach (also status-3). Filed: `../../frama-c-monitoring/getting-better/20260724-0030-wp-calls-clause-placement-nested-and-localdef.md`.
