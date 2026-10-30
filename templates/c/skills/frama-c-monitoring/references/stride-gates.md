# STRIDE gates (N-1, N-4..N-9) — how the workstream gates compose with the four base gates

The extended-STRIDE workstreams (WS1, WS4/5/6, WS8a/b, WS9) add new gates to `frama-c-monitoring`.
**None of them is a new mechanism** — each is the *existing* monitoring apparatus pointed at a new
obligation class. This file states, per gate, **which existing gate it reuses** and **what it adds**.
Read `../SKILL.md` §4 (the top gates A/B/C/S) and §6 (the four base gates F / B / C / C′ + the
prover-escalation `Print Assumptions` audit) first — the vocabulary below is theirs, not new.

> **The four base per-unit gates (§6), named once so the table can cite them:**
> **Gate F** — faithfulness (strip-ACSL == `framac-orig/`, byte-identical); **Gate B** —
> no-smuggled-behavioural-axiom (an `axiom`/`Admitted`/over-promising stub asserting a *behavioural*
> fact is an escape hatch; a *definitional* axiomatic is the carve-out); **Gate C** — non-vacuity
> (the mutation probe / macsl negative control must turn a goal RED); **Gate C′** — completeness vs
> `framac-gold` / the disjoint completeness oracle (the trivial-witness probe — the sorting trap).
> Plus the **prover-ladder audit**: an SMT→Coq escalation counts only as a *cache-clean, zero-admit*
> replay whose `Print Assumptions` is ⊆ the intended definitional set.

The **ledger ratchet** these gates feed is `bin/ledger-ratchet.sh` (repo root): the cross-run CI gate over
the STRIDE coverage ledger (crosswalk-template §3). It is **regression-only** — a PROVED/TRUSTED cell
backsliding to UNMODELED, or a high-value asset row vanishing, FAILs; an incomplete matrix only WARNs
(Issue 2 — a too-strict gate gets disabled). The WS1 stage-1 rule (N-1) is *enforced* there; this file
explains *why*.

---

## N-1 — lock-order gate [WS1]

**Reuses:** the leaf-first schedule + the cross-unit `ensures→requires` propagation (§5 step 4) +
Gate B (no smuggled behavioural axiom) + the ledger ratchet (`bin/ledger-ratchet.sh`, the stage rule).

**Adds three obligations:**
1. **Held-lock propagation across the leaf-first schedule.** A `\guarded_by(lock)` (or the
   held-lock ghost predicate) obligation on a callee's access becomes a `requires`-the-lock-held
   contract OWED by every caller — propagated bottom-up exactly as a proven `ensures` is, so that a
   caller that reaches the access without the lock is caught at the call site, not inside the leaf.
2. **Cross-unit lock-order coherence.** The acquisition order must be a single global partial order:
   unit A taking L1-then-L2 and unit B taking L2-then-L1 is a deadlock the leaf-first stub-implication
   check surfaces (the two stubs cannot both be satisfied by one order). This is the lock analogue of
   the cross-unit stub-over-promise check (§8d).
3. **The stage rule (Issue 3) — encoded in `bin/ledger-ratchet.sh`, justified here.** A syntactic
   `\guarded_by` proof establishes *lock-held-at-access*, **not** check-then-act atomicity: it cannot
   rule out a TOCTOU window where the lock is held at *each* of two accesses but released between
   them. While only **WS1 stage-1** (the held-lock syntactic check) ships, the race/concurrency-family
   ledger cell therefore **stays `TRUSTED`, never `PROVED`** — a held-lock green is real but does not
   retire the race family's amenable core, which needs the **rely-guarantee** lane (WS1 stage-2).
   `bin/ledger-ratchet.sh` reads `# ws1-stage: N` (default 1) and **FAILs** any race-family cell marked
   `PROVED` while stage < 2. Promote the cell to `PROVED` only when stage-2 lands — and then it is a
   *new prover lane*, so it also re-triggers the sl-auditor C1–C4 re-audit (N-8).

> Why not just trust the green? A `PROVED` race cell at stage 1 is the canonical **coherent-and-wrong**
> for concurrency: the machine is satisfied (lock held at every access) yet the property (no data race
> under interleaving) is not established. The ratchet refuses to let a stage-1 syntactic green
> masquerade as a stage-2 atomicity result — the no-blend rule applied to the time/interleaving plane.

---

## N-4 — boundary-contract propagation [WS8a]

