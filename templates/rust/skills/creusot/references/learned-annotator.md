# Learned knowledge — Annotator (creusot-sl)

Append-only, Gate-S-gated proof-scaffolding patterns the **annotator** capitalized
while running the `creusot-sl` loop (see the `creusot-sl` skill (`config/skills/creusot-sl/SKILL.md`) §11). Each entry
passed an `sl-monitoring-sl` Gate S audit by a disjoint monitor (the coordinator) and
carries provenance.

**Scope / barrier:** proof-scaffolding *patterns* that make Creusot discharge —
invariant templates per loop shape, ghost/snapshot idioms, `#[variant]` choices,
intermediate `proof_assert!` placements, prover-selection tips ("introduce a `found`
flag", "open a `#[logic(open)]` body the prover can't see"). **Generalize to a
pattern — never a verbatim copy of one program**, and never weaken a contract or
record an escape hatch (`#[trusted]`/`assume!`) as a "fix". Future runs load this file
at delegation time.

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

### Pair `#[variant]` with `#[check(terminates)]` on executable recursive fns
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: mc91.rs (creusot-monitoring run 20260616)
- Heuristic: on a non-`#[logic]` recursive function a bare `#[variant]` is **silently
  ignored** (Creusot emits only a "variant will be ignored" warning) — termination is
  never checked yet the partial-correctness proof still shows green. Add
  `#[check(terminates)]` alongside `#[variant]` when termination is intended, and treat
  that warning as a failure.

### Count-down `#[variant]` for recurse-up-to-a-bound
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: mc91.rs
- Heuristic: for recursion whose argument grows toward an exit bound `B` (exit when
  `arg > B`), the well-founded measure is the count-down `(B+1) - arg@` (e.g. `101 - x@`
  for the `> 100` exit). A nested `f(f(arg+k))` still decreases it because the verified
  postcondition pins the inner result's value.

### Derive the panic precondition from the `is_none()` / checked assert
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: checked_ops.rs
- Heuristic: in assert-style tests mixing `checked_X().is_none()` with a closed-form
  result on a parameter, the boundary `#[requires]` that makes the `is_none()` assert
  hold (e.g. `a@ >= 1` at the 255 boundary) usually also discharges the in-Pearlite
  arithmetic under/overflow in the result formula. Derive the precondition from the
  `is_none()` assert first.

### `#[bitwise_proof]` for SWAR / bitmask overflow obligations
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: bitvectors/popcount.rs (creusot-monitoring batch 4)
- Heuristic: when a function's overflow/underflow VCs hinge on bitwise facts (`&`, `>>`,
  masks) — e.g. SWAR popcount `x - ((x>>1)&0x55)` — the default translation leaves
  `bw_and`/`shr` *uninterpreted over Int*, so `(x>>1)&M <= x` is unprovable at any
  timeout. Annotate the whole function `#[bitwise_proof]`: it retranslates the body
  against Why3's bitvector theory and Z3/CVC5 decide the bit-level facts. Pair with
  `#[ensures(result@ <= BITS)]`. This adds only an attribute (strips clean — faithful).

### Recursive ADT view: define `#[logic]` recursion on `self`, not via `Box::view`
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: binary_search_list.rs (creusot-monitoring batch 4)
- Heuristic: to model a recursive enum (e.g. a linked `List<T>`), write a recursive
  `#[logic(open)] pub` fn directly on the consumed `self`/`Box` argument (Creusot accepts
  structural recursion with NO `#[variant]`). Do NOT route the model through an
  `impl View` that calls `Box::view`: that triggers a spurious "Mutually recursive
  functions" error via the Box View impl, and the enum is not `WellFounded` so it can't
  serve as a `#[variant]` measure. Keep length/get as plain `Int`/`Option`-returning
  logic fns rather than a `Seq` view. A recursive predicate used in a postcondition must
  be both `#[logic(open)]` and `pub` or the self-call hits a "less-visible item" error.
- CARVE-OUT (private-field ADT): if the enum/struct has PRIVATE fields (e.g. a tuple struct
  `List(u32, Option<Box<List>>)` defined in the same module that consumes it), `#[logic(open)] pub`
  FAILS twice: "Cannot make field transparent (less-visible item)" on the private field AND
  "Cannot prove termination for <fn>" because `open` forces an external-termination obligation the
  non-`WellFounded` enum can't discharge (no valid `#[variant]`). Fix: drop `open`/`pub` and use a
  bare `#[logic]` helper — same-module callers still see the body, the transparency error vanishes,
  and no `WellFounded` variant is demanded. So: `#[logic(open)] pub` for cross-module/public models
  with public fields; bare `#[logic]` for same-module private-field ADTs. (Arose from list_index_mut.rs,
  batch 13.) The `&mut`-walking prophecy-chain template — `snapshot!` the original `l`/`ix`, carry
  implication-form invariants `^cursor ... ==> ^*old_l ...` — discharges the whole-structure
  postcondition cleanly.

### `&mut` slice/Vec mutated in a loop: preserve length across the call
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: bitvectors/bitwalker.rs (creusot-monitoring batch 4)
- Heuristic: when a callee takes `&mut [T]`/`&mut Vec<T>` and a loop invariant references
  `addr@.len()`, give the callee `#[ensures((^addr)@.len() == addr@.len())]` AND give the
  loop `#[invariant(addr@.len() == *snapshot!(orig_len))]` (snapshot the original len
  before the loop) to carry length-preservation across early-return prophecy resolution.
  Separately, `8 * slice.len()` in executable code is a real machine multiply with its own
  overflow VC — guard it with `#[requires(8 * addr@.len() <= usize::MAX@)]`, distinct from
  the Int-level range bound. For `a/8 < len` from `a < 8*len`, alt-ergo needs the explicit
  chain `proof_assert!(8*(a/8) <= a); proof_assert!(a/8 < len);`.

### `&mut`-walking loop over a recursive structure: chain prophecies, not `old()`
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: all_zero_list.rs (creusot-monitoring batch 4)
- Heuristic: for a loop that walks a `&mut` cursor down a linked structure, `old()` is
  rejected inside `#[invariant]`. Instead `snapshot!` the original mutable cursor
  (`let g = snapshot!(loop_l);`) and carry the invariant `pred(^cursor) ==> pred(^*g)`
  where `^*g == ^orig_borrow`; at the base-case exit the antecedent holds, forcing the
  whole-structure postcondition.

