# Modeling kinds, the two cross-cutting decisions, and the ghost kernel state

Consult this when deciding HOW to model an API (which of C/L/G), which memory model
to use, where the concurrency boundary lies, or how the ghost kernel state is laid
out and confined.

## The three model kinds (from `linux-api-plan.md`)

| Kind | What it is | Use for | Default bucket |
|---|---|---|---|
| **(C) Contract stub** | bodiless header: `requires`/`assigns`/`ensures`/`allocates`/`frees` | allocators, string/mem, refcount, registration | Specified |
| **(L) Logic / axiomatic** | ACSL `logic`/`predicate`/`axiomatic` + lemmas, or a WP builtin | `memcpy`, `container_of`, list reachability, `ERR_PTR`, atomics, overflow | Modelled |
| **(G) Ghost protocol** | stub with no real semantics; updates ghost state to enforce a *call discipline* | locks, preempt/IRQ depth, sleep context, refcounts | Specified |

The kind is chosen by *what the property needs*: a **value** property (what bytes/ints
result) → (L); a **resource/lifetime/context** property (balanced, in-range, fresh) →
(C) for the local frame, (G) for the cross-call discipline. Many APIs are mixed: §3
`copy_from_user` is (C) for the frame + (L) for the byte-equality post; §11 timers are
(C) for the handle + (G) for init-before-use.

## Cross-cutting decision 1 — the memory model (per unit)

WP offers a spectrum; the relevant poles:

- **Typed** — fast, structured; **rejects pointer punning**. Use wherever the unit does
  not reinterpret memory across types. Default for §1, §2, §4, §6, §9, §10, §11.
- **Bytes / Caveat** — sound on `container_of`, `ERR_PTR`, packet/struct parsing, and
  any cast between pointer and integer or between incompatible pointer types — but
  **much slower**. Forced by §8 (ERR_PTR punning), §7 (`container_of` member→struct
  arithmetic), §3/§13 where a user/iomem region is parsed as bytes.

**Rule.** Choose per unit, decided at Step 1, recorded in the model's notes. **Isolate
punning behind modeled accessors** so the rest of the unit can stay Typed: wrap the
`container_of`/`ERR_PTR` move in a single (L) logic function with a proved round-trip
lemma, and let callers use the lemma — they never see the cast. If a unit *mixes*
(most of it Typed, one accessor punning), the accessor's lemma is the seam: prove it
once under Bytes, expose it as a contract, keep the caller Typed. Deep WP memory-model
behavior (why a cast/region goal won't discharge, the +cast/Region models) is the
`frama-c-internals` skill — route a genuine model wall there as a Step-6 gap.

## Cross-cutting decision 2 — the concurrency boundary (the no-blend line)

**WP is sequential.** This is the single most important honesty constraint of the
campaign, and the source of its dominant coherent-and-wrong.

- A lock modeled as **ghost balance** (raise on acquire, lower on release) gives:
  *lock-discipline* (balanced acquire/release, no double-acquire, correct IRQ
  save/restore, no-sleep-while-held) **AND** a sequential functional proof **under
  ASSUMED mutual exclusion**.
- It does **NOT** give **race-freedom**. Two threads, interleavings, store buffering,
  and memory ordering are entirely outside WP's view.

**The no-blend rule (Gate C).** A ghost-lock model must **never** stand in for a
race-freedom claim. The deliverable's scope statement says, per lock and per barrier:
"modeled as ghost/no-op; discipline proved, *ordering and race-freedom are residual*."
The residual is handed to the companion lane — **GenMC / Dat3M / herd7 / VSync / the
Linux-Kernel Memory Model** (the plan's prior-art list). An §5 barrier (`smp_mb`,
`READ_ONCE`/`WRITE_ONCE`, `smp_load_acquire`) is a **G/no-op for WP** — it has no
sequential effect — and its ordering semantics are pure residual; record them, never
model them as if WP saw them.

Blending these two planes (letting "the lock discipline proved" read as "the code is
race-free") is exactly the failure `sl-internal`'s Gate C / archetype-C no-blend
cross-check exists to catch. Keep them visibly separate in every report.

## The ghost kernel state — layout and confinement

One shared set of ACSL ghost variables, mirroring the kernel's one coherent state
(the analog of `pycsl-stdlib-coverage`'s World). Declared once in the overlay's common
header, **region-partitioned by ownership**:

```c
//@ ghost int      atomic_depth;   // §10: preempt/IRQ/spinlock/RCU nesting; 0 == sleepable
//@ ghost int      irqs_off;       // §10/§4: local IRQ-disabled flag
//@ ghost integer  lock_balance;   // §4: acquire/release balance (per lock class if modeled)
//@ ghost integer  refcount[N];    // §6: per-object ghost refcount
//@ ghost int      armed[N];       // §11: timer/work init-before-use & armed flags
```

| Region | Owner stubs (the ONLY writers) | Readers |
|---|---|---|
| `atomic_depth`, `irqs_off` | `preempt_disable/enable`, `spin_lock/unlock`(+irq/bh variants), `local_irq_save/restore`, `rcu_read_lock/unlock` | `might_sleep` and every sleeping op: `GFP_KERNEL` alloc, `mutex_lock`, `msleep`/`usleep_range`/`schedule`, `copy_*_user`, `wait_event` |
| `lock_balance` | the §4 lock stubs | the unit-exit balance gate |
| `refcount[obj]` | `kref_get/put`, `refcount_inc/dec(_and_test)`, `get/put_device`, `get/put_page`, `get_file/fput`, `try_module_get/module_put` | the UAF/leak gate (freed only at last put) |
| `armed[obj]` | `timer_setup`/`mod_timer`/`del_timer(_sync)`, `INIT_WORK`/`schedule_work`/`cancel_work_sync` | the init-before-use / cancel-before-free gate |

### Confinement (the HAPPY analog)
Coherence across sections is enforced by **confinement, not per-call `assigns`
enumeration**. Each stub's `assigns` set names *only the region(s) it owns*; a stub
that owns none assigns `\nothing` over the ghost state:

```c
/*@ assigns \nothing; */   // printk owns no ghost region — cannot perturb atomic_depth
int printk(const char *fmt, ...);
```

**What this buys.** Because §12 logging, §5 barriers, and the pure (L) helpers have
**no write site** into `atomic_depth`/`lock_balance`/`refcount`, the property "the
atomic context / lock balance / refcount is preserved across a `printk` (or barrier,
or `min()`) call" is a **corollary of ownership** — no `assigns` clause enumerates it.
This is what keeps a §12 logging call from ever *relieving* a §10 sleep-context
obligation, and is the direct analog of `pycsl-stdlib-coverage`'s HAPPY ownership
confinement (`sys`/`io`/`time` cannot perturb the `fs` region).

**Consequence for the ledger.** Every stub that *does* own and mutate a ghost region
is **Specified (trusted)** — its `ensures` on the ghost state is an axiom, not a VC.
The set of such stubs is the ghost-protocol TCB; list it in
`references/soundness-ledger.md`. A green run trusts that these stubs update the ghost
state faithfully to the real kernel behavior — which is exactly what the fidelity
oracle (the `linux-7.1.1/` body) and the non-vacuity bad-caller are there to keep
honest.
