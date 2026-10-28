# Lessons, gotchas, and the WP tool-gap catalogue

Consult this when a model won't parse or a harness goal won't discharge, to check
whether the blocker is a known kernel-ACSL gotcha or a known WP tool gap (with its
workaround) before treating it as new. Deep WP-internals fixes are the
`frama-c-internals` skill; this is the field guide.

## ACSL / kernel modeling gotchas

### `assigns \nothing` and the ghost frame
A bodiless `val`-style stub with no `assigns` is **not** effect-free for the ghost
state in the reader's eyes — be explicit. A no-op stub (§12 logging, §5 barrier) must
write `assigns \nothing;` so confinement holds (it cannot perturb `atomic_depth`).
A stub that *does* own a ghost region names **only** that region in `assigns` — never
a region it does not own (that would let it relieve another section's obligation).

### Bytes-model casts (`container_of`, `ERR_PTR`)
- The Typed model **rejects** member→struct pointer arithmetic and pointer↔integer
  punning. Switch the unit to the Bytes model (`-wp-model bytes` / Caveat) — see
  `modeling-kinds.md`.
- Wrap the punning in **one** (L) logic function with a proved round-trip lemma
  (`container_of_of_member`, `PTR_ERR(ERR_PTR(e))==e`) and let callers use the lemma so
  the rest of the unit stays Typed.
- `ERR_PTR` window: model `MAX_ERRNO = 4095` and the top-page predicate explicitly;
  the reserved range is what lets a kmalloc model filter error pointers (the Klever
  trick — see `linux-api-plan.md` prior art).

### `copy_*_user` return semantics (the classic fidelity trap)
`copy_from_user` / `copy_to_user` return **bytes NOT copied** (0 == full success), and
`copy_from_user` **zero-pads** the destination tail on a short copy. `__copy_from_user`
/ `__copy_from_user_inatomic` do **NOT** zero-pad. Transcribing the wrong one of these
is a faithful-to-a-fiction defect (Step-5 rule 5). `get_user`/`put_user` return 0 or
`-EFAULT`, a different convention — do not unify them.

### `__user` / `__rcu` / `__iomem` sparse annotations
WP does not consume these `__attribute__` taint markers directly. Strip them at the
overlay header (`#define __user` / `__iomem` to empty) and instead encode the taint
*structurally*: the user region is a `\separated` opaque region (§3), the iomem region
is an opaque modeled region (§13). Note in `notes/` that the sparse taint is modeled by
separation, not consumed.

### Macros vs functions
Much of §9 (`min`/`max`/`ALIGN`/`BIT`/`GENMASK`) and the list iterators (§7
`list_for_each_entry`) are **macros**, not functions — they expand in the unit, so they
cannot carry a stub contract. Two options: (a) provide an (L) `logic` definition + a
lemma the expanded code matches; (b) for iterators, supply the loop-invariant pattern
(reachability predicate) the macro's `for` expands to. Record which.

### `assigns` over arrays / ghost arrays
`assigns refcount[obj];` and `assigns ((char*)to)[0..n-1];` are the frame forms you
need most. WP's `assigns` inference is weak across calls — state the frame explicitly;
do not rely on inference for the ghost arrays.

### Chained / nested context depth
`spin_lock_irqsave` both raises `atomic_depth` AND sets `irqs_off` and must restore
*both* in `spin_unlock_irqrestore` — model the flags-save/restore as ghost so the
balance gate catches an unbalanced restore. `rcu_read_lock` raises depth too (no
sleeping in an RCU read-side critical section).

## WP tool-gap catalogue (route to Step 6 / convergence)

A *tool gap* is: the model is faithful and the property is true, but WP cannot express
or discharge it. Distinguish from a spec gap (contract too weak — fix the contract) and
a prover weakness (escalate to a cross-validated lemma). When it is a genuine tool gap,
write `DD-HHMM-convergence-gap-N.md` and route per `../SKILL.md` convergence loop.

| Symptom | Likely class | First move |
|---|---|---|
| `container_of` / cast goal won't discharge under Typed | model limitation | switch unit to Bytes; if still failing → `frama-c-internals` (cast/region trail) |
| inductive list/tree reachability `Unknown`/`Timeout` | prover weakness | cross-validated lemma (ACSL-by-Example predicates), not `Admitted` |
| `assigns` not propagated through a callee | tool gap | state the frame explicitly at the caller; gap if it blocks |
| pointer↔integer punning rejected | model limitation | Bytes + isolated accessor lemma |
| barrier/ordering property unstatable | **out of scope (by design)** | record as concurrency residual; hand to GenMC/Dat3M/herd7 — NOT a WP gap |
| a stub's behavioural fact needed but unprovable | prover weakness OR spec gap | run the non-vacuity probe: if the bad caller now passes, it was a spec gap |

**The escape order (never skip a goal):** compose from a proven callee contract FIRST;
a cross-validated `#@ proof`/Coq lemma only for irreducible facts; **never** a bare
`Admitted` / lemma-as-axiom / `\trusted`. A green obtained by an escape hatch is a
coherent-and-wrong proof — the exact failure the campaign exists to prevent.

## Stuck-proof strategy (in order)
1. Is it a **known gotcha** above? Apply the workaround.
2. Is it a **known WP gap** in the table? Apply the first move; gap it if blocked.
3. Does a **stronger precondition** legitimately hold (a real caller invariant)? Add it
   — but re-run the **non-vacuity** bad caller, since a stronger `requires` can make the
   contract vacuously easy.
4. Does a **weaker but still faithful** postcondition suffice for the section's
   `Property`? Use it, and record the strength (totality vs functional content).
5. Otherwise it is a genuine **Step-6 tool gap** → convergence loop / `frama-c-internals`.
