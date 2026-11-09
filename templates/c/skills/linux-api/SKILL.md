---
name: linux-api
description: >-
  Build a Frama-C/WP-checkable model of Linux kernel APIs: ACSL contract stubs, logic models and ghost-state protocols. Use to verify real kernel callers against auditable service models, with coverage accounting and non-vacuity checks.
---

# Linux Kernel API Modeling (Squeeze Loop)

A Squeeze Loop that BUILDS the Linux kernel's API as a Frama-C/WP-checkable "modeled runtime" — ACSL contract stubs, logic/axiomatic models, and ghost-state protocol stubs that stand in for the kernel services a unit calls, so that real kernel code can later be verified against them. It is the kernel analog of pycsl-stdlib-coverage: a coverage CAMPAIGN over the API surface inventoried in linux/linux-api-plan.md (14 subsystems: allocation, mem/string, the user/kernel boundary, locks, atomics, refcounting, containers, ERR_PTR, integer/overflow, sleep/preempt context, time/timers/work, logging, MMIO/IRQ, registration), faithful to the Linux sources in linux/linux-7.1.1/. Each model is squeezed between two sources of truth — the kernel-doc/man/POSIX English (upper bound, the strongest property each API buys) and the actual C in linux-7.1.1/ (lower bound, the fidelity oracle) — and is accepted only when (a) it is faithful to the source, (b) a client harness proves a downstream CONSEQUENCE through the public API, and (c) a seeded-bad caller is CAUGHT (non-vacuity mutation probe). Produces the durable linux/linux-acsl/ overlay consumed by frama-c-launch / frama-c-monitoring / framac-sl, with an explicit Soundness Ledger (TCB) of what is trusted vs proved. Use when adding a new kernel-API model, writing ACSL contract/logic/ghost stubs for a subsystem, authoring a client harness, diagnosing a WP proof failure on a kernel stub, deciding the per-unit memory model (Typed vs Bytes), or applying the convergence loop ("apply the linux-api convergence principle to <section>" — e.g. "model the user-boundary API").

## Purpose and scope

The kernel is its own libc: verifying *any* kernel unit with Frama-C/WP first
requires a **modeled runtime** — the ACSL contracts, logic models, and ghost-state
stubs that stand in for the kernel services the unit calls. This skill governs the
disciplined *construction* of that modeled runtime as a Squeeze Loop, faithful to
the inventory in **`linux/linux-api-plan.md`** and to the Linux sources in
**`linux/linux-7.1.1/`**.

The deliverable is the **`linux/linux-acsl/` overlay**: bodiless contract stubs,
ACSL `logic`/`axiomatic` models, and ghost-protocol stubs, mirroring the
`include/linux/` header paths, *each one squeezed between the two sources of truth
and accepted only by gates* — never by an author's say-so. Its consumers are the
existing Frama-C SL family (`frama-c-launch` scaffolds the overlay, `frama-c-monitoring`
schedules units, `framac-sl` proves each unit against these stubs). This skill is to
that family what `pycsl-stdlib-coverage` is to PyCSL: the **coverage campaign** that
decides *what* to model, *to what strength*, and *how you know the model is honest*.

This skill assumes the SL vocabulary (`sl-internal`: the squeeze, coherent-and-wrong,
disjointness, gates A/B/C/S, DRAFT→APPROVED→DONE) and the ACSL vocabulary (`frama-c`:
`requires`/`ensures`/`assigns`, `\valid`/`\separated`, `logic`/`predicate`/`axiomatic`,
ghost code, `-wp-rte`). It does **not** re-derive them; it points at them.

### What the deliverable is NOT

- It is **not** a re-implementation of the kernel. A contract stub is a *bodiless*
  ACSL header (kind C/G) or a *logic model* (kind L) — it captures the
  contract-relevant behavior (pre/post, state transition, error condition), not the
  real allocator/list/lock machinery.
- It is **not** a race-freedom proof. WP is sequential; locks modeled as ghost
  balance give lock-discipline *under assumed mutual exclusion* — see the
  **concurrency boundary** decision below.
- It is **not** done when "the stubs parse." A stub that parses but is vacuous (too
  weak to reject a bad caller) certifies a fiction. Done is gate-defined (Step 5).

---

## Source of truth — what shapes every stub