**Reuses:** the monitor's *core* mechanism — leaf-first `ensures→requires` propagation + the
stub-over-promise check (§8d: a stub stronger than the callee's documented surface is unsound; a
stubbed callee *with a body in scope* must PROVE its stub).

**Adds:** each **trusted stub** at a system boundary (`verify_token`, `get_query_param`, the storage
layer, the clock) is turned from an assumed black box into a **proof obligation OWED by the peer
unit**, scheduled and gated by exactly that propagation. The stub's assumed `ensures` is the peer's
`requires`; when the peer is in scope it must discharge it — when it is external it is a *named
residual* (crosswalk §5), never a silent green. Frame it as the monitor's own mechanism with new
operands:
- **storage** — `fsync-before-ack` ordering: the ack path's `requires` is the storage stub's
  `ensures durable(record)`; an ack emitted before the durability `ensures` is a stub-over-promise the
  cross-unit check catches.
- **parser** — totality + non-aliasing: the consumer's `requires \valid`/`\separated` are owed by the
  parser's `ensures` (a total parse that returns disjoint, in-bounds buffers). An over-promising
  parser stub (claims totality it cannot prove) is the Gate-B / §8d catch.
- **`verify_token` / `get_query_param` / clock** — each contributes one `ensures` (authenticated /
  in-range / monotonic) that becomes a downstream `requires`; unmet ⇒ residual, not green.

This gate **does not invent a new check** — it is the statement that a boundary stub is just a callee
whose body lives in another unit (or outside the codebase), and the existing leaf-first discipline +
stub-over-promise gate already govern it.

---

## N-5 — prover-ladder audit for new TCB classes [WS4/5/6, Issue 6]

**Reuses:** the SMT→Coq prover-escalation soundness audit (§6: `Print Assumptions` ⊆ intended
definitional axioms, **0 admits**, cache-clean replay) + Gate B (no smuggled behavioural axiom).

**Adds:** extends the `Print Assumptions` audit to the **new lemma classes** the extended
workstreams introduce, and pins which symbols must stay **uninterpreted**:
- **WS4 — uninterpreted hash `H`.** `H` is a logic function with **no behavioural axiom** (no
  collision-resistance, no preimage equation): it must appear in `Print Assumptions` only as an
  uninterpreted symbol. The instant `H` acquires an axiom relating its outputs to its inputs beyond
  congruence, Gate B (no-smuggled-behavioural-axiom) FIRES — that axiom is a crypto assumption
  smuggled into the TCB.
- **WS5/WS6 — cost / ranking lemmas.** The `\cost` / `\fuel` step-bound and the ranking/measure
  lemmas must be **admit-free**: shipped as hardened twins (`*_hardened.v` + the Lean twin per the
  `coqwp-hardened` discipline) **or** classified as an explicit `AUDIT.md` entry with its residual
  named. A cost lemma closed by `admit` is the prover-ladder audit's REJECT.
- **The no-smuggled-behavioural-axiom gate is the guard** that the relational/system predicates
  `H`, `\flow`, `\held`, `\stable` stay **uninterpreted** — they describe *the program's* behaviour,
  so any axiom about them is a behavioural fact assumed rather than proved. They earn meaning only
  through macsl's *instrumentation* (assertions at every matching site), never through an axiom.

---

## N-6 — ATT&CK coverage view [WS9]

**Reuses:** the verdict join (crosswalk §4) + the ledger's `ATT&CK` column (§3.3) — pure
traceability, **zero added TCB** (a report view, not a proof obligation).

**Adds:** join macsl's red-control technique tags (M-8 — the technique each negative-control /
red-team assertion exercises) to the ledger's per-asset `ATT&CK` column, and emit an
**attack-coverage report**: per technique, which (asset, family) cells are `PROVED` / `TRUSTED` /
`UNMODELED`. This surfaces a technique with **no PROVED/TRUSTED cell** as an attack-surface gap the
ranking missed — the dual of a high-value asset with no ledger row (which the ratchet already FAILs).
Because it adds no axiom and no goal, it can never be a source of unsoundness; it is the coverage view
that keeps the campaign honest about *which adversary techniques* the greens actually retire.

---

## N-7 — Gate-S over new learned skills [§6]

**Reuses:** Gate S (skill-consistency) audited from a **disjoint base** via `sl-monitoring-sl` — the
recursion stopping at an external reviewer (`sl-auditor` Dimension 8); the producer of a skill may
**not** approve it.

