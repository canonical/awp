# Lace `peimage::parse_pe` — `e_lfanew - 64` subtraction underflow (panic on crafted PE)

- **Trigger:** creusot-monitoring lace attack-surface run, peimage.rs (priority-1 PE parser).
- **Confirmed by:** Creusot leaves exactly one `integer overflow` VC unproved on `parse_pe` (`vc_parse_pe`, 30/31); adding `if e_lfanew < 64 { Err }` closes all goals — proving the gap is precisely the missing `e_lfanew >= size_of::<DosHeader>()` fact. Reproduced on real rustc 1.96.0 (panic in debug AND release).

## Location
`lace/lace-util/src/peimage.rs:223`
```rust
let dos_data = &dos_data[..dos_hdr.e_lfanew as usize - size_of::<DosHeader>()];
```
This is a **raw slice** (not `.get()`) whose end index is an **unchecked subtraction** `e_lfanew - 64`.

## Why it is reachable
Nothing on the path forces `e_lfanew >= 64`. The earlier
`s.get(e_lfanew..).and_then(|s| NtHeaders64::read_from_prefix(s).ok())`
only requires `s.len() - e_lfanew >= 264` (room for the NT headers at offset `e_lfanew`);
it says nothing about `e_lfanew` versus the DOS-header size (64). An attacker can place
the NT headers at a small offset that **overlaps** the DOS-header region.

## Minimal adversarial input
A **274-byte** buffer:
- `"MZ"` (DOS_SIGNATURE) at offset 0
- `e_lfanew = 10` (u32 LE at offset 60)
- NT signature `"PE\0\0"` at offset 10
- `size_of_optional_header = 240` (u16 LE at offset 10+20 = 30)
- optional-header `magic = 0x20b` (u16 LE at offset 10+24 = 34)
- `number_of_sections = 0` (u16 LE at offset 10+6 = 16)

Passes every validation, reaches line 223 where `10 - 64` underflows.
- **debug:** `panicked: attempt to subtract with overflow`
- **release:** subtraction wraps to `18446744073709551562`, then `&dos_data[..HUGE]` →
  `panicked: range end index … out of range for slice of length 210`.

## Impact
Pre-OS, pre-Secure-Boot-measurement **panic / DoS** in the PE parser used by
`lace-stubble`, `lace-platform`, and `pewrap`. A malformed `.efi` on the ESP (or any PE
handed to `parse_pe`) aborts the bootloader.

## Suggested fix
Use a checked subtraction / `.get()`:
```rust
let dos_data = dos_data
    .get(..(dos_hdr.e_lfanew as usize).checked_sub(size_of::<DosHeader>()).ok_or(PeError::Truncated)?)
    .ok_or(PeError::Truncated)?;
```
(or reject `e_lfanew < size_of::<DosHeader>()` up front).