### Adding `use` for macro disambiguation is a faithfulness FABRICATION — do not
- Kind: ignore-signal
- Gate S: CARVE-OUT
- Arose from: 100doors.rs (creusot-monitoring batch 4, monitor caught fabrication)
- Heuristic: the std `vec!` macro clashes with the `creusot_std` prelude re-export
  (`error[E0659]: vec is ambiguous`). Do NOT add `use std::vec;` to fix it: the strip gate
  does not remove arbitrary `use` lines, so it counts as altering executable code and the
  faithfulness monitor (`monitor-check.sh`) flags FABRICATED. Carve-out → if a prelude
  glob clashes with a macro the original file uses, prefer a NON-glob prelude import or a
  fully-qualified path that the strip tool DOES erase; if neither is faithful, report
  PARTIAL/FAILED rather than inventing a `use`. Only `use creusot_std::prelude::*;` and
  imports the strip tool removes are faithful additions.

### Calling a generic `FnMut`/`FnOnce` closure: supply precondition + re-establishment
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: bug/1410.rs, bug/1396.rs (creusot-monitoring batch 5)
- Heuristic: calling an unconstrained generic `F: FnMut()`/`FnOnce()` inside a function or
  loop emits a `precondition(())` VC with no caller constraint. The faithful fix is a pair:
  `#[requires(f.precondition(()))]` (callable initially) plus a *closure-state-agnostic*
  re-establishment `#[requires(forall<g: F, r: F> g.postcondition_mut((), r, ()) ==>
  r.precondition(()))]`. Crucially quantify over FRESH states `g,r` — binding the live `f`
  makes the loop invariant unprovable to preserve across the call. For a "call once then
  drop" wrapper, give it `#[ensures(f.postcondition_once((), ()))]`; for FnMut prefer
  `postcondition_once` over the `exists<st> postcondition_mut && resolve(st)` form (the
  existential leaves the witness for SMT to guess and the caller's VC stays one short).

### Closure mutating a captured `&mut`: state the effect with `old(*r)`, not `^r`
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: bug/1396.rs (creusot-monitoring batch 5)
- Heuristic: for a closure that mutates through a captured `&mut`, write the effect as
  `#[ensures((*r)@ == old(*r)@ + 1)]`, NOT `#[ensures((^r)@ == (*r)@ + 1)]`. Under a
  `FnOnce` capture the borrow is captured as a double borrow (`MutBorrow(MutBorrow T)`) and
  the `^`/`*` form translates to the wrong layer (`final.final` vs `current.final`), failing
  the closure's own VC. Pair with the overflow guard `#[requires((*r)@ < TYPE::MAX@)]`.

### Reborrow through a `&mut` to an inner `&mut` field: result final is `*(^outer).field`
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: bug/922.rs (creusot-monitoring batch 8)
- Heuristic: a function that reborrows `&mut *p.field` where `p: &mut (.., &mut T)` returns
  a `&mut T`. The current-value clause is straightforward: `#[ensures(*result == *(*p).field)]`.
  The final-value clause is the trap: the reborrow rewires the inner field's *current* to
  `result.final`, and resolving the outer borrow `p` makes `(^p).field.current == result.final`.
  So write `#[ensures(^result == *(^p).field)]` — NOT `^(*p).field`. The inner field's own
  prophecy `^(*p).field` is an independent value that is never touched and is not provably
  equal to `^result`. Same form for an owned-tuple reborrow `g(x) -> &mut *(x.0).1`:
  `*result == *(x.0).1` and `^result == ^(x.0).1`.

### A spec-less `&mut`-mutating callee blocks downstream arithmetic — give it a `^`-postcondition
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: final_borrows.rs (creusot-monitoring batch 8)
- Heuristic: when a private helper takes a `&mut T` and has NO `#[ensures]`, Creusot models
  its effect as fully arbitrary, so any later arithmetic on the mutated value (e.g. `x + y`
  after `set_7(&mut y)`) raises an unprovable overflow/value VC even though the runtime values
  are concrete. The faithful fix is to specify the *callee's* prophecy postcondition
  (`#[ensures(^r == 7i32)]`), which propagates the final value through even a non-final reborrow
  and discharges the caller's VC — no `#[requires]` on the caller and no escape hatch. General
  rule: an unproved overflow/value VC downstream of a spec-less `&mut`-mutating call is usually
  fixed by specifying the callee's `^`-postcondition, not by guarding the caller.

### Closure precondition over a PRIVATE field: discharge via `impl Invariant`, not `#[requires]`
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: closures/05_map.rs (creusot-monitoring batch 9)
- Heuristic: when a public trait-impl method calls a generic `F: Fn(A)->B` closure stored in a
  PRIVATE struct field (e.g. `Map { iter, func }`'s `next` calling `(self.func)(e)`), you cannot
  put `#[requires(forall<e: A> self.func.precondition((e,)))]` on the method — Creusot rejects it
  with `Cannot make "Struct::field" transparent … as it would call a less-visible item`. Instead
  add a Creusot type invariant: `impl<…> creusot_std::invariant::Invariant for Struct<…> {
  #[logic(prophetic)] fn invariant(self) -> bool { pearlite!{ forall<e: A> self.func.precondition((e,)) } } }`.
  It is assumed on method entry and discharges the call. Three required details: (1) re-state
  enough bounds on the impl so every generic param is constrained (else E0207); (2) `precondition`
  is prophetic, so the fn must be `#[logic(prophetic)]`, not bare `#[logic]`; (3) this is FAITHFUL
  because the strip tool removes whole `impl Invariant`/`View`/`DeepModel`/`Resolve` blocks by the
  trait's last path segment — write the trait as `creusot_std::invariant::Invariant` (last segment
  `Invariant`) and the monitor gate ACCEPTs it.

### A `panic!()`-only fn that a live caller calls is an irreducible PARTIAL
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: closures/01_basic.rs (creusot-monitoring batch 9)
- Heuristic: a `pub fn … { panic!() }` whose only "spec" that discharges its body is
  `#[requires(false)]` does NOT yield a faithful whole-file proof if another function in the file
  actually calls it — `#[requires(false)]` just relocates the unproved goal to the live call site.
  Report PARTIAL and annotate nothing rather than chasing it. (Distinct from an unreachable/never-
  called divergent stub, which is TRIVIAL.)

### Closures carry their OWN inline `#[requires]`/`#[ensures]` — faithful, strips clean
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: closures/07_mutable_capture.rs (creusot-monitoring batch 10)
- Heuristic: an inline closure can bear its own contract placed directly before the `||` (or
  between the surrounding `{` and the `||`). The strip tool removes these attribute lines, so
  they are a FAITHFUL annotation-only addition (monitor gate ACCEPTs). For a `&mut`-captured `u32`
  doing `x += 1`, the pair `#[requires(x@ < BOUND)]` + `#[ensures(x@ == old(x)@ + 1)]` on the
  closure simultaneously discharges the closure's own overflow VC AND supplies the
  `postcondition_mut` the caller's FnMut re-establishment needs. When the caller's
  re-establishment quantifies over arbitrary closure states, a bare overflow guard on the caller
  is too weak; pin a concrete starting capture value (e.g. `#[requires(x@ == 100_000)]`) so the
  closure `#[ensures]` keeps the incremented field in range across the chain.

### `&F`/`&mut F`/`Box<F>` adaptors forward `precondition` automatically
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: closures/13_ref_box.rs (creusot-monitoring batch 10)
- Heuristic: when a caller passes a closure through a reference or box adaptor (`&f`, `&mut f`,
  `Box::new(f)`) into a helper `fn call(g: G) { g(x) }`, the helper's `g.precondition((x,))` VC is
  discharged automatically from the caller's `f.precondition((x,))` via Creusot's stdlib forwarding
  impls for `&F`/`&mut F`/`Box<F>`. No extra clause about the reference/box is needed — the SAME
  `#[requires(f.precondition((x,)))]` on the caller covers the direct-move, `&`, `&mut`, and
  `Box::new` variants uniformly. (For a `&mut F: FnMut` forwarding wrapper, the post slot is
  `(*f).postcondition_mut((args,), ^f, result)` — use `(*f).precondition` and the `^f` prophecy.)

### `&mut *x` reborrow through `DerefMut`: quantify the precondition over reborrows
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: generic_deref.rs (creusot-monitoring batch 11)
- Heuristic: a wrapper `fn(x: &mut T) -> &mut T::Target { &mut *x }` over `T: DerefMut` is NOT
  discharged by the naive `#[requires(T::deref_mut.precondition((x,)))]` (the obvious form a user
  writes) — it leaves the final-reborrow subgoal unproved because Creusot can't link the borrow
  handed to `deref_mut` to `^x`. Faithful fix: quantify over all matching reborrows:
  `#[requires(forall<bor: &mut T> *bor == *x ==> T::deref_mut.precondition((bor,)))]`, mirroring the
  stdlib `Option::as_deref_mut` extern-spec shape. The immutable `Deref` case needs only the simple
  `#[requires(T::deref.precondition((x,)))]`.

### Pin a spec-less constructor's exact model to collapse downstream slice/index/assert VCs
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: index_range.rs (creusot-monitoring batch 11)
- Heuristic: for an assert-style test that builds a fixed concrete container in a spec-less private
  helper and then asserts many facts about slice ranges/elements (`&arr[a..b]`, `&mut arr[..=k]`,
  `.get(range)`, length/value/out-of-bounds-is-none), the whole file's panic/index/assert
  obligations collapse to ONE fix: give the constructor an `#[ensures]`-set pinning its exact model
  (`result@.len() == N` plus `result[i]@ == v_i`). The std slice-range `Index`/`get` extern specs
  already carry the bounds and `is_none` facts, so no per-callsite invariant or `proof_assert!` is
  needed.

### Generic overflow contracts inside `macro_rules!`: use `<$t>::MAX@`/`<$t>::MIN@`
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: integer_ops.rs (creusot-monitoring batch 11)
- Heuristic: to annotate arithmetic inside a `macro_rules!` body instantiated across many integer
  types, write bounds as `<$t>::MAX@` / `<$t>::MIN@` so ONE annotation discharges every
  monomorphization for both signed and unsigned. The `MIN@` lower bound is load-bearing for signed
  sub/neg/div (catches `MIN/-1` and negation-at-MIN) and is harmlessly trivial (0) for unsigned.
  Pair add/sub/mul with `#[requires(l@ OP r@ <= <$t>::MAX@ && l@ OP r@ >= <$t>::MIN@)]` +
  `#[ensures(result@ == l@ OP r@)]`; div needs `#[requires(r@ != 0)]` plus the same range guards.
  Also: `#[bitwise_proof]` extends from SWAR popcount to ANY assertion-only function whose
  obligations are `&`/`|`/`^`/`!`/`<<`/`>>` over constants.

### Faithful `vec!` fix: `use creusot_std::prelude::{vec, *};`
- Kind: ignore-signal
- Gate S: PASS
- Arose from: filter_positive.rs (creusot-monitoring batch 11)
- Heuristic: the `vec!` glob ambiguity (E0659 from `use creusot_std::prelude::*;` clashing with std's
  `vec!`) is faithfully fixed by `use creusot_std::prelude::{vec, *};` — the strip tool removes any
  `use creusot_std::…` line by its root segment regardless of brace form, so this strips clean and
  the monitor gate ACCEPTs it. This is the canonical alternative to reporting FAILED on the `vec!`
  clash (supersedes the older "no faithful fix exists" framing for files that may add a brace-form
  prelude import): creusot-std's own docs use this exact form. (Still never add `use std::vec;` — the
  strip tool does NOT remove a `std::` use, so that FABRICATES.)

