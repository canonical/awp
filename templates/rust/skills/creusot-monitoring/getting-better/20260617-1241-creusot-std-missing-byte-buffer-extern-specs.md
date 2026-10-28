# Creusot-std: missing extern specs for byte-buffer primitives block crypto/parse code

Date: 2026-06-17
Surfaced while: verifying `lace-util/src/sha1.rs` and `acpi`/`elf64` (lace priority-2).

## Gaps found (each blocks straightforward verification of `&[u8]`/`[u8;N]` code)
1. **Array (`[T;N]`) range Index/IndexMut has no extern spec** — only slice
   (`[T]`) range-indexing is specced. `self.buffer[a..b]` on a `[u8;64]` field
   leaves the in-bounds goal undischarged until you add an `Index`/`IndexMut for
   [T;N]` extern spec with the standard in_bounds/has_value/len clauses.
2. **`u32::rotate_left` / `u32::to_be_bytes` / `u32::from_be_bytes` /
   `usize::to_be_bytes`** — no creusot-std contracts (warn "no contract →
   impossible precondition"). Must be added as totality/length-only extern specs.
3. **`usize::try_from(u64)`** — no `TryFrom<u64> for usize` extern spec; the `Ok`
   branch becomes unreachable, blocking the no-overflow proof that depends on a
   validated `usize` bound (elf64 `parse`/`segment_data`). Add a totality spec:
   `Ok(v) with v@==x@` iff `x@ <= usize::MAX@`, else `Err`.
4. **`slice.try_into().unwrap()` → `[u8;4]`** and **`AsRef<[u8]> for [u8;N]`** —
   `extern_spec!` on these reaches through blanket `TryInto`/`TryFrom`/`AsRef`
   impls and fails with the opaque `error: extern spec generics don't match`.
   Workaround: replace `s[a..b].try_into().unwrap()` with explicit element reads
   `[s[a], s[a+1], s[a+2], s[a+3]]` (byte-identical); replace `.as_ref()` with the
   `&array` unsize coercion.
5. **`ChunksMut<T>` (and other std slice iterators) lack `IteratorSpec`** — a
   `for chunk in digest.chunks_mut(4)` loop cannot be translated. Workaround:
   rewrite as an indexed `while` over the same chunks.

## Suggested fix (upstream)
Ship extern specs for `[T;N]` range Index/IndexMut, integer byte-swap /
`rotate_left` / `to_be_bytes`/`from_be_bytes`, `TryFrom<u64> for usize`, and an
`IteratorSpec` for `ChunksMut`/`Chunks`. Also fix `extern_spec!` so it can target
trait methods reached through blanket impls (`TryInto`, `AsRef`).

## Impact on monitoring
These are all *workaroundable* with totality-only extern specs or byte-identical
rewrites (so the verdict stays ROBUST), but each adds a trusted assumption to the
trust base. A file that needs several of them is honest-ROBUST-under-N-trusted-
totality-specs, not BLOCKED.
