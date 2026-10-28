# Creusot: `in_bounds_Range_usize` requires for `&s[i..e]` not discharged
even when the identical bound facts prove as assertions

Date: 2026-06-17
Surfaced while: verifying `lace-util/src/lib.rs::find_byte_sequence` (robustness).

## Setup
```rust
while i < n {                       // n = s.len() - sub.len() + 1
    let e = i + sub.len();
    proof_assert!(i@ <= e@ && e@ <= s@.len());   // <-- PROVES (green)
    let window: &[u8] = &s[i..e];                // <-- index_requires FAILS (red)
    if window == sub { return Some(i); }
    i += 1;
}
```
Loop invariants supplied:
- `i@ <= n@`
- `n@ + sub@.len() == s@.len() + 1`
- `i@ < n@ ==> i@ + sub@.len() <= s@.len()`

## Symptom
The generated index VC is exactly
`in_bounds_Range_usize {start=i; end'=e} (view s)`
which unfolds to `i <= e /\ e <= len(s)`.

The `proof_assert!(i@ <= e@ && e@ <= s@.len())` placed on the line immediately
above PROVES. The `index requires` VC (same straight-line block, no mutation of
`i`,`e`,`s` in between) does NOT prove — with alt-ergo / z3 / cvc5 / cvc4 at
fast=10, time=30s, depth=12. Score stuck at N-1/N with `index requires` the
sole red goal.

## Diagnosis
A solver-reachability / context gap specific to the slice-range `in_bounds`
predicate on an `any`-call requires position. The fact is provable (proof_assert
witnesses it) but the requires goal for `index_slice_u8` is generated in a
context where the solver does not retrieve it. Tried: strengthening invariants,
binding `e` to force the add-overflow VC, hoisting the slice to a `let window`,
multiple proof_asserts in machine (`e@`) form. None close the requires goal.

## Status
The function is bounds-SAFE (mathematically): the proof_assert discharging the
exact precondition is green. Only the auto-generated `index requires` resists
the bundled SMT solvers. Verdict recorded as PARTIAL, not REFUTED — there is no
counterexample; it is an incompleteness, not an unsoundness.

## Routes to try next
- Use `s.get(i..e)` (returns Option) + match, avoiding the panicking index.
- Provide a `#[logic]` lemma `forall i e. i<=e -> e<=len -> in_bounds ...` and
  invoke via proof_assert to seed the trigger.
- Try a manual byte-by-byte inner comparison loop generating only single-element
  `s[i+k]` index VCs (`i+k < e <= len`) instead of the Range predicate.

## Update (same run): `s.get(i..e)` removes the index-requires but a residual
## `i + sub.len()` add-overflow VC and an `Option<_>` result type-invariant VC
## remain solver-sensitive
Switching `&s[i..e]` to `match s.get(i..e)` eliminates the `index requires`
(it becomes a non-panicking `get ensures`). After that, `find_byte_sequence`
proves to 14/15 — the sole residual red is the `UInt64.add` overflow VC for
`e = i + sub.len()`, even with the supporting invariant
`i@ < n@ ==> i@ + sub@.len() <= s@.len()` and three passing proof_asserts
(`i@+sub@.len() <= s@.len()`, `s@.len() <= usize::MAX@`,
`i@+sub@.len() <= usize::MAX@`). The supporting facts PROVE; the consuming
add-overflow VC does not, with alt-ergo/z3/cvc5/cvc4 at fast up to 12, time up
to 30s, depth up to 12. Likewise `Guid::try_from_str`'s only VC (the
`Option<Guid>` result type-invariant — there are NO index VCs; the `len()==36`
guard discharges `bytes[8/13/18/23]` statically) flickers green/red across
budgets. Both are incompleteness, not counterexamples.

## Impact on monitoring
When a slice-RANGE index requires (or the dependent add-overflow / result
type-invariant) stays red while a co-located proof_assert of the same
inequality goes green, classify the function PARTIAL (solver gap), do NOT
report it as a REFUTED runtime panic. These VCs also flip between green and red
purely on `fast`/`depth`/`time` budget — treat such functions as PROVABLE-with-
effort / PARTIAL, never REFUTED.