### Don't reflexively annotate break-only / single-pass loops
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: bug/164.rs (creusot-monitoring batch 5)
- Heuristic: loops whose body unconditionally `break`s on the first iteration (and trailing
  asserts after such a body) need NO `#[invariant]` — Creusot's translation discharges them
  automatically. Run the bare copy through `cargo creusot` first and only annotate what
  actually stays unproved; adding a needless invariant is wasted effort and can stall.

### Faithful derive-macro glob clash fix (generalizes `vec!`): `use creusot_std::prelude::{Clone, *};`
- Kind: ignore-signal
- Gate S: PASS
- Arose from: lang/const.rs (creusot-monitoring batch 12)
- Heuristic: when the target has `#[derive(Clone, ...)]` (or another derive re-exported by the
  prelude), `use creusot_std::prelude::*;` can raise `error[E0659]: Clone is ambiguous` because the
  prelude re-exports a `Clone` derive macro that conflicts with std's outer-scope `Clone`. The
  faithful fix is the brace form naming the clashing item first: `use creusot_std::prelude::{Clone, *};`.
  Same mechanism as the `vec!` clash (`{vec, *}`) — the strip tool removes any `use creusot_std::…`
  line by its root segment regardless of brace form, so it strips clean and the monitor gate ACCEPTs.
  General rule: any prelude-glob/derive-macro name clash (E0659) is faithfully resolved by listing
  the clashing name(s) in the brace form, never by adding a separate `use std::…` (which FABRICATES).

