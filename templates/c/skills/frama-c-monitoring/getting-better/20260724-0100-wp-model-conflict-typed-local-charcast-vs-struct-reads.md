# WP 32.1 model conflict: char-cast of a small-element typed LOCAL (needs Bytes) vs typed struct-field reads + void*-blob composition (needs Typed+cast) — no single model discharges both

- **Trigger (unit/gap):** linux-7.1.3 LSM campaign cycle-448, SELinux `avtab_write_item`
  (`security/selinux/ss/avtab.c:520-554`), a policy-blob node serializer that stages fields into
  typed locals `__le16 buf16[4]` / `__le32 buf32[8]` and hands them to the WITNESSED `put_entry`
  (whose faithful precond is `requires \valid_read((char*)buf + (0 .. bytes*num - 1))` — a
  **char-range** over the caller's buffer).
- **The conflict (independently confirmed, disjoint failure sets):**
  - `-wp-model Typed+cast`: **100/101** — proves the typed struct-field reads
    (`cur->key.*`, `cur->datum.u.xperms->{specified,driver,perms.p[i]}`) and the `void*`→char blob
    composition inside `put_entry`, but **cannot** prove `\valid_read((char*)buf16 + (0..7))` — the
    char-view of a local `u16[4]`. Minimal reproducer: `u16 b[4]; //@ assert \valid_read((char*)b+(0..7));`
    → Timeout under Typed+cast; `\block_length((char*)b)==8` (statically true for the local) is likewise
    underivable (alt-ergo & z3 both exceed 120 s).
  - `-wp-model Bytes`: **94/101** — proves the local char-ranges trivially (the minimal reproducer is
    5/5 under Bytes) but **fails** the u8 xperms-field `src_readable` reads, the `blob_writable`
    composition, and the `put_entry` cursor-advance ensures.
  - Caveat 94/100; Region hits a Why3 encoding bug (unusable); `+raw ≡ Typed+cast`.
  So each individual goal is TRUE and provable **under some model**, but **no single model proves them
  all** — and WP runs one memory model per verification.
- **Why it BLOCKS a sound partial (load-bearing — do not record a partial):** leaving the one
  Typed+cast residual (`call_put_entry_requires_src_readable`) undischarged is NOT a benign carry —
  WP asserts-then-ASSUMES the unproven precond, which **vacuity-contaminates the whole post-call
  region**. Confirmed: `ensures false_probe: \false;` **PROVES 1/1** on the real unit under Typed+cast;
  `-wp-smoke-tests` reports Doomed dead-code across both branches; and the off-by-one buffer attack is
  **MASKED** (no flip). Weakening `src_readable` so every precond proves flips all of these to the sound
  reading (false_probe 0/1, smoke 37/37 no-Doomed, attack flips `assert_rte_index_bound`). So a 100/101
  here is a VACUOUS proof, not a sound partial — it must NOT be recorded WITNESSED.
- **Classification.** status-3 (BUG-IN-FRAMA-C): the goals are TRUE + entailed and each is
  WP-dischargeable, but the single-memory-model-per-unit constraint makes them jointly undischargeable —
  a model-orchestration incompleteness, not a spec gap or a code bug. **Recurring:** it bites EVERY
  caller of the char-range-precond serialization primitives (`put_entry`/`next_entry`) that stages
  **mixed-width typed locals** (u16/u32 arrays) rather than plain `u8`/char buffers.
- **Desired behaviour / candidate fixes:** (a) let Typed+cast derive `\block_length((char*)p)` /
  `\valid_read((char*)p + (0 .. sizeof(p)-1))` for a **local** typed array from its declaration (the size
  is static); or (b) a sound per-goal model-mix (prove the char-cast goals under a byte view while keeping
  the typed struct reads under Typed); or (c) a memcpy-into-char[]-staging shim contract. Until then,
  serializers staging non-u8 typed locals through `put_entry` are status-3-BLOCKED for a sound in-place
  proof — record the block, do NOT record a vacuous partial as WITNESSED.
