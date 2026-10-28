# Creusot-std: `String` has no `Invariant` impl, so any `&mut String` op is unprovable

Date: 2026-06-17
Surfaced while: verifying `lace-util/src/edid.rs::ParsedEdid::panel_id` (attack-surface, lace priority-2).

## Symptom
`panel_id` does `let mut s = String::new(); s.push(c); ...`. Every real
panic/overflow/index obligation (the `b'A' + (val-1)` overflow, the four
`HEXCHARS_LOWER[(x & 0xF) as usize]` index bounds, `u8 as char` validity) is
discharged, but 3 goals stay red:

```
inv_String((any_l(): MutBorrow String).current)
inv_String((any_l(): MutBorrow String).final)
```

i.e. the *abstract type invariant* of the `&mut String` borrow created for
`String::push`.

## Cause
`Vec<T>` ships `impl Invariant for Vec<T>` (with
`trusted_trivial_if_param_trivial`), so `inv_Vec` reduces. `String` ships **no
`Invariant` impl** at all, so `inv_String` is an uninterpreted predicate and
any `&mut String` borrow yields `inv_String(borrow.current/.final)` goals that
no solver can close.

## Why it can't be fixed from the verification crate
The orphan rule blocks `impl creusot_std::invariant::Invariant for String` in a
downstream crate, and `#[trusted]`/`assume!` are forbidden under the
faithfulness rule. So `String`-producing parsers are BLOCKED, not refutable —
the real safety paths all prove; only the spurious String-invariant goals remain.

## Suggested fix (upstream)
Add `impl Invariant for String` to creusot-std mirroring `Vec`
(`String` is a `Vec<u8>` wrapper). Also missing: extern specs for
`String::new`, `String::push(char)`, and the integer `from_be`/`from_le`/
`to_be`/`to_le` byte-swaps (all emit "no contract → impossible precondition").

## Impact on monitoring
Any lace parser that returns/builds a `String` (`edid::panel_id`,
`chid::chid_sources_from_smbios_and_edid`, `smbios` string extraction into
`String`) inherits this BLOCK. Verdict for such functions: BLOCKED on the
String-invariant gap, with a note that every *real* panic/index/overflow path
was discharged. Not a code defect.
