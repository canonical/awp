# The Soundness Ledger (TCB) — what a green proof does NOT guarantee

Consult this when reporting coverage, accepting a section as done, or answering "what
does this modeled runtime actually guarantee?". This is the campaign's **headline
honesty artifact** — the analog of `pycsl-stdlib-coverage`'s Soundness Ledger. Every
**Specified (S)** stub and every **ghost (G)** protocol is *trusted, not proved*: its
`ensures` is an assumption a client proof inherits. The ledger makes that trusted base
legible instead of letting "all green" read as "all proved."

## The bucket → trust mapping (restated)

- **Modelled (M)** — the `ensures`/lemma is backed by a discharged WP VC (or a
  cross-validated Coq/Rocq lemma). **Proved.** Low TCB.
- **Specified (S)** — bodiless contract/ghost stub; the `ensures` carries **no VC of
  its own** — it is an axiom. **Trusted.** Enters the TCB; **must be listed below.**
- **Stubbed (X)** — signature/no-op; proves nothing. Not part of any guarantee.

**Reporting rule.** Never report a bare "N% proven." Always split:
`M modelled VCs discharged · S specified stubs trusted (ledgered) · X stubbed`. A
100%-Specified section is "100% green" and guarantees only **self-consistency of the
client against an assumed runtime** — useful, but not a proof of the kernel.

## What a green run does NOT guarantee (per source)

| Where | What is trusted (the assumption) | Consequence if the assumption is wrong |
|---|---|---|
| §1 allocators (S) | `kmalloc` returns `NULL`-or-`\fresh`-of-`size`; `kfree` frees exactly that | a real allocator bug (wrong size class, early reuse) is invisible |
| §3 `copy_*_user` (S) | bytes-not-copied return; short-copy zero-pad; user/kernel separation | a real uaccess fault path divergence is invisible |
| §4 locks (G) | acquire/release update the ghost balance faithfully | **no race-freedom** — interleavings, ordering, store buffering all unmodeled |
| §5 barriers (G/no-op) | no sequential effect | **all memory-ordering semantics are residual** |
| §6 refcount (G) | get/put move the ghost count faithfully | a real refcount bug outside the modeled API is invisible |
| §7 containers (M/L) | the reachability predicate matches the real structure | a structure the predicate mis-models proves a false integrity |
| §10 context (G) | depth raised/lowered faithfully by preempt/spin/irq/rcu | a sleep in atomic via an *unmodeled* path is invisible |
| §13 MMIO (S) | the iomem region is opaque; reads unconstrained | device-side semantics (side effects of a read) unmodeled |
| §14 entry (harness) | the framework→driver contract is the real one | a wrong entry contract makes §3 checks meaningless |
| **everything** | the stub is faithful to **`linux-7.1.1/`** | a version drift silently breaks fidelity |

## The concurrency residual (always recorded)

WP is sequential. For **every** §4 lock and §5 barrier modeled as ghost/no-op, the
ledger records: *"discipline proved under assumed mutual exclusion; ordering and
race-freedom are residual, owned by the weak-memory lane (GenMC / Dat3M / herd7 /
LKMM)."* This line is non-negotiable — omitting it is the dominant coherent-and-wrong
(letting a ghost-lock proof read as race-freedom). See `modeling-kinds.md` § concurrency
boundary.

## Per-section ledger entry (the form to keep)

For each section accepted as done, record:

```
SECTION §<n> <name>            baseline: linux-7.1.1   date: <YYYY-MM-DD>
  Bucket split:   M=<vcs discharged>  S=<stubs trusted>  X=<stubbed>
  Memory model:   Typed | Bytes (and why, per unit)
  Property:       <the upper-bound sentence proved, across the WHOLE listed surface>
  Strength:       totality/safety | functional content   (per harness)
  Trusted set:    <the S/G stubs whose ensures is an axiom — the TCB contribution>
  Non-vacuity:    <bad-caller harness names; all confirmed FAILING>
  Residual:       <concurrency residual lines; any Step-6 gaps still open>
  Escape hatches: NONE   (any Admitted/lemma-as-axiom/\trusted ⇒ section NOT done)
```

## Discipline for the ledger itself
- **Loud-fail, never approximate.** An undischarged goal is `UNPROVEN`/`gap`, never
  quietly counted green.
- **Ground every entry.** Each trusted stub cites the `linux-7.1.1/` line it
  transcribes; a trust claim with no `// cite:` is hearsay.
- **Safe direction.** When unsure, *grow* the trusted set / *shrink* the proved claim —
  understating what is proved is a style choice; overstating it is the failure the
  campaign exists to catch.
- **No escape hatch in a "done" section.** A single `Admitted` / lemma-as-axiom /
  `\trusted` voids the section's done status — it is a coherent-and-wrong proof. Route
  the underlying need to the convergence loop / `frama-c-internals` instead.
