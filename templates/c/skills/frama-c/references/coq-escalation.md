# Escalating SMT-undischargeable WP goals to Coq/Rocq

Reference for the case the SMT back-ends (Alt-Ergo, Z3, CVC5) **cannot** close: goals
needing **induction or non-linear reasoning**. The canonical example is proving the
Euclidean algorithm returns the *greatest* common divisor — `∀k. k>0 ∧ k|a ∧ k|b ⇒ k ≤ gcd(a,b)`
quantifies over a *variable* divisor with no useful e-matching trigger, so SMT cannot
instantiate it. That irreducible kernel goes to an interactive prover (Coq/Rocq) through Why3.

This file is the distilled, **verified** record from closing that gate end-to-end (the former
`gcd/` flagship; 15/15 headless). Where it differs from generic docs, trust this file — it
reflects what actually worked on **Frama-C 32.1 / Why3 1.8.2 / Coq 8.20.1**.

---

## 1. The matched toolchain (this is the load-bearing prerequisite)

Why3 1.8.2's Coq driver matches the **legacy** banner "The Coq Proof Assistant, version 8.x"
and a hard **8.16–8.20** version range, and it ships *realization* libraries (76 `.v`) that must
precompile against that stdlib. **Rocq 9.x fails on all three counts**: it reports "The Rocq
Prover, version 9.2" (regex miss), ships only the `rocq` binary (Why3 expects `coqtop`/`coqc`/
`coqdep`), and reorganized the stdlib (`Coq.*`→`Stdlib.*`) so 8.x realizations don't compile.
A `coqc→rocq` shim fixes invocation but **not** detection or the realization ABI — it dead-ends.

