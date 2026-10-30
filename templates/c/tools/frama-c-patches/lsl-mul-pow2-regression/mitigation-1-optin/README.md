# mitigation-1-optin — make `lsl_mul_pow2` opt-in per unit

**Frama-C:** 32.1 Germanium (opam switch `framac-coq8`).
**Problem source:** `../wp-cbits-bound-lemmas/` ships the shift lemma
`lsl_mul_pow2` (`forall x n. 0<=n -> lsl x n = x * power 2 n`) as a **global** axiom in
`$(frama-c -print-share-path)/wp/why3/frama_c_wp/cbits.mlw`. It closes the `byte<<k`
signed-overflow class (crc16/xmodem/packet assembly) but, being global, it enlarges
Alt-Ergo's E-matching search for *every* WP goal and pushed one **unrelated, security-relevant**
goal over its timeout (OpenTitan `ecdsa_verify_sa2auth.c`
`sigverify_encoded_message_check::loop_invariant_xform_preserved`, an XOR invariant with no
shift terms). See the trade-off caveat at the bottom of `../wp-cbits-bound-lemmas/README.md`.

This directory is **mitigation (1)**: keep the axiom out of the global `cbits` theory and let only
shift-heavy units pull it in.

## Mechanism (approach (a): separate Why3 theory + opt-in driver — MEASURED to work)

Two independent halves:

1. **Lean default.** A mitigation-1 deployment removes `lsl_mul_pow2` from the global
   `cbits.mlw`. (This repo must NOT touch the installed switch — other agents depend on the axiom
   staying global — so `verify.sh` demonstrates the lean default on a *copy* via `-wp-share`.)
   A production adoption would just delete the one `axiom lsl_mul_pow2` line from `cbits.mlw`.

2. **Opt-in re-addition, per invocation, no share edit:**
   - `wp-library/frama_c_wp/cbits_shift.mlw` — a **separate** Why3 theory `CbitsShift` that does
     `use frama_c_wp.cbits.Cbits` and declares the single `axiom lsl_mul_pow2`. Because it `use`s
     Cbits, its `lsl` **is** `Cbits.lsl`, so the axiom's trigger `[lsl x n]` E-matches the exact
     term WP's RTE overflow goals build. WP does **not** auto-load this theory.
   - `shift_lemmas.driver` — a WP driver that appends
     `why3.import += "frama_c_wp.cbits_shift.CbitsShift"` to the always-loaded `cbits` library.
     `why3.import +=` **appends** (it does not replace), so all of `Cbits` (`bit_test`, `land`, …)
     stays available; the extra `use` only adds `CbitsShift`.

   A shift unit opts in with:
   ```
   -wp-driver=<mitdir>/shift_lemmas.driver  -wp-library=<mitdir>/wp-library
   ```
   `-wp-library` prepends a why3 load path, so `frama_c_wp.cbits_shift` is found there; the installed
   share is untouched. Shift-free units simply omit both flags and never see the axiom.

### Why approach (b) (an ACSL `axiomatic` header) was not used
Approach (a) already MEASURED-works and keeps the soundness story identical to the shipped patch
(the axiom is one Why3 declaration, realizable from `Zbits`). An ACSL-level `//@ axiom … x << n …`
header would have to be re-validated to E-match WP's internal `lsl` and would introduce an
ACSL-`<<`↔`lsl` bridging question; approach (a) sidesteps it because `CbitsShift.lsl` is literally
`Cbits.lsl`. Since `crc16` proves **21/21** with the driver (see below), the bridge is confirmed
at the level that matters — WP's own `lsl` term.

## Files
- `wp-library/frama_c_wp/cbits_shift.mlw` — the opt-in `CbitsShift` theory (one axiom).
- `shift_lemmas.driver` — the opt-in WP driver (appends `CbitsShift` to library `cbits`).
- `Cbits_shift.v.realization` — Coq realization note (same admit-free `Zbits` derivation as the
  parent patch; for the Coq-prover path / soundness of record).
- `verify.sh` — reproduces (A) and (B) end-to-end on a scratch copy of the share.

