# API inventory (enriched) — the upper/lower bound per section

Consult this when picking what to model next, deciding a section's bucket, or
checking the TCB consequence of a section. It **enriches** the authoritative
inventory in `linux/linux-api-plan.md` (which lists the actual symbols) with the
**squeeze spine** the plan leaves implicit: for each section, the upper bound (the
`Property` it buys), the lower-bound *fidelity oracle* (how you know the model is
honest, not just provable), the dominant **bucket**, and the **TCB** consequence.

> `linux/linux-api-plan.md` is the source of truth for the symbol lists and the
> (C)/(L)/(G) kind. Do **not** duplicate the symbol lists here — read them there.
> This file adds the bounds, the bucket, and the honesty column.

## The spine, per section

Legend — Bucket: **M** modelled (proved, low TCB) / **S** specified (trusted stub,
enters TCB) / **X** stubbed (proves nothing). Mem: default memory model for the unit.

| § | Subsystem | Upper bound (Property — from the plan) | Lower-bound fidelity oracle (pin to `linux-7.1.1/`) | Bucket | Mem | TCB note |
|---|---|---|---|---|---|---|
| 1 | Allocation | no-leak / no-UAF / no-double-free / correct-context alloc | `NULL`-on-fail; `\fresh`+size from the slab/page body; GFP sleep semantics | S (+L for sizing) | Typed | every allocator stub trusted |
| 2 | mem/string | no OOB r/w, no dst overflow, correct NUL-term | adapt Frama-C libc `__fc_*` ACSL; check vs `lib/string.c` | C→S, mem L | Typed | adapted libc stubs trusted |
| 3 | **user boundary** | every user buf bounds-checked via `access_ok`; tainted len validated; bytes-not-copied return | `uaccess.h`: return = bytes NOT copied; `copy_from_user` zero-pads short copy | S (+L) | Bytes if punning | **highest value**; stubs trusted |
| 4 | locks | lock-discipline (balanced, no double-acq, no sleep-while-held) — **NOT** mutual exclusion | ghost balance only; the real lock body is irrelevant | G→S | Typed | **concurrency residual** recorded |
| 5 | atomics/bitops/barriers | functional effect of counters/flags; bit indices in range | sequential effect from the body; **ordering = residual** | L (barriers G/no-op) | Typed | ordering trusted/residual |
| 6 | refcounting | refcount ≥ 0; freed only at last put; balanced get/put | ghost `refcount[obj]` per `kref`/`refcount` body | G→S | Typed | lifetime protocol trusted |
| 7 | **containers** | structural integrity; no traversal of freed node; membership | inductive reachability predicate vs `list.h`/`rbtree` body | L | **Bytes** for `container_of` | the bulk of effort; lemmas |
| 8 | ERR_PTR | callers test `IS_ERR` before deref; err-ptr never used as object | `err.h`: `MAX_ERRNO=4095`, top-page window | L (M) | **Bytes** | round-trip lemmas proved |
| 9 | int/overflow/align/endian | no int/size overflow in alloc-size & index computations | the `check_*_overflow`/`struct_size` macros *encode* the property | L (M) | Typed | mostly proved |
| 10 | **sleep/preempt/IRQ** | no sleeping op while `atomic_depth>0` | ghost depth; raised by preempt/spin/irq/rcu, asserted 0 at `might_sleep` | G→S | Typed | **kernel-unique**; protocol trusted |
| 11 | time/timers/work/wait | blocking only in sleepable ctx; init-before-use, cancel-before-free | sleeping calls tie to §10; ghost init/armed flags | C+G→S | Typed | protocol trusted |
| 12 | logging/assert/panic | effect-free **except** assertion macros | `BUG_ON(c)` as `assert !c` (catch) vs `assumes !c` (prune) — decide! | X (assert→M) | Typed | no-op; assert choice is load-bearing |
| 13 | MMIO/port/IRQ-reg | IO only within mapped region; no unmapped cookie; balanced req/free_irq | opaque modeled region; ghost map/irq registration | C+L→S | Bytes for iomem | iomem region trusted |
| 14 | registration/entry | entry validates every framework/user input before use | model the framework→driver contract, not a stub | harness | per-unit | the harness that makes §3 meaningful |

**How to read a row.** The Property column is what the section's harness (Step 5) must
re-prove over symbolic inputs across the *whole* listed surface. The fidelity-oracle
column is what Step 1 reads in `linux-7.1.1/` to keep the contract honest (and what the
non-vacuity bad-caller targets). The Bucket column tells you whether a green run is a
*proof* (M) or a *trusted assumption* (S) that must appear in
`references/soundness-ledger.md`.

## MVP ordering — why this order (faithful to the plan's §"minimal-viable")

Each tier unblocks the next; the highest bug density and the kernel-unique properties
come first, the heaviest prover effort last.

1. **§1 + §8 + §9** — without allocation, error-pointer encoding, and overflow-safe
   sizing, *nothing allocates or sizes safely*; this is where the heap-overflow CVE
   density lives. Note the coupling the plan implies: §9's `struct_size`/`array_size`
   *feed* the §1 allocator size argument — write the allocator contracts to **consume**
   the overflow-checked size, not merely coexist (the GFP→sleep hook of §1→§10 is the
   other cross-section seam).
2. **§2 + §3** — the data-handling primitives and the trust boundary; §3 is the highest
   security value (STRIDE info-disclosure/tampering are caught here) and depends on §2.
3. **§10 + §4** — the discipline properties unique to the kernel (libc has no analog);
   the biggest payoff per line of model. §4 raises the §10 ghost depth, so model §10
   first, then §4 on top of it.
4. **§6 + §11** — lifetime correctness (refcount balance; timer/work init-before-use,
   cancel-before-free). §11's sleeping calls tie back to §10.
5. **§7 containers** — last and largest; needs inductive predicates and the most prover
   effort. **Scope to the ONE structure the target unit actually uses.** Start with
   `list` + `container_of`: the doubly-linked list is what `hlist`, the rbtree
   `*_entry` accessors, and most intrusive containers *compose on*, and `container_of`
   is the concrete forcing case for the **Bytes** memory model (member→struct pointer
   arithmetic that the Typed model rejects). Do not attempt rbtree/xarray/idr before
   `list` proves end-to-end.
6. **§5 + §12 + §13 + §14** — fill in as the specific unit requires (atomics' sequential
   effect, logging no-ops, MMIO opaque region, the entry-point harness).

Decide the **memory model per unit** up front (Typed where you can; Bytes where §3/§7/§8
punning forces it) and record the **concurrency residual** for every §4 lock and §5
barrier modeled as ghost/no-op — both are in `references/modeling-kinds.md`.
