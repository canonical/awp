---
name: framac-sl
description: >-
  The per-unit Frama-C/WP verification squeeze loop (SL): annotate EXISTING C with ACSL and prove
  it with `frama-c -wp -wp-rte`, structured so the loop converges on correct code-with-specs rather
  than a plausible-looking one. Specifies the actor cast (coordinator, spec author, annotator,
  verifier, probe) and their disjoint (U,L) pairs, the physical code-blindness barriers, Gates
  A/B/C/C′/S, the executable-oracle setup (NO EVA — a TCB-minimization rule), the non-vacuity /
  refutation probe, and the knowledge-capitalization discipline (§11). This is the inner/base loop;
  `frama-c-monitoring` is the outer loop that drives it over a whole codebase, and the sibling
  `framac-sl.sl.json` in this directory is its formal machine-readable SL encoding. Invoke when
  proving one C translation unit against a transcribed external requirement — e.g. 'verify this C function with Frama-C/WP', 'add ACSL and prove it correct', or 'prove this unit has no runtime errors and meets its spec'.
---

# framac-sl — a full SL-compliant loop for Frama-C verification

**Name:** `framac-sl` (the Frama-C Squeeze Loop).

A **Squeeze Loop (SL)** that annotates **existing** C with **ACSL** and proves it with
**Frama-C/WP**, structured so the loop converges on *correct* code-with-specs rather than
on a *plausible-looking* one. This is the inner / base loop; the outer loop that drives it
over a whole code base is `../frama-c-monitoring/references/framac-workflow.md`. It is the Frama-C port of `creusot-sl.md`.

> Drafted with the `sl-builder` methodology (Frama-C worked example). Slots the context
> did not fix are marked `ASSUMPTION:`; run the C1/C2 checks (§10) before trusting an
> instance.

---

## 0. Deliverable & correctness
- **Deliverable:** the original C functions, annotated with ACSL, such that
  `frama-c -wp` discharges **every** goal (every VC `Valid`) **and** the proved theorem is
  the property the requirement intends — no escape hatch (`Admitted`, `lemma`-as-axiom,
  vacuous `assigns`, over-promising stub) on the target.
- **"Correct" means (checkable):** every requirement clause is expressed as an ACSL clause
  that WP + the SMT backends discharge against the original C, and a mutation of the code
  that violates the requirement is caught by some VC or formal test.
- **Terrain archetype: A/B mix.** The *requirement* is external (transcription, A), but the
  *ACSL contracts* that make it checkable are **authored upstream** by an actor that never
  sees the body (authored authority, B). **Author independence carries the soundness
  argument.** For a pure robustness sweep, `U` = "no runtime error for any input", supplied
  by RTE (terrain A — the C language standard *is* the external spec).
- **Dominant coherent-and-wrong to guard:** a **vacuously-true / weaker-than-intended
  contract** — `ensures \true`, an `assigns \nothing` that drops a real effect, a
  `requires` so strong it is unsatisfiable, or a goal that passed only because a call
  routed through an *unspecified* stub whose body WP modelled as `\false`. WP reports
  `Valid`, but the theorem is not the intended one.
