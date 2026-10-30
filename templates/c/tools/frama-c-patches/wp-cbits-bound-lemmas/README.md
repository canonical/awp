# wp-cbits-bound-lemmas — expose WP's bitwise bound/nilpotence lemmas to SMT

**Frama-C:** 32.1 Germanium (opam switch `framac-coq8`). **Pairs with:**
`bugs-to-report/wp-bitwise-smt-incompleteness/` (filed item) and
`config/skills/frama-c-internals/references/bitwise-smt-trail.md`.
**Upstream status:** local; candidate for upstream (the lemmas already exist in `Zbits.v`).

## What & why
WP's `cbits` theory (`share/wp/why3/frama_c_wp/cbits.mlw`) axiomatizes `land`/`lor`/`lnot`
with AC + `0`/`-1` constants only — it does **not** expose the monotonicity/bound or
`land/lnot` nilpotence facts, so Alt-Ergo/Z3 reliably fail `(a&b)<=a`, `a&~a==0`,
`a<=(a|b)` (the `wp-bitwise-smt-incompleteness` gap). These facts are **already proven
theorems** in `share/wp/coqwp/Zbits.v`; they are simply not surfaced as Why3 axioms.

This patch adds them as `cbits.mlw` axioms (so Alt-Ergo E-matches them) and realizes each
in `Cbits.v` from the existing `Zbits` theorem (so they are **sound, not bare axioms**).

## Files
- `cbits.mlw.patch` — the 6 bound/nilpotence axioms (`land_le_l/r`, `land_lnot_zero(_bis)`, `lor_ge_l/r`).
- **The SHIFT-class axiom `lsl_mul_pow2`** (`0<=n -> lsl x n = x * power 2 n`) closes the `byte<<k`
  signed-overflow class (crc16/xmodem/packet assembly). **It is NOT applied globally** — doing so
  regressed the shift-free ecdsa `loop_invariant_xform_preserved` goal (Alt-Ergo search-space
  enlargement; see the trade-off caveat below). Since **2026-07-14 it ships as OPT-IN mitigation M1**
  (`../lsl-mul-pow2-regression/mitigation-1-optin/`): a separate why3 theory pulled in per-unit via
  `-wp-driver`/`-wp-library` for shift-heavy units only. `apply.sh` now keeps the global `cbits` theory
  **lean** (and strips any stale global `lsl_mul_pow2` it finds).
- `Cbits.v.realization` — the realization Lemmas to merge into `coqwp/Cbits.v` (one-line
  `apply Zbits.{uint_land_range,uint_lor_inf,land_lnot_nilpotent}` for the 6 bounds; a short rewrite
  derivation from `Zbits.lsl_pos + lsl_arithmetic_shift + two_power_nat_correct` for `lsl_mul_pow2`).

## Soundness status
- **Established by correspondence:** each axiom is a literal restatement of a named,
  `Theorem` (not `Admitted`) in the shipped, CI-verified `Zbits.v` — statements read and
  cited in `Cbits.v.realization`; `Cint.land ≡ Zbits.land`.
- **Mechanical recompile (gold standard): PENDING the build harness.** Hand-compiling the
  coqwp chain (`Qed→Qedlib→Bits→Zbits→Cint→Cbits`) needs the full Why3 Coq realization lib,
  which is only *partially* prebuilt in this opam install (`int.ComputerOfEuclideanDivision.vo`
  absent). The proper gate is Frama-C's own dune rule for the coqwp library; run it upstream/CI.
- **Not bare axioms:** the realization Lemmas are provided; do not ship `cbits.mlw` without
  merging `Cbits.v.realization` (else the theory has unrealized axioms).
