# Cast/region trail — the hypothesis/refutation log (mechanism 2, CONTAINER_OF)

The investigation into why the CONTAINER_OF round-trip `(T*)((char*)&c->m − offsetof(m)) == c` does
not discharge. Recorded so the next session does not re-walk refuted paths. All results reproduced on
Frama-C 32.1 (installed for baselines; `framac-src` dev build for model edits). Reproducers in
`reproducers/`.

## The reference probe
`reproducers/c2_literal.c`: `struct node {int payload; int hook;}` (hook at byte 4), `requires
\valid(c)`, body recovers `c2 = (struct node*)((char*)&c->hook − 4)`, `assert rt: c2 == c`, then
`return c2->payload`. The `assert rt` isolates the single missing fact.

## Hypotheses, each REFUTED by a grounded probe

**H1 — "the cast fabricates a fresh address."**
Refuted: `MemTyped.cast s l` returns `l` unchanged (`MemTyped.ml:910`, both Fits-fits and Unsafe
branches). The location carries the source base/offset; the cast is not the source of freshness.

**H2 — "it's a spec gap: the contract must state `\valid(container)`."**
Refuted: with `requires \valid(c)` in scope the member access is still 3/4 (Timeout on
`c2->payload`) under **both** Typed and `+cast`. Adding `/*@ assert c2 == c; */` makes everything else
green (**4/5**) — so container validity is *not* what's missing; the *only* irreducible fact is the
round-trip identity itself. Not a spec gap.

**H3 — "WP's `addr` lacks extensionality (base+offset eq ⇏ addr eq)."**
Refuted: `addr` is a **Why3 record** `{ base:int; offset:int }` (`memaddr.mlw:15`), with
`shift p k = { p with offset = p.offset + k }`. Records are extensional in Why3/SMT — the lemma would
be a no-op. (The registered `phi_base`/`phi_field`/`phi_index` simplifiers, `MemTyped.ml:322/388`, do
reduce `base c2 → base c` and `offset c2 → offset c`.)

**H4 — "`+cast` completes it (only the frame is unsound elsewhere)."**
Refuted: under `+cast` the `rt` goal reduces to **`Prove: false`** (`-wp-print`, only
`valid_rw(Malloc_0, c, 2)` assumed). So `+cast` does not fail to *prove* `c2 = c` — Qed decides
`c2 ≠ c`: the `+cast` cast/byte-arithmetic path computes a `c2` with the **wrong offset**; the
round-trip `shift(shift(c,4),−4)` does **not** collapse to `c` there. A *mis-computation*, not
incompleteness.

## Goal dumps (evidence)
- **Typed (default), `rt`** (`-wp-print`): `forall t, a:addr, a1:addr. region(a.base)≤0 → linked t →
  valid_rw t a 2 → a1 = a` — `a1` (= `c2`) is a **fresh opaque addr**, because the non-fitting cast hit
  `CodeSemantics.exp_protected`'s `Warning.handle … "Hide sub-term definition"` (`:319`). Unprovable by
  construction.
- **`+cast`, `rt`** (`-wp-print`): warnings `"Keep pointer value"` (sint32*→sint8*, sint8*→node*),
  then `Assume { valid_rw(Malloc_0, c, 2) } Prove: false`.
- **`+cast` soundness canary** (`reproducers/canary.c`, `ensures \false`): 2/3 — `\false` is **not**
  proved, so `+cast` is not trivially unsound; its frame defect is the specific `assigns *(cast)ptr`
  call scenario (`wp-cast-frame-defect`), not blanket.

## ROOT CAUSE (mechanism 2 — now pinned, H5 confirmed)

**H5 — "the Typed model offsets are in CELLS, not bytes; CONTAINER_OF mixes a cell field-shift with
byte arithmetic." CONFIRMED.**
`length_of_object (C_int|C_float|C_pointer) = F.e_one` (`MemTyped.ml:234`) — every scalar is **1 cell**.
So `position_of_field` (`:256`, a sum of `length_of_field`) is in **cells**: `position(hook) = 1` (not
the 4 bytes of `offsetof(hook)`). `phi_field offset [p] = offset(p) + offset` (`:291`) and
`phi_index size [p;k] = offset(p) + size·k` (`:297`). On the reference probe:
- `&c->hook` → `offset(c) + 1` (cells)
- `(char*)n − 4` → `shift_sint8(n,−4)` = `offset(n) + 1·(−4)` = `offset(n) − 4` (the byte literal `4`
  consumed as 4 char-cells)
