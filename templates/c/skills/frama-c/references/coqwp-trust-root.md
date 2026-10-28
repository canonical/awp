# `coqwp` — the Coq-backend trust root, and how to harden it

`coq-escalation.md` covers proving *your* WP goal in Coq. This file covers what that
proof **rests on**: WP's Coq *realization library* `coqwp`, the TCB of every
`-wp-prover coq` green. Distilled & **verified** from vendoring + hardening it
end-to-end on **Frama-C 32.1 / Why3 1.8.2 / Coq 8.20.1** (the `framac-coq8` switch).

## 1. What `coqwp` is, and why it is the TCB

`-wp-prover coq` does **not** `Require` a precompiled library — it **inlines** WP's
Why3→Coq theories into each goal's prelude. Those theories are the ~36 `.v` files at
**`$(frama-c -print-share-path)/wp/coqwp/`** (`Memory.v`, `Vset.v`, `Cfloat.v`,
`Cint/Cbits/Zbits`, `Qed/Qedlib`, the float theories, plus the Why3 stdlib
realizations `bool/int/map/real`). Every coq green is sound **only modulo whatever
those files leave unproved** — so a `Print Assumptions` clean on *your* script (§
coq-escalation) is necessary but **not sufficient**: the realization layer underneath
it can itself carry admitted facts. Audit it once; it is shared by every proof.

## 2. The three kinds of "unproved" in `coqwp` — they are NOT equal

Grep the vendored copy; classify each `Admitted`/`Axiom` before trusting or "fixing":

1. **`Axiom` (3 total)** — all `WhyType` instances (`addr_WhyType`,
   `rounding_mode_WhyType`, `float_kind_WhyType`): a type-class witness
   (inhabitant + decidable eq) for a declared type. **Standard and benign.**
2. **`Admitted` *opaque definitions* (~52)** — `Definition region : Z -> Z. Admitted.`,
   `linked`, `sconst`, most float/set operators. These are **abstract symbols with no
   body** = the Coq image of a Why3 *declared* (uninterpreted) symbol. **Sound** (an
   opaque constant relates to nothing, so it cannot prove `False`) and **carry no
   information**.
3. **`Admitted` *lemmas* (~57)** — e.g. all 11 in `Memory.v` are tagged
   `(* Why3 goal *)`: Why3 expected a **proof** and the realization left it admitted.
   **These are the real trust surface** — every coq green using one rests on it.

| file | opaque-def Admitted | **lemma Admitted (trust surface)** |
|---|---|---|
| `Memory.v` | 9 | **11** |
| `Vset.v` | 11 | **11** |
| `Cfloat.v` | 30 | **32** |
| `ArcTrigo.v` | 2 | **2** |
| `ExpLog.v` | 0 | **1** |

## 3. The rigor rule (the heart of it — same root as the `sconst` decision)

**Never realize an abstract Why3 symbol with *content* in order to close a goal.** WP
emits abstract symbols (`sconst`, `region`, …) as content-free tags; giving one a Coq
body that implies a fact you want **smuggles an axiom into the TCB**, and one wrong
axiom makes every coq green vacuous — the opposite of rigor. The discipline:

- Realize a symbol only to **match** its Why3 definition.
- **Prove** (`Qed`) the Why3 *goals* (the `(* Why3 goal *)` lemmas).
- **Admit** only Why3 *assumptions*, and document each.
- After proving, `Print Assumptions` must show **only** the intended axioms — see §5.

This is why we did **not** patch `sconst` to imply `is_sint8` to close the strncpy
`valid_read_nstring` goal: `is_sint8` of a char is genuinely true but WP supplies it
**per char read**, not as a property of the raw `addr→Z` map — asserting it on the map
would be unsound (the int chunk is also an `addr→Z` map; chunk-typing is erased). The
sound closes were upstream (WP goal generation) or C-side, **never** in `coqwp`.

## 4. Hardening technique — self-contained `*_hardened.v`

`coqwp` is **source-only and does NOT build on Coq 8.20** (it uses `omega`, removed in
8.12 → use `lia`). So you cannot just fill its `.v` in place; instead write a
**self-contained `<Theory>_hardened.v`** that **restates the admitted lemmas verbatim**,
**restates the relevant definitions verbatim**, realizes any abstract symbols with a
**sound witness**, and proves each with `lia`/stdlib. Build each with:

```sh
coqc -R "$(why3 --print-libdir)/coq" Why3 Memory_hardened.v     # exit 0
```

Three grades of result — **state which one each lemma is**, they are not equal in force:

- **Proved OUTRIGHT** — over the verbatim *concrete* definitions ⇒ an unconditional
  theorem exactly matching `coqwp`'s lemma. (5 of Memory's 11: `separated_*`,
  `eqmem_*`.)
