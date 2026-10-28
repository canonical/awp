# WP drops the memory frame across a macro-expanded `do{}while(false)` loop

**Date:** 2026-06-26  **Context:** zk37 Zephyr-kernel `/time-loop` cycle-3, RS5 SA2 permission gate
(`userspace_handler.c`).

## Symptom
A handler that does `ko = validate(...); K_OOPS(K_SYSCALL_VERIFY_MSG(ko != NULL, ...)); use(ko);`
leaves the `\valid(ko)` precond of `use(ko)` as a **TIMEOUT** even though the validator's
`ensures \result==\null || \valid(\result)` + the noreturn-`oops` guard logically entail it (and the
same pattern proves 6/7 in a tiny isolation probe). High `-wp-timeout` (90s+) does **not** help.

## Trap (what cycle-2 got wrong)
Concluding "true-but-SMT-hard under the `_kernel`/`_current` aggregate → class A prover ceiling →
escalate to Coq." **WRONG.** Dump the actual goal (`-wp-interactive edit`, `EDITOR=true`): the
load-bearing pointer (`ko`/`a:addr`) is **completely unconstrained** in the goal, or the deref and the
validity hypothesis sit on **two unlinked heap/state symbols** (`t` vs `t1`, `z` vs `z1`). That goal is
**FALSIFIABLE as posed** — so Coq cannot close it admit-free either; a "Coq close" would require a
smuggled frame/equality axiom. A falsifiable goal is a **frame gap**, never a prover-capacity ceiling.

## Root cause
`K_OOPS` / `K_SYSCALL_VERIFY_MSG` expand (via `LOG_ERR`) to a `do{ ... }while(false)`, which CIL
normalizes to `while(1){ ...; break; }`. To WP this is a real loop; with no `loop assigns`/`loop
invariant` it conservatively **havocs the whole memory frame** across the loop, dropping `\valid(ko)`
and `\valid(_current)`. Reproduced with a bare `if(c) while(1){break;}` and **no call inside** —
removing just the loop flips TIMEOUT → PROVED.

## Fix
- **`-ulevel 1`** (loop unrolling). The macro loop is once-through (`do{}while(false)`), so unrolling is
  **sound and semantics-preserving** — and source-free (kernel stays pristine). This restores the frame.
- If a sibling call on the path (e.g. a `static inline` helper like Zephyr's `k_object_validation_check`)
  also lacks an explicit `assigns`, give it `assigns \nothing` (faithful when its body only reads + logs)
  so WP can prove the global aggregate (`_kernel`) is preserved across it — this supplies the missing
  `z=z1`/`t=t1` link.

After both: 17/17 on the verifier bodies, cache-clean (`-wp-cache none`), SMT-only, no Coq, no EVA.
Mutation probe (weaken the validator `ensures` to `\true`) re-breaks it → non-vacuous.

## Rule
When a goal-dump shows the key pointer unconstrained or two unlinked heap/state symbols: it is a
**WP frame drop**. Look for an un-annotated macro `do{}while(false)` loop (unroll with `-ulevel 1`) and
un-`assigns`'d `static inline` helpers on the path. Do NOT relabel as "SMT-hard / escalate to Coq" —
Coq cannot fix a falsifiable obligation.