- round-trip `offset(c2) = offset(c) + 1 − 4 = offset(c) − 3 ≠ offset(c)` → `Prove: false`.

**Decisive confirmation** (`reproducers/c2_cellconfirm.c`): replace the byte literal `4` with `1` (so
the byte subtraction matches the 1-cell field shift) → the round-trip proves **4/4** under `+cast`. The
fault is *exactly* the unit mismatch `offsetof(hook)=4` **bytes** vs `position_of_field(hook)=1` **cell**.

This **supersedes** the H1–H4 framing: not extensionality, not a fresh address, not a spec gap — a
**byte↔cell representation-consistency gap**. It holds (vacuously) only for offset-0 fields and
`char`-typed fields (1 byte = 1 cell). See `../../../23-0545-consistency-plan.md` for the consistency
law + oracle + the two reconciliation directions (byte-indexed offsets vs cell-kept-byte-arith-lifted).

## Settled
- **Settled:** mechanism (2) is a **model limitation** (not spec — H2; not prover-weakness — Coq sees
  the same hidden/false goal). `Fits`↔`Unsafe` differ only in `cast` (`Context.get pointer` used only
  at `MemTyped.ml:897/913`). **Root cause = the cell-vs-byte offset unit mismatch (H5).** The remaining
  open question is now the *fix* (direction A vs B), not the diagnosis.

## Frame / cast-assigns-call scenario — RUN (the A-vs-B gate; result favors A)
`reproducers/frame_char.c` + `frame_castcall.c`: callee `assigns *(char*)p; ensures *(char*)p==0`,
caller zeroes `a`'s first byte then asserts a post-state. Result:

| assert | truth | Typed | `+cast` | `bytes` |
|---|---|---|---|---|
| `a==7` (false post) | FALSE | **1/1 PROVES (UNSOUND)** | **1/1 PROVES (UNSOUND)** | **0/1 rejects (SOUND)** |
| `a==0` (true post) | true | 0/1 | 0/1 | 0/1 (shared incompleteness) |
| `b==99` (separation) | true | 1/1 | 1/1 | 1/1 |

**Typed (default) and `+cast` are UNSOUND on `assigns *(cast)ptr` calls** — they prove `a==7` after
`a`'s byte was zeroed: the cast assigns-target is dropped from the callee frame (cast errors → hidden →
effectively `assigns \nothing` → `a` unchanged → false post proves). This is the documented
`wp-cast-frame-defect`, now a concrete *soundness* hole (not mere incompleteness). **`bytes` is sound**
(rejects the false post; the byte-assigns genuinely modifies `a`) — only incomplete on the *true* post,
which is safe-side. **So direction A's gating risk inverts in A's favor:** the byte model is strictly
more sound than the default on the exact frame scenario that sank `+cast`. (The `bytes` incompleteness on
the true post is the precision cost to measure at scale — `23-0545-consistency-impl.md §2`.)

## Consistency-oracle matrix — RUN (direction A completeness+teeth generalize)
`bugs-to-report/wp-cast-region-soundness/consistency-oracle/{matrix.c,verify.sh}`: round-trip over a
field/type matrix (mid/last int, int-after-char padding, int-after-ptr, nested-struct member,
field-after-array), `_ok` (real offsetof) vs `_bad` (off-by-one), in **separate functions**.
**`bytes` = PASS** (7/7 `_ok` proved, 7/7 `_bad` rejected — complete + teeth); **Typed & `+cast` = FAIL**
(both incomplete — neither proves the correct round-trip; `+cast`'s same-function `_bad` "proofs" were
vacuity from the contradictory assumed-false `_ok`, gone once separated). So **direction A (adopt
`MemBytes`) clears both self-contained gates: soundness (frame scenario above) AND completeness+teeth
(this matrix).** Remaining for A: at-scale regression/precision on real cast-heavy units + malloc-heap
frame (`23-0545-consistency-impl.md` §2/§4).

## At-scale regression — RUN (direction A chosen; one blocker, one located cost)
RTE-only, whole-unit, identical bare source, real-board `zk37` build
(`bugs-to-report/wp-cast-region-soundness/consistency-oracle/at-scale-results.md`):
- **No precision regression:** `bytes` ≥ Typed on every completing unit — queue 154→155, mailbox
  85→86, mempool 8/12=8/12, wolfssl `GetASN_Integer` 4/7=4/7.
