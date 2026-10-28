# creusot-std has no extern spec for integer `div_ceil` (forces macro expansion)

- **Trigger:** lace attack-surface run — `peimage::relocate_into` via `align_up!` macro
  (`v.div_ceil(a) * a`), and `gpt.rs` test helpers.
- **Confirmed against L:** a direct `u32::div_ceil(a)` call translates to an unreachable
  `{false}` / `absurd` block, so any VC over its result is vacuous and the real
  division-by-zero / overflow obligations are NOT surfaced. The annotator had to manually
  expand `align_up!` to primitive `let q=v/a; let r=v%a; let dc=if r>0 {q+1} else {q}; dc*a`
  to make Creusot emit the genuine `div by zero` and `mul overflow` VCs (which then
  exposed two real bugs — see bugs-to-report 20260617-1117 peimage align_up).

## Observed behaviour
`{u32,u64,usize,i32,…}::div_ceil` have no extern spec in creusot-std 0.13.0-dev. Calls
translate to a `{false}`-guarded block (treated as unreachable), silently masking the
div-by-zero precondition and the multiply-overflow that `div_ceil` semantically carries.

## Desired behaviour
Add an extern spec for integer `div_ceil`:
- `#[requires(rhs@ != 0)]`
- `#[ensures(result@ == (self@ + rhs@ - 1) / rhs@)]`
- with the implicit-add overflow VC retained.

## Why it matters
`div_ceil` is the backbone of alignment helpers (`align_up!`,
`count_blocks_aligned_up!`) used pervasively in bootloader offset math. Without the extern
spec these helpers either can't be verified (false sense of safety from the vacuous
translation) or must be hand-expanded per call site (unfaithful / error-prone). The
hand-expansion in this run is what surfaced the `section_alignment == 0` divide-by-zero
and the multiply overflow in `relocate_into`.
