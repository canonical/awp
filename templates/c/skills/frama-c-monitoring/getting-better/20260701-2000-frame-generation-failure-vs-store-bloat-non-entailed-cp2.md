# NON-ENTAILED-as-generated (WP frame-GENERATION failure) is NOT store-bloat — read the goal to tell them apart; neither is closeable by Coq

**Date:** 2026-07-01 (libbpf cycle-34, "manual Coq on cp2"). **Bottom line:** a whole-function loop-point
validity goal that TIMES OUT can be one of two very different things, and the manual-Coq lever only helps ONE.

## The two failure modes (both print `[Timeout]`, both prove as a slice)
- **STORE-BLOAT:** the frame/needed hypotheses ARE emitted, but the SMT query is saturated (string-`Init`
  bloat, too many hyps). The goal is ENTAILED. Coq-`clear` the bloat + `assumption`/frame closes it. Class-C.
- **FRAME-GENERATION FAILURE:** WP does NOT emit the frame link at all, so the symbol is under-constrained
  and the goal is **NON-ENTAILED as generated**. **No prover — SMT or Coq — proves a non-theorem;
  Coq-`clear` removes bloat, it cannot ADD a missing hypothesis.** Also class-C (the property is true), but
  the lever is a WP fix / restructuring, NOT a manual Coq proof.

## How to tell them apart — READ THE GENERATED GOAL (don't assume store-bloat)
`btf_validate_type`'s `cp2` (`\valid_read((char*)(t+1)+(0..n*16-1))` at the member-loop point):
its Coq goal `valid_rd t a4 (16*to_sint32 x3)` has the cp2 alloc symbol **`t` appearing ONLY in
`valid_rd t a2 4`** — while `cp_env` sits in the hypotheses as `valid_rd t1 a4 (16*land 16777215 x)`
(alloc `t1`). The frame links **`t==t1`** (alloc) and **`x2==x`** (info re-read) — both TRUE (nothing
allocs/writes between the points) — are simply **not emitted**. `allocates \nothing` on the function AND
the callees does **not** restore them (the split is WP's loop/switch symbol versioning in the big context,
not a callee-alloc effect). So `t` is under-constrained ⇒ non-entailed ⇒ **the manual Coq cannot close it**.

## Why it's still CLASS-C, not class-A (the discriminator)
The `btf_member_walk` slice (`attacks/btf_member_walk.c`) proves the SAME walk **14/14** — one alloc symbol,
no split — so the property is true and closeable-in-principle. `no_ceiling_gate` REJECTs class-A on
twin-proves. The closure is a **WP frame-generation** fix (keep one alloc symbol across the loop/switch — the
filed `\valid_read` validity-carry-across-switch feature), or a restructuring; the **memory-safety is already
slice-WITNESSED**. Record: `btf_validate_type`/`sanity_check`/`bswap_rest` = **class-C, whole-function in-situ
owed, blocked by WP frame-generation (non-entailed cp2), safety slice-witnessed**. See [[no-ceiling-gate]],
[[wp-typed-ptr-cmp-no-baseaddr]], the §4b Breadth default.

## CORRECTION (cycle-35) — the "frame-generation failure" characterization is REFUTED; NO bug filed
Asked to file the WP frame-generation limit as a bug, I tried to build a minimal reproducer — the
bug-report discipline (a report needs a standalone reproducer). Built **7** (`reproducers/fg-bisect/t0..t7`)
adding, one at a time, every structural element of `btf_validate_type`: the member loop, `-simplify-cfg`
switch, a pre-switch `assigns/allocates \nothing` call, the length read from memory (`t->info&0xffffff`),
an inner call in the loop, BOTH `cp_env`+`cp2` asserts, a signed loop index, and a second object with a
recursive `valid_btf`-style predicate. **ALL SEVEN PROVE (cp_env+cp2 discharged).** So WP *does* emit the
frame link in every structurally-faithful minimal case — **the failure is NOT reproducible standalone**,
so there is **no sound bug to file**, and the "WP frame-GENERATION failure / non-entailed" label above is
**UNCONFIRMED and most likely WRONG**: cp2 in the full 300-line 6-kind function is **store-bloat** (the link
is emitted, but the accumulated context — all kinds' accessors + string-`Init` literals — saturates SMT),
not a frame-generation bug. My cycle-34 "t appears only in valid_rd t a2 4" read was **incomplete** (the
reproducers prove, so the link is present). LESSON REINFORCED and sharpened: **"non-entailed" is itself a
claim that needs a reproducer — an unreproducible frame-gen/non-entailment claim is exactly the tool-limit
say-so the no-ceiling gate forbids.** A minimal reproducer that PROVES refutes the tool-limit claim (same
as the no_ceiling twin-proves rule). Disposition unchanged in substance: cp2 = **store-bloat class-C**,
whole-function in-situ owed, closeable via context reduction; NOT a WP bug. The general store-bloat-vs-
frame-gen distinction (read the goal) stays valid; cp2 is store-bloat, not a confirmed frame-gen instance.

## FINAL (cycle-40) — cp2 IS non-entailed (frame-generation), settled by the definitive goal-read; the cycle-35 "store-bloat" label was WRONG
Trying theorem provers (per user) forced a full goal-read. DEFINITIVE (unambiguous math): cp2's alloc
symbol `t` is constrained ONLY by `valid_rd t a2 4` (=> t(base a1) >= off+8); the goal needs
`valid_rd t a4 (16*to_sint32 x3)` (=> t(base a1) >= off+12+16*x3). For x3>=1 a counterexample exists
(t(base a1)=off+8) => the goal is NON-ENTAILED as generated. The equalities that hold — `t==t1` (alloc
unchanged: `assigns __fc_errno; allocates \nothing` on fn + callees) and `t2==t3` (info unwritten) — are
NOT emitted by WP across the loop/switch, EVEN WITH `allocates \nothing` added (re-checked: goal identical).
So NO prover closes it (Coq batch = [Unknown]; SMT sweep AE/Z3/cvc5 all Timeout) — all consistent with a
non-theorem, NOT with store-bloat. **The cycle-35 "store-bloat, entailed" conclusion was WRONG**: it was
inferred from 7 reproducers that PROVE, but those reproducers EMIT the frame equality (they are entailed) --
they are non-faithful to the real goal's dropped equality. The definitive evidence is the goal-read (the VC
itself), which trumps the reproducers. So: cp2 = **NON-ENTAILED (WP frame-generation gap)**, not store-bloat.
UNREPRODUCIBLE minimally (the trigger for WP dropping the equality in the 300-line 6-kind fn isn't isolable;
small fns emit it) => filed as a FEATURE REQUEST `-wp-collapse-frame` (emit the frame equalities), NOT a
defect (per the reproducer discipline). Safety UNCHANGED: member reads safe = slice-witnessed given the
envelope + the envelope carries BY CONSTRUCTION (nothing writes/deallocs) = a REVIEWED-CAREFUL in-situ carry
(WP can't mechanize it). LESSON: the GOAL-READ (is the conclusion's symbol constrained?) is the ground truth
for entailed-vs-non-entailed; a proving reproducer only shows ITS goal is entailed, never the target's.
