# Lace `grub::parse_submenu` — unbounded native recursion (stack-overflow DoS)

- **Trigger:** creusot-monitoring lace attack-surface run, grub.rs (priority-1 config parser).
- **Confirmed by:** by-hand call-graph analysis (Creusot itself is BLOCKED on this file — see
  the matching getting-better/ note — so it cannot catch a stack-depth bug anyway). Not a
  Creusot-discharged VC; a source-level robustness finding.

## Location
`lace/lace-util/src/grub.rs`, `GrubParser::parse_submenu` — at `brace_depth == 1` a
`submenu` word recursively calls `self.parse_submenu()` with **no depth limit**.

## Why it is reachable
Adversarial input of deeply nested submenus:
```
submenu 'x' { submenu 'x' { submenu 'x' { ... (tens of thousands deep) ... } } }
```
drives unbounded native recursion. A few tens of thousands of nesting levels (a
kilobyte-scale input) overflows the native stack and **aborts the process**. In a
`no_std`/UEFI bootloader with a small fixed stack the threshold is even lower.

## Impact
Pre-OS **stack-overflow / DoS** from a malicious `grub.cfg` on any disk `lace-speedboot`
scans. (`menuentry` does not self-recurse into nested blocks; only `submenu` does.)

## Secondary (debug-only) caveat
`brace_depth += 1` is an `i32` add; ~2.1 billion unmatched `{` (a ~2 GB input) overflows it
in debug, wraps in release. Impractical but noted.

## Suggested fix
Thread an explicit depth counter through `parse_submenu` and bail (skip the block) past a
fixed maximum nesting depth.