### `&mut`-returning selector fn: write a prophecy clause per branch and PIN the unselected borrow
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: projection_toggle.rs (creusot-monitoring batch 14)
- Heuristic: for a function that returns `&mut T` by choosing among several input borrows
  (`if toggle { a } else { b }`), give it a branch-split contract: one clause per branch forwarding
  BOTH the current and prophecy of the selected borrow (`toggle ==> *result == *a && ^result == ^a`),
  AND — crucially — pin every NON-selected borrow as resolved-unchanged (`^b == *b`). Without the
  pin the caller cannot prove the unselected variable is untouched (even though it is never written),
  so its later asserts/overflow VCs won't close. Generalizes "specify the callee's `^`-postcondition"
  to multi-borrow selectors.

### Prophecy `^` assert is order-sensitive and carries the borrowed value's MACHINE type
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: prophecy.rs (creusot-monitoring batch 14)
- Heuristic: `proof_assert!(^y == v)` placed BEFORE the determining write `*y = v` is UNPROVABLE
  (the prophecy is unconstrained until the write/resolution pins it); place it AFTER the write, where
  `^y == *y` at resolution discharges it. Also `^y` has the borrowed value's machine type, so compare
  `^y == 5i32` (or `(^y)@ == 5`), never bare `^y == 5` (that types as `Int` and fails E0308).

### Hand-rolled Result/Option enum: one `#[logic(open)] pub` discriminant predicate is the lever
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: result/own.rs (creusot-monitoring batch 14)
- Heuristic: for a user-defined Result/Option-style enum, define a single `#[logic(open)] pub`
  discriminant predicate (e.g. `is_ok_log(self) -> bool`). It both specifies the `is_ok`/`is_err`
  queries (`#[ensures(result == self.is_ok_log())]` / `... == !self.is_ok_log()`) AND supplies the
  exact panic-ruling `#[requires]` for each consumer: `unwrap`/`expect` → `#[requires(self.is_ok_log())]`,
  `unwrap_err` → `#[requires(!self.is_ok_log())]`. Total methods (ok/err/as_ref/unwrap_or/and/or/...)
  need no spec. Note: in this Creusot version open-logic syntax is `#[logic(open)]` on ONE line —
  `#[logic]` + a separate `#[open]` fails with "cannot find attribute `open`".

