# The C23 / GNU-extension frontend trail (parse gap — NOT a proof residue)

Companion to the filed item `bugs-to-report/frama-c-c23-frontend-gaps/`. Read when a real
Linux-kernel (or any C23) TU won't even *parse* in Frama-C 32.1.

## What it is (and where it sits)
A **frontend / parsing limitation**, on a *different axis* from the residue taxonomy (§1 of
this skill — those are undischarged *proof goals*). Here the TU **fails to type-check**, so WP
never runs. It is the root blocker behind the hardest walls of the kernel parse cascade
(`linux/linux-acsl/notes/ext4-asm-overlay-scope.md`).

## The three gaps (Frama-C 32.1, verified)
| Construct | Behaviour | Sound shim? |
|-----------|-----------|-------------|
| **C23 `auto`** (`const auto x = e;`) | parses but `[typing:implicit-int]` (no deduction; falls to int) | **NO** — must be a frontend fix; downgrading implicit-int mistypes `min`/`max`/… → unsound. GNU `__auto_type` is also unsupported, so no bridge. |
| **`__typeof_unqual__`** | `syntax error` | yes — `#define __typeof_unqual__(x) __typeof__(x)` |
| **`__int128` / `u128`** | "currently unsupported by Frama-C" | partial — map to 64-bit + `u128` typedefs to *parse*, **unsound** for real 128-bit math |

## What to do
- **`auto` is the sound blocker.** It cannot be shimmed soundly; needs a CIL-frontend change
  (deduce `auto x = e` as `__typeof__(e) x = e`, + the `__auto_type` alias) or a newer Frama-C.
  Until then, sound full-TU parsing of modern kernel code is blocked — record `PARSE-BLOCKED`
  (the `linux-acsl` `--full-tu` onboarding does this) and do **not** downgrade `implicit-int`.
- The other two are handled in `linux/linux-acsl/include/framac_kernel_shim.h` (typeof_unqual
  `#define`; `__int128`→64-bit + `u128` typedefs, scoped unsound).

## Fix (filed)
Implement C23 `auto` deduction in the frontend (highest value), recognize `typeof_unqual`, and
support `__int128` — or onboard a newer Frama-C. Detail + reproducers + `verify.sh` in the filed
item. A fix to `auto` alone unblocks `linux-analysis.md` §5.2 past the documented wall.

## RESOLVED (2026-06) — full-TU parse achieved via three frontend fixes
`frama-c-patches/cabs2cil-c23-auto/` now implements, in the **vendored** `framac-src` dev tree
(the installed campaign opam switch is untouched), three sound `cabs2cil.ml` fixes that take
the real `security/commoncap.c` all the way through parse (RC=0, 0 errors, 13580-line AST with
all seven `cap_*` hooks):
1. **C23 `auto` deduction** — `auto x = e` ⇒ type of `e` (complete `intType`-marker sentinel,
   deduced in `doInitializer`, cv-quals preserved). The headline sound blocker.
2. **`return <void-expr>;` in a `void` function** (C11 6.8.6.4 legal; was hard-errored) — probe
   the expr type with `AType`, error only when non-void. Cleared `ratelimit.h`/`sysfs.h`.
3. **`offsetof`/`container_of` with a runtime array index** — recover from
   `SizeOfError "Index is not constant"` by using the member-address-against-null expression
   (exact runtime offset). Cleared `rbtree_latch.h` and the whole `container_of(…, arr[i])` class.

The remaining `__typeof_unqual__`/`__int128` shims and the transitive-header walls
(`log2.h`→`const_ilog2`, `__ilog2`, `__builtin_clz`, `CACHELINE_PADDING`, `asm` neutralizations)
live in `linux/linux-acsl/include/framac_kernel_shim.h` + `hdr-overlay/`. Full grind log of the
cascade order is in the patch README. Next axis is **step 3** — authoring/verifying ACSL
contracts on the now-parsing `commoncap.c` (a proof-residue problem, back on the §1 axis).

## Provenance
Surfaced by the `linux-api` `--full-tu` onboarding: `security/commoncap.c` parses the whole arch
syntax cascade (shim + asm/hdr overlays + `-std c23`) and stops at `string_64.h:34` — the C23
`auto` wall. Distinct from `wp-bitwise-smt-incompleteness` (a proof residue).
