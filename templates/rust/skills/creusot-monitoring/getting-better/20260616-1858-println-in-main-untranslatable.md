# `println!` in `main` blocks whole-crate `cargo creusot`

- **Trigger (files):** `bitvectors/bitwalker.rs`, `bitvectors/popcount.rs`,
  `bitvectors/rightmostbit.rs` (creusot-monitoring batch 4). Recurs across the
  `bitvectors/` corpus, all of which carry a demo `fn main` that prints.

## Observed behaviour
A `fn main` (or any fn) containing `println!("{...}", ...)` makes `cargo creusot`
hard-error for the **entire crate**:

```
error: Unsupported constant value: Scalar(alloc3) of type &[u8; 20]
```

(the byte-array length matches the format string). The error aborts compilation of
the whole crate, so even functions that verify cleanly cannot be discharged in the
same `cargo creusot` invocation. Every other (non-`println!`) function in the file
proves green when `main`'s body is isolated/emptied.

## Why it matters here
Under the creusot-monitoring faithfulness rule the sub-agent may not edit executable
code, so it cannot strip/replace the `println!` body. Upstream Creusot's own
`tests/should_succeed/bitvectors/*` resolve this by marking `fn main` `#[trusted]`,
but `#[trusted]` is a forbidden escape hatch in this loop. Result: such files can
only reach **PARTIAL** (substantive functions proved, crate gate blocked by the
driver), never all-green — purely an artifact of the demo driver, not the verified
code.

## Desired behaviour
Either (a) Creusot translates string-literal / format-string constants used by
`println!`/`write!` (lower them to opaque/abstract values rather than erroring on the
`&[u8; N]` constant), or (b) `cargo creusot` skips/abstracts `main` (or any fn it
cannot translate) with a *warning* instead of aborting the whole crate, so the
remaining obligations still discharge.

## Minimal example
```rust
fn rightmost_bit_8(x: i8) -> i8 { x & x.wrapping_neg() }  // proves fine alone

fn main() {
    println!("{}", rightmost_bit_8(12));  // <-- "Unsupported constant value &[u8; N]"
}
```
Removing only the `println!` line lets the crate verify; with it, `cargo creusot`
errors out before any obligation is checked.
