# `creusot_std::prelude` re-exports a `vec!` that shadows std's → glob import is ambiguous

- **Trigger:** annotate/bug/874.rs (creusot-monitoring batch 7). Confirmed against L:
  the file genuinely cannot be carried to Proved without editing executable code.
- **Observed behaviour:** Creusot refuses to verify a file unless
  `use creusot_std::prelude::*;` is present (it emits "The creusot_std crate is not
  loaded … you will not be able to verify"). But that prelude glob re-exports its own
  `vec!` macro, which collides with `std::prelude`'s `vec!`. Any pre-existing call site
  using the bare `vec![...]` macro then fails to compile with
  `error[E0659]: vec is ambiguous`. The only compiler-suggested fixes
  (`use std::vec;`, `crate::vec!`, swapping to the `creusot_std` vec constructor) all
  add a second `use` or rewrite executable code — both forbidden under the faithfulness
  rule (they strip as added/changed code → FABRICATED). Net: with the mandatory prelude
  the file won't compile; without it Creusot won't verify. Verdict forced to FAILED.
- **Desired behaviour:** the prelude's `vec!` should glob-import without shadowing std's
  — e.g. (a) don't re-export a `vec!` that collides with `std`'s, (b) make the
  re-export a passthrough so a glob import stays unambiguous, or (c) special-case the
  std `vec!` macro in translation so existing source verifies as-is.
- **Minimal example:**
  ```rust
  use creusot_std::prelude::*;        // mandatory for verification
  pub fn f() -> Vec<i32> { vec![1, 2, 3] }   // error[E0659]: vec is ambiguous
  ```
- **Relation to existing notes:** distinct from
  `20260616-1739-prelude-clone-derive-ambiguous.md` (that one is the derive-macro
  `Clone`). Same root cause class (prelude glob shadows a std item), but the `vec!`
  macro is a separate, very common call site, so it warrants its own entry. The
  annotator-side guidance ("Adding `use` for macro disambiguation is a faithfulness
  FABRICATION") already tells the base loop to report PARTIAL/FAILED rather than invent
  a `use`; this note routes the underlying tooling gap to the Creusot team.