**Adds:** any heuristic these workstreams cause `framac-sl` (or this loop) to consolidate is run
through Gate S from a base that did not produce it. The live example is
[`getting-better/20260620-0830-macsl-unguarded-policy-vacuous.md`](../getting-better/20260620-0830-macsl-unguarded-policy-vacuous.md)
(`macsl-unguarded-policy-vacuous` — "an unguarded/zero-expansion HAPPY policy gives a VACUOUS green;
require the negative control"). Classify it (`defer-to-oracle`: on a macsl green, take the
mutation-probe/negative-control-sanctioned action) and run the matching consistency check — does the
WP oracle / negative control actually distinguish the case? PASS, **carve-out** (defer to the guidance
clause), or **prune** (spurious). The disjointness rule is load-bearing: **its producer may not
approve it** — a self-approved skill is an un-squeezed editorial judgment, exactly what Gate S exists
to stop.

---

## N-8 — sl-auditor re-audit triggers [WS1-stage2, WS8b]

**Reuses:** the mandatory `sl-auditor` C1–C4 + stabilizer re-audit that fires **on any cast change**
(a new memory model, a new prover lane, a new evidence base changes the (U,L) authority pairs and must
be re-checked for disjointness/barriers).

**Adds:** two new triggers, each adding an **evidence base** that must be re-audited:
- **WS1 stage-2 (rely-guarantee) — a new prover lane.** Promoting the race cell from `TRUSTED` to
  `PROVED` (N-1) introduces the rely-guarantee discharge as ground truth; the sl-auditor re-confirms
  the new lane is a *disjoint* lower bound (its oracle is not the same actor that authored the
  rely/guarantee annotations) before any `PROVED` race cell is accepted.
- **WS8b — the external protocol oracle.** An out-of-band protocol-state oracle (e.g. a model checker)
  is a second lower bound; the re-audit confirms it is evidence-disjoint from the verifier and that a
  green from it is gated, not blended with a WP `Valid` (no-blend, §8d).

Each new base re-runs C1 (pairwise-distinct (U,L) pairs), C2 (catchability — seed a coherent-and-wrong
and confirm the gate fires), C3 (physical barrier — the new oracle does not read the producer's
rationale), C4 (done is gate-defined). A new lane that has not passed the re-audit is not `APPROVED`.

---

## N-9 — faithfulness preserved [every new HAPPY policy]

**Reuses:** Gate F (faithfulness — strip-ACSL == `framac-orig/`, byte-identical) + the canary phase
(§8c).

**Adds:** the invariant statement that **a HAPPY policy instruments assertions, it never alters
behaviour** — macsl expands a policy to ACSL `assert`s at matching sites *in place* (the in-place
command line, no `-then-last`), all inside comment spans. So for every new policy, `strip-ACSL ==
framac-orig` **still holds**: stripping the instrumented assertions returns byte-identical C. Gate F is
re-run after each policy instrumentation as the mechanical proof of this; a policy whose strip does
*not* round-trip to pristine has either edited executable C (the FABRICATED failure) or hit a
line-oriented strip trap (a force-include/reformat left behind — §6 Gate F caveat), and is reverted.
This keeps the HAPPY tier on the same faithfulness footing as every contract: the proof is
trustworthy-by-construction because the program it proves about is provably the pristine one.

---

### How they roll up to the ledger ratchet

| Gate | Plane it touches | Ledger effect | Enforced by |
|---|---|---|---|
| N-1 | race / interleaving | race cell `TRUSTED` until stage-2; `PROVED@stage1` ⇒ FAIL | `bin/ledger-ratchet.sh` (`# ws1-stage`) |
| N-4 | boundary contracts | stub-owed `ensures` ⇒ peer `requires`; else §5 residual | leaf-first stub-over-promise (§8d) |
| N-5 | new TCB lemmas | `H`/cost lemmas admit-free or `AUDIT.md` residual | `Print Assumptions` audit + Gate B |
| N-6 | ATT&CK traceability | technique with no PROVED/TRUSTED cell ⇒ surfaced gap | crosswalk §4 join (report view) |
| N-7 | learned skills | skill consolidated ⇒ Gate S PASS/CARVE-OUT/REJECT | `sl-monitoring-sl`, disjoint base |
| N-8 | new evidence bases | new lane/oracle ⇒ C1–C4 re-audit before APPROVED | `sl-auditor` |
| N-9 | faithfulness | each HAPPY policy ⇒ strip-ACSL == pristine | Gate F + canary |

Every row's PROVED is the **named plane only** (no-blend, crosswalk §3); a green never lowers a risk
*level* — the risk owner / AO does that at the human terminus, downstream.