### Increment-then-assert-on-incremented-value: overflow bound is `orig + 2*k`, not `orig + k`
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: rusthorn/inc_max_many.rs, inc_max_repeat.rs (creusot-monitoring batch 15)
- Heuristic: when a loop/body does `*mc += k` then is followed by `assert!(a >= b + k || b >= a + k)`,
  the binding overflow VC is NOT the `+= k` increment — it is the `b + k`/`a + k` adds in the TRAILING
  assert, which use the POST-increment (grown) values. Because the max-increment makes the larger var
  reach `initial + k`, the assert's add computes `initial + 2*k`, so the precondition must give
  `orig + 2*k <= MAX` (twice the headroom), and a bounding loop invariant must carry the doubled slack
  (e.g. `x@ + n@ + (n@ - produced.len()) <= u32::MAX@`). Diagnose by reading `why3session.xml`: the LAST
  unproved `expl="integer overflow"` goal (after the body's) points at the trailing assert. Corollary: a
  focused `proof_assert!` that proves fact F before an op does NOT discharge the op's VC if the failing
  goal is a DIFFERENT one — confirm the failing goal's identity in the session XML before chasing it.

### Constant-index slice access `a[K]`: `#[requires(a@.len() >= K+1)]`
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: slices/01.rs (creusot-monitoring batch 15)
- Heuristic: for a constant-index slice read or write `a[K]` / `a[K] = v`, the panic-ruling precondition
  is just `#[requires(a@.len() >= K+1)]` on the Seq-view length; the std slice `Index`/`IndexMut` extern
  specs carry the in-bounds fact, so no `proof_assert!`/invariant is needed. An index already guarded by a
  runtime `if a.len() > N` branch needs NO annotation (the branch condition discharges it).

### `std::mem::swap` extern spec discharges a swap wrapper without `#[trusted]`; `old()` gotchas
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: rusthorn/inc_max_3.rs (creusot-monitoring batch 15)
- Heuristic: a `swap` wrapper around `std::mem::swap` (even on nested `&mut &mut T`) does NOT need
  `#[trusted]` — creusot-std's extern_spec gives `^x==*y && ^y==*x`, lifted one borrow level as
  `#[ensures(^mma == *mmb && ^mmb == *mma)]`, and it discharges. Two operator gotchas: (a) `old(...)` is
  rejected wherever its sub-expression dereferences through a `&mut` (`old(**mmb)`, `*old(mmb)`) — write the
  effect with current borrows (`^outer == *otherInner`) instead of `old`; (b) prophecy/deref bind looser
  than `@`, so `^ma@`/`*ma@` fail E0614 — for `&mut u32` comparisons drop `@` and compare borrows directly
  (`^ma != ^mb`, `*ma <= 1_000_000u32`).

### Value-aggregating recursive `&mut` selector (RustHorn sum/count): delta-prophecy + element-bound
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: rusthorn/inc_some_{list,tree,2_list,2_tree}.rs (creusot-monitoring batch 15)
- Heuristic: a callee that returns `&mut elem` (and possibly `&mut rest`) extracted from a recursive ADT
  modeled by a recursive `#[logic(open)] pub fn sum(self) -> Int` is NOT specified by the naive
  `sum(self) == elem + sum(rest)`. Use the DELTA-PROPHECY form
  `(^self).sum() - self.sum() == ((^elem)@ - (*elem)@) + ((^rest).sum() - (*rest).sum())`
  (the change to the whole equals the sum of changes to each returned borrow), PLUS an element-BOUND
  clause `(*elem)@ + (*rest).sum() <= self.sum()` so the caller's per-borrow `*elem += k` overflow VC
  closes from the whole-aggregate bound. Non-negativity of the Int sum must be a SEPARATE
  `#[logic] #[ensures(self.sum() >= 0)]` lemma proven by structural recursion, materialized in executable
  code via `proof_assert!(x.sum_nonneg() == ())`. A `#[logic]` body using `@` inside a `match` arm must be
  wrapped in `pearlite!{ ... }` (bare `a@` in a match arm is a Rust parse error — rustc reads `@` as the
  binding-pattern operator). NOTE: these RustHorn benchmarks include a `fn random() -> bool { panic!() }`
  nondeterminism stub called live — it is the documented irreducible PARTIAL (only `#[trusted]` or an
  unfaithful `#[requires(false)]` closes it), so the whole file stays PARTIAL even when all real specs prove.

### `slice::binary_search(&K).unwrap()`: rule out panic via sorted + value-present precondition
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: slices/02_std.rs (creusot-monitoring batch 16)
- Heuristic: creusot-std's extern spec on `[T]::binary_search` requires `self.deep_model().sorted()`
  and gives `Ok(i) ==> deep_model()[i]==K` / `Err(i) ==> forall j: deep_model()[j]!=K`. To rule out the
  `.unwrap()` panic for a constant key K, supply ONE precondition that both (a) makes the slice sorted
  and (b) forces K present — e.g. `#[requires(forall<i> 0<=i && i<s@.len() ==> s[i]@ == i)]` (strictly
  increasing ⇒ sorted; value K sits at index K), contradicting the `Err` "K absent" postcondition so only
  `Ok` remains. No `proof_assert!` needed for the unwrap.

### Shift-by-loop-index `1 << i`: bound the index, do NOT reach for `#[bitwise_proof]`
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: slices/bitwise.rs (creusot-monitoring batch 16)
- Heuristic: a `1u64 << i` inside `for/while i < slice.len()` raises only a SHIFT-AMOUNT VC (`i < 64`),
  not a bit-value VC. Discharge it with a length bound `#[requires(slice@.len() <= 64)]` chained through
  the index invariant `#[invariant(i@ <= slice@.len())]` and the loop guard — no `#[bitwise_proof]`.
  Reserve `#[bitwise_proof]` for VCs over bit VALUES (masks/and/or/comparisons). Same chaining discharges
  a loop-variable slice index `slice[i]` (the std Index extern spec carries in-bounds once `i@<len`).

### Inclusive-range slice `&a[L..=U]`: `#[requires(a@.len() >= U+1)]`
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: slices/range.rs (creusot-monitoring batch 16)
- Heuristic: an inclusive-range slice `&mut a[L..=U]` is panic-ruled by a single `#[requires(a@.len() >= U+1)]`
  (upper endpoint + 1); the std slice-range extern spec then carries the resulting slice's length, so
  constant-index writes into it (`s[0]`, `s[1]`) need no further invariant/proof_assert. Generalizes the
  constant-index-slice heuristic from `a[K]` to ranges.

### `#[check(terminates)]` propagates to callees, and `#[variant]` needs the callee's `#[ensures]`
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: spans.rs (creusot-monitoring batch 16)
- Heuristic: when `#[check(terminates)]` decorates a recursive fn, EVERY program fn it calls must ALSO be
  `#[check(terminates)]` or Creusot errors "called program function in terminates context" — so even a
  simple non-recursive helper invoked from the terminating fn must be marked terminating. Further, a
  `#[variant]` measure that decreases through a callee's RETURN value is unprovable unless that callee
  carries the `#[ensures]` pinning its returned value (e.g. a `decr` helper needs
  `#[ensures(result.0@ == self.0@ - 1)]` for the caller's `#[variant(i.0@)]` to decrease) — `#[requires]`
  alone is not enough.

### Illegal recursive type (e.g. `Vec<Rose<T>>` inside `struct Rose`): irreducible FAILED without `#[trusted]`
- Kind: ignore-signal
- Gate S: PASS
- Arose from: specification/trusted.rs (creusot-monitoring batch 16)
- Heuristic: a type that recurses under a non-WellFounded/opaque generic container (a `struct Rose<T>` with
  a `Vec<Rose<T>>` field, or one ADT nested inside another's generic) is rejected by Creusot at TRANSLATION
  time with `error: Illegal recursive type` — a hard front-end error, NOT a proof obligation. No
  `#[requires]`/`#[ensures]`/`#[invariant]`/`#[logic]` can suppress it; the ONLY Creusot mechanism that makes
  it translate is `#[trusted]` on the type/fn. Under the faithfulness rule (never ADD `#[trusted]`) such a
  file is an irreducible FAILED — analogous to the "panic!()-only fn called live = irreducible PARTIAL" case
  but at the type-modeling layer. Diagnose early: a bare `cargo creusot` printing "Illegal recursive type"
  means STOP, not iterate.

### Generic-`T` tuple swap: specify with borrow EQUALITY, not prophecy operators
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: swap_borrows.rs (creusot-monitoring batch 17)
- Heuristic: a hand-written generic `fn swap<T>(x: (T,T)) -> (T,T)` whose `T` may be a `&mut` is specified
  by plain equality `#[ensures(result.0 == x.1 && result.1 == x.0)]`, NOT by `*`/`^`. Creusot cannot apply
  the prophecy operators to an arbitrary generic `T` (they are not defined on every `T`), but `==` on the
  moved borrows carries BOTH current and prophecy structurally. This discharges a downstream
  write-through-the-swapped-borrow (`*p.0 = 10`, which otherwise errors "Acc(...val_ref) cannot be
  obtained") because the equality re-links the swapped field to the original borrow's prophecy. Generalizes
  the `mem::swap` extern-spec heuristic to a hand-written generic swap with no `mem::swap` call, no `#[trusted]`.

### Slice `take_first_mut` (`&mut &mut [T] -> Option<&mut T>`): four double-prophecy projections
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: take_first_mut.rs (creusot-monitoring batch 18)
- Heuristic: the `mem::take(self_).split_first_mut()` idiom on a DOUBLY-borrowed cursor
  `self_: &mut &mut [T]` is fully specified by a single result-match `#[ensures(match result { ... })]`
  using FOUR distinct double-prophecy projections of `self_`: current/current `**self_`, final/current
  `^*self_`, current/final `*^self_`, final/final `^^self_`. Some-branch: tie the returned element's
  current/prophecy to slot 0 (`*r == (**self_)[0] && ^r == (^*self_)[0]`) and equate the updated cursor's
  current and final views to the TAIL (`(*^self_)@ == (**self_)@.tail() && (^^self_)@ == (^*self_)@.tail()`).
  None-branch: force all four views to `Seq::empty()`. creusot-std's `mem::take`/`split_first_mut` extern
  specs discharge it with no loop/invariant/proof_assert; the `[0]` is logical-view only (no index guard).

### Range/nonzero newtype invariant: `impl Invariant` + re-establish the invariant on each returned `Self`
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: type_invariants/non_zero.rs (creusot-monitoring batch 20)
- Heuristic: for a tuple-struct newtype carrying a data invariant (`NonZeroU32(pub u32)` with `field != 0`,
  or any range/nonzero constraint), declare it with a NON-prophetic
  `impl creusot_std::invariant::Invariant for T { #[logic] fn invariant(self) -> bool { pearlite!{ self.0@ != 0 } } }`
  (strips clean — the strip tool removes whole `impl Invariant` blocks by trait segment). The invariant is
  ASSUMED on every `self`/arg and MUST BE RE-ESTABLISHED on every returned `Self`. Pair each arithmetic op
  with the usual `<TYPE>::MAX@` overflow/underflow guard AND a `result.0@ == ...` ensures. Watch the
  re-establishment gap: for `add`, nonzero-result is free once both operands' invariants hold and overflow is
  ruled out; for `sub`, the underflow guard `self.0@ >= rhs.0@` does NOT alone keep the result nonzero — add a
  SEPARATE `#[requires(self.0@ - rhs.0@ != 0)]` so the result still satisfies the invariant.

### VecDeque / std-container assert tests discharge from std extern specs alone
- Kind: ignore-signal
- Gate S: PASS
- Arose from: vecdeque.rs (creusot-monitoring batch 20)
- Heuristic: a straight-line assert-style test over a std container (VecDeque `with_capacity`/`new`/`push_front`/
  `push_back`/`pop_front`/`pop_back`/`len`/`is_empty`/`clear`; also Vec capacity mutators `reserve`/`reserve_exact`/
  `shrink_to_fit`/`shrink_to`/`clear`) needs NO Pearlite — creusot-std ships extern specs that thread the Seq
  model precisely enough that concrete-value asserts after a fixed push/pop sequence (e.g. `pop_front()==Some(2)`,
  `pop_back()==Some(3)`) all prove with just the prelude import. Run the bare copy first; don't reach for
  invariants/proof_assert! on straight-line container tests. (Vec capacity-only mutators are even TRIVIAL — no VC.)

### Re-opening corpus-stripped husks: spec-only fixtures and "No files to prove"
- Kind: ignore-signal
- Gate S: PASS
- Arose from: re-open batch 0 (bug/1030, 265, 564, 768, 797, 1342, 1438, etc.)
- Heuristic: many `should_succeed` fixtures are PURE SPEC — their whole body is `#[logic]`/`#[predicate]`/
  `#[law]` items (often `#[logic(open)]`), so corpus-stripping leaves an empty or comment-only husk. To re-open,
  port the reference's logic items verbatim (the reference already uses `creusot_std::prelude` syntax). For
  associated-type / blanket impls the open form is `#[logic(open(self))]`; a trait method declared `#[logic]`
  (no body) is defined `#[logic(open)]` in the impl, and any `#[ensures]` on the trait method must be REPEATED
  verbatim on the impl method.
- Heuristic: a bare `#[logic(open)]` function with NO contract and NO caller emits ZERO Why3 goals — `cargo
  creusot` prints "No files to prove" (sometimes as `Error: No files to prove`). For a compile-only / translation-
  regression fixture (e.g. exercising `!true`, `<<`/`&`, record-update `A{l,..self}`, tuple-pattern Mapping
  closures inside a logic body) that clean translation IS the success state — count it PROVED, not FAILED. First
  `rm -rf verif target/creusot` so stale `.coma` artifacts from a prior scaffold don't give a misleading verdict.
- Heuristic: `cargo creusot new` always scaffolds a BIN crate (`src/main.rs`); a spec-only library fixture with
  no `fn main` fails rustc with `E0601: main function not found` before Creusot runs. Rename `src/main.rs` ->
  `src/lib.rs` to host such fixtures (template lints/deps already work as a lib).

### Spec-only logic-operator trait imports (`logic::ops::*Logic`) are a legitimate exception to "prelude only"
- Kind: ignore-signal
- Gate S: PASS
- Arose from: re-open batch 1 (cc/arithmetic.rs)
- Heuristic: the "only import `creusot_std::prelude`" rule has a carve-out for LOGIC-ONLY operator traits that
  the prelude does NOT re-export, e.g. `use creusot_std::logic::ops::NthBitLogic as _;` needed to call `.nth_bit()`
  inside a `proof_assert!`/`snapshot!`. These are spec-level (used only by ghost/logic code), strip clean with the
  attribute/assert that uses them, and do not violate the no-stray-executable-`use` intent. Same for other
  `logic::ops::*Logic` traits and `creusot_std::logic::{FSet, Mapping, Int, Seq}` paths. Import with `as _` when
  only the methods are needed. `#[bitwise_proof]` discharges assertion-only functions whose VCs are pure `nth_bit`
  bit-value facts (extends the existing SWAR/mask note).

### Trusted-only and `#[trusted]`-on-helper fixtures
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: re-open batch 1 (bug/trusted_static, bug/negative_int_pats)
- Heuristic: a regression fixture whose reference's sole annotation is `#[trusted]` on a module/item (e.g. a
  `#[global_allocator]`-bearing module) is faithfully restored by re-adding that `#[trusted]` — it is the
  reference's OWN spec content, not an escape hatch, and yields "No files to prove" (trusted suppresses obligation
  generation). Conversely, when the reference puts `#[trusted]` on a non-logic HELPER (e.g. a `Default`-returning
  stub) only to sidestep translating it, you may DROP the `#[trusted]` if Creusot translates the helper fine and
  the real proof_asserts still discharge — verify it was not load-bearing rather than copying it blindly.

### Logic opacity modifiers and ghost-check attribute port verbatim from creusot to creusot_std
- Kind: ignore-signal
- Gate S: PASS
- Arose from: re-open batch 2 (weak_opacity, opaque, snapshot_in_ghost, logic_vcgen)
- Heuristic: the opacity-argument forms `#[logic(open)]`, `#[logic(open(crate))]`, `#[logic(open(self))]`, and a
  bare closed-by-default `#[logic]` all port UNCHANGED to creusot_std; only the import header differs. A logic
  function's `#[ensures]` CONTRACT is visible to callers even when its BODY is closed (default-opaque) — so a
  `proof_assert!(f() == 1)` discharges against f's contract though f is not `open`. Use `open` (body visible) only
  when a caller's VC needs the definition, not just the contract.
- Heuristic: `#[check(ghost)]` is a strip-clean attribute required on a function that itself contains/forwards
  ghost `snapshot!`/`proof_assert!` code; restore it whenever the reference has it. `ghost!{}`, `snapshot!(..)`,
  `proof_assert!`, and `#[check(ghost)]` all strip clean, so a ghost-only fixture restores with zero executable
  change (the husk body may be empty even though a full ghost block is being added).
- Heuristic: a `#[logic]` function may take `&mut` arguments and reason over `*x` (current), `^x` (prophecy/final),
  and `@` (model) in its body/contract — write it `#[logic]` (or `#[logic(prophetic)]` when the body actually
  observes `^`). Logic-level closures support Mapping application as `map.get(x)` or index sugar `map[x]`.

### `#[logic(opaque)]` with `dead` body, `open(super)` visibility, and default-impl logic specialization
- Kind: ignore-signal
- Gate S: PASS
- Arose from: re-open batch 3 (traits/14, traits/16, termination/default_impl*, syntax/08)
- Heuristic: an OPAQUE logic function (declared `#[logic(opaque)]`) has the canonical body `dead` — used for a
  `View::view` whose model is abstract, or for round-trip/projection axioms over an associated type `T::Ty` in
  logic position. With an opaque View, `#[ensures(x@ == (*x)@)]` on a `&mut` closes immediately (only the
  entry-equality fact is available). Pair an intrinsically-axiomatic opaque fixture (a body-less `#[trusted] fn`
  carrying an `#[ensures]` that relates opaque logic fns) with the reference's own `#[trusted]` — it is the
  fixture's intended AXIOM, not an escape hatch, and yields "No files to prove".
- Heuristic: logic visibility modifiers extend beyond open/open(crate): `#[logic(open(super))]` exposes a logic
  method body to the parent module. `default impl<T> Trait for T { #[logic(open)] ... }` (trait specialization of
  logic methods) and qualified logic calls `<Self as Trait>::f()` port verbatim and emit no obligations when
  contract-free (clean "No files to prove").

### Robustness of a raw slice/index after a checked op: carry the length relation, don't re-guard
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: lace peimage.rs / chid_mapping.rs / gpt.rs / mbr.rs (creusot-monitoring lace run 20260617)
- Heuristic: an attack-surface parser that does a CHECKED op (`x.get(..n)`, `checked_mul`/`checked_add`)
  and THEN a RAW slice/index/arith using the same quantities (`&remaining[entry_length..]` after
  `body.get(..entry_length-H).is_some()`; `start + i*size` inside `for i in 0..n` after a pre-loop
  `n.checked_mul(size).and_then(|t| start.checked_add(t))`) is proven ROBUST by making the byte-model
  EXPLICIT so the length/no-overflow relation from the checked op is in scope — NOT by adding a guard.
  E.g. model `T::read_from_prefix(s)` as `if s.len() < SIZE_OF_T { Err } else { take SIZE_OF_T bytes }`,
  so `body.get(..body_len).is_some()` gives `remaining.len() >= entry_length` and the raw advance is
  in bounds; carry the pre-loop `validated == start + n*size` as a loop `#[invariant]` so `i < n`
  proves `start + i*size <= validated <= MAX`. Under SECURITY GATE C this is the ONLY admissible way:
  any `#[requires]` narrowing the adversarial input is REJECTED, so the proof must come from the
  parser's own checks. If the raw site has NO prior checked op establishing the relation (e.g. peimage
  `&dos_data[..e_lfanew - 64]` with nothing forcing `e_lfanew >= 64`; mbr `current_lba * sector_size`
  with no `checked_mul`), the VC is genuinely unprovable → that is a REFUTED bug, not a missing annotation.

### Documented-`unwrap()`/structural-bounds robustness: encode the field relation as a type Invariant
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: lace peimage.rs `PeRef::nth_section` (creusot-monitoring lace run 20260617)
- Heuristic: when a method's in-bounds safety rests on a STRUCTURAL relationship between a struct's
  fields (e.g. `PeRef.sect_hdrs.len() == number_of_sections * 40`, justifying a `.unwrap()` the source
  documents as "cannot panic"), do NOT add an input-restricting `#[requires]`. Instead declare an
  `impl creusot_std::invariant::Invariant for T { #[logic] fn invariant(self) -> bool { ... } }`
  capturing the relation; the CONSTRUCTOR (`parse_pe`) must then PROVE it on return (a real obligation,
  Gate-C-legal because it constrains the type, not the adversarial input), and every method gets it for
  free to discharge the slice/unwrap. Strips clean (whole `impl Invariant` removed by trait segment).
  This is the faithful way to verify a "this unwrap can't panic because the type guarantees it" comment.

### Surface a masked VC by expanding a vacuously-translated stdlib call (`div_ceil`)
- Kind: ignore-signal
- Gate S: PASS
- Arose from: lace peimage.rs `relocate_into` via `align_up!` (creusot-monitoring lace run 20260617)
- Heuristic: a stdlib method with NO creusot-std extern spec (here integer `div_ceil`) translates to a
  `{false}`/`absurd` block, making any VC over its result VACUOUS — a green proof that proves nothing,
  the dominant coherent-and-wrong for safety. When a parser's safety hinges on such a call, EXPAND it to
  primitive ops that carry their real VCs (`div_ceil(v,a)` → `let q=v/a; let r=v%a; if r>0 {q+1} else {q}` then `*a`)
  to surface the genuine division-by-zero and multiply-overflow obligations. Doing so on lace's `align_up!`
  exposed two real bugs (div-by-zero on `section_alignment==0`, u32 mul overflow). FAITHFUL only because
  it is the documented literal expansion of the project's own macro; flag the missing extern spec to
  getting-better/. NEVER trust an all-green result that routed through an unspecced stdlib call — check
  whether the call translated to `{false}` first.

### SMT trigger annotations and trait `#[law]` items port verbatim
- Kind: ignore-signal
- Gate S: PASS
- Arose from: re-open batch 4 (trigger.rs, traits/18_trait_laws)
- Heuristic: a quantifier trigger is written `forall<i, j> #[trigger(id(i), id(j))] (i <= j ==> ...)` — the
  `#[trigger(t1, t2)]` attaches to the bound body inside the `forall`/`exists` and ports unchanged from upstream
  creusot to creusot_std (it is a Pearlite-level annotation, no `creusot_std::logic` import needed). To USE a
  monotonicity/law lemma at a proof site, bring it into scope with `snapshot!(lemma_fn)`.
- Heuristic: a trait LAW is declared `#[logic(law)] #[ensures(...)] fn lemma(...)` in the trait and provided in
  the impl as `#[logic(open, law)] fn lemma(...)`; free-standing law lemmas are `#[logic(open)] #[ensures(result
  == true)]` with a pure `pearlite!` body. All are strip-removable, so a law-only fixture strips to an empty/
  comment-only husk and re-opens verbatim. The `Invariant` trait is at `creusot_std::invariant::Invariant` (not in
  the prelude) — import it explicitly when restoring an `impl Invariant`; it discharges under both `forall` and
  `exists` quantifiers over the invariant-bearing type.

### Loop offset `base + i*stride` proved from a parse-time table-fits invariant + a mul-monotonicity lemma
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: lace elf64.rs `for_each_phdr` (creusot-monitoring lace priority-2 run 20260617)
- Heuristic: a parser that pre-validates a table fits (`phoff.checked_mul... checked_add... <= data.len()`)
  and then walks it with a RAW `off = base + i*stride` (no checked op, `i` in `0..n`) is proven ROBUST by
  (1) encoding the fit relation as a TYPE invariant `impl creusot_std::invariant::Invariant for T {
  #[logic] fn invariant(self) -> bool { pearlite!{ self.base@ + self.n@ * self.stride@ <= self.data@.len() } } }`
  (Gate-C-legal: constrains the type, `parse` PROVES it on the returned `Self`), and (2) supplying a
  multiplication-monotonicity lemma to bridge `i < n` to `i*stride <= n*stride` — the SMT solvers do NOT
  derive monotonic multiply automatically. Write it as a PROVEN lemma (not trusted):
  `#[logic] #[requires(0 <= c)] #[requires(a <= b)] #[ensures(a*c <= b*c)] fn mul_mono(a:Int,b:Int,c:Int){}`
  and invoke it at the mul site `proof_assert!(mul_mono(i@, n@, stride@); i@*stride@ <= n@*stride@);`. Carry the
  loop invariant `base@ + i@*stride@ <= data@.len()`. This generalizes the gpt `checked_mul`-in-scope idiom to
  the case where the walk uses a raw multiply that must be bridged by an explicit monotonicity lemma.

### A caller-supplied closure that returns an ARBITRARY-length `&[u8]` needs no precondition; model it opaque
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: lace acpi/mod.rs `Rsdp::find_table(deref: impl Fn(u64,usize)->&[u8])` (lace priority-2 run 20260617)
- Heuristic: when robustness must hold for ANY behaviour of a caller-supplied `Fn`/`FnMut` that returns a
  borrowed slice of unconstrained length (a `deref`/resolver closure), do NOT try to constrain the closure's
  result — model its returned length as an opaque trusted getter (`#[trusted] fn deref_len(addr,len)->usize {}`
  returning an arbitrary value) and prove every slice access via the code's OWN runtime guard
  (`if off+k > slice.len() { break }`). The proof then holds for all closures with no closure precondition.
  The robustness comes entirely from the parser's bounds checks, which is exactly what Gate C demands. (Contrast
  with elf64 `for_each_phdr`, where the closure is CALLED and its `precondition`/`postcondition_mut` VC must be
  threaded — there the FnMut-precondition pair IS needed; the difference is "call the closure" vs "consume its
  returned slice".) Confirm the proof has TEETH with a negative control: weaken the `> slice.len()` guard to
  `> slice.len() + K` and check the slice-bounds VC goes RED — a green result through an unspecced closure that
  STAYS green when you break the guard is a rubber-stamp.

### Byte-string-reference constants `&[u8; N] = b"..."` fail Creusot translation — use a value array
- Kind: ignore-signal
- Gate S: PASS
- Arose from: lace edid.rs `HEXCHARS_LOWER`, smbios.rs `b"\0\0"` needle (lace priority-2 run 20260617)
- Heuristic: a `const X: &[u8; N] = b"...";` or an inline `b"\0\0"` byte-string LITERAL of reference type
  translate-fails with `error: Unsupported constant value: Scalar(allocN) of type &'{erased} [u8; N]`. This is a
  front-end translation error, NOT a proof obligation — no annotation suppresses it. Faithful workaround: replace
  the reference-to-array constant with a `[u8; N]` VALUE array (`const X: [u8;N] = [...];`) and an inline needle
  with a runtime `[0u8, 0u8]` local; indexing and all bounds reasoning are unchanged, so it strips/compares
  byte-equivalent. Also: `(1..=K).contains(&v)` (RangeInclusive::contains) has no applicable contract — rewrite as
  `v >= 1 && v <= K` (faithful, same branch condition). And the `(x & 0xF) as usize` array-index bound is
  discharged by factoring it into a `#[bitwise_proof] #[ensures(result@ < 16)] fn nibble(x)->usize { (x&0xF) as usize }`
  helper (the bitwise theory proves the mask bound that the default Int translation leaves open).
