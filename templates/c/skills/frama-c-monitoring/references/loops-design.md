# Two complementary SL loops for running Frama-C on a large code base

This document specifies how to verify a **large C code base** with **Frama-C** using
**two complementary Squeeze Loops** — the same architecture this repo used for Creusot
(see `creusot-loops-complementarity-explained.md`, `creusot-sl.md`, `workflow.md`), ported
to C/ACSL/WP.

- **`framac-sl`** — the **inner / base loop**: prove **one translation unit** correct
  (depth).
- **`framac-monitoring`** — the **outer / monitoring loop** (Workflow-driven): drive the
  inner loop over the **whole code base**, police each result, commit per batch (breadth).

Together they are the `sl-monitoring-sl` pattern: a squeeze loop monitoring a squeeze loop.

---

## 0. Creusot → Frama-C concept map

The topology is identical; only the *materials* of each squeeze change.

| Concept | Creusot (done) | Frama-C (this spec) |
|---|---|---|
| Spec language | Pearlite (`#[requires]`/`#[ensures]`) | **ACSL** (`/*@ requires/ensures/assigns/loop invariant */`) |
| Oracle `L` | `cargo creusot` → Why3 → SMT | **`frama-c -wp`** → VCs → SMT (Alt-Ergo, Z3, CVC5) |
| Second oracle | — | **none — WP is the sole oracle** (EVA excluded; TCB-minimization, §6.2) |
| Unit of work | one `.rs` file | one **translation unit** (`.c` + its preprocessing flags) |
| "Robustness spec" | total-robustness Pearlite | **`-rte` / `-wp-rte`** auto-generated runtime-error VCs |
| Verdict | per-obligation `Proved ✔` | per-goal **`Valid` / `Unknown` / `Timeout`** from WP |
| Escape hatches to ban | `#[trusted]`, `assume!`, axioms | `axiomatic`/`lemma`-as-axiom, unproven `//@ assert`, `assigns \nothing` gaming, `Admitted`, stub over-promise |
| Faithfulness gate | strip `#[...]`/`use`/proof-macros → byte-identical Rust | **strip ACSL comments + ghost code → byte-identical C** |
| Build driver | `cargo` | **`compile_commands.json`** (per-file `-I`/`-D`) |

**The key Frama-C-specific facts** (§6 expands them): Frama-C needs **preprocessing
flags per file**, it uses **WP as its sole oracle** (EVA excluded — a TCB-minimization rule,
§6.2; breadth comes from the Phase-0 architectural-audit ranking, not an EVA sweep), and
**`-rte` turns "is this safe?" into discharge obligations** — an undischarged RTE goal
localizes a latent bug exactly as the undischarged Creusot VCs localized the four `lace`
bugs.

---

## 1. The two loops, in one line each

- **`framac-sl` (inner):** a full Squeeze Loop that takes **one translation unit**, has a
  spec author write ACSL contracts *blind to the body*, an annotator add proof scaffolding
  (loop invariants, assertions, ghost code), a verifier run `frama-c -wp` + mutation
  probes, and gates A/B/C/S decide done. **Correctness in depth** on one unit.
- **`framac-monitoring` (outer):** a deterministic JS coordinator (the Workflow tool) that
  fans `framac-sl` out over the *whole code base* in batches, runs a **faithfulness gate**
  on each result, reverts fabrications, and commits per batch. **Scale and fidelity in
  breadth.**

The outer loop squeezes the *soft outputs* of the inner loop (the ACSL it produced) from a
disjoint evidence base — never the inner loop's rationale.

---

## 2. Inner loop `framac-sl` — the per-unit Squeeze Loop

### 2.1 Bounds
- **Upper bound `U`** = the **external requirement** (plain English / coding standard /
  ticket / MISRA rule) **made precise as ACSL** (`requires`/`ensures`/`assigns`/
  `loop invariant`/`loop assigns`/`loop variant`, logic functions, predicates). For a
  robustness sweep, `U` = "**no runtime error for any input**", materialized by `-rte`.
