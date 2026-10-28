# Coq Standard Library Guide

Navigation guide for the Coq standard library and common packages.

## Library Structure

```
Coq.Init          — Core types, logic, nat basics
Coq.Logic         — Classical logic, extensionality, decidability
Coq.Arith         — Natural number arithmetic
Coq.ZArith        — Integer arithmetic
Coq.QArith        — Rational arithmetic
Coq.Reals         — Real number analysis
Coq.Lists         — List operations
Coq.Vectors       — Vectors (length-indexed lists)
Coq.Strings       — String operations
Coq.Bool          — Boolean operations
Coq.Sets          — Set theory (Ensembles)
Coq.Relations     — Relations
Coq.Sorting       — Sorting algorithms
Coq.Structures    — Ordered types
Coq.Numbers       — Unified number library
Coq.Program       — Program mode support
Coq.Classes       — Type classes
Coq.Wellfounded   — Well-founded recursion
```

## Searching

### Via MCP (preferred)
```
rocq_query("Search (nat -> nat -> nat).")       # By type pattern
rocq_query("Search \"add\" \"comm\".")           # By name
rocq_query("SearchPattern (_ + _ = _ + _).")    # By pattern
rocq_query("About Nat.add_comm.")               # Full info
rocq_query("Print Nat.add.")                    # Definition
rocq_query("Locate \"+\".")                      # Find notation
```

### Useful Queries by Domain

**Arithmetic:**
```
Search (forall n, n + 0 = n).
Search Nat.add.
Search (_ * (_ + _)).    (* distributivity *)
```

**Lists:**
```
Search (length (app _ _)).
Search (In _ (map _ _)).
Search (rev (rev _)).
```

**Logic:**
```
Search (~ ~ _ -> _).          (* double negation *)
Search (_ \/ _ -> _).         (* disjunction elimination *)
Search (exists _, _ /\ _).    (* existential with conjunction *)
```

## Common Lemma Patterns

### Natural Numbers (Coq.Arith)
| Lemma | Statement |
|-------|-----------|
| `Nat.add_0_r` | `forall n, n + 0 = n` |
| `Nat.add_comm` | `forall n m, n + m = m + n` |
| `Nat.add_assoc` | `forall n m p, n + (m + p) = (n + m) + p` |
| `Nat.mul_comm` | `forall n m, n * m = m * n` |
| `Nat.mul_assoc` | `forall n m p, n * (m * p) = (n * m) * p` |
| `Nat.add_sub` | `forall n m, n + m - m = n` |

### Lists (Coq.Lists.List)
| Lemma | Statement |
|-------|-----------|
| `app_nil_r` | `forall l, l ++ [] = l` |
| `app_assoc` | `forall l1 l2 l3, l1 ++ (l2 ++ l3) = (l1 ++ l2) ++ l3` |
| `rev_involutive` | `forall l, rev (rev l) = l` |
| `map_length` | `forall f l, length (map f l) = length l` |
| `in_map_iff` | `forall f l y, In y (map f l) <-> exists x, f x = y /\ In x l` |

### Logic
| Lemma | Statement | Import |
|-------|-----------|--------|
| `classic` | `forall P, P \/ ~P` | `Classical_Prop` |
| `NNPP` | `forall P, ~~P -> P` | `Classical_Prop` |
| `not_and_or` | `forall A B, ~(A /\ B) -> ~A \/ ~B` | `Classical_Prop` |

## MathComp

### Installation
```bash
opam install coq-mathcomp-ssreflect
opam install coq-mathcomp-algebra
```

### Key Differences from Standard Library
- Uses `ssreflect` proof language (`move=>`, `apply/`, `rewrite`)
- Boolean reflection: proofs via `bool` computation
- `finType` for finite types
- `eqType` for types with decidable equality
- Different naming conventions

### Common Imports
```coq
From mathcomp Require Import ssreflect ssrbool ssrnat eqtype seq.
From mathcomp Require Import fintype bigop.
From mathcomp Require Import ssralg ssrnum.
```

## Other Common Packages

| Package | Purpose | Install |
|---------|---------|---------|
| `coq-mathcomp-ssreflect` | SSReflect proof language | `opam install` |
| `coq-mathcomp-algebra` | Algebraic structures | `opam install` |
| `coq-coquelicot` | Real analysis | `opam install` |
| `coq-flocq` | Floating-point arithmetic | `opam install` |
| `coq-ext-lib` | Extended library | `opam install` |
| `coq-equations` | Dependent pattern matching | `opam install` |
| `coq-elpi` | Coq-Elpi metaprogramming | `opam install` |

## Coq 8.20 + Frama-C / Why3 realizations (verified on the `framac-coq8` switch)

Proving against Why3's Coq realization library (e.g. hardening Frama-C WP's `coqwp` — see the
`frama-c` skill's `references/coqwp-trust-root.md`) hits version- and path-specific traps:

- **`omega` is removed (since 8.12).** `Require Import Lia.` and use **`lia`** everywhere. Old
  Why3/coqwp sources that `Require omega` do **not** compile on 8.20 — re-prove in a self-contained
  file rather than fixing them in place.
- **The realization library is mapped to the `Why3` logical root:**
  `coqc -R "$(why3 --print-libdir)/coq" Why3 file.v` (and the same `-R` for `coqtop`). `BuiltIn.vo`
  must exist there — it is built by the `why3` opam package **only if Coq was installed first**.
- **Name clash: `Require Import Bool` picks *Why3's* `bool.Bool`, not Coq's**, under that `-R …
  Why3` mapping (partial names resolve against the mapped root) → `orb_true_iff`/`andb_true_iff`
  "not found". Force the stdlib module with **`From Coq Require Import Bool.`** (same fix for any
  module name living in both trees — `ZArith`, `Reals`, …).
- **`Coq.Reals` is axiomatized** (`ClassicalDedekindReals.sig_forall_dec` + usually
  `functional_extensionality_dep`): an `R`-based lemma can be free of *custom* axioms with **0
  admits** but can never be "Closed under the global context" — see the SKILL Quality-Gate note.
- **`Cantor`** (stdlib, 8.20) gives a ready `nat×nat ↔ nat` bijection (`Cantor.to_nat`/`of_nat`,
  `cancel_of_to`/`cancel_to_of`) — handy for realizing an abstract pair-encoding/decoding axiom.
- **Comment lexer:** a `"`-quoted string or an apostrophe inside `(* … *)` can swallow the closing
  `*)` ("non-terminated string") — keep header comments quote-free.

### Sound-witness vs genuine realization (the rigor distinction when filling an abstract `Admitted`)
When the `Admitted` thing is an **abstract symbol** (a bodyless `Definition`), its admitted *lemma*
is that symbol's **defining axiom**. Proving it for a **concrete witness** you choose shows the
axiom is *consistent/satisfiable* (sound to assume) — it is **not** an unconditional theorem; say
so. Witnesses that worked: a set as `a -> bool`; a float as a real **clamped** to `[-max,max]`; a
map as its access function `a -> b`. Only when Coq's stdlib already **defines** the symbol (realize
`asin := Ratan.asin`, `exp := Rtrigo_def.exp`) is the result a **genuine** theorem (the stdlib
lemma itself). Never give an abstract symbol a body that *implies the fact you want* — that smuggles
an axiom into the trusted base.
