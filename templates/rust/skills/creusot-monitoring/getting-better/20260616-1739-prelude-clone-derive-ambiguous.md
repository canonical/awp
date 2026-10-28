# `use creusot_std::prelude::*;` + `#[derive(Clone)]` is ambiguous (E0659)

- **Trigger:** `creusot-monitoring` batch 1, file `bug/02_derive.rs` (a `#[derive(Clone)]` on an empty struct).
- **Observed:** the canonical pattern — `use creusot_std::prelude::*;` plus a bare
  `#[derive(Clone)]` — fails to compile: `error[E0659]: Clone is ambiguous`, because the
  Creusot prelude re-exports a `Clone` derive macro that collides with the std-prelude
  `Clone`.
- **Desired:** the recommended `prelude::*` import should not make the std derives
  ambiguous; either don't glob-export the colliding derive, or document the
  disambiguation (`use creusot_std::prelude::Clone;` or `#[derive(creusot_std::prelude::Clone)]`)
  prominently.
- **Minimal example:**
  ```rust
  use creusot_std::prelude::*;
  #[derive(Clone)] pub struct Lit {}   // error[E0659]: `Clone` is ambiguous
  ```
- **Guidance link (U):** "specify thoroughly" — users following the documented prelude
  pattern shouldn't hit a compile error on the most common derive.