- **Lower bound `L`** = `frama-c -wp` goal discharge (**every goal `Valid`**) **plus**
  test execution of the compiled C **plus** the **mutation probe** (perturb the C; the
  proof must break). **WP is the sole oracle — no EVA** (TCB-minimization, §6.2).
- *Pilot first:* prove one tiny function (e.g. a bounded `abs`/`max`) end-to-end before any
  sweep, to pin the WP invocation, prover set, and timeout.

### 2.2 Actors and disjoint `(U,L)` pairs

| Actor | Builds | U (above) | L (below) | Forbidden move | Must NOT see |
|---|---|---|---|---|---|
| **Coordinator** | Gate A approvals, sequencing, gap-doc adjudication, DONE verdicts | requirement + plan | WP logs, test + mutation results | edit C/ACSL; approve an unjudged plan; let a self-report end an item | a producer's rationale |
| **Spec author** | the ACSL **contracts** (+ ACSL **stubs** for externals) | the **external requirement** + function prototypes/headers | expressibility: each clause dischargeable by *some* WP mechanism | read or infer the function body | the C implementation; the formal tests |
| **Annotator** | proof scaffolding: `loop invariant`/`loop assigns`/`loop variant`, intermediate `//@ assert`, `/*@ ghost */` | the contracts (strongest mandated claim) | `frama-c -wp` discharge + standing test suite | weaken a contract/`assigns`; add an axiom/`Admitted`/over-broad stub; touch acceptance evidence | the formal tests / acceptance evidence |
| **Exerciser/Verifier** | **formal tests** (acceptance test drivers proven by WP over all inputs — broadest `requires`, the property checked in the body, `ensures \result==1`) + **mutation probes** that prove they have teeth; runs `frama-c -wp` fresh | the requirement's acceptance clauses + the documented surface | what actually discharges when WP is run | read the implementation or the annotator's diff | the C implementation; the diff |
| **Probe** | minimal Frama-C/WP capability experiments (does WP model this construct? which prover discharges?) | one design claim per probe | Frama-C/WP's *actual* behaviour | implement a fix | — |

### 2.3 Physical barriers
Spec author ⊥ body and verifier ⊥ body+diff: their contexts contain **only the
requirement + the public prototypes/headers**, never the `.c` body or the annotator's
diff. Annotator ⊥ acceptance evidence. Coordinator judges against `U`, never a producer's
account. **Anchoring tell:** if a contract or a formal test starts mirroring an
implementation quirk (a magic constant, an off-by-one), a barrier leaked — re-delegate
from a fresh, body-free context.

### 2.4 Gates
- **Gate A — editorial (judgment).** Coordinator judges the ACSL + plan against the
  requirement: each requirement clause typed and pre-bound to an ACSL obligation;
  strongest-claim check; explicit `NOT`-claims. Amend/cut/sharpen, never rubber-stamp. No
  C/ACSL edit flows from a `DRAFT`.
- **Gate B — machine.** `frama-c -wp` → **all goals `Valid`** (no `Unknown`/`Timeout`);
  tests pass; **no escape hatch on the target** — no axiomatic/`lemma`-as-axiom smuggled to
  kill a goal, no `Admitted`, no unproven `//@ assert`, no `assigns \nothing` that drops a
  real effect, no stub `ensures` stronger than the callee proves; **standing proof count**
  holds (previously `Valid` goals stay `Valid`); determinism re-run gives identical
  verdicts (fix `-wp-prover`, `-wp-timeout`, prover versions).
- **Gate C — coverage / no-blend / coherent-and-wrong.** Every requirement clause maps to
  a *proven* ACSL clause **and the proved theorem is the intended one**: the **mutation
  probe** must break the proof (non-vacuity — guards `ensures \true`, a too-loose
  `assigns`, an unsatisfiable `requires`); the **proof plane** (WP) and the **test plane**
  (runtime) never substitute for one another (§6.2 — WP is the sole oracle, no EVA plane).
