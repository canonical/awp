# `#[variant]` silently ignored without `#[check(terminates)]`

- **Trigger:** `creusot-monitoring` run, file `mc91.rs` — annotator added `#[variant(101 - x@)]`
  to a recursive `fn` intending to prove termination.
- **Observed:** Creusot emits only a *warning* ("variant will be ignored") and proceeds;
  the proof reports `Proved ✔` for partial correctness while **termination is never
  checked**. A reader sees green and reasonably (but wrongly) believes termination was
  proved.
- **Desired:** make a `#[variant]` on an executable function that lacks
  `#[check(terminates)]` an **error** (or a deny-by-default lint), so a termination
  measure cannot be silently dropped. At minimum, surface it prominently in the
  `cargo creusot` summary rather than as an easy-to-miss warning.
- **Minimal example:**
  ```rust
  #[variant(101 - x@)]                 // silently ignored -> termination NOT checked
  pub fn mc91(x: u32) -> u32 { if x > 100 { x - 10 } else { mc91(mc91(x + 11)) } }
  // fix today: add `#[check(terminates)]` above the #[variant]
  ```
- **Guidance link (U):** "specify thoroughly" — a thorough spec that *intends* total
  correctness should not be able to lose its termination obligation without an error.