## Soundness
`lsl_mul_pow2` here is **character-for-character** the axiom in `../wp-cbits-bound-lemmas/`. It is
**not a bare axiom**: it is realizable admit-free from `Zbits.lsl_pos + Zbits.lsl_arithmetic_shift`
(+ `two_power_nat_correct`), the derivation recorded in `Cbits_shift.v.realization` and in
`../wp-cbits-bound-lemmas/Cbits.v.realization`. Moving it from theory `Cbits` into theory
`CbitsShift` (which `use`s Cbits) changes nothing mathematically — same symbol, same statement,
same backing theorem. TIER-1 correspondence GREEN; TIER-2 mechanical coqwp recompile carries the
same environment block as the parent patch.

## MEASUREMENTS (this switch, `-wp-cache none`, `-wp-timeout 20`, alt-ergo,z3)

Recipe: `-machdep gcc_x86_32 -cpp-extra-args="-iquote $OT -I$OT -I$AN/gen-include -I$AN/include
-include opentitan_tcb.h -DOPENTITAN_IS_EARLGREY -DMANIFEST_UNIT_TEST_ -ffreestanding"`,
`OT=…/opentitan`, `AN=…/opentitan-analysis-acsl`.

### (A) shift-free `ecdsa_verify_sa2auth.c` recovers without the global axiom
Measured on the **full** `sigverify_encoded_message_check` function (the borderline `xform`
goal only tips over in the full-function context — an isolated `-wp-prop xform` run is too small to
show it and proves 2/2 in every config):

| cbits state | `sigverify_encoded_message_check` proved | `loop_invariant_xform_preserved` |
|---|---|---|
| GLOBAL axiom (current switch)      | 80/89 · 83/92 (2 runs) | **TIMEOUT** (in the timeout set) |
| CLEAN / lean default (no axiom)    | 82/89 · 85/92 (2 runs) | **proved** (recovered)          |
| CLEAN + opt-in driver *loaded on this unit* | 81/90 | TIMEOUT (see note) |

→ **(A) holds:** removing the global axiom recovers `xform` and yields a net **+2** proved goals on
the affected function, reproducibly across runs. The whole-unit campaign figure for this delta is
`ecdsa 72/79 (clean) vs 71/79 (global)` — the same one goal.

**Caveat / important nuance.** The regression is a **borderline timeout**, not a hard failure:
on a quiet machine the global axiom sometimes still proves `xform` (it is fast in isolation), and it
tips over under the full-function search + machine load — exactly the "borderline goal over its
timeout" the parent README describes. The **opt-in isolation therefore works by NOT loading the
driver on shift-free units**: loading `shift_lemmas.driver` *on* `ecdsa` re-introduces the identical
timeout (row 3) — because it is the identical axiom. Correct usage = shift units add the driver,
everyone else omits it.

### (B) shift-heavy units that opt in still close their shift goals
CLEAN default (no global axiom), `-wp-model bytes`:

| function | CLEAN, no opt-in | CLEAN + opt-in driver+library |
|---|---|---|
| `crc16`             | 20/21 (shift `*p<<8` TIMEOUT)     | **21/21** (shift closed)               |
| `xmodem_recv_frame` | 53/55 (shift `pkt[0]<<8` TIMEOUT) | **54/55** (shift closed; remaining 1 = `assigns` store-bloat, a different class) |

→ **(B) holds:** both shift goals close via the opt-in mechanism with **no** edit to the installed
share, matching the numbers the global axiom achieves (crc16 21/21, xmodem 54/55).

## Reproduce
```sh
eval $(opam env --switch=framac-coq8 --set-switch)
./verify.sh          # copies the share, strips the axiom from the copy, runs (A) and (B)
```
`verify.sh` never modifies `~/.opam/framac-coq8/...`; it operates on a `mktemp -d` copy and drives
WP with `-wp-share`. The opt-in half (`shift_lemmas.driver` + `wp-library/`) needs no share edit and
can be pointed at the real switch too.

## Verdict
A clean, sound opt-in is **achievable** in WP 32.1 via the separate-theory + driver mechanism, and
both (A) and (B) are MEASURED to hold. The only subtlety is that the underlying regression is a
borderline timeout, so the isolation guarantee is "shift-free units must not load the driver" (which
is the natural usage) rather than "the axiom is harmless when present" — loading it anywhere it is
visible can still tip a borderline neighbour.