- **Gate S — skill-consistency.** When a role consolidates a reusable heuristic (a loop-
  invariant template, a prover-selection tip, a stub idiom), audit it with
  `sl-monitoring-sl`: a disjoint monitor squeezes it against `U` and `L` → **PASS /
  CARVE-OUT / REJECT**; only PASS/CARVE-OUT are appended to the role's learned file.

### 2.5 Loop steps (per unit) & execution order
DRAFT → APPROVED → DONE; the only backward motion is a numbered **gap document**.
1. Coordinator delegates the unit (requirement clauses + prototypes + barriers + the
   per-file preprocessing flags from the build DB).
2. Spec author writes ACSL contracts/stubs @ `DRAFT`.
3. Gate A → APPROVED.
4. Annotator adds scaffolding to the original C, runs `frama-c -wp` locally, runs the
   standing invariant.
5. Verifier runs `frama-c -wp` fresh + authors **formal tests** (acceptance drivers proven over
   all inputs — broadest `requires`, property checked in the body, `ensures \result==1`) and the
   mutation probes that prove they have teeth, from requirement + surface only.
6. Gate B → Gate C.
7. DONE → next. Any divergence (a goal won't discharge; a mutant still proves; a probe
   surprises) → `gap-N` doc → re-plan — **never** a silent `Admitted`/axiom/`assume`.
8. Capitalize (Gate S) into the role's learned file.

**Order:** pilot first; then **leaf functions first**, propagating each proven callee
`ensures` as the caller's assumption (WP is modular per-function — the same bottom-up rule
as Creusot); parallelize only across functions that share no evidence base.

---

## 3. Outer loop `framac-monitoring` — the Workflow coordinator

Identical role to `workflow.md`: move the **coordinator into deterministic JavaScript**
(zero LLM context) so per-unit results land in JS variables, not a context window, and the
run can finish the whole code base in the background, committing per batch.

```
Workflow script (JS coordinator — not an LLM)
  build the queue: each item = { file, flags }  (flags from compile_commands.json)
  chunk into batches of N:
     pipeline over the batch (concurrent, capped ~min(16, cores-2)):
        stage 1  agent framac-sl  -> annotate + frama-c -wp     (isolated context)
        stage 2  agent monitor    -> faithfulness gate, revert if fabricated
     agent committer -> update verdict log + git commit this batch
```