- **Necessary, not sufficient (BearSSL cycle-4 finding) — one of three further classes now ADDED.**
  The 6 *bound* facts close the linux-api capability-lattice idioms but NOT: (i) the `byte<<k`
  **shift-overflow** class, (ii) the `(a & 0xFFFFFFFF)` **all-ones normaliser**, (iii) the `(q|−q)>>31`
  **sign-bit** constant-time comparators.
  - **(i) SHIFT — DONE (this addendum, `lsl_mul_pow2`), sound + realized + tested.** WP does not reduce
    `lsl(x,k)` to `x*2^k`, so a `<<`-by-a-larger-constant is opaque where the equivalent `*` is
    transparent; `lsl_mul_pow2` supplies exactly that reduction. Verified: `uint8_t x; x<<8` 4/5→5/5;
    OpenTitan `crc16 c^=*p<<8` 6/6; no regression (bitwise_lemmas 9/10). Backed by admit-free
    `Zbits.lsl_pos + lsl_arithmetic_shift`.
  - **(ii) all-ones mask identity** (`0<=a<2^n -> a & (2^n−1) == a`): candidate Zbits backing
    `pos_mod_two_power_nat_land_edge`/`uint_mod_two_power_extraction` — a multi-step derivation (mod↔mask
    edge + `a mod 2^n = a`), NOT a one-line apply; still SPECIFIED-PENDING.
  - **(iii) `>>`-sign-bit extensionality** (`(q|−q)>>31==0 iff q==0` — the OpenTitan ECDSA sigverify
    2's-complement saturation `diff|=~diff+1; diff|=~(diff>>31)+1`): **ROOT-CAUSED (2026-07-14 deep run,
    see REPORT.md §2).** The three atomic facts it needs are all SOUND and individually reachable — the
    hard "head" (`p≠0 ⟹ bit31(p|(−p)) set`) even has a matching axiom `lor_negself_bit31` that FIRES.
    But they **don't compose**: WP represents the bit-31 slice in multiple non-normalized forms
    (`lsr x 31` as a shift operand vs `land (−2³¹) x` in a comparison), so a lemma in one form won't
    E-match a goal term in another. The fix is a **WP-level bit-slice normalization pass**, not an SMT
    lemma; the only sound lemma-free route is a whole-VC WP→Coq proof (headless-blocked). NOT shipped
    (the firing axiom is goal-shape-specific and doesn't close the target — a fragile near-bare axiom).
    Stays status-3 (root-caused).
  See `bugs-to-report/wp-bitwise-smt-incompleteness/REPORT.md` §"Requested next lemmas".

## Effect (verified, this install)
- Reproducer `bugs-to-report/wp-bitwise-smt-incompleteness/reproducers/bitwise_lemmas.c`:
  7/10 → **9/10** on plain SMT (`(a&b)<=a`, `a&~a==0` now discharge; `andnot_hi` composite
  still needs a guided case-split).
- `linux/linux-acsl` capability monotonicity (`cap_issubset(cap_intersect(a,b), a)` — the
  no-privilege-escalation invariant, previously a documented residual): **26/26, Valid.**
- No regression: `linux/linux-acsl/verify.sh` still **17/17**.
- **SHIFT addendum (`lsl_mul_pow2`, 2026-07-13):** `uint8_t x; x<<8` signed-overflow **4/5 → 5/5**;
  OpenTitan `crc16 c^=*p<<8` (the real campaign residual) **6/6**; `bitwise_lemmas.c` still 9/10 (no
  regression). Validated via `-wp-share` with the axiom (`-machdep gcc_x86_32 -wp -wp-rte`, alt-ergo+z3).
  NB the OpenTitan ECDSA saturation `(q|−q)>>31` stays 4/5 — it needs class (iii), not the shift lemma.

## Apply
```sh
SHARE=$(frama-c -print-share-path)
patch "$SHARE/wp/why3/frama_c_wp/cbits.mlw" < cbits.mlw.patch     # runtime axioms (effective immediately)
# merge Cbits.v.realization into $SHARE/wp/coqwp/Cbits.v (and the framac-src source),
# then rebuild the coqwp Coq library via Frama-C's build to discharge the realization.
```
`./apply.sh [--check]` automates the `.mlw` part against the installed share.

## land_to_uint32_mask (added — RS8 securebits locked-state)
`is_uint32 m -> land (to_uint64 z) m = land z m`. Sound: a uint32 mask only sees bits 0..31,
where `to_uint64 z` (= `z mod 2^64`) agrees with `z`. It bridges WP's unsigned-`~` representation
(`to_uint64 (lnot arg2)`) so the SMT solvers close the locked-state goal directly — Z3, 49 ms, no
Coq script. Realization argument in `Cbits.v.realization` (a bit-extensionality derivation from the
realized `to_uint64_extraction_inf` + `land_extraction`, not a single-theorem apply).

**Note (corrects earlier §7 framing):** WP's Coq prover *does* work in this switch (Coq 8.20.1 is
detected and discharges nonlinear goals). The §7 `coqwp-gate.sh` TIER-2 failure was an artifact of
compiling the *stale static* `coqwp/*.v` (omega/`set_def`) directly, NOT WP's real why3-generated
Coq path. So Coq discharge is available in-switch; RS8 just turned out to need only the SMT axiom.

