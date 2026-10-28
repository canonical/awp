# Lace `fs::mbr::parse_ebr_chain` — `current_lba * sector_size` u64 multiply overflow

- **Trigger:** creusot-monitoring lace attack-surface run, mbr.rs (priority-1 partition parser).
- **Confirmed by:** Creusot proves the whole EBR chain green **except** one unproved VC —
  the line-128 raw `u64` multiply (`UInt64.mul {current_lba} {ss}`). Guarding it with
  `checked_mul` closes all 42 goals. The other two raw adds (lines 138, 147) were proven
  safe.

## Location
`lace/lace-platform/src/fs/mbr.rs:128` (inside `parse_ebr_chain`)
```rust
let ebr = match read_mbr_sector(dev, current_lba * sector_size) {
```
A **raw `u64` multiply** with no checked guard; both operands are attacker-controlled.

## Why it is reachable
- First iteration: `current_lba = ebr_lba <= u32::MAX`, `sector_size <= u32::MAX`, product
  fits in u64.
- But line 147, `current_lba = extended_start + next.lba_start.get() as u64`, grows
  `current_lba` to up to `2*(2^32 - 1) = 2^33 - 2` — **beyond u32**. On the next iteration
  the multiply overflows u64.

## Minimal adversarial input (malicious USB stick / disk image)
- `extended_start = 0xFFFF_FFFF`, slot-1 EBR link `lba_start = 0xFFFF_FFFF`
  ⇒ `current_lba = 0x1_FFFF_FFFE` (8 589 934 590)
- `sector_size = 0xFFFF_FFFF`
- product `= 36 893 488 130 239 234 050 > u64::MAX` → panic (debug) / silent wrap (release).
- Requires valid `0x55AA` signatures at the two EBR offsets so reads don't bail early —
  fully on-disk-controllable.

## Impact
Pre-OS **panic / DoS** (or a wrapped offset reading the wrong sector, in release) in the
MBR partition parser, reachable from any disk Lace probes (`fs::probe`).

## Suggested fix
Mirror the GPT parser's own `checked_mul` (gpt.rs:84):
```rust
let off = current_lba.checked_mul(sector_size as u64).ok_or(FsError::Invalid)?;
let ebr = match read_mbr_sector(dev, off) { ... };
```
