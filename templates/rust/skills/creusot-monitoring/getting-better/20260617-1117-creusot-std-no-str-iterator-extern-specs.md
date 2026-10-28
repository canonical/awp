# creusot-std lacks `&str` iterator / parsing extern specs (blocks all string-config parsers)

- **Trigger:** lace attack-surface run — `bls.rs` (`parse_bls_entry`) and `grub.rs`
  (`parse_grub_cfg`) both BLOCKED at translation, not by a proof obligation.
- **Confirmed against L:** `cargo creusot` fails to translate. For `bls.rs` the first
  operation `for line in content.lines()` fails with
  `E0277: std::str::Lines<'_>: creusot_std::prelude::IteratorSpec is not satisfied`.
  Reduced to `for _ in content.lines() { n += 1 }` — fails identically.

## Observed behaviour
creusot-std 0.13.0-dev models `str`/`String` only as far as: `View`/`DeepModel`
(→ `Seq<char>`), `str::len`, `str::split_at`, `String::len`,
`String::from_utf8_unchecked`, `Deref`, `ToOwned::to_owned`, `Clone for Box<str>`.

It models **none** of the `&str` iterator/parse methods used by real config parsers:
- `str::lines` (`std::str::Lines` has no `IteratorSpec`)
- `str::chars` / `Peekable<Chars>` (no `IteratorSpec`)
- `str::trim`, `str::split_once` (char-predicate closure), `str::starts_with`,
  `str::is_empty`
- `String::to_string` (no `ToString` extern spec — only `to_owned`)
- `Option::as_deref`, `Option::unwrap_or`

`IteratorSpec` is implemented only for array/Vec/slice/Option/HashMap/VecDeque/Range and
the iterator adaptors — never for any `str` iterator.

## Desired behaviour
Add extern specs / `IteratorSpec` impls for the common `&str` parsing surface so that
panic-free string parsers can be verified robust. Minimum useful set:
`IteratorSpec for std::str::Lines` and `std::str::Chars` (+ `Peekable`), and extern specs
for `str::trim`, `str::split_once`, `str::starts_with`, `str::is_empty`,
`ToString::to_string`.

## Why it matters
These parsers are demonstrably robust by construction (all-total stdlib ops, no
arithmetic/index/unsafe), yet are **un-mechanizable** today — the gap is purely in the
modeling layer. It blocks the entire class of `&str`-config attack surface in Lace
(`bls`, `grub`) and elsewhere.

## Faithfulness side-note (separate, also routed implicitly)
creusot-std's prelude `PartialEq` derive emits a spec over `DeepModel::deep_model(self)`,
forcing structs with `Option<String>` fields to also `#[derive(DeepModel)]`. The strip
tool does not edit `#[derive(...)]` lists, so that added derive cannot be stripped → a
faithfulness FABRICATION. Verifying any such struct cleanly would need either a
non-DeepModel `PartialEq` path or strip-tool support for derive-list edits.