- **Robustness blocker — FIXED & VERIFIED.** `bytes` *fataled* on `mem_slab.c` (unknown-size
  linker-section array): `MemBytes.protected_sizeof_object` let `Ctypes.sizeof_object`'s `Failure
  "Sizeof unknown-size array"` escape; fix guards `C_array {arr_flat=None}` → max_int/Warning.error like
  `MemTyped.length_of_object`. After fix `mem_slab.c` 43→**44/80** (no abort). Patch
  `bugs-to-report/wp-cast-region-soundness/fix/membytes-sizeof.patch`, report `REPORT-membytes-sizeof.md`,
  repro `reproducers/membytes_sizeof_crash.c`. **Build gotcha:** WP plugin loads dynamically — `dune build
  @install` is required for a `.ml` edit to take effect; `dune exec frama-c` alone runs the stale plugin
  (backtrace line numbers unchanged is the tell).
- **Located precision cost:** `bytes` can't prove heap cross-object separation across a byte-assigns
  call (Typed 1/1, bytes 0/1); specific pattern, real units didn't exhibit it. Weigh for default-on
  vs opt-in.
- **Soundness:** on the local addressable-var cast-assigns, Typed AND `+cast` are UNSOUND (prove the
  false post); `bytes` is sound. **Net: A is viable; the one blocker is fixed** (`bytes` ≥ Typed on every
  unit post-fix).

## Corpus-wide `bytes` pass — RUN, PASS (`consistency-oracle/corpus-results.md`)
Full Zephyr kernel (35 units), fixed build, RTE-only: **`bytes` ≥ Typed on EVERY unit — 0 regressions,
0 crashes.** 5 improve (+6 net: stack +2, mailbox/mem_slab/msg_q/queue +1), 29 tie (incl. sched 360/503,
userspace 417/475), 1 pre-existing parse-fail (`thread`, both models). Aggregate ≈2455→2461/3583. The
byte-model precision risk did not materialize anywhere. **§4 non-regression criterion met at corpus
scale.** The sizeof fix holds corpus-wide (no unit aborts).

## Vacuity probe on the +6 gains — RUN, PASS (`consistency-oracle/vacuity-probe.md`)
All 6 new greens are `\valid` mem_access goals on the **empty (zero-size) `k_spinlock`** member write
in the `*_init` prologues (+1 downstream sibling). Mechanism: `struct k_spinlock` is empty in this
config; `bytes` proves zero-size access validity (dereferences nothing — sound) where the cell model
times out. Vacuity test (`assert \false` at each point): `bytes` proves none (0/1 ×6) → consistent
contexts → **non-vacuous**. Soundness sanity (minimal cases): `bytes` rejects non-zero-size
unconstrained writes (`f` 2/3) and NULL derefs (`h` 2/3), identical to Typed → **not blanket-unsound**.
Nuance for model-selection docs: `bytes` treats a 0-byte access as always-valid (defensible/sound).

## §4 precision-cost — RUN, quantified (`consistency-oracle/s4-precision-cost.md`)
Contracts applied to 6 units (mem_slab/mempool/stack/mailbox/msg_q/queue), Typed vs `bytes`,
`-wp-timeout 12`: **`bytes` net +23** (722 vs 699), positive on every unit, 27 gained vs **4 lost**
(~0.4 %). The 4 lost are all **byte-range `\valid`/`\valid_read` preconditions over `(char*)`-cast /
pointer-arithmetic regions** (create_free_list buffer ×2, memcpy dest, ring-read) — so the byte model
*solves* CONTAINER_OF yet is *less complete* on byte-range-`\valid`-at-call-site than the cell model.
All 4 are **`timeout` (SMT-hardness), not decided-false**: 12→60s closes some, a residual hard core
likely needs Coq/byte-range lemma → incompleteness, not unsoundness. **Decision: opt-in per cast-heavy
unit (A.2 separate-pass)** — Typed default (cheap byte-range validity), `bytes` where CONTAINER_OF /
cast-region wins matter; no soundness obstacle to default-on, purely a prover-effort trade. This closes
the contracts-applied gate; all A gates checkable on zk37 are green.

## Mechanism (1) note (for completeness)
`*(char**)p = v` (`reproducers/castmin.c`): Typed 2/4 (cast errors → store target hidden), `+cast` 4/4
(sound for this no-call case). The `+cast` unsoundness is the *frame drop across an `assigns
*(cast)ptr` call* — reconstruct that scenario before trusting/using `+cast`.