**The fix is a version-matched pair, not a workaround: Coq 8.20.1** (top of Why3's window,
emits the legacy banner, realizations compile clean). Install it in a **dedicated opam switch**,
**Coq first, then Why3** (so Why3's build compiles its Coq realizations against the present Coq):

```sh
# 1. dedicated switch so you don't disturb a 9.x environment
opam switch create framac-coq8 4.14.2
eval $(opam env --switch=framac-coq8 --set-switch)

# 2. Coq 8.20.1 FIRST — what Why3's realizations compile against
opam pin add coq 8.20.1      # pin, not install: a later dune upgrade would move it to 9.x

# 3. THEN Why3 + an SMT solver; Why3's build now builds the realizations.
#    Frama-C itself is the PATCHED source build, not `opam install frama-c`:
#    see install.md (steps 4-5).
opam install "why3>=1.8.0" "why3<1.9" "why3-coq>=1.8.0" "why3-coq<1.9" alt-ergo z3

# 4. detection should now find Coq with a real version AND compiled libraries
why3 config detect
why3 config list-provers          # expect: Coq 8.20.1  (+ the SMT solvers)
```

If Why3 was installed **before** Coq in the switch, force the realizations to build:
`opam reinstall why3` (or, from a Why3 source tree: `./configure && make coq && make install-coq
LIBDIR="$(opam var lib)"`). Verify the realizations landed: `ls "$(why3 --print-libdir)/coq"`
should be non-empty and carry a `version` marker.

**Do not pollute the default switch** — it has no Coq and shouldn't. Always
`eval $(opam env --switch=framac-coq8 --set-switch)` before any `-wp-prover coq` work.

**The acceptance test is the headless replay, not `coqc --version`.** Declare the coupling
"wired" only when a real lemma closes in Coq *and replays headlessly* (§5). That replay is the
only evidence the whole binary/realization/encoding stack composes on your machine. If your
package repo offers only Rocq 9.x and no 8.x, the honest outcome is to record the goal as
"needs interactive proof — toolchain coupling unavailable" — **never** paper over it with an `axiom`.

---

## 2. The WP interactive-Coq workflow (verified, with the traps)

The prover name and invocation that **actually work** here (generic docs claiming the native
backend is gone and you must use `why3:coq` did **not** match this setup):

- **Find the exact name:** `frama-c -wp-detect` → it lists `(coq)`. Use it lowercase:
  `-wp-prover coq`. (The Why3-routed `why3:coq` form is version-dependent; `-wp-detect` is
  authoritative for your install.)
- **Generate proof skeletons:** `frama-c -wp -wp-interactive update -wp-prover coq -wp-session SESS file.c`
  writes `.v` skeletons under `SESS/interactive/` (one per goal). Until a script is filled you
  get "Missing script(s) for prover Coq".
- **Validate a script standalone** while developing:
  `coqc -R "$(why3 --print-libdir)/coq" Why3 SESS/interactive/lemma_X.v` (exit 0 = compiles).

Traps that cost real time (every one verified on Frama-C 32.1 / Why3 1.8.2 / Coq 8.20.1):

1. **User `Require` imports MUST go INSIDE `Proof.`, not in the prelude.** WP regenerates the
   Why3-translation prelude (`Require map.Map.` / `Parameter` / `Axiom` block) on every replay and
   splices only your *proof region* into it — any `Require Import Lia.` placed in the prelude is
   silently discarded → the goal reports `Unknown` (and replays in ~0.6 ms, the tell-tale it never
   ran). Put them right after `Proof.` (Coq 8.20.1 accepts `Require` after `Proof.`).
2. **The SMT cache masks new Coq scripts.** A plain replay re-reads cached Alt-Ergo/Z3 timeouts
   (`[Timeout] … (Cached)`) and never invokes your script. Force it with **`-wp-cache none`**
   (recompute) or `-wp-cache replay`.
3. **Multi-prover scheduling can mask the Coq verdict — discharge lemmas with `-wp-prover coq`
   ALONE.** With `-wp-prover alt-ergo,z3,coq`, WP may settle a lemma goal on the cached SMT
   `[Timeout]` and never dispatch the interactive Coq script, so the console summary shows it
   unproven even though the script is valid. Do the **lemma pass separately** (`-wp-prover coq
   -wp-cache none`) and the **function-VC pass** with SMT; the authoritative per-goal verdict is in
   `-wp-report-json out.json` (`"verdict":"valid"`, `"Coq:8.20.1" success=1`), not the multi-prover
   console line. (A combined `alt-ergo,z3,coq -wp-cache none` *can* report N/N — as on the GCD gate —
   but don't trust it when a lemma silently stays red; split the passes.)
4. **`coqc` passing is NOT enough — Why3 runs `coqtop -batch -R %l/coq Why3 -l file.v`.** `coqtop -l`
   *loads* the file into module **`Top`**, not as module `<basename>`. So any name qualified with the
   filename module (e.g. `lemma_X.shift`) compiles under `coqc` but FAILS under coqtop with
   "reference … not found" → a silent `(Qed 0.5ms) Unknown`. Use **unqualified** names (or `Top.foo`),
   and always test BOTH `coqc -R "$(why3 --print-libdir)/coq" Why3 file.v` AND
   `coqtop -batch -R "$(why3 --print-libdir)/coq" Why3 -l file.v`.
5. **WP regenerates a LEANER prelude than the on-disk skeleton.** The freshly emitted goal may DROP
   hypotheses present in a stale `.v` (e.g. an `is_sint32_chunk` hyp). The `(* Why3 intros … *)`
   comment line WP writes just above `Proof.` shows the REAL hypothesis names/count — edit and
   validate against the file *after* a fresh `-wp-interactive update`, not the pristine skeleton.
   **Better still: write the hand script change-ROBUST** so a later *contract* edit (which re-hashes
   the goal and shifts hypothesis positions) does not silently break replay — prefer anonymous `intros`
   + `match goal with | H : _ |- _ => …` selection + `cbv zeta` over a positional `intros h1 h2 h3`.
   (Field-derived, mbedtls 4.1.0: adding `requires end-*p <= SIZE_MAX` to `asn1_get_tag`/`get_len`
   re-hashed their goals and broke the saved positional script; a `match`-based rewrite survived.)
6. **Coq can show as `[partial_prover]` in `~/.why3.conf`** → goals report `Unknown` / "Missing
   script(s)" even though `coqc` works. Run `why3 config detect` once to finalize it (`Found prover
   Coq version 8.20.1, OK`).

- **Audit soundness:** `Print Assumptions wp_goal` on each `.v` must show **only the intended
  definitional axioms** (and already-proved upstream lemmas) and **0 admits** — any `classic`/
  `admit`/smuggled behavioural axiom means the green is not a proof.
- **…but that audits only YOUR script.** `-wp-prover coq` *inlines* WP's realization library
  `coqwp` (`$(frama-c -print-share-path)/wp/coqwp/`), which itself ships ~57 `Admitted` **lemmas** —
  the real TCB of the Coq backend. To turn those into machine-checked theorems (vendoring,
  classification of the three kinds of unproved, witness models, the `R`-axiom bar, the Coq-8.20
  `omega→lia` / `From Coq Require Import Bool` traps, the `check.sh` CI gate), see
  **`coqwp-trust-root.md`**.

---

## 3. Methodology principles (what separates a maintainable proof from a brittle one)

- **SMT-first, escalate last.** Run `-wp-prover alt-ergo,z3 -wp-rte` first; find *exactly which*
  VC is red. Most of a contract (loop preservation, exit, range checks) is SMT-tractable; only
  the residue goes to Coq.
- **First try to DISSOLVE the obligation, not prove it — the `reads`-footprint reformulation.** A
  recursive `logic` function declared with an explicit `reads` footprint lets WP frame it
  *automatically* across writes that don't touch that footprint, which can eliminate the inductive
  "frame lemma" that would otherwise force a Coq proof. Verified: the StandardAlgorithms `partial_sum`
  cluster was PARTIAL ("needs the inductive `psum_frame` lemma SMT can't discharge") until the header
  was rewritten as
  `logic integer AccumulateDefault{L}(value_type* a, integer n) reads a[0 .. n-1];`
  with its base/step axioms — then WP auto-frames it and **SMT closes every goal, no Coq at all**.
  Before escalating an inductive frame/preservation obligation, ask whether a `reads`-footprint
  logic function (or a `\at`/label reformulation) makes WP frame it for free.
- **Isolate the hard fact as a named `lemma` — never hand-prove a postcondition VC.** The
  postcondition VC is entangled with WP's memory model; proving it by hand re-derives program
  logic. Instead hoist the mathematical statement into a standalone ACSL `lemma`: WP turns it into
  its *own* VC, detached from the C. Prove that one clean goal in Coq; once proved it enters the
  context as a hypothesis and the postcondition VC closes under SMT.
- **Lemmas, not axioms.** `axiom` *assumes* without proof — one wrong axiom makes everything
  vacuously provable. Reserve `axiom` for genuine *definitions* (the defining recurrence of a logic
  function). Every *consequence* is a `lemma` and must be proved.
- **A definitional axiom set still joins the TCB — probe it.** If the defining axioms are mutually
  *inconsistent*, every goal proves vacuously and a green replay means nothing. Cheap guard: state a
  deliberately false `lemma` against the axioms and confirm it does **not** prove.
- **Keep the Coq surface minimal and confirm each lemma is load-bearing.** Interactive scripts are
  brittle (a statement/encoding change can break a saved proof). Prove the *smallest* lemma that
  lets SMT close the function; then remove it and confirm a function VC turns **red** — a lemma used
  by no VC is dead weight and hints the postcondition is too weak.
- **Persist + replay in CI.** Commit the `-wp-session` directory (the `.v` scripts + cache). CI is
  just the headless replay; use `-wp-cache replay` in CI (read-only — a goal not in the cache fails,
  so a dropped/stale script can't silently pass) and `-wp-cache none`/`update` while developing.

---

## 4. The GCD example — spec, and the *verified* proof patterns

ACSL (note: define `gcd` by its recurrence as definitional axioms; state the consequences as
lemmas; run with `-wp-rte` and `unsigned` operands so `%`/overflow obligations are also checked):

```c
/*@ axiomatic Gcd {
      logic integer gcd(integer a, integer b);
      axiom gcd_base: \forall integer a; a >= 0 ==> gcd(a, 0) == a;
      axiom gcd_step: \forall integer a, b; a >= 0 && b > 0 ==> gcd(a, b) == gcd(b, a % b);
    } */
/*@ lemma gcd_positive: \forall integer a,b; a>=0 && b>=0 && (a>0||b>0) ==> gcd(a,b) > 0;
    lemma gcd_divides:  \forall integer a,b; a>=0 && b>=0 ==> a%gcd(a,b)==0 && b%gcd(a,b)==0;
    lemma gcd_greatest: \forall integer a,b,k;                       // the flagship Coq target
      a>=0 && b>=0 && (a>0||b>0) && k>0 && a%k==0 && b%k==0 ==> k <= gcd(a,b); */
/*@ requires a>0 || b>0; assigns \nothing;
    ensures \result>0;
    ensures a%\result==0 && b%\result==0;
    ensures \forall integer k; k>0 && a%k==0 && b%k==0 ==> k <= \result; */
unsigned gcd_compute(unsigned a, unsigned b) {
  /*@ loop invariant gcd(a,b) == gcd(\at(a,Pre),\at(b,Pre));
      loop assigns a, b; loop variant b; */
  while (b != 0u) { unsigned r = a % b; a = b; b = r; }
  return a;
}
```

**Critical encoding fact (corrects the mod-based generic skeleton):** WP translates C `%` to
**`Z.rem`** (truncated remainder), *not* `Z.modulo`. So the bridge lemmas are the `rem` family,
and the WP-emitted axioms read e.g. `Q_gcd_step : ∀a b, 0<b → 0≤a → L_gcd b (Z.rem a b) = L_gcd a b`.

**Proof shape that works for all three lemmas: well-founded induction on the Euclidean descent**
(`Zwf` on the second argument, which decreases under `Z.rem a b`). Imports go *inside* `Proof.`:
`Require Import Lia ZArith Coq.ZArith.Zwf Coq.ZArith.Zquot.` The verified building blocks:

- `Z_rem_mult : Z.rem (a*b) b = 0` — unconditional (handles `b=0`); the clean `(d|r) ⇒ Z.rem r d = 0`
  bridge: `intros r d [z ->]. apply Z_rem_mult.`
- `Z.rem_divide : b<>0 → (Z.rem a b = 0 <-> (b|a))` — the other direction (when you know `b≠0`).
- `Z.quot_rem' : a = b*(Z.quot a b) + Z.rem a b` — to split `a` for divisibility of `a` from `b` and `Z.rem a b`.
- `Z.divide_add_r / Z.divide_mul_l / Z.divide_add_cancel_r / Z.divide_0_r / Z.divide_refl`.
- `Z.divide_pos_le : 0<m → (n|m) → n<=m` — the order step: from `k | gcd`, `gcd>0`, `k>0` conclude `k ≤ gcd`.
- `Z.rem_bound_pos : 0<=a → 0<b → 0 <= Z.rem a b < b` — feeds the `Zwf` measure.

Skeleton of the induction (the actual gcd_positive proof; divides/greatest follow the same frame —
prove a `Z.divide` form by induction, then convert via the bridges above):

```coq
Proof.
Require Import Lia ZArith Coq.ZArith.Zwf Coq.ZArith.Zquot.
intros i i1 h1 h2 h3.
revert i h2 h3. revert h1. pattern i1.
apply (well_founded_ind (Zwf_well_founded 0)). clear i1.
intros x IH Hx i Hi Hor.
destruct (Z.eq_dec x 0) as [E|N].
- subst x. rewrite (Q_gcd_base i Hi). destruct Hor as [H|H]; lia.
- assert (Hpos: (0 < x)%Z) by lia.
  pose proof (Z.rem_bound_pos i x Hi Hpos) as Hb.
  rewrite <- (Q_gcd_step i x Hpos Hi).
  apply (IH (Z.rem i x)); [ unfold Zwf; lia | lia | lia | right; lia ].
Qed.
```
Two gotchas while writing these: integer literals default to `nat` — write `0%Z` / `… = 0%Z` in
asserts; and when `pattern b` bakes the `0<=b` hypothesis into the motive, the IH needs an extra
`(0 <= Z.rem a b)` proof argument before the `a := b` instantiation.

---

## 4b. Array-aggregate proof patterns (count / multiset / sortedness)

Beyond GCD, the StandardAlgorithms residuals needed the same family of inductive lemmas — useful
templates when verifying functional contracts of array algorithms (sorts, heaps, copy/remove):

- **Counting functions** (`CountNotEqual`, `Count`): define by a one-step recurrence
  (`Empty`/`Hit`/`Miss`). The *frame*/*unchanged* facts auto-discharge under SMT via the
  `reads`-footprint trick (§3) — `remove_copy`/`remove_copy2`/`remove_copy3` proved **fully with SMT,
  no Coq**, once the count function carried its read footprint. The genuinely inductive ones
  (`Count_Union` over a split range, `Count_Unchanged` over a frame) go to Coq by **well-founded
  induction on the range bound** via the count recurrence — the same `Zwf`/`well_founded_ind` shape
  as GCD.
- **MultisetReorder / permutation** (the hard core of every sort and `shuffle`): the swap-level facts
  (`MultisetReorder_DisjointUnion`, `MultisetSwap_*`) reduce to the proved `Count` lemmas (a
  permutation preserves every element's count). Prove the `Count` lemmas in Coq, then the reorder
  lemmas are mostly non-inductive consequences. `shuffle` reached PROVED with 4 Coq lemmas this way;
  sortedness (`Increasing`) + `MultisetReorder` is the standard two-part sort postcondition.
- **Corpus convention (no `.acsl` includes).** This tree's WP flags lack `-Iframac/Logic`, so a C
  `#include "MultisetReorder.acsl"` cannot resolve. **Inline** the predicate/lemma blocks into the
  unit's own `.h` (the established `push_heap.h` pattern) — pure ACSL, so faithfulness holds. The
  gold's `Logic/*.acsl` files are the source to copy from.
- **Loop-invariant buffer validity: prefer the range form over the fixed-base `\forall`.** The
  `requires \forall i; 0<=i<end-*p ==> \valid_read(*p+i)` *precondition* template (above) is fine,
  but as a **loop invariant that must be PRESERVED** it generates a quantified goal SMT closes
  poorly at scale (verified: the mbedtls `x509_csr_parse_extensions` loop produced ~30 cascading
  `loop_invariant_..._preserved` timeouts from exactly this). Use the **range predicate**
  `loop invariant \valid_read(*p+(0 .. end-*p-1));` instead — WP carries it as one term with a good
  trigger, so preservation across the loop closes. Reserve the fixed-base `\forall` for the
  function precondition where the per-index instantiation is actually needed.
- **A buffer-extent precondition (`requires end-*p <= SIZE_MAX`) can't be bolted onto a leaf parser
  in isolation — propagate it through the whole `(buf,end)` family or it REGRESSES callers.** WP's
  Typed model treats a valid region's size as an unbounded `Z`, so a `(size_t)(end-*p)` cast in a
  postcondition won't collapse without this bound (it's what closed `mbedtls_asn1_get_bitstring_null`).
  But adding it as a `requires` to a *heavily-called* leaf (`get_tag`/`get_len`) turns it into a new
  obligation at **every** call site, and a caller with no size bound of its own (e.g.
  `x509_get_serial`) cannot discharge it — measured regression 57/57 → 57/58, and the target
  cast-residual didn't even close (mbedtls, 2026-06-19). The bound is only derivable at the
  **top-level** `*_parse_der(buf, len)` where `end = buf + len` and `len:size_t`. So either thread
  `obj_size` through the entire contract chain (top-level → every intermediate `(buf,end)` callee) in
  one coordinated pass, or leave the cast pointer-order goal as an honest PARTIAL. Do NOT add it to a
  middle/leaf function alone.

**`_Bool` is modelled truth-functionally — pin a canonical 0/1 when you compare two results.**
WP models a `_Bool` result by its *truth value*, so `ensures \result == (e)` constrains it only to
"nonzero iff `e`", **not** to exactly 1. A caller that compares two such results for equality
(`f(x) == f(y)`) then has a *non-entailed* goal (counter-model: the two results are 2 and 3, both
"true"). Fix by strengthening the callee contract with `ensures \result == 0 || \result == 1;` so
the comparison is determined. (This is what turned `stack_empty_wd` from a falsely-"unprovable"
PARTIAL into 14/14 SMT — see §0 on classifying non-entailment as a spec defect.)

## 5. The validation-gate checklist (acceptance test for "the coupling is sound")

- [ ] `why3 config list-provers` shows an SMT solver **and** Coq 8.20.1 (in the `framac-coq8` switch),
      and `frama-c -wp-detect` lists `(coq)`.
- [ ] Axiom set **consistency-probed**: a deliberately false lemma against the defining axioms does NOT prove.
- [ ] Batch SMT closes all *function* VCs (invariant, variant, RTE, postconditions) once the lemmas are available.
- [ ] SMT alone **fails** `gcd_greatest` (else suspect an over-strong axiom — the gate must be hard).
- [ ] The lemmas are proved in Coq, scripts saved into the session; each is **load-bearing** (removing it reddens a VC).
- [ ] `Print Assumptions wp_goal` on each: only definitional axioms (+ proved upstream lemmas), **0 admits**.
- [ ] A **fresh, headless** replay reaches 100% proved, reproducible on a clean checkout:
      `frama-c -wp -wp-rte -wp-prover alt-ergo,z3,coq -wp-cache replay -wp-session SESS file.c`.

---

## 6. Production alternative — link to Why3's `int.Gcd`

For real work you often should not re-prove gcd at all: Why3's stdlib `int.Gcd` already proves
divisibility/maximality. A WP **driver** can map your ACSL `gcd` symbol onto the library symbol so
WP emits goals against the proven theory and SMT closes maximality with no interactive proof
(`logic integer gcd(integer a, integer b) = "int.Gcd.gcd";` — exact syntax is version-sensitive;
check the WP manual). Trade-off: you inherit the library's *definition* (your spec's `gcd` must
coincide) and the C `%` facts still bridge to it. When that fits, maximality is free; when not, use
the hand-written-lemma + Coq route above — which is exactly why the gate validates the harder path.

## 7. Pitfalls
- **Looping on `why3 config detect`.** If re-detection keeps finding only SMT, the cause is
  structural (binary rename / realization mismatch / version pairing), not stale config. Fix the
  pairing (§1) or record the goal as "needs interactive proof — coupling unavailable."
- **`(Cached)` masking the Coq script** — use `-wp-cache none`/`replay` (§2).
- **Imports in the prelude get discarded** — put `Require` inside `Proof.` (§2).
- **Using `Z.modulo` lemmas** — C `%` is `Z.rem`; use the `rem`/`quot` family (§4).
- **Vacuous green from inconsistent definitional axioms** — consistency-probe (§3).
- **Hand-proving the postcondition in Coq** — isolate a lemma instead (§3).
- **`axiom` for a consequence** — silent unsoundness; prove it as a lemma (§3).
- **Signed `%`** — keep operands non-negative so divisibility reasoning stays clean.