- **Queue with preprocessing flags (Frama-C-specific).** The script has no filesystem
  access, so compute the queue *outside* and pass it via `args` — and unlike the Creusot
  port, each item must carry its **`-I`/`-D` flags** so Frama-C can preprocess it. Derive
  them from `compile_commands.json` (e.g. with Frama-C's `-json-compilation-database`).
- **Faithfulness gate (`monitor-check.sh` analogue).** Strip every ACSL comment
  (`/*@ … */`, `//@ …`) and `/*@ ghost … */` block from the annotated file; the remaining
  C **must be byte-identical to the original**. Mismatch ⇒ the annotator altered
  executable C to make a goal pass ⇒ revert and downgrade the verdict. This is the
  *conservative-transformation gate* from `sl-monitoring-sl` ("strip `X`, require the rest
  to equal the input"). *Note:* ACSL is confined to comments, so the strip is well-defined
  — but the gate must also reject changes to `#define`s, includes, or any non-ACSL token.
- **Verdict schema:** `PROVED` (all goals Valid) / `PARTIAL` (some Unknown) / `FAILED` /
  `TRIVIAL` (nothing to prove). Faithfulness `false` downgrades to `TRIVIAL`/`FAILED`.
- **Cost & resume:** pass a token target (`+800k`) to bound the run; resume with
  `resumeFromRunId` so completed units return cached. The on-disk verdict log re-queues
  only unprocessed units after an interruption.

---

## 4. The complementarity, precisely (three points)

### 1. Depth vs. breadth — and why the coordinator moves
`framac-sl` carries the disjoint cast, physical barriers, and gates that make a *single*
proof trustworthy, but its coordinator is an LLM — run inline, every sub-agent summary
piles into one context and the run caps out after a few batches. `framac-monitoring` keeps
the sub-agents identical and moves *only the coordinator* into deterministic JS. Inner =
rigor; outer = the scale the inner loop can't reach alone.

### 2. Two different coherent-and-wrong failures, each caught by the other's bound
The inner Gate C mutation probe catches a *vacuous contract* (`ensures \true`, a loose
`assigns`). It cannot catch its own annotator **cheating the C** — editing a statement,
loosening a `#define`, or stubbing out a call so a goal discharges. That is exactly the
outer loop's faithfulness gate: strip ACSL → require byte-identical C → revert on
mismatch. Each loop closes the failure the other is blind to.

### 3. Disjointness across the boundary
The outer monitor is a separate sub-agent that sees only the inner loop's **returned soft
output** (the verdict + the modified file) — never its rationale. The sub-agent delegation
boundary *is* the physical barrier, so the monitor can't share the annotator's blind spot.
Done stays gate-defined (`frama-c -wp` + faithfulness gate), never self-reported, even
unattended.

---

## 5. How bugs would surface (the `lace` mechanism, ported)

The two loops together turn safety into mechanical obligations:

> **Specify each untrusted-input parser / boundary function for *total robustness*
> (`-rte`, no runtime error for any input) → run the inner loop → an undischarged WP goal
> is, by construction, a missing safety guard = a candidate bug.**

This is precisely how 3 of the 4 `lace` bugs were found (undischarged Creusot VCs that
localized a missing guard and suggested the one-line patch). The C analogues of those VC
classes — and the ACSL clause that proves each absent:

| Bug class | RTE / ACSL goal that fails | Patch shape |
|---|---|---|
| Subtraction underflow (the `e_lfanew - 64` bug) | `-rte` unsigned-overflow goal on the subtraction | guard `x >= K` before subtracting; fallible slice |
| Multiply overflow | `-rte` overflow goal on `a * b` | `checked`-style guard / widen + bound |
| Div-by-zero | `-rte` `\divisor != 0` goal | reject zero divisor up front |
| OOB array/pointer access | WP `\valid`/`mem_access` goal | bounds precondition + length check |
| Unbounded recursion / DoS | *not* a WP goal — needs call-graph/`loop variant` analysis | bound the depth (honest scope: label it as found by a different method, as `lace` Issue 4 was) |

The honesty rule carries over: where WP cannot reach a property (e.g. native
recursion depth), the finding is **labeled as coming from a different method**, not
silently passed.

---

## 6. Frama-C-specific considerations for a large code base

These are the places the Frama-C port genuinely diverges from the Creusot one.

### 6.1 Build integration is part of the queue
Creusot rode `cargo`; Frama-C needs each file's **preprocessing context**. Generate a
`compile_commands.json` (Bear/CMake/intercept-build), feed it via
`-json-compilation-database`, and carry per-file `-I`/`-D` in the `args` queue. A unit that
won't preprocess is a `gap` (missing flags / generated header), not a proof failure.

### 6.2 One oracle — WP only (no EVA; a TCB-minimization rule)
Frama-C also ships **EVA** (abstract interpretation, whole-program RTE), but this loop
**does not use it — not as an oracle, and not even as a proposed triage plane.** Letting EVA
discharge (or even rank) an obligation would fold the **entire abstract-interpretation
engine into the trusted computing base**; in the age of capable AI the labor EVA once saved
— hand-authoring enough ACSL for WP to converge — is affordable, so we pay it and keep the
TCB minimal.
- **`frama-c -wp` goal discharge is the SOLE executable lower bound** (together with test
  execution of the compiled C and the mutation probe). A verdict records *which* WP/SMT/Coq
  oracle closed each obligation; Gate C **rejects any verdict that cites EVA** as a discharge.
- **Breadth without EVA.** Risk-ranking the whole base — what an EVA sweep was once for —
  comes from the **Phase-0 architectural audit's attack-surface ranking** (severity ×
  likelihood), not from an abstract-interpretation pass.
- **No-blend still holds** among the surviving evidence: a WP `Valid` must never stand in for
  runtime test coverage, and neither tests nor the mutation probe substitutes for a WP proof
  of the functional obligation.
- **Residue, not EVA.** For RTE/cast goals WP cannot close in the Typed model, the move is a
  `-wp-model bytes` / representation-predicate / symbolic-base-allocator idiom — **never an
  EVA split** (see the `never-use-eva` rule and `frama-c-monitoring`'s "No EVA").

### 6.3 Externals need ACSL stubs (a clean barrier fit)
A large base calls libc / drivers / other TUs whose bodies are out of scope. The **spec
author** writes ACSL **stubs** (`requires`/`ensures`/`assigns`) from the documented surface
— exactly the body-blind role it already plays, so this fits the barrier. Gate B forbids a
stub `ensures` stronger than the real callee guarantees (an over-promising stub is the C
analogue of `#[trusted]`): when a callee is in scope, its proven `ensures` must imply the
stub.

### 6.4 Prover budget, determinism, and the probe role
WP discharge depends on prover set, timeout, and memory. Fix `-wp-prover`,
`-wp-timeout`, and prover versions so the determinism re-run is meaningful; route a goal
that only discharges under a longer timeout to the **probe** (one capability claim per
probe) before building on it. `Timeout`/`Unknown` is a **gap**, never a silent `Admitted`.

### 6.5 Modular scheduling
WP is modular per-function, so the **leaf-first** propagation (callee `ensures` ⇒ caller
assumption) and **per-TU** batching both apply directly. Schedule **attack-surface /
untrusted-input parsers first** (as the `lace` run did), and report coverage as a fraction
of the *high-value* surface, not the whole base.

---

## 7. Concrete artifacts to create (checklist)

To stand this up, mirroring the Creusot layout:
- `../../framac-sl/SKILL.md` — the inner-loop spec (this §2, expanded with a worked pilot).
- `framac-workflow.md` — the outer-loop Workflow script + how to run/watch/resume (this §3).
- `monitor-check.sh` — the ACSL-strip faithfulness gate (`/*@…*/`, `//@…`, `/*@ ghost…*/`
  removed → `diff` against the original C must be empty).
- `gen-verdicts.sh` + `.verdicts.tsv` — the per-batch verdict log.
- A build step producing `compile_commands.json` and the `{file, flags}` queue.
- `config/skills/frama-c/` — the shared skill + per-role `learned-*.md` files, governed by
  Gate S.
- `framac-issues/` — one report per finding (minimal adversarial input + draft patch),
  as `lace-issues/` does.

## 8. Compliance check (before trusting an instance)
- **C1 Disjointness:** five distinct `(U,L)` pairs; no actor relieves its own bound;
  certification = the intersection. (Holds only if §2.3 barriers are physical.)
- **C2 Catchability:** every blind spot has a named catcher (annotator gaming a weak
  contract → verifier's formal tests + mutation probe; vacuous contract → Gate C;
  misread requirement → Gate A; cheated C → outer faithfulness gate).
- **C3 Physical barriers:** spec author/verifier contexts built from requirement +
  prototypes, never the `.c` body or the diff.
- **C4 Gate-defined done:** done = all WP goals `Valid` + no escape hatch + mutation-probe
  breaks + faithfulness gate ACCEPT + Gate S; no self-report counts.