## Applied to framac-src (2026-06-26, run-2, user-approved)
The bound-lemmas (`land_le_l/r`, `land_lnot_zero(_bis)`, `lor_ge_l/r`) are now merged into the
**framac-src** dev tree used by the full-TU recipe (previously only `land_to_uint32_mask` was
there; the full set was only in the installed switch):
  - `src/plugins/wp/share/why3/frama_c_wp/cbits.mlw` — the 6 axiom declarations.
  - `src/plugins/wp/share/coqwp/Cbits.v` — the 6 realization Lemmas (each `apply`-ing a named
    admit-free `Zbits` theorem: `uint_land_range`, `uint_lor_inf`, `land_lnot_nilpotent`).
After editing, propagate to the dune build: `touch` the .mlw then
`dune build _build/install/default/share/frama-c/share/wp/why3/frama_c_wp/cbits.mlw`.
Soundness: coqwp-gate TIER-1 GREEN against framac-src (all present, admit-free, cited, backed;
Zbits.v + Cbits.v admit-free). Effect: variable-mask bounds (e.g. `x & m <= m` for symbolic m)
now discharge — unlocks bloom_filter hash() bound (h<=bitset_mask, 8/8) and the variable-mask
class generally. NOT smuggled: realized + audited.

## Trade-off caveat for `lsl_mul_pow2` (2026-07-14, measured) — RESOLVED via M1 opt-in
Adding `lsl_mul_pow2` to the shared `cbits.mlw` theory has a **measured side effect**: it enlarges
Alt-Ergo's axiom/E-matching search space for *every* WP goal, which can push a BORDERLINE unrelated goal
over its timeout. Confirmed instance: OpenTitan `ecdsa_verify_sa2auth.c` `sigverify_encoded_message_check`
`loop_invariant_xform_preserved` (an XOR-transform invariant, no shift terms) **proves 2/2 without the
axiom but TIMES OUT with it** (isolated, `-wp-cache none`, even at 60 s / z3-first). The regression is real
and lands on a security-relevant (authorization) goal.

**Resolution (adopted 2026-07-14):** the axiom is no longer global. Three mitigations were explored and
independently re-verified in a quiet environment (`../lsl-mul-pow2-regression/VERIFICATION.md`); **M1 —
a separate opt-in `CbitsShift` theory imported only by shift-heavy units** — was the only clean fix (M2
timeout-tuning was invalid; M3 invariant-rewrite traded `xform` for a `diff_match` regression). M1 is now
operational on the live switch (measured 2026-07-14, real lean share):
- shift-free `ecdsa` back to **72/79** with `xform` AND `diff_match` proved (no regression);
- shift units close via the opt-in driver — `crc16` 20/21→**21/21**, `xmodem_recv_frame` 53/55→**54/55**.
Wiring: pass `$OT_SHIFT_OPTIN` (defined in `opentitan-analysis-acsl/onboard-flags.sh` =
`-wp-driver=…/shift_lemmas.driver -wp-library=…/wp-library`) to shift-heavy units only.