- **Proved for a SOUND WITNESS realization** — the symbol is *abstract* in `coqwp`, so
  its admitted lemma is its *defining axiom*; proving it for a concrete witness shows the
  axiom is **consistent / satisfiable** (sound to assume). The witness models that worked:
  | theory | witness model |
  |---|---|
  | `Memory.v` | `farray a b := a->b`; `addr↔Z` via a `Z↔nat` bijection + stdlib **`Cantor`**; `havoc` via a decidable `separated`; `table_to_offset` = identity |
  | `Vset.v` | `set a := a -> bool` (decidable membership; `singleton` uses `WhyType`'s decidable eq) |
  | `Cfloat.v` | `f32:=f64:=R`; `of_f`=id; `to_f`=**clamp into [-max,max]**; ops=`to_f(real op)`; compares via `Rle_dec`/`Req_EM_T`; `classify` Finite iff in range |
- **GENUINE realization** — when Coq's stdlib already *defines* the symbol, realize it as
  that and the lemma is the stdlib fact itself (not a witness): `ArcTrigo` `asin/acos` :=
  `Ratan.asin/acos` ⇒ `sin_asin`/`cos_acos`; `ExpLog` `exp` := `Rtrigo_def.exp` ⇒ `exp_pos`.

## 5. The axiom bar — and why `R`-based theories can't be "Closed"

`Print Assumptions <lemma>` is the gate. Two achievable bars:

- **"Closed under the global context"** — zero axioms (Memory: all 11; Vset: 9 of 11).
- **Depends only on whitelisted *standard* axioms** — the honest bar when the theory is
  built on axiomatized stdlib. Two cases seen:
  - `functional_extensionality` — needed wherever a lemma states **equality of two
    functions** (Vset's `union_empty`/`inter_empty`, with `set := a->bool`). It is a
    standard Coq axiom and exactly what `Qedlib` itself assumes (`Hypothesis
    extensionality`).
  - **Coq's `R` is itself axiomatized**, so **no `R`-lemma can be "Closed"** — every
    `Cfloat`/`ArcTrigo`/`ExpLog` lemma depends on exactly
    `ClassicalDedekindReals.sig_forall_dec` (pulled in by `Rle_dec`/`Req_EM_T` and `%R`
    literals) + `functional_extensionality_dep`. **No admits, no custom axioms** is the
    real claim there, not "Closed".

Gate it in CI with a `check.sh` that, per file: greps for no `Admitted.`/`admit`,
compiles, and asserts every lemma is `Closed under the global context` **or** every
axiom-name line matches that file's standard-axiom whitelist (empty whitelist ⇒ must be
Closed). Any other axiom name fails the build.

## 6. Coq-8.20 / Why3-realization traps (cost real time)

- **`omega` is gone (since 8.12)** → `Require Import Lia.` and use `lia`. `coqwp`'s own
  `Qedlib.v` does not compile on 8.20 for this reason — hence the self-contained files.
- **`Require Import Bool` resolves to *Why3's* `bool.Bool`, not Coq's**, under
  `-R "$(why3 --print-libdir)/coq" Why3` (the dir is mapped to the `Why3` root, and
  partial names match it) → `orb_true_iff` "not found". Force Coq's: **`From Coq Require
  Import Bool.`** (same for any name that exists in both trees).
- **Double-quotes / apostrophes inside a Coq comment** trip the comment lexer
  ("non-terminated string … `*)`") — keep header comments quote-free.
- Build the realizations once with Coq present (§ launch); `BuiltIn.vo` must exist under
  `$(why3 --print-libdir)/coq` or `Require Import BuiltIn` fails.

## 7. Vendoring + CI (the "extreme rigor" deliverable)

When a coq backend is load-bearing, **vendor `coqwp` into the repo** (copy
`$(frama-c -print-share-path)/wp/coqwp/` verbatim, record CEA/LGPL-2.1 attribution),
add the `*_hardened.v` proofs + `AUDIT.md` (the §2 classification) + `check.sh`, and
**gate it in CI**. To override WP with the vendored copy at proof time use
`-wp-share <dir>` (recompile). CI install order is load-bearing: **Coq before Why3**
(Why3 builds its Coq realizations only if Coq is already in the switch) — see the
`frama-c-launch` skill. Result on this repo: all ~57 admitted lemmas machine-checked;
the ~52 opaque-def Admitteds + 3 `WhyType` Axioms remain **by design** (abstract
symbols, not facts).

## 8. This is shipped in `macsl` — a strictly smaller TCB than legacy Frama-C

This hardening is **done and CI-gated in the `macsl` project** (`macsl/axiom-wp/coqwp/`,
`check.sh` → exit 0, audited 2026-06-21). It is a concrete, measurable benefit of macsl over
stock Frama-C, independent of the HAPPY policy language:

| | stock Frama-C `coqwp` | macsl `coqwp` |
|---|---|---|
| Unproven trust-bearing lemmas (the real trust surface) | **58** | **0** (admit-free `*_hardened.v` twins, CI-gated) |
| Custom / behavioural axioms | 0 | 0 |
| Standard axioms relied on | — | `functional_extensionality`, `sig_forall_dec`/`sig_not_dec`, classical logic, Coq native `PrimInt63`/`Uint63` (only where needed: ℝ-based float/real lemmas + the π lemma's CoqInterval computation) |

So when a Coq backend is load-bearing, prefer **macsl's hardened `coqwp`** — the same WP realizations
with the entire 58-lemma trust surface discharged. The last lemma `Pi_double_precision_bounds` (tight π
bounds) is now **proved with CoqInterval** (`split; interval with (i_prec 70)`), in both the twin and
the patched original `real/Trigonometry.v` (so that file gains a build-time `coq-interval` dependency).
Remaining work: the parallel **Lean** cross-validation (`macsl/axiom-wp/leanwp/`, `DUALTP-STATUS.md`) —
a future `Why3 ≡ Coq ≡ Lean` 3-way check.