- **The subtlest form of that coherent-and-wrong — the GHOST-FIAT antecedent (SEMANTIC
  vacuity).** When the unit's real property is *system-level* (an authorization/integrity
  invariant — "root cannot be regained", "the exec is confined"), it is carried by a
  macsl / HAPPY meta-property whose antecedent is often supplied by a **ghost model function
  (`//@ ghost sc_model_*();`) with a POSTULATED `ensures`**. WP proves `ghost ⟹ property`
  soundly and it goes green — but **nothing proves the ghost**. This is **not** the
  `\false`-stub vacuity above (the ghost's `ensures` is satisfiable and non-trivial); it is
  **semantic** vacuity — the fact the theorem rests on is *asserted, not derived*. The Gate-C
  mutation probe on the *code* does **not** catch it (the ghost is set by fiat regardless of
  the body). See §4b — for system properties this is the dominant trap.

## 1. Bounds
- **Upper bound `U`** = the **external requirement** (plain English / coding standard /
  MISRA rule / ticket) **made precise as ACSL**: `requires`/`ensures`/`assigns`,
  `loop invariant`/`loop assigns`/`loop variant`, `predicate`/`logic` functions,
  `behavior`s. The strongest claim the code must satisfy. Robustness sweep: `-wp-rte`
  emits the runtime-error obligations as `U`.
- **Lower bound `L`** = `frama-c -wp` → **every goal `Valid`** (Why3 → SMT, + audited admit-free Coq
  escalation), **plus** test execution of the compiled C, **plus** the **mutation probe** (perturb the
  C; the proof must break). A mechanical verdict no actor can alter.
  - **EVA is deliberately NOT an oracle here** — a TCB-minimization rule: letting EVA discharge a goal
    adds the whole abstract-interpretation engine (no per-goal checkable certificate) to the TCB. Keep
    the TCB to {WP VC-gen + SMT/Coq}; in the age of AI the contracts are AI-authored, so converge by
    *adding spec*, not by *trusting more analyzer*. For a cast/RTE residue use `-wp-model bytes` / a
    representation predicate, never an EVA split. (See `frama-c-monitoring` "No EVA — a TCB-minimization rule".)
  - *Pilot (§12) confirms the invocation, prover set, and timeout before any sweep.*

## 2. Actors and their disjoint `(U,L)` pairs

The canonical cast, instantiated for Frama-C verification of existing code. A role exists
only for a **new evidence base**; the *implementer* here is an **annotator** (it adds proof
scaffolding, it does not rewrite behaviour).

| Actor | Builds | U (above) | L (below) | Forbidden move | Must NOT see |
|---|---|---|---|---|---|
| **Coordinator** | Gate A approvals, sequencing, gap-doc adjudication, DONE verdicts | the requirement + plan sections | the machine gate output (WP logs, test + mutation results) | edit C/ACSL; approve an unjudged plan; let a self-report end an item | a producer's rationale |
| **Spec author** | the ACSL **contracts** (+ ACSL **stubs** for externals) | the **external requirement** + function prototypes / headers | expressibility: each clause dischargeable by *some* WP mechanism | read or infer the function body | the C implementation; the formal tests |
| **Annotator** (implementer) | proof scaffolding: `loop invariant`/`loop assigns`/`loop variant`, intermediate `//@ assert`, `/*@ ghost */`, lemmas it proves | the contracts (strongest mandated claim) | `frama-c -wp` discharge + standing test suite | weaken a contract/`assigns`/gate; add `Admitted`/axiom/over-broad stub to land; touch acceptance evidence | the formal tests / acceptance evidence |
| **Exerciser/Verifier** | **formal tests** (acceptance test drivers proven by WP over all inputs — broadest `requires`, the property checked in the body, `ensures \result==1`; the adversarial checks ARE the body) + the **mutation probes** that prove they have teeth; runs `frama-c -wp` fresh | the requirement's acceptance clauses + the documented public surface | what actually discharges/proves when WP is run | read the implementation or the annotator's diff | the C implementation; the diff |
| **Probe** | minimal Frama-C/WP capability experiments (does WP model this construct? which prover/timeout discharges it?) | one design claim per probe | Frama-C/WP's *actual* behaviour | implement a fix | — |

**Disjointness (C1):** the spec author holds the requirement (never the body); the
annotator holds the contracts (never the formal tests); the verifier holds the
requirement + the runnable oracle (never the body or diff); the coordinator holds the
requirement + gate output (never producing an artifact it grades). **Intersection** = C
that *both* discharges contracts authored from the requirement *and* survives formal tests derived independently from that same requirement — no single actor certifies it
alone.

**Catchability (C2):**
- annotator games a weak contract → caught by the verifier's formal tests + Gate
  C mutation probe;
- spec author writes a **vacuous** contract → caught at Gate C (mutation probe fires) and
  by the verifier (formal tests that *should* fail against a vacuous spec);
- spec author **misreads the requirement** → caught by the coordinator at Gate A;
- a goal that passed via an **unspecified stub** (WP modelled the body as `\false`) → caught
  at Gate C (the obligation is vacuous; the mutation probe does not move it);
- verifier anchors to the implementation → structurally prevented (barrier) and the
  coordinator confirms each formal test derives from `U`.

## 3. Physical barriers (not honorary)
- **Spec author ⊥ body** and **Verifier ⊥ body + diff.** Their contexts contain only the
  requirement + public prototypes/headers; the function bodies and the annotator's diff are
  *absent*, not merely off-limits.
- **Annotator ⊥ acceptance evidence.** The formal tests and mutation set are not
  in its context, so it cannot tune the code to them.
- **Coordinator judges against `U`** — the requirement and the gate output, never a
  producer's account of *why* its artifact is right.
- **Anchoring tell:** if a contract or a formal test starts mirroring an
  implementation quirk (a magic constant, an off-by-one), a barrier leaked — re-delegate
  from a fresh, body-free context.

## 4. Gates
- **Gate A — editorial (judgment).** The coordinator judges the ACSL + plan against the
  requirement: each requirement clause typed and pre-bound to an ACSL obligation; the
  strongest-claim check; explicit `NOT`-claims. **Amend / cut / sharpen, never
  rubber-stamp.** No C/ACSL edit flows from a `DRAFT`.
- **Gate B — machine.** `frama-c -wp` → **all goals `Valid`** (no `Unknown`/`Timeout`);
  `-wp-rte` goals included for a robustness target; tests pass.
  - **no escape hatch on the target** — no `Admitted`, no `//@ assert \false`/`assumes \false`,
    no unproven `lemma` used as a hypothesis, no `assigns \nothing` that drops a real effect,
    no stub `ensures` stronger than the callee proves.
  - **Carve-out (definitional axiomatic):** an `axiomatic` block that merely *defines* a recursive
    `logic`/`predicate` over a memory range via its base/step equations is the standard, legitimate
    ACSL idiom — **not** a hatch; what is forbidden is an `axiom` asserting a *behavioral fact* about
    the function (one that mentions the C function or `\result`). Consistency of a definitional
    axiomatic is checked by Gate C (an inconsistent one would also prove the mutant).
  - **Standing proof count** holds; the determinism re-run gives the identical verdict (fixed
    `-wp-prover`, `-wp-timeout`, prover versions, `-machdep`).
- **Gate C — coverage / no-blend / coherent-and-wrong.** Every requirement clause maps to a
  *proven* ACSL clause, **and the proved theorem is the intended one**: the **mutation
  probe** must break the proof (non-vacuity — guards `ensures \true`, a loose `assigns`, a
  goal routed through an unspecified stub); the **proof plane** (WP) and the **test plane**
  (runtime) never substitute for one another (no-blend). (There is **no abstract-interp / EVA
  plane** — EVA is excluded by the TCB-minimization rule above; a verdict rests only on WP + the
  runtime/mutation checks.)
- **Gate C′ — completeness (the intended property, not just a non-vacuous one).** The mutation
  probe proves the *written* spec has teeth but **cannot tell it is complete**: a sort that
  ensures `Sorted(a,n)` but not permutation, or a search that ensures only a result-bound,
  passes faithful+B+C yet is under-specified (a zero-fill / return-`n` body satisfies it). So
  where an intended-property reference exists — the requirement, or the human **gold** spec —
  compare the loop's `ensures` against it (`framac-completeness.sh` gives a hint; an *editorial*
  judge, disjoint from the implementer, decides, since an inlined `\forall` may cover a gold
  predicate under a different name). A unit is PROVED only if its contract ensures every intended
  property; one that omits one is **PARTIAL**, not PROVED. No external reference ⇒ this reduces to
  the requirement-vs-spec editorial check (Gate A).
