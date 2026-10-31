---
name: creusot
description: >-
  Annotate Rust programs with Pearlite specifications for verification with
  Creusot (the deductive verifier that translates Rust to Why3 and discharges
  proof obligations with SMT solvers). Covers function contracts
  (#[requires]/#[ensures]), the model/view operator @, the prophecy operators *
  and ^ for &mut, loop invariants #[invariant], termination #[variant], logic
  functions #[logic], predicates, laws, proof_assert!, snapshot!/ghost! code,
  type invariants, the View/DeepModel traits, the Int/Seq/Mapping/FSet logical
  types, and the escape hatches (#[trusted], assume!, extern_spec!) with their
  soundness cost. Use whenever the user wants to "add a Creusot spec", "write
  Pearlite", "annotate this Rust for verification", "add requires/ensures", "add
  a loop invariant", "prove this Rust function correct", "specify sortedness /
  permutation / bounds", asks why a proof obligation won't discharge, or asks
  what @, ^, forall, ==>, Int, or Seq mean in a Creusot spec.
---

# Annotating Creusot programs with Pearlite

Creusot verifies Rust by translating it (plus its specifications) into the Why3
platform, computing verification conditions, and discharging them with SMT
solvers (Alt-Ergo, Z3, CVC4, CVC5). You write specifications in **Pearlite**, a
pure, immutable fragment of Rust extended with logical connectives. This skill is
the reference for *writing those annotations correctly*.

Run the verifier with `cargo creusot` in a project (scaffold one with
`cargo creusot new <name>` / `init`). A function is verified when its obligations
report `Proved … ✔`.

## Installing Creusot

Creusot installs from its repository with its own `./INSTALL`, which builds
`cargo-creusot`, its pinned Rust nightly, Why3, why3find and the provers
(Alt-Ergo, Z3, CVC4, CVC5). In short:

```sh
opam init --disable-sandboxing -y --bare
curl -sSf https://sh.rustup.rs | sh -s -- -y && . ~/.cargo/env
git clone https://github.com/creusot-rs/creusot.git ~/git/creusot
cd ~/git/creusot && git checkout f15b985 && ./INSTALL     # an hour or more
cargo creusot version                                      # lists Why3, why3find and the four provers
```

Keep `~/git/creusot` where it is: `./INSTALL` points `~/.cargo/config.toml`
at it. Never create a Creusot project under another `Cargo.toml`:
`cargo creusot new` then writes `why3find.json` next to that parent manifest.
The system packages, the AppArmor fix needed inside an LXD container, the
tested versions, the smoke test and the workaround for a parent `Cargo.toml`
are in **`references/install.md`**.

## Preamble every file needs

```rust
extern crate creusot_std;
use creusot_std::prelude::*;
// for the logical types when you name them explicitly:
use creusot_std::logic::{Int, Seq};
```

The contract attributes (`requires`, `ensures`, `invariant`, …) and macros
(`proof_assert!`, `snapshot!`, `ghost!`, `pearlite!`) come from the prelude.

## 1. Function contracts

- `#[requires(P)]` — a precondition. Repeatable; multiple are conjoined.
- `#[ensures(Q)]` — a postcondition. Repeatable. The return value is named
  `result` by default.

```rust
#[requires(arr@.len() <= usize::MAX@)]
#[requires(sorted(arr@))]
#[ensures(forall<x: usize> result == Ok(x) ==> arr[x@] == elem)]
pub fn binary_search(arr: &Vec<u32>, elem: u32) -> Result<usize, usize> { /* … */ }
```

Rename or destructure the result with a closure-style binder:

```rust
#[ensures(|resultat| v@[0] == resultat)]   // bind result as `resultat`
#[ensures(|(fst, snd)| fst <= snd)]         // destructure a tuple result
```

## 2. The model operator `@`, and `*` / `^` for references

These three operators are the heart of Creusot specs.

- **`@` — the logical model (view)** of a value. `x@` desugars to `x.view()`.
  It maps a concrete Rust value to the mathematical object you reason about:
  `i32`/`u32`/`usize` → **`Int`** (unbounded), `Vec<T>`/`&[T]`/`[T]` → **`Seq<T>`**,
  `bool` → `bool`. Use it constantly: `x@ < usize::MAX@`, `v@.len()`, `arr[i@]`.
- **`*x` — the current value** of a reference (`&T` or `&mut T`) in specs.
- **`^x` — the *final* value** of a mutable borrow `&mut T` (its prophesied value
  when the borrow ends). This is Creusot's **prophecy model**: a `&mut T` is a
  pair `(current, final)`, written `(*x, ^x)`.

```rust
#[requires(*g < i32::MAX)]
#[ensures((^g)@ == (*g)@ + 1)]   // the final value's model is the current's + 1
fn add_one(g: &mut i32) { *g += 1; }
```

For a `&mut Vec<T>`, `v@` is the current sequence and `(^v)@` is the final one:

```rust
#[ensures(array@.permutation_of((^array)@))]   // final is a permutation of initial
#[ensures(sorted((^array)@))]                   // final is sorted
pub fn insertion_sort(array: &mut [i32]) { /* … */ }
```

## 3. Pearlite expression language

Pearlite is pure Rust expressions plus logical extensions:

- **Quantifiers:** `forall<x: T> BODY` and `exists<x: T> BODY`. The type can be
  inferred: `forall<i, j> …`. Bind the index type to `Int` for arithmetic:
  `forall<i: Int> 0 <= i && i < s.len() ==> s[i] == 0`.
- **Implication:** `==>` (Rust's `=>` is taken). `&&`, `||`, `!` as usual.
- **Logical equality:** `==` (this is *logical* equality, not `PartialEq::eq`).
- **Indexing:** `s[i]` on a `Seq`/`Mapping`, `arr[i@]` to index a viewed slice by
  an `Int`.
- **Logical types:** `Int` (unbounded integer), `Seq<T>`, `Mapping<K, V>`,
  `FSet<T>` (finite set), `Set<T>`. `Seq::len()` returns an `Int`.
- **`pearlite! { … }`** — wrap a block to enable Pearlite syntax inside a
  `#[logic]` body or a macro.

```rust
proof_assert!(false ==> true);   // vacuously true
```

## 4. Loops: invariants and termination

Place `#[invariant(...)]` attributes **immediately before** the `for` / `while` /
`loop`. Each must hold on entry and be preserved by every iteration. Repeatable.

```rust
#[invariant(0 < size@ && size@ + base@ <= arr@.len())]
#[invariant(forall<i: usize> i < base ==> arr[i@] <= elem)]
while size > 1 { /* … */ }
```

In a **`for` loop**, the snapshot `produced` holds the sequence of elements
yielded so far — use it to phrase progress:

```rust
let original = snapshot!(*array);
#[invariant(sorted_range(array@, 0, produced.len() + 1))]
#[invariant(original@.permutation_of(array@))]
for i in 1..n { /* … */ }
```

**Termination (total correctness)** is opt-in:

- `#[variant(EXPR)]` on a loop or recursive function — `EXPR` must strictly
  decrease (its type must implement `WellFounded`; `Int`/`usize` work).
- `#[check(terminates)]` on a function requires it to terminate: every loop needs
  a `#[variant]`, and it may only call other terminating functions. Without it,
  Creusot proves *partial* correctness (postcondition holds **if** the function
  returns).

```rust
#[logic]
#[variant(x)]
fn recursive_add(x: Int, y: Int) -> Int {
    if x == 0 { y } else { recursive_add(x - 1, y + 1) }
}
```

## 5. In-body assertions, snapshots, ghost code

- **`proof_assert!(P);`** — inserts a proof obligation `P` at that program point.
  Erased at runtime; `P` may use full Pearlite.
- **`snapshot!(EXPR)`** — captures an immutable logical `Snapshot<T>` of a value
  for use in later specs/invariants. Deref/`@` it in specs.
- **`ghost!{ … }`** / **`Ghost<T>`** — runtime-erased ghost *computation* (more
  powerful than a snapshot; can be mutated inside `ghost!`). Functions called from
  `ghost!` need `#[check(ghost)]` and must terminate.

```rust
proof_assert!(sorted_range(array@, 0, array@.len()));
let mut g = ghost!(50);
ghost! { *g *= 2; };
proof_assert!(g@ == 100);
```

`Snapshot<T>` = immutable, usable in `#[logic]` and `snapshot!`. `Ghost<T>` =
owns ghost state, mutable only inside `ghost!`. Reach for a snapshot first.

## 6. Logic functions, predicates, laws

`#[logic]` defines a **pure logical function**, callable only from specs,
`snapshot!`, and other logic functions — never from executable code. Use it to
name and reuse predicates.

```rust
#[logic(open)]
pub fn sorted_range(s: Seq<u32>, l: Int, u: Int) -> bool {
    pearlite! { forall<i, j> l <= i && i < j && j < u ==> s[i] <= s[j] }
}
```

Modifiers (combine with commas, e.g. `#[logic(open, prophetic)]`):

- `#[logic(open)]` — body is **visible** to the prover at call sites outside the
  module. Restrict with `open(crate)` / `open(super)`. **Without `open`, the body
  is opaque** and only the function's own contract is known to callers — a very
  common reason a downstream proof won't go through.
- `#[logic(opaque)]` — body fully hidden (only its contract). The one place the
  `dead` keyword is allowed (a body you never define).
- `#[logic(prophetic)]` — may use `^` (final values); cannot be called from
  `snapshot!`.
- `#[logic(inline)]` — inlined into proof obligations.

A `#[logic]` returning `bool` is a **predicate**. Logic functions may carry their
own `#[requires]`/`#[ensures]` and `#[variant]` (for recursion).

A **lemma** is a logic function used for its postcondition; a **law** is a lemma
auto-loaded into the proof context, declared on a trait method with
`#[logic(law)]`:

```rust
#[logic(law)]
#[ensures(self.op(other) == other.op(self))]
fn commutative(self, other: Self);
```

## 7. Type invariants

Implement `Invariant` so every value of a type carries a property — Creusot adds
it as a precondition on arguments and a postcondition on results automatically.

```rust
impl Invariant for SumTo10 {
    #[logic]
    fn invariant(self) -> bool { pearlite! { self.a@ + self.b@ == 10 } }
}
```

Invariants compose structurally (tuples, structs, enums, `&T`, `&mut T` over both
`*` and `^`, `Vec<T>` elementwise). Note: `#[logic]` functions do **not** receive
type invariants on their arguments.

## 8. Models: `View` and `DeepModel`

- **`View` (`@`)** — a shallow logical model. Implement `view` (as `#[logic]`) to
  give your type an `@`. Standard: `Vec<T>`/`[T]` → `Seq<T>`, integers → `Int`.
- **`DeepModel` (`.deep_model()`)** — a model that recurses into contained values,
  used when you need *value* equality/order under generics (e.g. sorting `T: Ord`).

```rust
#[ensures(sorted((^v).deep_model()))]
#[ensures((^v)@.permutation_of(v@))]
pub fn gnome_sort<T: Ord + DeepModel>(v: &mut Vec<T>) { /* … */ }
```

## 9. Common idioms

- **Sortedness:** a `#[logic]` predicate with `forall<i,j> i<j ==> s[i] <= s[j]`.
- **Permutation:** `a@.permutation_of(b@)` (from the prelude) — the workhorse for
  sorting/reordering postconditions.
- **Bounds in invariants:** quantify over indices, e.g.
  `forall<i: usize> i < base ==> arr[i@] <= elem`.
- **Remembering the input:** `let original = snapshot!(*x);` then refer to
  `original@` in invariants.
- `#[maintains(...)]` (from `creusot_std`) is a shorthand combining a `*`-form
  precondition and a `^`-form postcondition over a `&mut` argument.

## 10. Escape hatches — and their soundness cost

These make obligations vanish instead of discharging them. **Each one you add to a
target is a hole in the proof**; treat adding one as a finding, not a fix, and
never reach for one silently to make a stubborn VC pass.

- `#[trusted]` — skips verification of the body; its contract is *assumed*. Puts
  the function in the trusted computing base. Also applies to `proof_assert!` to
  turn an assertion into an assumption.
- `assume!(P)` — injects `P` as a hypothesis with no proof. Unsound if `P` is
  false; the most dangerous hatch.
- `extern_spec! { … }` — attaches `#[requires]`/`#[ensures]` to functions from
  other crates (e.g. std). Sound only if the spec faithfully models the real
  function — an over-strong `ensures` here silently corrupts everything that calls
  it.
- `#[law]` / opaque axioms — an `#[ensures]` with no proof obligation behind it.

When a proof won't close, the sound moves are: **strengthen** the loop invariant,
open a `#[logic(open)]` body the prover can't see, add an intermediate
`proof_assert!` to guide the solver, or split the lemma — not weaken the contract
or assume the goal. A contract may legitimately be made *stronger* than required;
making it *weaker* to land is a bug. (See the `creusot-sl` loop in
the `creusot-sl` skill (`config/skills/creusot-sl/SKILL.md`): a
vacuously-true contract that discharges is the dominant "coherent-and-wrong"
failure.)

## 11. Worked example (read top to bottom)

```rust
extern crate creusot_std;
use creusot_std::{logic::{Int, Seq}, prelude::*};

#[logic(open)]
pub fn sorted_range(s: Seq<u32>, l: Int, u: Int) -> bool {
    pearlite! { forall<i, j> l <= i && i < j && j < u ==> s[i] <= s[j] }
}
#[logic(open)]
pub fn sorted(s: Seq<u32>) -> bool { sorted_range(s, 0, s.len()) }

#[requires(arr@.len() <= usize::MAX@)]   // no length overflow
#[requires(sorted(arr@))]                 // caller guarantees a sorted input
#[ensures(forall<x: usize> result == Ok(x) ==> arr[x@] == elem)]   // Ok ⇒ found here
#[ensures(forall<x: usize> result == Err(x) ==>
    forall<i: usize> i < x ==> arr[i@] <= elem)]                    // Err ⇒ insertion point
pub fn binary_search(arr: &Vec<u32>, elem: u32) -> Result<usize, usize> {
    if arr.len() == 0 { return Err(0); }
    let mut size = arr.len();
    let mut base = 0;

    #[invariant(0 < size@ && size@ + base@ <= arr@.len())]
    #[invariant(forall<i: usize> i < base ==> arr[i@] <= elem)]
    #[invariant(forall<i: usize> base@ + size@ < i@ && i@ < arr@.len() ==> elem < arr[i@])]
    while size > 1 {
        let half = size / 2;
        let mid = base + half;
        base = if arr[mid] > elem { base } else { mid };
        size -= half;
    }
    let cmp = arr[base];
    if cmp == elem { Ok(base) } else if cmp < elem { Err(base + 1) } else { Err(base) }
}
```

## 12. Gotchas

- Use `==>` not `=>`; `==` in specs is logical equality.
- Reason about `@` models, not raw machine values: write `x@ + 1 <= y@`, and bound
  with `usize::MAX@` to discharge overflow obligations.
- A `#[logic]` body the prover can't see (not `open`) is the most common cause of
  a stuck downstream proof — open it or expose a lemma about it.
- `for`-loop invariants almost always need `produced` to state progress.
- The std `vec!` macro isn't supported as-is (see the guide's *limitations*); use
  the `creusot_std` vec constructor.
- Partial vs total correctness: without `#[check(terminates)]`/`#[variant]`, a
  proof says nothing about termination.
- Proofs are validated for the target architecture (integer widths matter).

## Functional specs, not just safety

Proving "no panic / overflow / out-of-bounds" is necessary but **not the whole job** — a
function can be fully safe yet still carry a *functional* obligation worth proving, and a
large class of code has its entire verification content at the **spec level** with no
safety VC at all. **Do not equate "nothing can panic/overflow/index" with "nothing to
verify."**

- After safety, state the **functional intent**: a constant-returning fn deserves
  `#[ensures(result@ == K)]`; a selector deserves `result == a || result == b`; a `&mut`
  function deserves its prophecy postcondition (`^x`) — none of which computes anything
  that can fault, yet each is a real obligation.
- **Spec-only items ARE the verification target** in many units: `#[logic]` functions and
  their `#[logic(law)]` laws, `View`/`DeepModel`/`Invariant` impls, `proof_assert!` and
  prophecy lemmas, and pure functional `#[ensures]` emit *no* panic/overflow obligation but
  are exactly what such a unit exists to establish. **An empty-bodied function or a
  struct-only file is not automatically trivial** — check whether the intended content is a
  logical definition, a law, or a model before concluding there is nothing to prove.
- **Prefer proving over `#[trusted]`.** Where an existing annotation leans on `#[trusted]`
  to *assume* a fact, a discharged `#[requires]`/`#[ensures]`/`#[variant]` that *proves* it
  is strictly stronger (less trusted code) — drop the hatch whenever the obligation is
  dischargeable.

*(Provenance: the 241-file comparison against the Creusot reference suite —
`annotate/COMPARISON-SUMMARY.md` — found that safety-only triage systematically dropped
this spec-demonstration content; ~44 files marked "trivial" were missing the reference's
`#[logic]`/law/`impl` scaffolding.)*

## Learned knowledge (creusot-sl) — reference files

The `creusot-sl` loop (the `creusot-sl` skill (`config/skills/creusot-sl/SKILL.md`)) capitalizes role-scoped heuristics
into this skill after each file is verified. Load the file for your role at the start
of a run; append to it only through **Gate S** (`sl-monitoring-sl`) — a disjoint
monitor audits each proposed heuristic against the requirement `U` and `cargo creusot`
`L`, and only PASS/CARVE-OUT entries are kept, with provenance. The `spec-author` and
`verifier` files must never contain implementation specifics (those roles are
barriered from the code).

- `references/learned-coordinator.md` — judgment/gate heuristics (clause-typing,
  NOT-claims, when to cut a DRAFT).
- `references/learned-spec-author.md` — requirement→Pearlite patterns (requirement-level only).
- `references/learned-annotator.md` — proof-scaffolding patterns (invariant templates,
  ghost idioms, prover tips).
- `references/learned-verifier.md` — adversarial-property & mutation patterns.

## Source of truth

This summarizes the Creusot guide (`guide/src/` in the creusot repo:
`pearlite.md`, `basic_concepts/*`, `logic_functions/*`, `ghost.md`,
`snapshots.md`, `view.md`, `type_invariants.md`, `termination.md`, `trusted.md`,
`limitations.md`) and the `examples/*.rs`. When a detail is load-bearing or looks
to have changed, verify against the installed guide and `cargo creusot version`.
```
