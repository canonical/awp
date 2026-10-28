# bytes-model `\valid_read` of a typed member-array won't derive from a record char-range envelope (sub-range lemma proven but won't auto-fire)

**Date:** 2026-07-01  **Context:** libbpf `/time-loop` → frama-c-monitoring sweep, `btf_validate_type`
(`btf.c`) — the composite that walks the untrusted `vlen`-counted member arrays.

## Symptom
A validator reads `m->name_off` / `m->type` for `m = (struct btf_member *)(t+1) + i`, `i < vlen`. The
member reads are in-bounds because the whole type record (header + `vlen` members) fits in the type
section — expressed as a function envelope `requires \valid_read((char*)(t+1) + (0 .. vlen*16 - 1))`
(16 = max member size; `vlen = t->info & 0xffffff`). But WP will **not** derive from it either:
- the typed member array `\valid_read((struct btf_member*)(t+1) + (0 .. vlen-1))`, nor
- the char sub-range `\valid_read((char*)(t+1) + (0 .. vlen*12 - 1))` (btf_member = 12 bytes).

Both Timeout@30s. Probed 4 ways (typed array / char range / matched `(t+1)` base / `wp:bitrange`
+inline `btf_vlen`) — all Timeout. Even the *matched-base char sub-range* — logically just
`\valid_read(p+(0..a-1))` from `\valid_read(p+(0..b-1))` with `a=vlen*12 ≤ b=vlen*16` — does not close.

## Diagnosis (not a relabel — a proven lemma that WON'T auto-fire)
The enabling fact is a pure `\valid_read` **sub-range monotonicity** tautology:
```
/*@ lemma valid_read_char_subrange:
      \forall char *p, integer a, b;
        0 <= a <= b && \valid_read(p + (0 .. b - 1)) ==> \valid_read(p + (0 .. a - 1)); */
```
This lemma **PROVES 1/1 standalone** (Alt-Ergo/Z3, bytes model). But with it in scope it **does not
auto-apply** to close the member-region assert (0/1, not even a Timeout — WP won't e-match the
`\valid_read(...)` premise to discover the witness `b = vlen*16`, and the symbolic `land(0xffffff,info)`
product bound compounds it). So the property is TRUE and the tool has the lemma, yet SMT can't fire it.

## UPDATE (2026-07-01, cycle-20) — RECLASSIFIED class-A → class-C; the wall is STORE-BLOAT/FRAME, not the derivation
The "won't auto-fire" framing below is SUPERSEDED. A minimal 6-line reproducer (`struct M{unsigned a,b,c;}`
with the same envelope + member-region assert) proves the sub-range assert **1/1 with SMT alone** — so
the derivation is fine. Bisected the difference to the big-function CONTEXT:
- `mprobe` proves 1/1 standalone, Timeout in `btf_validate_type` → **store bloat**, not the lemma.
- Inlining `btf_vlen` (n = direct mask, matching the reproducer) does **not** help → not the n↔mask link.
- The decisive probe: re-assert the envelope `\valid_read((char*)(t+1)+(0..vlen*16-1))` as a checkpoint
  `cp`. At the **member-loop point** `cp` Times out; asserted **right after the pre-switch
  `btf_validate_str` call (before the switch)** `cp` proves **1/1**. So the stable `\valid_read` fact
  (the (t+1) region is never written — callees `assign __fc_errno`) is simply **lost through the switch
  dispatch** in the bloated bytes-model state; WP can re-establish it in a small pre-switch context.
**THE LEVER (`cp`):** assert the envelope once **before the switch**; it then holds as a hypothesis in
every case, and each member loop's `\valid_read((char*)(t+1)+(0..n*12-1))` loop-invariant derives from
it (mprobe proves *given* cp). This is the [[wp-flag-stability-checkpoint-slice]] pattern (a stable fact
store-bloated in a big fn, carried by a checkpoint). It advances `btf_validate_type` 111/161 → 122/172.
**So W1 is CLASS-C (closeable), not class-A** — the earlier class-A label was wrong (no probe had
isolated the store-bloat). Remaining scoped class-C work to converge validate_type: 2 STRUCT
loop-invariant residuals, the other 4 member loops (mechanical replicate), ~23 `assigns __fc_errno`
frame goals (the big-fn frame, likely the same `-simplify-cfg`/switch frame interaction as btf_type_size),
and 8 callee-precond goals (`valid_btf`/`valid_btf_types` reach at the call sites — likely another
pre-call `cp`-style checkpoint). `btf_sanity_check`/`btf_bswap_type_rest` inherit the same lever.

## Status / recipe for whoever cracks it next (SUPERSEDED by the UPDATE above — kept for the trail)
Closing needs the **GUI/Ivette TIP**: land on the member-region goal, `Wp.lemma valid_read_char_subrange`
+ `Wp.instance` (`p := (char*)(t+1)`, `a := vlen*12`, `b := vlen*16`), discharge the side
`vlen*12 ≤ vlen*16` with Alt-Ergo. That is a per-loop manual step ×5 (STRUCT/UNION, ENUM, ENUM64,
FUNC_PROTO, DATASEC) — disproportionate for a **Tier-1 RTE single-pass** on a well-specified surface,
so per the loop's "extreme-cases-only / no-budget-burn" rule it is **carried**, not ground. Same
derivation family as the `btf_parse_type_sec` void*-arith residual (cycle-8).

btf_validate_type advances 8/35 → 111/161 with the record envelope + a STRUCT loop invariant (the
non-loop cases + header reads close); the 5 member loops are the residue. Its two leaves are
WITNESSED (btf_validate_str 10/10, btf_validate_id 10/10, cycle-16); the type-id gate
(btf_type_by_id/btf__type_by_id) is WITNESSED (cycle-15). `btf_sanity_check` (loops validate_type over
all types) inherits the same wall.