- **Gate S — skill-consistency.** When a role consolidates a reusable Frama-C heuristic (a
  loop-invariant template, a prover-selection tip, a stub idiom), audit it with the
  `sl-monitoring-sl` pattern: a **disjoint monitor** squeezes the skill against `U` and `L`
  → **PASS / CARVE-OUT / REJECT**. Only PASS/CARVE-OUT entries are written to the role's
  learned file under `config/skills/frama-c/references/` (§11).

## 4b. When the property is SYSTEM-level: macsl is IMPERATIVE, and its ghosts must be earned

Per-function `requires`/`ensures` prove *local* facts. The **load-bearing security properties
are system-level** — universals over *all* program points / *all* attack vectors ("root is
unrecoverable **by any means**", "the app cannot escape the mount namespace", "a forged token is
never accepted"). A per-function contract **cannot even state** such a property, so a unit whose
risk is system-level **cannot be discharged at the contract tier alone**: lifting it to a
**macsl / HAPPY meta-property** (`/*@ happy \prop, \targets, \context, P; */`) is **IMPERATIVE,
not optional** — it is the only mechanism that instruments the invariant at every matching site
and lets a theorem prover discharge it. (This is `frama-c-monitoring` Tier-3; framac-sl is where
one such unit is actually proved.) A campaign that stops at RTE + functional contracts has proved
memory-safety and local behaviour — it has **not** proved the authorization/integrity property the
risk actually named.

**The imperative comes with a hard discipline — the ghost-fiat trap.** A HAPPY property is usually
proved as `ghost-state ⟹ property`, where the ghost state is established by a **ghost model
function** (`//@ ghost sc_model_*();`) whose `ensures` names the very fact the property needs. If
that `ensures` is **postulated** rather than **derived from a real leaf contract**, the whole proof
is **semantically vacuous** — green, non-`\false`, and *wrong*: it proves the property IF the ghost
is accurate, and nothing proved the ghost. macsl's own non-vacuity gate does **not** catch this —
that gate catches *structural* vacuity (zero instrumented asserts); here the asserts expand,
discharge, and pass. Gate C's *code* mutation does not catch it either (the ghost is set by fiat).

**The rule (Gate C extended for system properties):** every ghost antecedent of a HAPPY property
MUST be either
- (a) **derived** from a stated leaf `ensures` that a real callee/`G_kernel` contract discharges,
  with a **non-vacuity witness** — restore the empty/weak leaf frame and *exactly* the dependent
  conclusions must redden (the snapd RS1 witness: 13/13 → 10/13 when the strengthened `setresuid`
  `ensures` is reverted); **or**
- (b) an **enumerated, source-auditable NAMED axiom** in the TCB — a gluing `GA_*` or a behavioural
  `SB_*` assumption — never a silent ghost assignment.

And the property must be closed as a **universal over all its vectors** — each vector PROVED or
explicitly CARVED/REFUTED, **no vector silently green**. *Worked reference: the snapd RS1 "root
unrecoverable" crown jewel — its `sc_model_drop_complete` ghost fiat, its replacement by a derived
leaf `ensures`, and the 8-vector closure (6 proved, 2 refuted) — in `the-snap-story.md`,
`recover-root.md`, and the generalized `ghost-fiat-pattern.md`.*

## 5. Loop steps (per function / unit)
DRAFT → APPROVED → DONE; the only backward motion is a numbered **gap document**.
1. **Coordinator** delegates an item: requirement clauses + public prototypes + barriers +
   acceptance lines + **the per-file preprocessing flags** from the compilation database.
   Each agent first loads its own learned file (§11).
2. **Spec author** writes the ACSL contracts/stubs from the requirement @ `STATUS: DRAFT`.
3. **Gate A** → `APPROVED`.
4. **Annotator** adds proof scaffolding to the original C, runs `frama-c -wp` locally, runs
   the standing invariant.
5. **Exerciser/Verifier** runs `frama-c -wp` fresh + authors **formal tests** (acceptance test
   drivers — broadest `requires`, the intended property checked in the body, `ensures \result==1`,
   discharged by WP over all inputs) and the mutation probes that prove they have teeth, from
   requirement + surface only. (See `../frama-c/SKILL.md` "A formal test" for the pattern.)
6. **Gate B** (machine) → **Gate C** (coverage / non-vacuity / no-blend).
7. Item `DONE` → next. Any divergence (a goal won't discharge; a mutant still proves; a
   probe surprises) → `gap-N` doc → re-plan (re-spec, re-annotate, or flag a code bug / a
   Frama-C limitation) — **never** a silent `Admitted`/axiom.
8. **Capitalize (§11):** each producing role distills ≤1 reusable heuristic; a disjoint
   monitor runs **Gate S**; PASS/CARVE-OUT entries are appended (with provenance).

## 6. Executable oracle setup
`frama-c [FLAGS] -wp -wp-rte FILE.c` over the unit; **a verdict = the per-goal status**
(`Valid` / `Unknown` / `Timeout`) reported by WP, plus a determinism re-run. Pin the
machine model (`-machdep gcc_x86_64`), prover set (`-wp-prover alt-ergo,z3,cvc5`), and
timeout (`-wp-timeout 10`) so the re-run is meaningful. The mutation probe is scripted
(flip a comparator, drop a `+1`, widen a bound, loosen a guard) and **required to turn some
goal RED**. The file's `-I`/`-D` (from the compilation database) must be passed **inside
`-cpp-extra-args="…"`** — Frama-C rejects a bare `-Ifoo`; a corpus whose typedefs were
pulled via a now-stripped include also needs a force-include there (e.g.
`-cpp-extra-args="-Iframac -include typedefs.h"` for StandardAlgorithms), which restores
them without editing the source so the faithfulness gate still passes. Pilot on the
smallest function end-to-end before any sweep (§12).

## 7. Done criteria
Per item: contracts approved at Gate A against the requirement; spec authored blind to the
body; **all WP goals `Valid`** (incl. `-wp-rte`) with no `Admitted`/axiom/vacuous-stub
shortcut on the target; tests green; the mutation probe breaks the proof; determinism
re-run agrees; the **faithfulness gate** (`framac-monitor-check.sh`) returns ACCEPT (the C
was only annotated, never altered); any consolidated skill passed Gate S. **No actor's
self-report ends an item — only the gates.**

## 8. Stabilizers engaged (collapse mode → blocker)
- *Self-judging* → forbidden moves (annotator never authors acceptance evidence; verifier
  never reads the code).
- *Honorary barrier* → spec author & verifier delegated from fresh, body-free contexts.
- *Self-declared done* → done is gate-defined (Gate B/C machine output + faithfulness gate).
- *Coherent-and-wrong / weakened clause* → author independence + Gate C mutation probe;
  **strictness has a safe direction** (the contract may be *stronger* than the requirement,
  never weaker, to land).
- *Vacuous via unspecified stub* → Gate C checks no goal routed through a `\false`-modelled
  body; the probe must move the goal.
- *Rubber-stamp approval* → Gate A must amend/cut/sharpen.
- *Absorbed surprise* → a non-discharging goal routes to a gap doc, never a local `Admitted`.
- *Unpinned reality* → the probe pins one Frama-C/WP capability claim before machinery is
  built on it.
- *Shared evidence between actors who must disagree* → the C1 disjointness audit.

## 9. Execution order
Pilot/oracle first. Then **leaf functions first** (WP is modular per-function), propagating
each proven callee `ensures` as the caller's assumption; sequence by mechanism reuse;
parallelize only across functions that share no evidence base. For a security audit,
schedule **attack-surface / untrusted-input parsers first** and report coverage as a
fraction of the *high-value* surface.

## 10. Compliance check (run before trusting an instance)
- **C1 Disjointness:** ✓ five distinct `(U,L)` pairs; no actor relieves its own bound;
  certification requires the intersection. *(Holds only if §3 barriers are physical.)*
- **C2 Catchability:** ✓ every characteristic blind spot has a named catcher (§2).
- **C3 Physical barriers:** ✓ iff spec author/verifier contexts are built from the
  requirement + prototypes, never the source or the diff.
- **C4 Gate-defined done:** ✓ done = all goals `Valid` + no escape hatch + mutation-probe
  breaks + faithfulness ACCEPT + Gate S; no self-report counts.

---

## 11. Knowledge capitalization — `config/skills/frama-c/`

`framac-sl` analyzes **one unit at a time**; after a unit reaches DONE, each producing role
distills at most one reusable, role-appropriate heuristic into the shared `frama-c` skill,
so the next unit starts smarter. This is **append-only learning under Gate S**.

**Per-role learned files** (under `config/skills/frama-c/references/`):

| File | Role | Records (role-scoped) |
|---|---|---|
| `../frama-c/references/learned-coordinator.md` | Coordinator | judgment/gate heuristics: clause-typing, NOT-claim patterns, when a DRAFT must be cut/sharpened |
| `../frama-c/references/learned-spec-author.md` | Spec author | requirement→ACSL patterns; stub idioms; modelling — **requirement-level only** |
| `../frama-c/references/learned-annotator.md` | Annotator | proof-scaffolding patterns: loop-invariant templates per loop shape, ghost idioms, prover/timeout tips |
| `../frama-c/references/learned-verifier.md` | Verifier | formal-test & mutation patterns: which mutation exposes a vacuous spec of a given shape |

**Discipline (same as `creusot-sl` §11):** drafted by the role that learned it, **never
committed by that role**; Gate S audit by a disjoint monitor (coordinator audits the
producers; the coordinator's own heuristics are audited by the verifier or a human); append
only PASS/CARVE-OUT with provenance; an entry may record only generalizable, role-
appropriate knowledge — the `spec-author`/`verifier` files must contain **no implementation
specifics**, and a leak of forbidden evidence is a barrier breach → REJECT.

**Entry format:**
```text
### <short heuristic title>
- Kind: ignore-signal | defer-to-oracle      (Gate S classification)
- Gate S: PASS | CARVE-OUT
- Arose from: <file / gap-N>
- Heuristic: <the reusable rule>
- Carve-out: <exception deferring to requirement clause …>   (if any)
```

---

## 12. Worked example — the pilot (run before any sweep)

Pin the oracle end-to-end on the smallest meaningful function. Target: a bounded `abs`.

Original C (`framac-orig/pilot/abs.c`, copied verbatim into `framac/pilot/abs.c`):
```c
int abs_i(int x) {
    if (x < 0) return -x;
    return x;
}
```

**Spec author** (blind to the body — sees only the prototype `int abs_i(int)` and the
requirement "return the absolute value; must not overflow") writes:
```c
/*@ requires x > INT_MIN;
  @ assigns \nothing;
  @ ensures \result == (x >= 0 ? x : -x);
  @ ensures \result >= 0;
  @*/
int abs_i(int x);
```
The `requires x > INT_MIN` is the strongest-claim guard: `-INT_MIN` overflows, so without
it the `-x` RTE goal cannot discharge — *the missing precondition is itself the latent bug*
(the robustness mechanism of §5 in `../frama-c-monitoring/references/loops-design.md`).

**Annotator** adds the ACSL to the original body (no executable change) and runs:
```sh
frama-c -machdep gcc_x86_64 -wp -wp-rte \
        -wp-prover alt-ergo,z3,cvc5 -wp-timeout 10 framac/pilot/abs.c
```
Expect: all goals `Valid` (the `ensures`, the `assigns`, and the RTE `-x` overflow goal,
the last discharged by the `x > INT_MIN` precondition).

**Verifier** (fresh, body-free) authors a mutation probe: drop the precondition
(`requires \true`) and re-run — the `-x` overflow goal must turn **`Unknown`/RED**. If it
stays green, the proof had no teeth → gap doc.

**Faithfulness gate:** `./framac-monitor-check.sh pilot/abs.c` must print `ACCEPT`
(stripping the `/*@ ... */` leaves the body byte-identical to `framac-orig/pilot/abs.c`).

Only once this pilot is green-and-has-teeth does the outer loop start the sweep.

---

## ASSUMPTIONS & open questions
- `ASSUMPTION:` deliverable = a target C code base mirrored under `framac/` (pristine copy
  under `framac-orig/`); functional + RTE robustness; partial correctness unless a
  `loop variant`/`decreases` is in scope.
- **Requirement source.** The full loop needs an *external* `U` (docstrings, a spec doc, a
  standard, or a human author). Without one you are restricted to RTE-only robustness
  (still sound — the C standard is the external spec) or a self-consistency pass.
- **Externals.** Library/driver calls out of scope need ACSL **stubs** authored from the
  documented surface (§6.3 of `../frama-c-monitoring/references/loops-design.md`); an over-promising stub is a Gate
  B violation.
- **Cross-module.** Single functions, or contracts coordinated across translation units?
  The latter makes the *outer* loop a nested `sl-monitoring-sl` (bottom-up, leaves first).