A `linux/linux-acsl/` model is not invented; it is **transcribed and squeezed**
between two sources of truth (the Squeeze Strategy's cornerstone S0; exactly the
discipline `pycsl-stdlib-coverage` applies to a stdlib stub, lifted to ACSL):

- **English — the normative specification (upper bound `U`).** What the API is
  *specified* to do, including its error/return conditions:
  - the **kernel-doc** comments on the function in `linux/linux-7.1.1/` (the `/** … */`
    blocks — e.g. `ERR_PTR`'s "Encodes @error into a pointer value"),
  - `linux/linux-7.1.1/Documentation/` (subsystem semantics), and
  - `man 9` / POSIX where the API mirrors a libc one (`memcpy`, `str*`).
  **This is the source of the *property* each model buys** — every `ensures` should
  be a formal shadow of a documented sentence, and every section of
  `linux-api-plan.md` already names its "*Property:*" line. Write the **strongest**
  property the English justifies (see "Contract-writing rules").
- **Execution — the reference implementation (lower bound `L`, the fidelity oracle).**
  What the API *actually does*: the C body in `linux/linux-7.1.1/`. It is ground
  truth for everything the English leaves implementation-defined — exact return
  semantics (`copy_from_user` returns **bytes NOT copied**, and zero-pads the
  destination on a short copy; `__copy_from_user` does **not** zero-pad), the
  `MAX_ERRNO = 4095` reserved range for `ERR_PTR`, the GFP sleep semantics, the
  precise `assigns` set. **The model must agree with `linux-7.1.1/` on every input
  the client harness exercises.**

**How they divide the work on a stub:**
1. Read the **kernel-doc / Documentation** entry → write the strongest property it
   justifies (the `ensures`, the `assigns`, the `allocates`/`frees`).
2. Where the English is silent or ambiguous → read the **C body in `linux-7.1.1/`**
   and model *that* (do not guess a convenient contract). Pin the exact version:
   this overlay is faithful to **`linux-7.1.1`** — record it, never drift to a
   different tree (a fidelity tell, like pycsl's "wrong CWD").
3. Where the kernel-doc and the body **disagree** → that is a finding to surface
   (a doc bug or an undocumented quirk), recorded in the model's notes — not a coin
   to flip.

**Squeezed between the two, the stub has no freedom.** The kernel-doc bounds the
contract from above (the strongest postcondition the English justifies), the C body
bounds it from below (what actually executes). There is no convenient contract to
choose — only the one both force. That squeeze is *why* a faithful modeled runtime
is possible: you are not designing kernel behavior, you are transcribing it.

**Anchor the transcription, and close the loop.** Make fidelity *auditable*: anchor
each contract to the sentence/line it transcribes — `// cite: include/linux/err.h
kernel-doc ERR_PTR` and a one-line paraphrase — so a reader can trace any `ensures`
back to its authority. Transcribing is not one-way: the source of truth is where the
proof *ends*, not only where it begins. The **client harness** (Step 5) re-states
the section's own "*Property:*" promise over *symbolic* inputs and discharges it for
all of them — the descent into a faithful model returning, at the top, to the English
it came from. A section is "done" when that loop is closed for its **WHOLE listed API
surface**, not a sample (see Step 5's coverage rule).

---

## The ghost kernel state — one coherent state, region-partitioned

The Unix kernel maintains **one** coherent state; the `pycsl-stdlib-coverage` World
mirrors it with one shared filesystem/proc/clock. Here the analog is the **ghost
kernel state**: a single set of ACSL ghost variables that the protocol stubs (kind G)
read and update, so call-discipline properties are statable across calls.

```c
//@ ghost int      atomic_depth;     // preempt/IRQ/spinlock/RCU nesting (§10) — 0 == sleepable
//@ ghost int      irqs_off;         // local IRQ-disabled flag (§10/§4)
//@ ghost integer  lock_balance;     // ghost lock acquire/release balance (§4)
//@ ghost integer  refcount[...];    // per-object ghost refcount (§6)
// (heap freshness/ownership for §1 is carried by WP's allocation model + \fresh)
```

It is **region-partitioned by ownership**, exactly as the kernel's own state is:

| Ghost region | Owner stubs (may write) | Who reads it |
|---|---|---|
| `atomic_depth`, `irqs_off` | `preempt_disable/enable`, `spin_lock/unlock`, `local_irq_*`, `rcu_read_lock/unlock` (§10/§4) | `might_sleep`, every sleeping op (`GFP_KERNEL` alloc, `mutex_lock`, `msleep`, `copy_*_user`) |
| `lock_balance` | `spin_lock/unlock`, `mutex_lock/unlock`, … (§4) | the balance gate at unit exit |
| `refcount[obj]` | `kref_get/put`, `refcount_inc/dec`, `get/put_*` (§6) | use-after-free / leak gate |

**Confinement (the HAPPY analog).** A no-op stub (`printk`, a barrier, a logging
call) must **not** perturb the ghost context — its `assigns` set excludes the ghost
regions it does not own. Because `printk` et al. have no write site into
`atomic_depth`, "the atomic context is preserved across a `printk` call" is a
*corollary of ownership*, with no per-call `assigns` enumerating it. This is the
confinement that keeps the cross-section discipline coherent (e.g. §12 logging can
never accidentally relieve a §10 sleep-context obligation).

Full region/owner detail and the per-section bucket placement are in
`references/modeling-kinds.md` (ghost state) and `references/api-inventory.md`
(bucketing). The TCB consequence of every ghost/contract stub being *trusted* is in
`references/soundness-ledger.md`.

---

## Three buckets — and the two cross-cutting decisions

Every modeled symbol falls into exactly one **bucket** (the kernel mapping of
pycsl's modelled/specified/stubbed), and the bucket decides its TCB weight:

| Bucket | Meaning | Maps to plan kind | TCB |
|---|---|---|---|
| **Modelled (M)** | ACSL `logic`/`axiomatic` whose lemmas WP discharges, or a small modeled body proved by WP | most of (L) | low — proved |
| **Specified (S)** | bodiless contract/ghost stub trusted as an axiom (its `ensures` is an assumption, carries no VC of its own) | most of (C) and (G) | **enters TCB — must be ledgered** |
| **Stubbed (X)** | signature only / `assigns \nothing` no-op (e.g. `printk`) | logging (§12) | proves nothing |

Coverage is **always reported per bucket** — a 100%-Specified section can show "all
green" while guaranteeing only self-consistency, because a trusted `val`-style stub
carries no VC. The honest headline is "*N Modelled VCs discharged, M Specified stubs
trusted (ledgered), the rest Stubbed*."

**Two cross-cutting decisions, made per unit before any ACSL is written** (verbatim
from `linux-api-plan.md`; detail in `references/modeling-kinds.md`):

- **Memory model — Typed vs Bytes/Caveat.** Typed is fast and rejects punning; Bytes
  is sound on `container_of` / `ERR_PTR` / packet-parsing but much slower. Choose
  *per unit*; isolate punning behind modeled accessors. §7 containers and §8 ERR_PTR
  are the forcing cases for Bytes.
- **Concurrency boundary — the no-blend line.** WP is sequential. Locks modeled as
  ghost balance give lock-discipline + a sequential proof *under assumed mutual
  exclusion* — **NOT race-freedom**. Race-freedom is a different toolchain
  (GenMC / Dat3M / herd7 / the Linux-Kernel Memory Model). Record the **concurrency
  residual** explicitly for every lock and barrier modeled as ghost/no-op; never let
  a ghost-lock model stand in for a race-freedom claim (that blend is the dominant
  coherent-and-wrong of this campaign).

---

## The workflow (per API / per section)

One coherent arc — a **descent and a return**, the same shape as
`pycsl-stdlib-coverage` Steps 1–6, retargeted from PyCSL to Frama-C/WP. The section's
**source of truth** (kernel-doc + the C body) descends into a **faithful ACSL model**
(no convenient abstraction — model the real return semantics, keep partiality), which
you **parse and discharge** (Steps 2–4) so each layer rests on its callees' contracts,
and finally **crown with a client harness** (Step 5) that re-states the "*Property:*"
promise over *symbolic* inputs and proves it for every input at once. The bad-caller
seed of Step 1 and the consequence harness of Step 5 are the **same scenario** with
its inputs made universal. Keep the descent faithful and the return composes.

### Contract-writing rules (how to write the `ensures`)

These govern HOW you write postconditions in Step 2 and the strongest forms you
propagate in Step 5. (Same two rules as `pycsl-stdlib-coverage`, in ACSL.)

#### Contracts must reflect the English specification
Derive each `ensures` from the kernel-doc / `Documentation/` sentence, not from what
is "minimal" or "safe" to assert. `ensures \result == 0 ==> (\forall i; to[i]==from[i])`
for `copy_from_user` is a transcription of "on success the destination holds the
copied bytes", not a leak of implementation detail. Weakening to `ensures \result <= n`
when the English says more produces a model that is provable but **unfaithful**, and
that is exactly what lets client code "verify" while the property is hollow.

#### Always maximise postcondition precision
After writing a contract, **ask: can I make the postcondition stricter?** A loose
post like `ensures \result >= 0` is vacuous — it tells the caller almost nothing and
*accepts bad callers* (the non-vacuity failure). Capture the API's essence:
- the exact return discipline (`copy_from_user` → **bytes-not-copied**, 0 == success);
- the boundary/error case (`IS_ERR(p) ==> p` is in the reserved range);
- the frame: a tight `assigns` (a no-op stub assigns `\nothing`, never the ghost
  context it does not own);
- `allocates`/`frees`/`\fresh`/`\separated` for §1 allocation.
A caller must be able to prove **more** about its own code using the contract; if not,
it is too weak. (See the worked `copy_from_user` / `ERR_PTR` contracts below.)

### Step 1 — Read both sources, pick bucket + memory model, seed a bad caller (scratch)
For the chosen API: read the kernel-doc and the C body in `linux-7.1.1/`; decide the
**bucket** (M/S/X) and **kind** (C/L/G); decide the **memory model** (Typed/Bytes) for
the unit; and sketch — on scratch — both a *good* client (uses the API correctly) and
a *bad* client (the violation the property must catch: an unchecked `copy_from_user`
result used as length, a sleep while `atomic_depth>0`, a missing `put` after `get`).
The bad caller is the seed of the Step-5 non-vacuity probe; the scratch is not kept.

### Step 2 — Write the ACSL model in `linux/linux-acsl/`
Add the bodiless contract (C), the `logic`/`axiomatic` (L), or the ghost-protocol stub
(G), in the overlay file mirroring the real header path, per the Contract-writing
rules. Anchor every clause with a `// cite:` to its kernel-doc/source line.

### Step 3 — Parse with Frama-C and iterate
```bash
frama-c -wp -wp-rte -machdep gcc_x86_64 \
  -cpp-extra-args="-I linux/linux-acsl/include -I linux/linux-7.1.1/include ..." \
  linux/linux-acsl/<unit>.c
```
Fix ACSL well-formedness, machdep, includes, name clashes. (Exact invocation, the
overlay layout, and how this plugs into `frama-c-launch`/`frama-c-monitoring` are in
`references/frama-c-running.md`.) Iterate until it parses clean.

### Step 4 — Discharge the model's own VCs (Modelled bucket only)
For **(L)** logic models, discharge the `axiomatic` lemmas and any small modeled body
with WP; escalate SMT→Coq/Rocq only for irreducible facts (the cross-validated-lemma
discipline from `frama-c-monitoring`), **never** `Admitted`/lemma-as-axiom/`\trusted`
to land a goal. For **(S)/(G)** there is no body VC — the contract is trusted; record
it in the Soundness Ledger and proceed to Step 5.

### Step 5 — Write the client harness (the loop-closer)
This is the heart, and the kernel analog of pycsl's *formal test*. Create a harness
in `linux/linux-acsl/harness/<section>_*.c`. The crisp acceptance bar is in
`references/what-is-a-faithful-stub.md`; the five rules:

> **An artifact verifies a kernel stub ONLY if all five hold:**
> 1. **FOR-ALL** — every client input symbolic, constrained by `requires`; never concrete.
> 2. **CONSEQUENCE** — set up state → OPERATE via the API → assert a *downstream safety
>    property* (no OOB use of tainted data, balanced refcount, `atomic_depth==0` at a
>    sleep site). Never re-assert the stub's own `ensures` through a bare call — that is
>    **vacuous** (true by construction).
> 3. **CALLS THE API** — `#include` the public header and call the public function;
>    observe through it. Never inline the model or touch ghost internals directly.
> 4. **NON-VACUITY (the mutation probe)** — the seeded *bad* caller from Step 1 must
>    make WP **FAIL**. A contract a bad caller passes is too weak; tighten it. (This is
>    `frama-c-monitoring`'s non-vacuity gate, applied per stub.)
> 5. **FIDELITY** — the contract agrees with the `linux-7.1.1/` body on the inputs the
>    harness exercises (the source-anchored `// cite:` is checkable).
>
> Miss one and it is not an acceptance of the stub. Run with `-wp` AND a vacuity check.

**Whole-section coverage rule.** The harness must propagate the **"*Property:*" line of
the whole section across its WHOLE listed API surface** — every symbol the section of
`linux-api-plan.md` lists gets at least one universally-quantified consequence (one
composed scenario where the API composes — e.g. alloc→use→free for §1 — or one theorem
per symbol where it does not). A harness exercising a couple of a section's functions
leaves the rest's property unpropagated: the loop is **not** closed and the section is
**not** done, however green those few are.

### Step 6 — Document Frama-C tool gaps → convergence
Any WP/ACSL limitation found in Steps 3–5 (a memory-model wall, an `assigns`-inference
gap, a cast/region unsoundness, a missing builtin) is recorded as a tool-gap document
and fed to the convergence loop below. Known gaps and workarounds live in
`references/lessons-and-gotchas.md`; deep WP-internals work is the `frama-c-internals`
skill.

---

## Worked examples (the three buckets)

### (L / Modelled) — `ERR_PTR` / `IS_ERR` — §8, the clean logic model
The kernel stuffs a small negative errno into the top page and returns it as a
pointer. Model the encoding explicitly (Bytes model on this unit — pointer↔integer
punning). Faithful to `include/linux/err.h` (`MAX_ERRNO = 4095`):

```c
/*@ axiomatic ErrPtr {
  @   logic integer MAX_ERRNO = 4095;
  @   // cite: include/linux/err.h  IS_ERR_VALUE(x) = (ulong)x >= (ulong)-MAX_ERRNO
  @   predicate is_err_value(integer x) = x >= (1<<64) - MAX_ERRNO; // top-page window
  @ } */
/*@ requires -MAX_ERRNO <= error <= 0;
  @ assigns \nothing;
  @ ensures is_err_value((integer)\result);
  @ ensures PTR_ERR(\result) == error;          // round-trip with PTR_ERR
  @ */
void *ERR_PTR(long error);
```
The round-trip `PTR_ERR(ERR_PTR(e)) == e` and `IS_ERR(ERR_PTR(e))` are the lemmas;
the *property* (callers test `IS_ERR` before dereferencing) is proved by the harness.

### (C / Specified) — `copy_from_user` — §3, the flagship trust boundary
Highest security value: the user pointer is **untrusted, possibly faulting, separated
from kernel memory**, and the return is **bytes NOT copied** (0 == full success).
Faithful to `include/linux/uaccess.h` (and its note that `copy_from_user` zero-pads on
a short copy):

```c
/*@ requires \valid(((char*)to)+(0..n-1));
  @ requires \separated(((char*)to)+(0..n-1), ((char*)from)+(0..n-1));
  @ assigns  ((char*)to)[0..n-1];
  @ ensures  0 <= \result <= n;                                 // bytes NOT copied
  @ ensures  \result == 0 ==>
  @            \forall integer i; 0<=i<n ==> ((char*)to)[i] == ((char*)from)[i];
  @ ensures  \result != 0 ==>                                   // short copy: tail zero-padded
  @            \forall integer i; n-\result<=i<n ==> ((char*)to)[i] == 0;
  @ */
unsigned long copy_from_user(void *to, const void *from, unsigned long n);
```
- **Good harness (consequence):** `if (copy_from_user(kbuf, ubuf, len)) return -EFAULT;`
  then read `kbuf[0..len-1]` — WP proves no OOB use of tainted data **for all** `len`.
- **Bad harness (non-vacuity, must FAIL):** use `kbuf[0..len-1]` *without* checking the
  return, or use `\result` itself as a subsequent length. If WP passes the bad caller,
  the contract is too weak — tighten it.

### (G / Specified) — sleep-in-atomic — §10 + §4, the kernel-specific discipline
The property libc has no analog for. Ghost `atomic_depth`; spinlock/preempt raise it,
`might_sleep` (and every sleeping op) requires it zero:

```c
/*@ assigns atomic_depth; ensures atomic_depth == \old(atomic_depth) + 1; */
void spin_lock(spinlock_t *l);
/*@ requires atomic_depth >= 1; assigns atomic_depth;
  @ ensures atomic_depth == \old(atomic_depth) - 1; */
void spin_unlock(spinlock_t *l);
/*@ requires atomic_depth == 0; assigns \nothing; */   // cite: kernel-doc might_sleep
void might_sleep(void);
```
- **Good harness:** lock → (no sleeping call) → unlock — `lock_balance` returns to 0.
- **Bad harness (must FAIL):** `spin_lock(l); kmalloc(sz, GFP_KERNEL); …` — the
  `GFP_KERNEL` alloc asserts `might_sleep`, which requires `atomic_depth==0`, but the
  spinlock raised it. WP must reject "sleeping in atomic context."

---

## The Convergence Principle (campaign loop)

Building this modeled runtime serves **two purposes that converge**, exactly as in
`pycsl-stdlib-coverage`:
1. **Model the kernel API faithfully** — re-express each API as a squeezed ACSL
   model and discharge a consequence harness (the workflow, Steps 1–6).
2. **Stress Frama-C/WP** — driving real kernel idioms (`container_of`, `ERR_PTR`
   punning, packet parsing) to a *faithful* proof is the best WP stress test there
   is. Where the model is right but WP cannot express/discharge it, the attempt has
   found a **tool gap** (Step 6) — routed exactly like `frama-c-monitoring` routes
   gaps to `getting-better/` and bugs to `bugs-to-report/`; deep fixes are
   `frama-c-internals` work.

Every section modeled faithfully exposes WP gaps; fixing them lets more of the API be
modeled. The fixed point is a faithfully-modeled section — its harness propagating the
"*Property:*" line across the WHOLE listed surface — *and* a WP with no remaining gap
for it.

### The agent loop (roles kept strictly disjoint)

A **coordination agent** orchestrates the workers, mediated by the same dated
`DD-HHMM-convergence-gap-N.md` / `DD-HHMM-convergence-spec-N.md` paired traceability
documents and `STATUS: DRAFT → APPROVED → DONE` handshake as `pycsl-stdlib-coverage`
(reuse that convention verbatim). The **model author and the harness author are
deliberately SEPARATE agents** — this is the disjointness that makes the loop sound:

- **coordination agent** — sequences spawns; **Gate A is editorial** (judges the
  per-API modeling plan — bucket, memory model, the property — and may add/cut/sharpen
  to speed convergence; never rubber-stamps). Edits only the spec document.
- **model agent** (pycsl's stdlib-agent analog) — reads BOTH sources of truth; writes
  the ACSL model in `linux/linux-acsl/` and discharges Modelled-bucket VCs. *Forbidden:
  weaken a contract or use `\trusted`/`Admitted` to make a downstream proof land; write
  the harness.* Output: a parsed/discharged model and/or a gap document.
- **harness agent** (pycsl's test-agent analog) — writes the client harness (Step 5).
  **Given only the public header signature + the kernel-doc/`Property:` English — NEVER
  the model's ACSL body.** So it writes the consequence assertion from the *English*,
  and WP either discharges it via the contract (right + strong) or not — it physically
  *cannot* tailor the harness to a wrong contract. *Forbidden: read the ACSL stub.*
  Output: a passing consequence harness + the seeded bad caller (non-vacuity), or a gap.
- **tool agent** — answers a gap with a `STATUS: DRAFT` spec; on `APPROVED`, fixes
  **only** `src/` of Frama-C (or the overlay's machdep/config), gates it (byte-stable
  elsewhere, the affected unit proves, non-vacuity holds), sets `STATUS: DONE`. Never
  weakens a model to dodge a gap.

The loop repeats, `N` incrementing, until a pass produces **no new gaps**.

This campaign runs **on top of** the existing engine: `frama-c-launch` scaffolds the
`linux/linux-acsl/` overlay and proves a smoke unit; `frama-c-monitoring` schedules
units leaf-first and runs its four base-SL gates (faithfulness, no-smuggled-axiom,
non-vacuity, completeness-vs-gold) on each `framac-sl` run. `linux-api` decides the
*inventory, ordering, buckets, and Soundness Ledger* and feeds them in.

### Invocation
**"apply the linux-api convergence principle to `<section>`"** spawns the coordination
agent on a section of `linux-api-plan.md` — e.g. **"…to the user-boundary API"**
targets §3 (`copy_from_user` & friends), **"…to allocation"** targets §1.

### MVP ordering (faithful to `linux-api-plan.md`)
Model in this order — each tier unblocks the next (full rationale in
`references/api-inventory.md`):
1. **§1 allocation + §8 ERR_PTR + §9 overflow-safe sizing** — highest bug density;
   nothing allocates or sizes safely without them.
2. **§2 mem/string + §3 copy_\*_user** — data handling and the trust boundary.
3. **§10 sleep/preempt context + §4 locks (ghost)** — the kernel-unique discipline;
   biggest payoff per line of model.
4. **§6 refcounting + §11 timers/work init-before-use** — lifetime correctness.
5. **§7 containers** — last and largest; scope to the ONE structure the target uses
   (start with `list` + `container_of`, on which the rest compose).
6. **§5 atomics/barriers, §12 logging, §13 MMIO, §14 entry harness** — fill in as the
   specific unit requires.

---

## Anti-patterns

- **`\trusted` / `Admitted` / lemma-as-axiom to land a goal** — defeats the purpose.
  Identify the missing WP feature precisely and write a gap (Step 6).
- **Claiming race-freedom from a ghost lock** — the dominant coherent-and-wrong here.
  Ghost-balance ≠ mutual exclusion ≠ race-free. Record the concurrency residual.
- **A vacuous contract** (`ensures \true`, `ensures \result >= 0`) that a *bad* caller
  passes — always run the non-vacuity mutation probe (Step 5 rule 4).
- **The model agent writing its own harness** — collapses disjointness; they would
  tailor the harness to the (possibly wrong) contract. Keep the roles separate.
- **Typed memory model on `container_of`/`ERR_PTR`/packet-parsing** — unsound punning;
  use the Bytes model on those units (`references/modeling-kinds.md`).
- **A trusted (C)/(G) stub left out of the Soundness Ledger** — every Specified stub
  enters the TCB; an un-ledgered one is a silent overclaim.
- **Modeling from the wrong tree** — this overlay is faithful to `linux-7.1.1`; do not
  transcribe semantics from a different kernel version.
- **Wrong `-machdep` / missing `-cpp-extra-args`** — the kernel analog of pycsl's
  "wrong CWD": the proof is then about the wrong machine model. Pin it
  (`references/frama-c-running.md`).
- **Reporting "all green" without the per-bucket split** — a 100%-Specified section
  proves only self-consistency. Report Modelled-VCs vs Specified-trusted vs Stubbed.

---

## Reference files (load on demand)

- **`references/api-inventory.md`** — the 14-section inventory enriched with, per
  section: the upper-bound `Property`, the lower-bound fidelity oracle, the bucket
  (M/S/X), the memory-model note, and the TCB consequence; plus the MVP ordering
  rationale and the §7 container scoping. Faithful to and pointing at
  `linux/linux-api-plan.md` (the authoritative inventory).
- **`references/modeling-kinds.md`** — the (C)/(L)/(G) kinds in depth, the two
  cross-cutting decisions (memory model, concurrency boundary), and the full ghost
  kernel-state layout + confinement rules.
- **`references/what-is-a-faithful-stub.md`** — the standalone five-rule definition of
  what verifies a kernel stub (FOR-ALL / CONSEQUENCE / CALLS-THE-API / NON-VACUITY /
  FIDELITY), with good/bad harness shapes and the "what it is NOT" anti-patterns.
- **`references/frama-c-running.md`** — exact `frama-c -wp` invocation, `-machdep`,
  `-cpp-extra-args`, the `linux/linux-acsl/` overlay layout, provers, and how this
  campaign plugs into `frama-c-launch` / `frama-c-monitoring` / `framac-sl`.
- **`references/lessons-and-gotchas.md`** — ACSL/WP kernel gotchas and the known
  tool-gap catalogue (Typed-vs-Bytes walls, `container_of`, casts, `assigns`
  inference, the concurrency residual) with workarounds.
- **`references/soundness-ledger.md`** — the TCB: the per-section trusted set and the
  "what a green proof does NOT guarantee" table — the campaign's headline honesty
  artifact.

## Related skills & files
- `linux/linux-api-plan.md` — the authoritative API inventory (the source of truth for
  WHAT to model).
- `sl-internal` / `sl-builder` / `sl-auditor` / `sl-monitoring-sl` — the SL strategy,
  construction, audit, and skill-monitoring this campaign instantiates.
- `frama-c` (writing ACSL), `frama-c-launch` (onboarding + overlay scaffold),
  `frama-c-monitoring` (campaign engine + four gates), `framac-sl` (per-unit loop),
  `frama-c-internals` (WP memory-model fixes for Step-6 gaps).
- `pycsl-stdlib-coverage` — the sibling campaign this one is modeled on.