## Desired tool behaviour (the feature ask)
An auto-firing `\valid_read` sub-range/monotonicity simplifier (or a `-wp-auto` strategy that
instantiates a `\valid_read`-premised lemma on a syntactic sub-range match), so a typed member-array
walk bounded by a proven record-footprint envelope discharges without a manual TIP instance per loop.
Serves U = RTE/memory-safety on untrusted `vlen`-counted arrays (a very common parser shape).

## UPDATE (2026-07-01, cycle-25) — frame-Coq escalation DONE: definitively CLASS-C (faithful twin proves), NOT non-entailed
Ran the mandatory frame-Coq escalation (the owed lever). Reading the actual Coq goal mid-cycle, cp2 looked
NON-ENTAILED — the goal `valid_rd t a4 (16*to_sint32 x3)` (alloc `t`, info from mem `t2`) had no visible
hypothesis linking it to cp_env's `valid_rd t1 a4 (16*land 16777215 x)` (alloc `t1`, info from mem `t3`);
four independent memory/alloc symbols `t/t1/t2/t3` with no emitted frame equality. That reading was WRONG.
A FAITHFUL minimal twin (`libbpf-analysis-acsl/reproducers/w1-frame-twin.c` — read info→switch→re-read
info→assert `\valid_read((char*)(p+1)+(0..n*16-1))`) **proves 1/1** with SMT, and so does the variant WITH
a pre-switch call (callee `assigns __fc_errno`, ± `allocates \nothing`). So the read-across-switch frame
IS derivable — cp2 is ENTAILED; it is **STORE-BLOAT** in the full `btf_validate_type` context (the ~11
string-literal `Init` foralls + the recursive `valid_btf`/`valid_btf_types` predicates saturate SMT), NOT
a non-theorem and NOT a Coq-closeable-frame. `no_ceiling_gate.py` REJECTs the class-A claim → **class-C**
on the mechanical evidence (twin PROVES ⇒ closeable; store-bloat ⇒ class-C) — no disjoint attestor needed;
the gate settles it. **DEFINITIVE: W1 is class-C, store-bloat, closeable-in-principle.** Remaining closure
lever = bloat reduction (checkpoint-slice with loop `assigns` on the intervening loops, or analyzed-context
reduction), real class-C work of LOW marginal value (the two leaves + the type-id gate are WITNESSED; W1 is
a completeness/rigor closure on the walk-validator). Lesson reinforced: *read the goal AND build a faithful
twin before classifying* — the bare goal-read misled toward "non-entailed"; the twin corrected it to
store-bloat. A single-state reproducer that proves is NOT faithful to a multi-state store-bloat goal; the
twin must reproduce the same program shape (call + switch + re-read). See [[no-ceiling-gate]].

## UPDATE (2026-07-01, cycle-26) — bloat-reduction closure ATTEMPTED (6 levers) + PRECISELY LOCALIZED to switch dispatch
Took the bloat-reduction closure per user instruction. The store-bloat is now localized to the
**switch-case ENTRY**: the stable envelope `\valid_read((char*)(t+1)+(0..(t->info&0xffffff)*16-1))`
PROVES as `cp_env` right before the `switch`, and TIMES OUT at every point *after* dispatch —
`cp2` (loop point, `n`-form), `cp2b` (loop point, EXACT `cp_env` `t->info`-form), and `cp2c`
(composite-block entry, BEFORE the `btf_member*` cast) all Timeout, while `cp_env` and the
`n==t->info&0xffffff` bridge both Prove. So the bloat is neither the member cast, nor `btf_vlen`,
nor the recursive `valid_btf`/`valid_btf_types` predicates, nor the const-global `Init` hyps — it is
the **`switch` dispatch itself** (in the bytes model, after `-simplify-cfg` normalization + the ~13
kind-value disequalities): a validity fact that holds before the switch is not carried into any case
arm by SMT in the bloated whole-function state. Automated levers ALL fail to close it: `-wp-no-init-const`,
dropping the predicates from `requires`, `allocates \nothing` on the accessors, the checkpoint-slice
(`cp2b`/`cp2c` in `cp_env`'s exact syntactic form), `-simplify-cfg` on/off, contracted-vs-inlined
accessors, and the Coq escalation. The faithful twin (`reproducers/w1-frame-twin.c`, one switch case,
small context) PROVES — so it is definitively **class-C store-bloat**, closeable-in-principle.
**Remaining closure paths, all disproportionate or blocked:** (1) a manual per-case Ivette TIP that
`Clear`s the switch-dispatch bloat hypotheses then runs SMT, ×5-6 case arms; (2) a helper-function
extraction of the member loop — **breaks the faithfulness oracle** (`strip(//@)==pristine`), not allowed;
(3) a WP feature. **DEFERRED on a logged budget judgment** (leaves + type-id gate WITNESSED; W1 is a
rigor/completeness closure with no finding at stake; enormous spend across cycles 16/20-26). NOT class-A
(gate REJECTs — twin proves), NOT a self-declared ceiling.

## Desired tool behaviour (SHARPENED — the real feature ask)
A WP simplifier/strategy that **carries a `\valid_read`/`\valid` fact proven immediately before a
`switch` into each case arm** when the dispatch writes no memory (or an option to keep a pre-switch
proved-assert as a live hypothesis in every arm without re-deriving it in the bloated state). This is
the switch-dispatch dual of the `-simplify-cfg` assigns-frame fix ([[wp-switch-default-return-assigns-frame-bug]]):
that one fixed `assigns \nothing` framing across a switch default; this one is the `\valid_read`
validity-carry across switch dispatch. Serves U = RTE/memory-safety on the extremely common
"dispatch on a kind/tag, then walk a tag-counted array" parser shape.
