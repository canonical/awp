# `#[check(terminates)]` errors on polymorphic recursion

- **Trigger (file):** `bug/2022.rs` (creusot-monitoring batch 5). The Creusot issue
  #2022 reproducer.

## Observed behaviour
A non-`#[logic]` recursive function whose recursive call changes its generic type
argument (polymorphic recursion):

```rust
pub fn f<T>(x: usize) {
    if x == 0 { f::<usize>(1) }   // f<T> calls f::<usize>
}
```

- **Partial correctness** verifies trivially (`f.coma` Proved, zero annotations).
- The moment `#[check(terminates)]` is added (mandatory — a lone `#[variant]` is
  *silently ignored* on a non-`#[logic]` fn, see learned-annotator.md), Creusot
  **aborts the front-end** with:

  ```
  Polymorphic recursion is not supported: recursive calls should have the same
  type parameters.
  ```

  This is a hard error before any VC is produced — not an ordinary "unproved"
  obligation.

## Why it matters
Under the loop's faithfulness rule the sub-agent cannot rewrite the `f::<usize>`
call to monomorphic form, so termination simply **cannot be annotated** for such a
function. The file is forced to TRIVIAL/PARTIAL (partial correctness only), which
under-specifies it relative to the "prove termination where intended" guidance,
purely because of the tool limitation.

## Desired behaviour
Either (a) Creusot supports termination checking for polymorphic recursion (the
common case is a measure that decreases independent of the type argument), or (b)
`#[check(terminates)]` on a polymorphic-recursive fn yields a normal *unproved
termination VC* (which the user can then discharge or accept) instead of a
front-end abort.

## Minimal example
The 3-line `f<T>` above, with and without `#[check(terminates)]`.
