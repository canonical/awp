# Lace `peimage::relocate_into` — `align_up!` divide-by-zero and multiply overflow

- **Trigger:** creusot-monitoring lace attack-surface run, peimage.rs.
- **Confirmed by:** Creusot leaves two independent unproved VCs on `relocate_into`
  (`division by zero` and `integer overflow`); both vanish under the respective guard.
  Reproduced on rustc 1.96.0.

## Location
`lace/lace-util/src/peimage.rs:293-296` (inside `relocate_into`)
```rust
let virt_size = align_up!(
    shdr.virtual_size,
    self.nt_hdrs.optional_header.section_alignment
) as usize;
```
`align_up!(v, a)` expands to `v.div_ceil(a) * a` (lace-util/src/lib.rs:63).
`section_alignment` is read straight from the **adversarial** optional header and is never
checked.

## Bug A — divide-by-zero
`section_alignment == 0` ⇒ `virtual_size.div_ceil(0)` panics
("attempt to divide by zero") in **all** build profiles.
- Witness: a PE whose optional-header `section_alignment = 0` and at least one section.

## Bug B — multiply overflow (independent of A)
The `div_ceil(...) * section_alignment` step overflows `u32` when the rounded-up value
times the alignment exceeds `u32::MAX`.
- Witness: `virtual_size = u32::MAX`, `section_alignment = 0x1000` →
  `0x100000 * 0x1000 = 0x1_0000_0000 > u32::MAX`.
- **debug:** "attempt to multiply with overflow"; **release:** silently wraps to a wrong
  `virt_size` → subsequent `get_mut` copy/fill use a corrupted length (logic corruption,
  not just a panic).

## Impact
`relocate_into` lays out the image by virtual address (used by the PE loader path). A
crafted section header triggers a panic (A, B-debug) or a wrong-length memory layout
(B-release) before the OS runs.

## Suggested fix
Validate `section_alignment != 0` and use a checked multiply (or `checked_next_multiple_of`):
```rust
let a = self.nt_hdrs.optional_header.section_alignment;
if a == 0 { return Err(PeError::Truncated); }
let virt_size = shdr.virtual_size
    .checked_next_multiple_of(a)
    .ok_or(PeError::Truncated)? as usize;
```
