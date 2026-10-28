# The bitwise-SMT incompleteness trail (true-but-hard, bitmask sub-case)

A durable companion to the filed item `bugs-to-report/wp-bitwise-smt-incompleteness/`. Read
this when a WP goal over `&`/`|`/`~` won't discharge and you need to know whether to fight it,
trust it, or route it.

## What it is (and is NOT)
- **Residue class: (2) true-but-hard** — the goal is valid, has no counter-model, and is closed
  by Coq or the `wp:bitrange` tactic. It is **prover-automation incompleteness**, *not*
  unsoundness and *not* a model-limitation. Distinct from the `wp-cast-region-soundness` trail
  (class 3): there the fact is *discarded by the encoding*; here it is *present but unfound*.
- **Encoding:** WP lowers `&`/`|`/`~` to Why3 `land`/`lor`/`lnot` (axiomatized, **not** native
  bitvectors). Z3's BV theory is therefore never engaged on these goals.

## The discriminator (which facts fail)
Verified on Frama-C 32.1, Alt-Ergo 2.6.3 + Z3 4.13.3 (`reproducers/bitwise_lemmas.c`):
- **Discharge (OK):** anything with the constants `0`/`~0` (`a&0==0`, `0|a==a`, `a&~0==a`),
  commutativity (`a|b==b|a`), and the shift/div bridge (`a>>1 == a/2`).
- **Reliably FAIL:** monotonicity/bound + composition — `(a&b) ≤ a`, `a & ~a == 0`,
  `d < m ⟹ (d & ~m) < 2^63` (the `tnum_step` shift-safety case).
- **FLAKY** (prove on some runs only; solver/tactic-order nondeterminism, so unsafe to gate on):
  `(a&b) ≤ b`, `(a&b)&~a == 0`, `m ≥ 2^63 ⟹ ~m < 2^63`.

## What to do when you hit it
1. **Confirm the class** with the refutation probe (supply the negation antecedent — it does not
   flip to `Valid`, and there is no counter-model → not class 1).
2. **Avoid it if you can** — reformulate to a `~`-free / constant-anchored form (e.g. use
   `cap_combine`/`cap_intersect` `|`/`&` algebra and the `0`/`~0` identities, not `cap_issubset`'s
   `& ~`); or express the measure arithmetically (the `>>1 == /2` bridge turns a bitwise loop
   variant into `a/2`, which *does* discharge — this is how `tnum_mul` termination was closed).
3. **If unavoidable:** `wp:bitrange,wp:split` (sound bit-blast) closes most of them but is slow
   (~64 subgoals/word) and order-flaky — usable for a one-off proof, not a routine gate. Else
   demote the op to a *Specified* stub whose faithful contract is trusted, and **ledger it**
   (loud residual; never `\trusted`/`Admitted`/lemma-as-axiom).

## The fix (filed)
Add a proved `land`/`lor`/`lnot` monotonicity+bounds lemma library to the WP Why3 preamble (one
offline Coq proof each, then available to Alt-Ergo by E-matching) — would remove all three of the
campaign's bitwise residuals at once. Alternatives (BV routing, faster bitrange) in
`bugs-to-report/wp-bitwise-smt-incompleteness/REPORT.md` §"Suggested fixes".

## Provenance
Surfaced by the `linux-api` campaign (`linux/linux-acsl`): `tnum_step` shift (1 residual of 12),
the `security/` capability lattice (`cred.h` subset/drop laws), reconfirmed as a cross-subsystem
pattern. Reproducers + `verify.sh` under the filed item.
