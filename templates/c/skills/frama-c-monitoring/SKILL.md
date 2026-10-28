---
name: frama-c-monitoring
description: >-
  A top-level Squeeze Loop that drives the framac-sl loop across a whole C/C++
  codebase. Given a mission like "verify the library xxx in directory yyy", it
  runs a Phase-0 architectural audit, builds the file/dependency graph, schedules
  the translation units in the right order (leaf-first, propagating each proven
  callee ensures as the caller's stub requires), and instantiates a framac-sl
  sub-loop (coordinator/spec-author/annotator/verifier) on each unit — driven
  unsupervised through the Workflow tool (see references/framac-workflow.md). It is
  itself a squeeze loop MONITORING a squeeze loop (the sl-monitoring-sl meta-pattern):
  its lower bound / ground truth is framac-sl's own WP machine verdicts (frama-c -wp
  -wp-rte), and its upper bound is compliance with the mission guidance. Unlike a
  single-gate Creusot monitor, the base-SL monitor here runs FOUR gates per unit —
  faithfulness (strip-ACSL == framac-orig), Gate B (no smuggled behavioural axiom),
  non-vacuity (mutation probe), and completeness vs a framac-gold reference — and
  audits the SMT->Coq prover-escalation ladder for soundness (Print Assumptions:
  only definitional axioms, zero admits). It routes tooling gaps to getting-better/
  and bugs to bugs-to-report/, and capitalizes its own learning under
  config/skills/frama-c-monitoring/. Use to verify a whole C/C++ codebase (not a
  single function) with Frama-C/WP, to orchestrate/monitor many framac-sl runs, to
  schedule units leaf-first with per-unit preprocessing flags, to calibrate verdict
  coverage against a gold annotation set, or to collect Frama-C/WP feature requests
  and bug reports surfaced during verification.
---

# frama-c-monitoring — a Squeeze Loop driving and monitoring `framac-sl`

> **When to run this loop — extreme cases only, NOT by default (user directive, 2026-06-19).**
> The full multi-agent squeeze is *assurance machinery*, not bug-finding: the verification result
> is Frama-C/WP's; what the squeeze adds is **trustworthy-by-construction proofs** (the disjoint
> faithfulness gate) and a **defense against coherent-and-wrong** (a code-blind judge catching a
> spec that passes WP but betrays intent). That is worth its real cost (≈3 agent-roles/unit,
> ~10⁵–10⁶ tokens and ~1h wall per hard unit) **only** when all three hold: (a) a plausible-but-wrong
> result is expensive (bootloader, TLS/crypto parser, safety/policy code); (b) the property is
> contested/underspecified or the agent could plausibly produce something self-consistently wrong;
> and (c) the proof must be trusted *without* a human re-verifying it. **Default to a single
> Frama-C/WP pass (one agent) + your own spot-check** for quick, well-specified, or low-stakes work —
> there the extra agents catch nothing and are pure overhead. Reach for the full loop deliberately,
> not reflexively.

`frama-c-monitoring` is the **top** loop; `framac-sl` (`../framac-sl/SKILL.md`) is the
**base** loop it drives, one C/C++ translation unit at a time. It is built with the
`sl-builder` methodology and monitored with the `sl-monitoring-sl` meta-pattern ("a
squeeze loop monitoring a squeeze loop"). It launches sub-agents: for each unit it
instantiates a full `framac-sl` (coordinator + spec author + annotator + verifier +
probe), and it adds its own top-level cast on top. It is run **unsupervised** through
the **Workflow** tool — the coordinator lives in deterministic JavaScript, not the chat
window — exactly as `references/framac-workflow.md` describes.

> Drafted with `sl-builder`; monitoring discipline from `sl-monitoring-sl`. Slots the
> mission did not fix are marked `ASSUMPTION:`; unresolved forks are in *Open
> questions*. Run the C1/C2 checks before trusting an instance. The base loop / sister
> skill is `frama-c` (the ACSL-authoring reference).

## 0. Mission & deliverable
- **Mission shape:** `verify the library <xxx> in directory <yyy>` + **guidance** (the
  upper bound — see §1), e.g. *"prove total robustness (no RTE) for the parsers;
  specify functional behaviour thoroughly; disregard concurrency."*
- **Deliverable:** every in-scope goal carried to one of the **three terminal statuses (§8):
  PROVEN · VIOLATION (a code bug, reported) · BUG IN FRAMA-C (a true goal the tool can't prove,
  diagnosed to a reproducer and filed)**, in dependency order, consistently honoring the guidance —
  plus a recorded monitor verdict on each base-loop skill / inferred contract, a verdict log
  (`framac/.verdicts.tsv` → `VERDICTS.md`), and every filed Frama-C bug under `bugs-to-report/`.
  **`PARTIAL` is NOT a terminal status — it is unfinished work** to drive to PROVEN (author the spec)
  or to a filed Frama-C bug; it never survives as an acceptable end-state.
- **KEY PRINCIPLE — a missing-spec Timeout/PARTIAL is the loop's unfinished work, not a verdict:
  re-invoke `framac-sl` to finish it, *before* the report.** Calling `framac-sl` again where a unit
  did not fully discharge **is the whole purpose of this loop** ("drive `framac-sl` where needed").
  A bare-RTE pass *always* leaves undischarged goals that are **specification gaps, not
  prover-strength gaps**: an unconstrained pointer needing `requires \valid(p)`; a blocking /
  unbounded loop needing `terminates \false` (or a `loop variant`); a callee whose proven `ensures`
  was never propagated as the caller's stub; an index needing a bound. Those are **not** the unit's
  final verdict — the coordinator must **re-instantiate the `framac-sl` sub-loop to author exactly
  those contracts**, iterating (and cascading into the callee inlines each precondition surfaces)
  until WP converges. A goal that *survives* spec-convergence and is **probe-confirmed true-but-hard
  is not yet residue — it is escalated to Coq and *discharged*, not merely labelled** (§5 step 4):
  `COQ-NEEDED` names *work to do*, not a terminal verdict. Only what **even a sound Coq replay cannot
  close** (Coq-attempted), or an unmodelled construct (e.g. a linker-section iteration) / tooling
  defect, becomes an honest PARTIAL/`gap-N`. **This strengthening (spec-convergence *and* the Coq
  discharge) MUST complete before any report is generated (§8b):** a
  report that lists missing-spec Timeouts as residual risk is reporting the loop's own unfinished
  work, not the program's risk. (Worked example: a bare-RTE pass on Zephyr `kheap.c` left 7
  Timeouts; one `requires \valid` per API fn + `terminates \false` on the blocking allocs + the
  `\valid` cascade into `sys_dlist_init`/`z_waitq_init` closed all but the `statics_init`
  linker-section residue — SMT only, no Coq.)
- **MANDATORY GATE — the refutation probe: no goal may be labeled `COQ-NEEDED` / residue until a
  spec antecedent has been tried and *failed to flip it*.** A missing-hypothesis goal and a
  true-but-hard goal both print as `[Timeout]` — they are indistinguishable by the timeout alone,
  and the cheap-but-wrong move is to read "SMT timed out (esp. over a big aggregate / after an
  unspecified call)" as prover-weakness. It usually is not. **Before writing `COQ-NEEDED`, run the
  probe:** identify the antecedent the goal points at — a callee `ensures`, a caller `requires`, a
  `loop invariant`, a frame/`assigns` — add it, and re-run. **Flips to `Valid` instantly (Qed, ms) ⇒
  it was a *missing hypothesis* (a spec gap): keep authoring, it is NOT residue.** **Stays stuck with
  the antecedent in scope ⇒ genuinely true-but-hard: escalate to Coq.** Rationale: a missing
  hypothesis means the goal is *false in some model* (a counterexample exists) — no prover, SMT or
  Coq, proves a non-theorem; only the antecedent fixes it. A `COQ-NEEDED` verdict is a claim
  ("entailed but SMT-intractable") that MUST be backed by this probe — an unprobed `COQ-NEEDED` is an
  unaudited dead-end and is rejected at Gate C_top (§4) / §6. (Crisp tell: a function whose body is
  `{ }` still times out on `ensures \valid(p)` with no `requires \valid(p)` — a do-nothing function
  is not a hard proof; it is a missing antecedent.)
- **PATTERN — global-invariant threading (the cross-callee case the local patterns miss).** The four
  patterns above are *local* (one function, one clause). The harder, common residue is a **system
  invariant** that is *not read off any single function* and must be **invented, then threaded** as
  `requires`/`ensures` through a whole transitive callee chain — often across **shared headers**, and
  with **backtracking** (an over-broad contract that a callee body cannot prove must be narrowed or
  moved to a leaf). Recognize it when `\valid(x)` / a state fact is repeatedly lost *after calls* to
  several different helpers: the fix is one invariant (e.g. *"a syscall handler never frees the
  running thread"* → `requires \valid(_current); ensures \valid(_current)`) carried from the entry
  function down through every helper it transitively calls (extern leaves get it as an assumed
  contract; helpers with bodies must *prove* it from their callees — so thread leaf-first). This is
  in-scope `framac-sl` work, not residue. (Worked example: Zephyr `userspace_handler.c` — the 7
  `_current`-after-call goals were mislabeled `COQ-NEEDED`; threading `\valid(_current)` through
  `z_impl_*`→`z_vrfy_*`→`k_thread_perms_*`→`k_object_validation_check`→`k_object_dump_error` closed
  the 4 marshaller goals with SMT only, 43/50→59/64. The probe flips them instantly — proof it was a
  spec gap, not Coq. Residue only begins where the chain reaches a no-return I/O tier (`printk`) or
  genuine aggregate-grind survives the probe.)
- **Dominant coherent-and-wrong to guard:** a codebase that *looks* verified because
  each unit's WP went all-`Valid`, but where a goal is **vacuously** green — discharged
  through an unspecified callee (`\false` block), a trivially-true postcondition, a
  smuggled `axiom`/`Admitted`, or a spec that omits the intended property (the *sorting
  trap*: `Sorted` proved but not *permutation*). Each is right-by-the-machine yet wrong
  against intent — exactly what the four base monitor gates (§6) are positioned to catch.

## 1. Bounds
- **Upper bound `U` (soft, normative):** the **mission guidance** — the citable
  instruction on *what and how much* to verify (which properties: RTE-only vs full
  functional; which subsystems are in scope), plus the mission scope (`library xxx`,
  `dir yyy`). The strongest claim any base-loop output may make is "a reading the
  guidance does not refute." `U` is **seeded and sharpened by the Phase-0 architectural
  audit**: the audit's extracted *claims* about the system become citable, per-unit
  obligations — turning vague guidance ("specify thoroughly") into a concrete upper
  bound. When a **`framac-gold/`** reference (human ACSL from history) exists, it is a
  second, *concrete* upper bound on completeness (Gate C′, §6).
- **Lower bound `L` (executable, ground truth):** the **`framac-sl` loop itself** — its
  WP machine verdicts per unit (`frama-c -wp -wp-rte`: every goal `Valid`, or a residual
  + a `gap-N`), which `frama-c-monitoring` **cannot alter**. The base loop *is* the
  runnable oracle. Cross-unit, `L` also includes WP discharge **across units**: a callee's
  proven `ensures` must **imply** the stub `ensures` the caller assumed at the call site
  (an over-promising stub is unsound). When SMT cannot close a goal, `L` extends to the
  **Coq** replay (the `framac-coq8` toolchain) — but only a *cache-clean, zero-admit*
  Coq replay counts as ground truth (§6, prover-escalation audit).

## 2. Actors and their disjoint `(U,L)` pairs

The base-loop cast lives in `framac-sl`; this table is the **top** cast added on top.

| Actor | Builds | U (above) | L (below) | Forbidden move | Must NOT see |
|---|---|---|---|---|---|
| **Mission coordinator** | the per-codebase plan, the unit schedule, verdict-log adjudication, routing of suggestions/bugs | the mission guidance + scope | the aggregated `framac-sl` WP verdicts + cross-unit discharge | edit C or ACSL; declare the codebase done on a sub-loop's say-so; absorb a tooling surprise locally | — (judges against the guidance, never a sub-agent's rationale) |
| **Architect / auditor** (Phase 0) | the **architectural audit** — fan-out read-only deep-read → a report yielding the *claim set*, the WP-amenability *scope map*, and the value/risk *ranking* | the mission + the system's documented intent | the actual source (read-only) | edit the target; verify anything itself; assert a claim it did not read out of the code | — |
| **Scheduler / graph planner** | the include/call graph of `dir yyy`; the **leaf-first** topo-order *refined by the audit ranking*; the parallelizable set; **and the per-unit preprocessing flags** (`-I`/`-D`/`-machdep`/force-includes) from `compile_commands.json` | the mission scope + the audit ranking | the *actual* dependency + compile graph (`compile_commands.json`, the C preprocessor) | skip a unit silently; verify anything itself; emit a unit that will not parse | — |
| **Base-SL monitor** (`sl-monitoring-sl`) | per-unit **four-gate** verdicts (faithfulness / Gate B / non-vacuity / gold-completeness) + per-skill / per-inferred-contract verdicts on what `framac-sl` learned, **and** the soundness audit of any Coq escalation | `U` (guidance + `framac-gold`) | `L` (the WP oracle + cross-unit discharge + cache-clean Coq replay), as a differential comparator | edit `framac-sl`'s implementation; read a producing agent's rationale; accept a green it has not gated; fake a PASS for an un-runnable replay | the base agents' private notes |
| **framac-sl instances** | per-unit verified C + ACSL (the base deliverable) | the unit's requirement (from the guidance) | the per-unit WP gates | (the base loop's own forbidden moves) | (the base loop's own barriers) |

**Disjointness (C1):** the scheduler holds "what the dependency graph + compile flags
are" (never the specs); the base `framac-sl` instances hold "what discharges within a
unit"; the **monitor holds "what the guidance + `framac-gold` mandate" + "what the WP
oracle actually returns"** — a *disjoint* evidence base from the base loop that produced
the artifact; the coordinator holds the guidance + aggregated verdicts (never producing a
unit's artifact). **Intersection** = a codebase whose every unit is base-`Valid` *and*
whose annotations survive the four gates + the guidance + cross-unit oracle from outside
the base loop.

**Catchability (C2):** a base loop that produces a **vacuous** green (unspecified-callee
`\false`, trivially-true postcondition, smuggled axiom, under-specified spec) is caught
by the monitor's four gates (it holds the mutation probe + `framac-gold`, which the base
agents do not). A unit verified in the wrong order (a callee not yet specified) is caught
by the scheduler's leaf-first order + the cross-unit stub-implication check. A Coq script
that "closes" a goal via a smuggled axiom or `admit` is caught by the prover-escalation
soundness audit (`Print Assumptions`).

## 3. Physical barriers
- **Monitor ⊥ base rationale.** The monitor judges each base-loop artifact/skill only
  against `U` (guidance + gold) and `L` (the WP oracle) — never the base agent's account
  of *why* it annotated as it did. It emits a verdict + carve-out, never a silent fix; a
  FABRICATED unit is **reverted** from `framac-orig/`, not edited.
- **Coordinator judges against the guidance**, not a sub-agent's self-report; the
  codebase is never "done" because a sub-loop reported success.
- **Base barriers are inherited, not weakened.** The spec author writes stubs from the
  *documented surface*, never the callee body; the verifier never reads the body or the
  diff. Driving `framac-sl` as a sub-loop must not hand a barriered base role anything it
  is forbidden to see; the monitoring layer adds barriers, it never removes the base's.
- **Faithfulness is physical.** ACSL lives only in comments; `framac-monitor-check.sh`
  strips it and requires the remaining C to be byte-identical to `framac-orig/`. Editing a
  statement / `#define` / `#include` to make a goal pass is the FABRICATED failure.

## 4. Gates (top level)
- **Gate A_top — editorial.** The coordinator judges the per-codebase plan + unit
  schedule + the *interpretation of the guidance* against `U`: is "RTE-only for module Z"
  actually applied, is "specify thoroughly" met (no unit silently under-specified), is the
  leaf-first order sound, do the per-unit flags parse? **It also sets the verification *depth*
  per unit** — which tier of the depth ladder (§4b) each unit climbs (RTE floor / + formal tests /
  + macsl/HAPPY policies), driven by the EBIOS risk ranking. Amend / cut / sharpen; no delegation
  from a `DRAFT`.
- **Gate B_top — machine.** Every scheduled unit's `framac-sl` reaches its verdict with
  WP all-`Valid` for the claimed scope; the **leaf-first order held** (each callee
  specified before its callers; the proven `ensures` propagated as the caller's stub
  `requires`/`ensures`, and the proven callee `ensures` **implies** the assumed stub);
  **no unit in scope skipped**; the verdict log is complete.
- **Gate C_top — coverage / no-blend / coherent-and-wrong.** Every in-scope unit has a
  base verdict and passes the **four base monitor gates** (§6); the guidance was honored
  **uniformly**; a base-inferred contract that contradicts the guidance or another unit is
  caught by the monitor; an **EVA "no alarm" never stands in for a WP `Valid`** (no plane
  blend); a goal routed through an **unspecified callee** or a **trivially-true
  postcondition** is flagged vacuous; **every `COQ-NEEDED`/residue label carries its refutation-probe
  evidence (§0, §6) — an unprobed residue is REJECTED** (it usually hides an un-threaded system
  invariant); every tooling surprise was **routed** (§7), never absorbed.
- **Gate S — skill-consistency (both levels).** The base loop's learned skills (under
  `config/skills/frama-c/references/`) are audited by the monitor (§6). The monitoring
  loop's **own** learned skills (under `config/skills/frama-c-monitoring/references/`) are
  audited from a *disjoint base* (a cross-provider agent or a human — the recursion must
  stop at an external reviewer, per `sl-auditor` Dimension 8); never self-audited.

## Phase 0 — architectural audit (run this before §5, to *focus* the loop)

**Before delegating any unit, run a generic architectural audit of the target so the loop
is aimed, not blind.** If the target was onboarded by **`frama-c-launch`** (`../frama-c-launch/SKILL.md`), this audit + the scope map + attack-surface ranking arrive in its **onboarding package** (`../frama-c-launch/templates/onboarding-package.md`) — *consume* it rather than re-deriving, but still **re-judge** it at Gate A_top against the *verification* guidance (a launch PASS certifies the setup, not the units). With no onboarding package, run the audit here from scratch. Fan out read-only sub-agents (one per subsystem/module — the
`sl-monitoring-sl` sub-agent isolation keeps the coordinator's context clean), each
deep-reading its area, then synthesize one **architecture report**. The audit produces the
three things the rest of the loop runs on:

1. **An upper bound (`U`).** The report's **claims** — the properties the system asserts
   about itself ("these parsers bounds-check and never overflow", "this allocator never
   returns aliasing pointers") — become part of `U`. The loop's job becomes *check those
   claims hold*, per unit, rather than the vaguer "specify thoroughly."
2. **A scope map.** Which units are WP-amenable (pure-ish, bounded, in-scope memory) vs
   genuinely hard for WP (inline asm, true concurrency / data races, arbitrary function
   pointers, `setjmp`/`longjmp`, float where the model is weak). The loop concentrates on the
   amenable set and *records* the rest — never failing on, or faking, what WP cannot model.
   **GROUNDING RULE (load-bearing): "BLOCKED / out of scope / out of WP's reach" is a
   *verifiable* claim, not an assumption.** Confirm before marking it — much that is *assumed*
   unreachable is not: Frama-C's **ACSL libc** (`$(frama-c -print-share-path)/libc`) specifies
   the string / IO / **syscall** / socket functions (`string.h`, `unistd.h`, `sys/socket.h`),
   and variadics (`snprintf`/`sscanf`) go through the **Variadic** plugin — so libc/syscall-heavy
   code is reachable via those (coarse) contracts. Check the share dir, or run a one-file probe;
   **never assert a negative capability claim from memory** (two were filed wrong here — the
   system-property tool wrongly called a "no-op" (an invocation-order error, since fixed by macsl
   instrumenting in place) and "main.c is out of WP's reach"; see `getting-better/`).
3. **A value/risk ranking that focuses the schedule.** Leaf-first order is *refined by
   importance*: for a security audit, rank by **input-exposure** so the parsers of
   untrusted input (the attack surface) are proven first, and coverage is reported as a
   fraction of the *high-value* surface, not of the whole tree.

**Gate A_top** then judges the audit + the resulting `U`/scope/ranking before any unit is
delegated. The architecture report is a first-class output (alongside the verdicts).

**Also at Gate A_top: write the squeeze table (WS2).** Before any delegation the coordinator fills
the per-campaign `(U,L)` table from `templates/squeeze-table.md` — each actor's upper
bound, lower bound, **denied evidence**, and **provider** — and `framac-squeeze-audit.sh` must pass
(C1 pairwise-distinct pairs; C3 every judge — property-author, verifier, completeness oracle,
monitor — denies the implementation/annotation; providers recorded). The table is pasted row-by-row
into each sub-agent prompt, so an actor learns from fresh context which authorities bind it and, by
omission, which evidence it is denied. A campaign that has not passed the squeeze audit is not
`APPROVED`.

**Honesty — endogenous vs exogenous `U`.** The audit reads the *implementation*, so any
*functional* claims it extracts are an **endogenous** upper bound: verifying them is a
**self-consistency** check, not conformance to an external spec — *unless* a `framac-gold/`
reference or an external requirement supplies an independent intent. **Safety/robustness**
properties the audit *motivates* (no overflow / div-by-zero / out-of-bounds for **any**
input, via `-wp-rte`) are **exogenous** — universal, not derived from the code — so proving
those is genuinely sound. The audit's load-bearing jobs are to **focus** the loop and
**surface scope**; functional claims are self-consistency unless `framac-gold` or an
external requirement is also supplied.

## 4b. Verification depth ladder — RTE floor → formal tests → macsl/HAPPY policies
*What* to prove **per unit** is a Gate-A_top depth decision, not one-size-fits-all. Three tiers, in a
**soundness-dependency order** — each rests on the one below; you may not skip the floor.

**Tier 1 — RTE-robustness (WP `-wp-rte`). The mandatory floor.** No undefined behaviour for *any*
input (no OOB, overflow, div-by-zero, bad shift). `U` = the **C standard** — exogenous and universal,
so this tier needs no soft authority and closes **MACHINE-DONE with ~no soft residual**. It is layer
one for a *hard* reason, not an easy one: **UB poisons every higher claim** — in C a function that can
invoke UB has no defined semantics on that path, so a functional `ensures` proved over it is proved
against WP's *model*, not reality. **A formal test or meta-property on a unit whose RTE goals are still
un-discharged is conditional on an unproven assumption — the assumed-but-unproven Gate-B hatch.** Never
let a higher tier rest on open RTE goals.

**Tier 2 — Formal tests (functional behaviour).** Once RTE makes the semantics defined, validate *what
the function computes* via **formal tests** (see `../frama-c/SKILL.md` "A formal test": broadest
`requires`, the property checked in the body, `ensures \result==1`, proven over all inputs by WP;
authored disjointly from the requirement, **blind to the code**). `U` = the **requirement / English
description**; needs the verifier cast + a **human terminus** (did the description capture intent? —
Gate C′).

**Tier 3 — macsl / HAPPY system-property policies (global / policy meta-properties).** Contracts and
formal tests are *local* (per function); many security properties are **global** — invariants over
*all* relevant program points: "a forged certificate is never accepted", "secret data never reaches a
log", "authentication always precedes resource use". Express these as **HAPPY policies** (`/*@ happy
\prop, \targets, \context, P; */`) with **macsl** — the canonical system-property tool — which
instruments them as ACSL assertions at every matching site (in place) and discharges via WP. macsl
covers all six STRIDE letters via its `\context` families (`\writing`/`\reading`/`\precond`/`\postcond`/
`\total`/`\noninterference`); see `references/macsl-recipe.md`. `U` = a **security policy**; terminus =
the **risk owner** (the EBIOS W5 sign-off, §8e).

### Climb by risk, not by waterfall
RTE is the **universal floor** — every in-scope unit. The upper tiers are applied **selectively, by the
EBIOS risk ranking** (the crosswalk, §Phase 0 / `../frama-c-launch/templates/ebios-crosswalk.md`): the
top-risk parser climbs all three; a mid-risk unit stops at RTE+formal; a low-risk / crypto unit stays
RTE-only or BLOCKED. It is **not** "all RTE everywhere, then all formal" — go **leaf-first, unit by
unit**, and within a high-value unit RTE and functional goals **co-discharge** in one WP run (the tiers
are a dependency relation, not separate passes). **Gate A_top sets the depth per unit** from the
guidance + the ranking; the floor is non-negotiable, the height is risk-driven.

### Breadth: a SLICE witnesses the class; the DEFAULT deliverable is the WHOLE-FUNCTION in-situ proof
The ladder above is the *depth* axis (what property); this is the *breadth* axis (how much of the unit).
A **guarded-site slice** — a small driver modeling one site (an E2BIG bound, a `sh_link<sec_cnt` check, a
`vlen` member walk) with the site's envelope as `requires` — is a legitimate **WITNESS of the
memory-safety class** at that site, and it settles the anti-vacuity question (remove the guard => the
access goes Unproved). **But a slice is NOT the terminus. By DEFAULT drive every in-scope unit to
WHOLE-FUNCTION IN-SITU on the real TU** — all paths, the full body, the actual callees (contracted
leaf-first) — not a slice. A function proven **only** at slice-level, with its full body store-bloated or
deferred, is **class-C unfinished work** (the whole-function in-situ proof is the missing lever), never
"done"; record it class-C, and carry the slice in `formal-tests.tsv` as the **interim witness**. The
slice's second, diagnostic job: **localize a residual** — slice proves AND full-body times out => the
residual is a **store-bloat artifact blocking rigor, not a safety gap** (see [[no-ceiling-gate]]); slice
*also* fails => a real gap. When the whole-function proof store-bloats, the required closure ladder is:
**Typed-vs-bytes model split · `-simplify-cfg` · a proven region/derivation LEMMA fired at the site ·
checkpoint-slice · context reduction · Coq-clear escalation** — never relabeling the slice as the
deliverable. (Worked: libbpf `relo_core`/`linker`/`btf_dump` guarded sites are slice-WITNESSED for the
memory-safety class but stay **class-C until whole-function in-situ**; the `btf_validate_type` member-walk
slice proves the *same* walk that store-bloats in-situ, so the store-bloat blocks the whole-function
rigor, not the safety — the closure is the envelope-carry-across-switch store-bloat.)

### The ladder retires the EBIOS risk classes in order (no-blend, operationalized)
**Tier 1 retires the memory-safety class** (OOB/overflow on parse bytes — e.g. wolfSSL OS1/OS2);
**Tiers 2–3 retire the logic / policy class** (path validation, signature acceptance, downgrade — wrong
accept/reject decisions in well-typed, in-bounds code, which RTE *cannot* reach). A campaign must
**never** report a Tier-1 result as covering a Tier-3 risk — that is the no-blend violation the
crosswalk and §8e guard.

### The dominant failure shifts as you climb — and the catcher must too
At Tier 1 the coherent-and-wrong is a **missing guard**; at Tiers 2–3 it becomes a **missing case /
incomplete meta-property** ("we never modelled renegotiation"). So the refinement that adds use cases
and behaviours you did **not** first imagine is **not ad hoc** — it is the **operational cycle**
(gap-doc → re-plan), and it must be **driven by the disjoint completeness catchers** (Gate C′ / the
completeness critic / the EBIOS reviewer surfacing an omitted scenario), never by whoever happens to
notice. Higher tiers raise the human-terminus stakes: only a person reading the requirement/policy can
finally say "a behaviour is missing."

### The ghost-fiat trap — Tier-3's semantic vacuity (macsl is imperative, its antecedents must be DERIVED)
Tier 3 is **imperative, not optional, for the load-bearing risks.** Authorization/integrity properties
(EoP / Spoofing / Tampering) are *system-level universals* — "root is unrecoverable **by any means**",
"the process cannot escape the namespace", "a forged token is never accepted" — that Tiers 1–2 **cannot
express or reach** (contracts and formal tests are per-function). Only a macsl/HAPPY meta-property can
state them and let a prover discharge them, so a security-logic risk is **not** covered until its Tier-3
property was actually driven in-situ (the §8b tagline rule). "We proved RTE + functional contracts" is
**not** "we proved the authorization property."

**But a GREEN Tier-3 result has a failure mode the base gates (§6) must probe: the ghost-fiat
antecedent.** A HAPPY property is typically proved as `ghost ⟹ property`, the ghost established by a
model function (`//@ ghost sc_model_*();`) whose `ensures` asserts the needed fact. If that `ensures`
is **postulated, not derived from a real contract**, the proof is **semantically vacuous** — it proves
`ghost ⟹ property` soundly while *nothing proves `ghost`*. This is distinct from **structural** vacuity
(zero instrumented asserts): here the asserts DO expand and discharge, so **macsl's own non-vacuity gate
does not catch it**, and neither does Gate C's *code* mutation (the ghost is set by fiat regardless of
the body). It is a **Gate-B-adjacent smuggled behavioural assumption wearing a ghost's clothes.** The
per-unit Tier-3 gate therefore adds:

- **Ghost-antecedent audit (on any all-`Valid` Tier-3 result).** For every HAPPY property, trace its
  antecedent to either (a) a **derived** leaf `ensures` a real callee/`G_kernel` contract discharges,
  **non-vacuity-witnessed** (restore the weak/empty leaf frame → the dependent conclusions redden), or
  (b) a **NAMED, source-auditable axiom** (a `GA_*` gluing / `SB_*` behavioural assumption) in the TCB.
  A ghost model function with a postulated `ensures` and no such backing is a **semantic-vacuity FAIL** —
  classify it exactly like a smuggled Gate-B axiom (assumed, never proved), **never PROVEN**. And the
  property must be closed as a **universal over all its vectors** (each PROVED or explicitly
  CARVED/REFUTED — never silently green). *Worked reference: snapd RS1 "root unrecoverable" —
  `sc_model_drop_complete` fiat → derived leaf `ensures` → 8-vector closure (6 proved, 2 refuted); see
  `the-snap-story.md`, `recover-root.md`, `ghost-fiat-pattern.md`.*

## 5. Loop steps (per mission) — driven by the Workflow (`references/framac-workflow.md`)
0. **Architect/auditor** runs the **Phase-0 architectural audit** → the claim set (folded
   into `U`), the WP-amenability scope map, the value/risk ranking. Read-only.
1. **Coordinator** parses the mission + guidance + **audit** → `U`; opens the plan @
   `STATUS: DRAFT`.
2. **Scheduler** builds the include/call graph of `dir yyy`, topo-sorts **leaf-first**
   *refined by the audit ranking*, marks the independent (parallelizable) set, **and emits
   the `{file, flags}` queue** (`framac-queue.sh compile_commands.json
   framac/.verdicts.tsv`). Mirror the pristine sources to `framac-orig/` so the
   faithfulness gate has an original to diff.
3. **Gate A_top** → `APPROVED` (coordinator judges plan + schedule + guidance reading +
   flags parse).
4. **For each unit, in order** (parallel only across independent units, via the Workflow
   `pipeline`): instantiate a **`framac-sl`** sub-loop, threading the guidance into the
   spec author/annotator and the per-unit flags into the WP invocation. Propagate each
   proven callee `ensures` as the caller's stub `requires`/`ensures` (bottom-up).
   **MANDATORY — worktree isolation for parallel units (no shared checkout).** Each unit's
   `framac-sl`/convergence sub-agent *mutates the source tree* (it applies, edits, and reverts the
   unit's reversible ACSL patch to run WP). Parallel sub-agents on **one shared checkout therefore
   clobber each other** — concurrent apply/revert races silently drop another unit's contracts. So
   every parallel unit MUST run in its **own git worktree** (`isolation: 'worktree'` on the Agent /
   Workflow call), never the in-place tree. After a unit converges in its worktree, **harvest its
   reversible patch back to the overlay** (`<target>-acsl/patches/`) and discard the worktree; the
   canonical in-place tree stays pristine and is only touched serially when applying a harvested patch
   to re-measure. (Lesson — Zephyr cycle-03: parallel sub-agents shared one `zephyr/` checkout and
   reverted each other, regressing the `mailbox` patch from 154/204 to 130/185; the numbers were only
   recovered by re-measuring sequentially. Worktree isolation prevents the race; serial re-measure is
   the fallback, not the design.)
   **Then iterate the sub-loop (the KEY PRINCIPLE, §0): if WP leaves undischarged goals that are
   missing-spec artifacts (unconstrained-pointer `\valid`, blocking/unbounded-loop `terminates`,
   un-propagated callee precond, missing bound — *and* the cross-callee case: a system invariant that
   must be invented and threaded leaf-first through the callee chain / shared headers, §0
   global-invariant pattern), re-invoke `framac-sl` to author those contracts and cascade into the
   callees they surface — do not record the Timeout as the verdict until spec-authoring has
   converged.** Before banking ANY goal as Coq/residue, **run the refutation probe (§0 MANDATORY
   GATE): add the antecedent it points at and re-run — instant `Valid` ⇒ spec gap, keep going.** Only
   a goal that survives the probe (stays stuck with the antecedent in scope) is a genuine Coq case:
   **escalate to Coq AND discharge it — by default, not optionally** — via the `framac-coq8` toolchain
   (`-wp-prover …,coq -wp-interactive`). `COQ-NEEDED` is *work to do*, not a place to stop: actually
   author/run the Coq proof and accept a close ONLY under the soundness audit (cache-clean replay with
   `-wp-cache none`, `Print Assumptions` ⊆ the standard set, **zero admits** — §6 prover-escalation
   audit). A Coq close is a verdict delta. Interactive Coq is not guaranteed to auto-close every goal;
   what even a sound Coq replay cannot close is tagged **Coq-attempted** and only *then* becomes
   residue. (A campaign may opt out of this Coq stage — e.g. `/ebios --no-coq` — for a faster
   spec-only pass, leaving the goals `COQ-NEEDED`; that is an explicit choice, not the default.) What
   remains after spec-convergence *and* the Coq stage is the honest PARTIAL/`gap-N`, tagged with its
   probe evidence.
4b. **Second-model (byte-model) discharge — a convergence lever for cast/region residue, between
   spec-authoring and Coq.** When a probe-confirmed goal is a **cast/region** case (pointer-cast
   load/store, `*(void**)`/`*(char**)`, CONTAINER_OF) that times out under the default `Typed` model,
   try the opt-in **`-wp-model bytes` separate pass** (the `frama-c-launch` profile / `verify-bytes.sh`
   on the patched dev build) *before* concluding residue. **Banking discipline:** (i) tag each goal
   **bytes-banked vs Typed-banked** and **never double-count** — key the diff by `(function, property,
   line)` via `-wp-report-json` (see the `frama-c-internals` skill §6); (ii) bank only **sound** closes
   (`Valid`, **no `+cast`** — vacuity risk — **no admit**); a goal that closes only at a **larger
   `-wp-timeout` is still soundly Valid** (timeout is a budget cutoff, not unsoundness) — **but record the
   closing `-wp-timeout` in the bank entry and raise `verify-bytes.sh`'s default to it, or the default
   profile run won't reproduce the Valid** (a budget-dependent bank that isn't recorded is not
   reproducible); (iii) **honest
   scope** — the byte model banks the recast-pointer *derefs* and *some* byte-range `\valid`, but **not**
   the nonlinear core; never report "bytes solved the cast residue." **Byte-range-`\valid` convergence
   ladder** (for the byte model's own residue): **budget** (raise `-wp-timeout`) → **range→point /
   range-subsumption ACSL lemma** (`{L}`-labelled; a pure-logic instantiation tautology) → **Coq**. The
   residual core (pointer-difference reasoning under the byte model, `\forall`-instantiation, nonlinear
   `block_size*num_blocks`-style byte ranges) is Coq territory; what stays open is **Coq-attempted**
   residue. (W5 effect: a *banked* byte-model close earns a **likelihood ↓**; a byte-model pass that
   merely finds 0 counterexamples on the residue is corroboration → **residual-weight ↓** only — see
   `frama-c-launch/references/ebios-feedback.md`.)
5. **Base-SL monitor** runs the **four gates** on that sub-loop's output (faithfulness,
   Gate B, non-vacuity, gold-completeness) and audits any Coq escalation for soundness,
   then audits its *soft outputs* — newly written
   `config/skills/frama-c/references/learned-*.md` entries and inferred/strengthened
   contracts — against `U` and `L` (§6): **PASS / CARVE-OUT / REJECT**.
6. **Gate B_top** (cross-unit discharge) → **Gate C_top** (coverage / no-blend / four
   gates / guidance honored). The Workflow **committer** updates the verdict log and
   commits the batch.
7. Divergence (a unit won't reach `Valid`; a cross-unit stub isn't implied by the proven
   callee `ensures`; an inferred contract contradicts the guidance; a WP/model limitation
   blocks "thorough") → a `gap-N` doc → re-plan. If the surprise is a **tooling gap or
   bug**, route it (§7) — never absorb it with a local workaround.
8. **Capitalize (§7):** the top agents distill role heuristics under
   `config/skills/frama-c-monitoring/` (Gate-S gated); base agents continue to capitalize
   under `config/skills/frama-c/`.
9. Codebase `DONE` when every in-scope unit has a base verdict in leaf-first order,
   cross-unit contracts are consistent, the guidance is honored uniformly, every unit
   passed the four gates (or is an honest PARTIAL/FAILED with a `gap-N`), and every base
   skill/inferred contract has a monitor verdict.
10. **Emit the crosswalk (campaign close — Move 5).** Once the verdict log is final and the architect
    has filled `<prefix>-acsl/stride-ledger.tsv` (the §3 STRIDE coverage assessment), generate the
    threat↔verification join as a first-class deliverable: `./crosswalk-gen.sh <prefix>` writes
    `<prefix>-crosswalk.md` from the code-blind report (§1/§2/§5) + `verdicts.tsv` (§4) +
    `stride-ledger.tsv` (§3). The generator machine-checks every `PROVED` cell against the verdicts
    (a fabricated PROVED fails), bootstraps the `ledger-ratchet.sh` baseline on first run, and is gated
    by `make stride-ci` (G4 = drift, G1 = ratchet). Do NOT hand-write the crosswalk. See
    `references/crosswalk-generation.md`. The W5/feedback step below draws its deltas from this crosswalk.
11. **EBIOS W5 risk-feedback (campaign close — only if an EBIOS RM study + a filled
    `../frama-c-launch/templates/ebios-crosswalk.md` exist).** Turn the final verdict log into
    EBIOS workshop-5 treatment evidence per `../frama-c-launch/references/ebios-feedback.md`:
    PROVED → a SCIP security measure + a *proposed* likelihood reduction (memory-safety steps,
    amenable surface only); PARTIAL/BLOCKED → a citable residual risk routed to non-formal
    treatment. The coordinator *proposes* the W5 delta; the **EBIOS risk owner adjudicates** it
    (the human terminus — see §8e). Skip cleanly when there is no risk study.
    **Artifact convention — the W5 feedback is NUMBERED, one per cycle.** Write it as
    `<prefix>-W5-ebios-feedback-NN.md` (zero-padded; next index after the highest existing one — start
    at `-01`); **never overwrite a prior numbered W5 file** — the sequence *is* the
    continuous-improvement history the risk owner reviews (risk evolution over cycles). This is the
    one per-cycle artifact; the rest — `<prefix>-ebios-report.md` (W1–W4), `<prefix>-found-issues.md`,
    `<prefix>-ebios-gaps.md`, the overlay — are **consolidated** (single file, updated in place to hold
    current truth).

## 6. Monitoring `framac-sl` (the `sl-monitoring-sl` discipline)

The base loop produces a per-unit **artifact** (annotated C + ACSL) and **soft outputs**
(the `learned-*.md` skills + the contracts it *infers or strengthens*). Both can be
**coherent-and-wrong**: an all-`Valid` unit can still be vacuous; a skill right for one
unit can be guidance-wrong. The monitor squeezes each from a base it does not share —
`U` = the guidance + `framac-gold`; `L` = the WP oracle + cross-unit discharge.

### The four base gates (run per unit, on every all-`Valid` result)
1. **Gate F — faithfulness.** `framac-monitor-check.sh` strips all ACSL and requires the
   remaining C to be byte-identical to `framac-orig/`. Any edit to executable C →
   **FABRICATED** → revert + re-label FAILED. (Watch the line-oriented traps: a force-include
   or a reformat that the strip tool leaves behind reads as added code.)
2. **Gate B — no smuggled behavioural axiom.** An `axiom`/`Admitted`/unproved-`lemma`/
   over-promising stub that asserts a *behavioural fact* about the program is an escape
   hatch (assumed, never proved) → flag. **Carve-out:** a *definitional* `axiomatic` that
   only gives the base/step equations of a recursive `logic`/`predicate` (e.g. `gcd`,
   `count_occ`, `sorted`) is the standard idiom, **not** a hatch — flag only when an axiom
   mentions the C function under verification or `\result`. The residual risk of a
   definitional axiomatic is *inconsistency* (proves everything), which Gate C catches, not
   grep.
3. **Gate C — non-vacuity (mutation probe).** `framac-mutation-probe.sh` mutates the
   **code** (not the ACSL) and requires some goal to turn RED — proving the spec has teeth
   and any axiomatic is consistent. Two refinements are load-bearing: mutate **only outside
   ACSL spans** (a mutation that hits a loop invariant gives a *false* VACUOUS), and treat
   `VACUOUS`/`INCONCLUSIVE` as **NEEDS-MANUAL** (author one targeted body mutation), never a
   terminal FAILED. A trivially-true postcondition (`\result==0 || \result==1`) is the
   genuinely vacuous shape — no body mutation can break it.
4. **Gate C′ — completeness vs gold.** When `framac-gold/` exists, `framac-completeness.sh`
   / `framac-compare.sh` diff the proved theorem against the human reference. Mutation
   TEETH proves **non-vacuity, NOT completeness** — the *sorting trap*: `ensures
   Sorted(a,0,n)` passes Gate F+B+C yet a zero-fill body satisfies it (sortedness ≠
   permutation). A unit that machine-passes but omits the intended property is **PARTIAL**,
   never PROVED. This is the calibration that catches an over-broad TRIVIAL/PARTIAL triage
   (see `references/learned-monitor.md`).
   **Run Gate C′ from a disjoint *completeness oracle* (WS2), not the verifier.** The actor that
   judges "is the proved theorem the intended property?" holds the **requirement/`framac-gold`**
   + the **WP goal list**, and is **denied** the implementation, the annotator's rationale, and
   the proof scaffolding (a fresh, code-blind sub-agent). This is the evidence-disjoint catcher
   re-running WP cannot be: re-running the *same* WP on the merged tree catches faithfulness and
   concurrent-edit corruption, but it can never flag a contract that is *valid but answers the
   wrong question* — only a code-blind actor holding the intended property can. Its executable
   half is the **trivial-witness probe**: a constant/zero/identity artifact must NOT satisfy the
   written spec (the sorting-trap detector, generalized — extend `framac-completeness.sh`).

**Gate B/C extension for Tier-3 (system) properties — the ghost-antecedent audit.** On any all-`Valid`
result that includes a **macsl/HAPPY** property, additionally run the ghost-antecedent audit of §4b:
Gate C's *code* mutation and macsl's own non-vacuity gate both MISS a HAPPY property whose antecedent is
a **ghost model function with a postulated `ensures`** (semantic vacuity — green while nothing proves the
ghost). Require every ghost antecedent to be **derived** (non-vacuity-witnessed) or a **NAMED TCB axiom**
(`GA_*`/`SB_*`); an un-backed `sc_model_*` fiat is a semantic-vacuity FAIL, classified as a smuggled
Gate-B assumption, never PROVEN. (Worked: snapd RS1 — `the-snap-story.md`, `ghost-fiat-pattern.md`.)

### Classify every red goal — "prover limitation" is not a category (Curry–Howard)
Before the base loop escalates anything, the supervisor enforces the classification: by the
Curry–Howard isomorphism a proposition is provable iff it is true, so a goal that no prover can
close is **never** a prover limitation — it is **non-entailed**, i.e. a **specification defect**.
Every red goal is therefore exactly one of:
- **(a) entailed but SMT-incomplete** (needs induction / an un-triggered quantifier) → the
  legitimate Coq-escalation case (audited below);
- **(b) non-entailed** (a model of the hypotheses falsifies it — exhibit the counter-model) →
  the **specification is the issue**. The coordinator must strengthen/correct the spec (the
  unit's contract, or a dependency's ACSL — a header's ACSL is editable; only *executable C* is
  frozen), or, if policy forbids touching the dependency, record **PARTIAL — specification defect
  in `<dep>`: `<clause>`** with a `gap-N` and a strengthening proposal.

**Deciding (a) vs (b) is a GATE, not a judgement call — run the refutation probe (§0).** Both print
as `[Timeout]`; you may **not** assign (a) by eyeballing ("big aggregate / after an unspecified call
/ timed out at 120s" is NOT evidence of (a)). Identify the antecedent the goal points at — a callee
`ensures`, a caller `requires`, a `loop invariant`, a frame/`assigns` — add it, re-run:
**instant `Valid` ⇒ case (b)** (missing hypothesis — keep authoring; frequently this is the
*global-invariant-threading* pattern of §0, threaded leaf-first across the callee chain and shared
headers); **still stuck with the antecedent in scope, plus an exhibited counter-model-free argument
⇒ case (a)** (legitimate Coq escalation). An **(a)/`COQ-NEEDED` verdict asserted without the probe is
a Gate-S / Gate-C_top REJECT** — it is the precise failure mode that parks a spec gap (often a
system invariant not yet threaded) behind the prover.

There is **no third bucket.** A verdict of "PARTIAL — prover/Coq limitation" or "not addressable
by Coq" is a category error and a Gate-S **REJECT**: it hides a spec defect behind the prover.
(The one adjacent-but-distinct case: the goal IS entailed and Coq *could* close it, but the
`framac-coq8` toolchain isn't installed — that is a *tooling gap* → `getting-better/`, not a spec
defect and not a prover limitation.) This is the rule that makes the coordinator/supervisor decide
"the spec is the issue" instead of parking a non-entailed goal as an un-closable residual; see
`references/learned-coordinator.md` ("A goal no prover can close means the SPECIFICATION is the
issue").

**(b′) Non-entailed AS GENERATED but the property is TRUE — a VC-generation artifact (a Frama-C
bug/normalization issue), NOT a "tool quirk" to relabel.** The counter-model probe can come back
showing the goal is *literally* unprovable — e.g. WP prints `Prove: ta_tmp = false` with `ta_tmp` a
**free, unconstrained variable** — yet the underlying property genuinely holds. This is the
**most seductive relabel**: it looks like an inherent ceiling ("WP just can't frame this"), and
parking it as class-A is the same exempt-bucket failure as a bare `COQ-NEEDED`. **The rule: a
true-but-unprovable goal is a defect to DIAGNOSE TO A MINIMAL REPRODUCER, never a ceiling to
assert.** The diagnosis is a GATE with the same rigor as the refutation probe — **bisect the
artifact**: rewrite the program structure to an equivalent (e.g. a `switch` ⇄ the byte-identical
`if`-chain), flip the model (`-wp-model bytes` ⇄ typed), or toggle a sound normalization option, on a
**6-line twin**, until one variant proves with the *same contracts*. A variant that proves with
identical specs **localizes the artifact** and refutes the ceiling claim — and usually names the fix.
Only a reproducer earns the "tooling artifact" verdict; without it you have *laziness wearing a tool's
name* (the [[framac-negative-claims-must-be-grounded]] rule). Worked instance (libbpf
`btf_type_size`): the `assigns \nothing` check on a `return callee();` in a **`switch` default**
emitted exactly that degenerate `ta_tmp = false`; the equivalent `if`-chain proved with identical
`assigns \nothing` contracts in either model ⇒ a WP **switch-framing bug**, fixed by the sound CFG
normalization **`-simplify-cfg`** — which closed not just the frame goal but the whole unit (48/56
Coq-partial → **27/27 pure SMT**, the earlier `to_sint32`/Coq "wall" exposed as a raw-switch-CFG
artifact too). **Try `-simplify-cfg` early** when a `switch`/`break`/`goto`-heavy function leaves a
frame or postcondition goal that "no prover closes". Capitalize each such finding to `getting-better/`
(it is a sound-option/Frama-C-behaviour gap, not a spec defect). See
[[wp-switch-default-return-assigns-frame-bug]].

**(b″) STORE-BLOAT is class-C, never a ceiling — the specific trap, gate-enforced (`no-ceiling.md`).**
A goal that **proves 1/1 in isolation but times out inside a big function** is store-bloat, not a tool
limit: the VC carries too much accumulated context (string-literal `Init` hypotheses, memory-symbol
proliferation across a switch, an un-framed callee). It reads *exactly* like a ceiling and is the
single most-recurring premature class-A (5× in this project). **Class-C levers, in order:** the
**Coq escalation** (Coq's `clear` the irrelevant hyps + `assumption`/frame tactics are immune to the
SMT saturation that causes the blow-up — this is the mandatory lever the discipline names, and it was
skipped every time it recurred); a **checkpoint-slice** ([[wp-flag-stability-checkpoint-slice]]); or
reducing the analyzed context. **A class-A / "ceiling" label is UNWRITABLE by the producer's say-so:**
run `config/skills/sl-internal/scripts/no_ceiling_gate.py` — it REJECTS (→ class-C) any ceiling claim
that lacks a *named goal-dump* + a *non-proving minimal twin* + an *attempted-and-failed Coq residual*
+ a *not-store-bloat verdict*, and marks a bundle-complete-but-undisjointly-attested one `PENDING`
(an open class-C row). `framac-gen-report.sh --lint` rejects a `CEILING-*` report row without its
bundle. "I tried several levers, it's hard" is **not** the bundle; reading the actual goal is step one.

### The prover-escalation soundness audit (Frama-C-specific)
When the base loop escalates an SMT-unprovable goal to **Coq** (`framac-coq8`) — case (a) above —
the monitor treats *only a cache-clean, zero-admit replay* as ground truth:
- the WP replay must reproduce with `-wp-cache none`/`replay` (a `(Cached)` SMT timeout
  masking the Coq script is **not** a pass — see the `wp-interactive-coq-replay` note);
- `Print Assumptions wp_goal` on each script must show **only the intended definitional
  axioms** (and already-proved upstream lemmas) and **0 admits** — any `classic`/`admit`/
  smuggled behavioural axiom → **REJECT**;
- a lemma WP assumes downstream (e.g. `gcd_positive` used by `gcd_greatest`) is sound only
  if it was itself proved — verify the chain, don't trust the green.

### Classify and check the soft outputs (Gate S)
- **ignore-signal** ("treat signal X as noise" — e.g. *"ignore concurrency preconditions"*):
  the **high-risk** kind. **Trigger test:** does the guidance make X relevant? Under
  *"disregard concurrency"* the skill **PASSES**; under a mission that required it the same
  skill over-reaches → **CARVE-OUT** deferring to the guidance clause.
- **defer-to-oracle** ("on case S take the oracle-sanctioned action"): consistent by
  construction. **Validity test:** does the WP oracle / mutation probe actually distinguish
  S? PASS, or **prune** if spurious.
- **Verdicts:** PASS / CARVE-OUT / REJECT, each grounded in the guidance clause (or the
  `framac-gold` diff) and traceable to the unit/`gap-N` that surfaced it. The monitor
  **discriminates** — a monitor that flags everything or nothing is miscalibrated.

**Calibrate the loop's own coverage against ground truth.** Gate S audits the base loop's
*skills and inferred contracts* — but **not the coordinator's triage/coverage decisions**,
above all the fast-path that marks a unit `TRIVIAL`/PARTIAL and stops. Those need a separate
check: when a `framac-gold/` reference exists, **diff the loop's outputs against it**
(`framac-compare.sh`). A class of units the loop called done that the gold actually annotates
more deeply is a *systematic triage error*, not noise — feed it back as a carve-out to the
triage rule. (This is the C analogue of the Creusot 241-file calibration; here it surfaced
the PARTIAL-vs-PROVED gap that the strengthening waves then closed.)

## 7. Knowledge capitalization & routing — `config/skills/frama-c-monitoring/`
Append-only, **Gate-S-gated** (per `../framac-sl/SKILL.md` and `sl-monitoring-sl`).

**What the top agents learn** (under `references/`, drafted by the role, audited from a
disjoint base, committed only on PASS/CARVE-OUT, with provenance):
- `references/learned-coordinator.md` — mission-decomposition & guidance-interpretation
  heuristics; when to cut a unit from the plan; how to apply guidance uniformly.
- `references/learned-scheduler.md` — include/call-graph & leaf-first ordering heuristics;
  **per-unit preprocessing-flag** discovery (force-includes for stripped typedef chains,
  `-cpp-extra-args` wrapping, `-machdep`); when two units are truly independent.
- `references/learned-monitor.md` — base-loop audit heuristics: which base skills tend to
  over-reach, the four-gate tells (vacuous-via-unspecified-callee, trivially-true
  postcondition, sorting-trap), and the Coq-escalation soundness checks.

**Routed surprises** (a surprise is *routed, never absorbed*):
- `getting-better/` — one `*.md` per **feature suggestion** that would make units easier to
  verify (a missing WP/ACSL capability, a useful lemma/template, a tooling improvement).
  Confirmed by the monitor against `L` (the gap is real — `framac-sl` genuinely couldn't
  express/discharge it).
- `bugs-to-report/` — one `*.md` per **bug to report** (Frama-C / WP / Why3 / prover
  misbehaviour) with a minimal reproducer + the exact invocation, confirmed against `L`.

**Filename format (both dirs):** `YYYYMMDD-hhmm-simple-name.md` — e.g. today,
`20260618-1530-wp-coq-cache-masks-script.md`. Each file states: the trigger (unit/`gap-N`),
the observed behaviour, the desired behaviour, a minimal example, and the `U` clause it serves.

## 8. Done criteria
**DONE = the whole in-scope code and its non-vacuous contracts are PROVEN.** Every goal (each `-wp-rte`
PO and each functional/`\prop` goal, under non-vacuous contracts) resolves to EXACTLY ONE of **three**
terminal statuses — there is no fourth:
1. **PROVEN** — WP `Valid` / macsl witnessed (cache-clean; zero-admit if Coq was used).
2. **VIOLATION** — the goal is FALSE: a **bug in the code**, written to `found-issues` with its trigger.
3. **BUG IN FRAMA-C** — the goal is TRUE but the tool cannot prove it (a WP/macsl incompleteness,
   frame/store-bloat gap, frontend wall). By Curry–Howard a true entailed goal has a proof; if the machine
   cannot produce one, DIAGNOSE it to a minimal reproducer and FILE it under `bugs-to-report/`.
**A lingering `PARTIAL` is NOT a status — it is unfinished work.** A `PARTIAL`/`Timeout`/`COQ-NEEDED` must
be driven to one of the three: keep authoring the missing contract (usually → PROVEN — the KEY PRINCIPLE,
§0), or, once the refutation probe + Coq escalation are attempted-and-failed on a *true* goal, FILE the
Frama-C bug (→ status 3). "Reviewed by hand and believe it's fine" is a REJECT: prove it, or file the tool
bug. There is no "carried residue" that is not either a reported Violation or a filed Frama-C bug.
(Genuinely non-WP-expressible matter — crypto-primitive correctness, liveness — is OUT-OF-SCOPE by
declaration, not a contract with a status.)

Codebase-level: every in-scope unit has a base verdict in leaf-first order; **spec-authoring
has converged (the KEY PRINCIPLE, §0) — `framac-sl` was re-invoked on every unit whose Timeouts
were missing-spec artifacts, so no PARTIAL on the books is a not-yet-attempted contract**; cross-unit
`requires`/`ensures` consistent and the proven callee `ensures` implies each assumed stub;
every unit passed the four base gates (or is an honest PARTIAL/FAILED with a `gap-N`); any
Coq escalation is cache-clean and zero-admit; the guidance honored uniformly (Gate C_top);
every base skill/inferred contract has a monitor verdict; the verdict log committed; routed
suggestions/bugs filed; top-agent skills Gate-S-gated. **No sub-loop's self-report ends the
mission — only the top gates.**

**MACHINE-DONE vs DONE (the human terminus, WS3).** The gates above close the *hard* side
by construction — that is **MACHINE-DONE**. They do **not** close the *soft* side: by the
paper's nesting argument (§mechanics) a stack of monitors only relocates the un-squeezed
editorial judgment upward, so the campaign is **DONE** only after a person *outside* the loop
signs off the **soft-residual delta**. Emit it with `framac-soft-residual.sh` → `SOFT-RESIDUAL.md`
(the bounded thing the human adjudicates: intended-property clauses *not* mechanically discharged,
Gate-A amendments, Gate-S carve-outs — never a re-verify of the hard side, which WP settled).
The reviewer should be external and ideally a **different provider family** than the annotator;
record the provenance. A pure RTE-robustness campaign with **no** soft residual must say so
explicitly — it exercised the hard side only; the editorial half was not engaged.

## 8b. Reporting discipline (mandatory)
**Precondition — no report before spec-convergence AND the Coq stage (the KEY PRINCIPLE, §0).** A
report may be generated only once every unit whose Timeouts were missing-spec artifacts has had
`framac-sl` re-invoked to author the contracts, **and every probe-confirmed true-but-hard goal has
been escalated to Coq and discharged (or recorded Coq-attempted under the soundness audit)** — unless
the campaign explicitly opted out with `--no-coq`. A residual is reportable only if it *survived*
spec-authoring **and the Coq stage** (Coq-attempted, or an unmodelled construct / tooling defect)
**and carries its refutation-probe evidence (§0): the antecedent that was tried and failed to flip
it.** A `COQ-NEEDED` line with no probe — or, outside `--no-coq`, one that was never actually sent to
Coq — is not reportable; it is the loop's own unfinished work (typically an un-threaded system
invariant, §0 global-invariant pattern, or an un-attempted Coq discharge). Reporting a missing-`requires \valid` / missing-`terminates` /
un-propagated-callee / un-threaded-invariant Timeout as residual risk is a reporting-discipline
violation.

Every campaign report is generated/checked by **`framac-gen-report.sh`** (repo root), which fixes
how results are stated so a reader can't be misled and a skeptic can't credit the verifier for the
squeeze's work:
- **One count convention, stated once:** `N/M = proved/total` WP goals (RTE included); coverage is a
  fraction of the **amenable attack surface**, never the whole tree.
- **A summary table** `(unit, verdict, proved/total, residual-classes, guarantee-kind)` that stands
  on its own; every residual classified into the fixed taxonomy (alloc/`\fresh`, `+cast`-frame,
  crypto-oos, termination, libc-init, cast-residual, spec-incomplete, faithfulness).
- **Guarantee kind** tagged per verdict — `by-construction (hard)` vs `disjoint-authority (soft,
  human-pending)` vs `self-corrected (NOT a disjointness result)` vs `authored-authority` — so
  self-correction is never miscounted as a disjoint catch.
- **The attribution line** (required, top of report): *Frama-C/WP delivers the robustness/defect
  result; the squeeze adds trustworthiness-by-construction (faithfulness gate) + disjoint
  adjudication of the soft residual.*
- **Headline discipline:** a coverage/robustness headline may never appear without its denominator +
  residual taxonomy in the same sentence. `framac-gen-report.sh --lint REPORT.md` enforces this
  (rejects "end-to-end robust" / "fully verified" without the caveat, and a missing attribution
  line); run it on any hand-written report before shipping.
- Body order is **scope → verdicts → soundness**; tooling lore goes to `references/wp-gotchas.md`,
  not interleaved with results.
- **Status legend at the top of `<prefix>-found-issues.md` (MANDATORY, emit it every time).** The file
  name says "found issues" but it records *both* the bugs **and** the positive-assurance results
  (proven-safe units), so a reader/AO must not mistake a `WITNESSED` heading for a bug. Prepend a short
  legend block before the first section that fixes the per-section status vocabulary — only **FINDING /
  `FI-*`** sections are defects; **latent** is a real-but-unreachable weakness; **WITNESSED** is a
  *discharged proof → proven safe, NOT a bug*; **REVIEWED-CAREFUL** is safe-by-inspection;
  **DISCHARGED-by-delegation** is safe-because-it-calls-a-WITNESSED-primitive. **Enforced:**
  `framac-gen-report.sh --lint <file>` fails (exit 1) on any file whose name contains `found-issues`
  that lacks this legend near the top (and, for such files, it correctly does **not** require the
  report-only attribution/count lines). The same vocabulary keys the `…-kit/reviewed-alarms.tsv`
  `disposition` column, so the legend and the ledger agree by construction.
- **Methodology tagline — target-conditional, never "PURE WP, NO EVA".** Write the toolset
  *positively*, naming only the tools that **actually ran on this target**: **"PURE WP and MACSL"**
  **only** when a macsl/HAPPY Plane-H system property was driven **in-situ** on the target (i.e. Plane H
  was a live plane, not N/A); otherwise **"PURE WP"** alone (the WP Plane-W RTE result — e.g. when Plane H
  is N/A by construction, as with a target that has no in-process authorization gate). Do **not** use
  "PURE WP, NO EVA" as the headline either way: the positive form already implies no EVA, and the no-EVA
  discipline stays enforced by the gates regardless (it is not the place of the headline). A standalone
  "no smuggled axioms" soundness note is fine. *(Rule of thumb: the tagline must not advertise macsl on a
  target where macsl never fired — that would misrepresent what was done.)*
- **No vendor name in a kit.** Describe a verification kit purely by its structure (a "verification kit"),
  **never** "TrustInSoft", "TIS", "tis-interpreter", or "PolarSSL-kit". (See `time-loop` §6.)

## 8c. Canary phase (mandatory wiring check, WS4)
Run **`framac-canary.sh`** once per campaign (self-contained — no corpus needed) and **open the
report with its table**. It seeds two coherent-and-wrong artifacts and asserts the gates *fire*
(catchability as a consistency check, paper §synthesis — not an efficacy rate):
- **faithfulness (hard side):** a fabricated proof — executable C edited so WP discharges a false
  `ensures`. WP is green; the **faithfulness gate** (strip-ACSL == pristine) must revert it. This
  is the repeatable, self-contained form of the natural `ssl_ticket_parse` catch.
- **soft side (the more dangerous half):** a *valid-but-wrong-question* spec (`ensures ordered`
  only, no permutation); a zero-fill **trivial witness** also proves green. WP is green on **both**
  bodies and cannot tell — the catch belongs to **Gate C′ / the disjoint completeness oracle**.
A campaign whose soft canary is "caught" only by re-running WP (not by the trivial-witness probe /
a disjoint actor) is flagged as **not exercising disjointness**. `framac-canary.sh` exits non-zero
if either gate fails to fire — treat that as a broken loop, not a unit failure.

## 8d. Lower-bound integrity + cost (WS5 + WS8)
The gate rests on an executable ground truth — but that ground truth (WP + authored
stubs/axioms) can itself be coherent-and-wrong (paper §10). Three checks keep it honest:
- **Consistency probe (mandatory for any `axiomatic`)** — `framac-consistency-probe.sh`: an
  inconsistent axiom set proves everything, so every green is vacuous. The probe lemma **must
  reference the axiom symbols** at a concrete point (e.g. `lemma p: gcd(a,0)==a+1;`); a bare
  `lemma \false;` is **insufficient** — SMT won't instantiate quantified axioms without a trigger
  (verified). The script enforces that an axiomatic carries such a probe and that it is *not*
  provable.
- **Stub over-promise (Gate B)** — an authored callee stub `ensures` (or `axiom`) is squeezed by a
  disjoint actor holding the callee's *documented surface*, not the caller's need: a stub stronger
  than the surface is unsound. Structural backstop (leaf-first): a stubbed callee with a definition
  in scope must **prove** its stub (the proven callee `ensures` implies the assumed stub).
- **No EVA — a TCB-minimization rule (stronger than no-blend).** EVA is **not used to discharge any
  goal** — not merely "it never substitutes for WP." Letting EVA close an alarm adds the **entire
  abstract-interpretation engine to the verdict's TCB**, a large analyzer whose fixpoint result carries
  **no per-goal, independently-checkable certificate**. A pure-WP verdict keeps the TCB to {WP
  VC-generation + the SMT solvers / Coq kernel}, where every goal is a checkable VC (SMT unsat /
  kernel-checked Coq, `Print Assumptions`-auditable). **In the age of AI the historical reason to lean
  on EVA — the labor of hand-authoring enough ACSL for WP to converge — is gone:** the spec-author /
  annotator author the contracts, so we converge by *adding spec*, not by *trusting more analyzer*.
  For a Typed-model cast / RTE residue, reach for **`-wp-model bytes`** / a representation predicate /
  the symbolic-base allocator idiom — **never an EVA split**. `framac-gen-report.sh --lint` rejects a
  report that cites EVA as a discharge oracle; each obligation records *which* WP/SMT/Coq oracle closed it.
- **Cost telemetry** — `framac-cost.sh` records per-unit role-invocations / tokens / wall-clock and
  reports the structural multiple + the H4 amortization (one-time proof cost vs near-zero replay
  via `verify.sh`-style WP re-run — amortizes on long regression horizons, a dead loss on one-shot
  tasks).

## 8e. EBIOS W5 risk-feedback (when a risk study exists)
Closes the downstream half of the EBIOS bridge: the campaign's verdicts become risk-treatment
evidence for EBIOS workshop 5 (the upstream half — the risk-level *ranking* — is set during
`frama-c-launch` onboarding via the crosswalk). Run at campaign close, only if an EBIOS study +
a filled `../frama-c-launch/templates/ebios-crosswalk.md` exist; otherwise skip.
- **What it produces:** crosswalk §3 — per scenario, `PROVED` → a **SCIP security measure** +
  a *proposed* likelihood reduction; `PARTIAL`/`BLOCKED` → a **residual risk** citable to its
  scenario ID and routed to non-formal treatment (pentest/fuzzing/baseline). The full mapping is
  `../frama-c-launch/references/ebios-feedback.md`.
- **No-blend (mandatory):** the WP verdict is **hard**; EBIOS severity/likelihood are **soft**. A
  verdict *informs* the likelihood, never *sets* it; severity is never changed by a verdict. The
  step writes a **proposed** delta + evidence — it does not rewrite the risk level.
- **Honest reduction:** a `PROVED` retires the memory-safety class of attack steps on the amenable
  surface of **one** asset — not logic/crypto/state-machine/BLOCKED parts. Name what is left.
- **Human terminus (MACHINE-DONE → DONE):** the coordinator *proposes*; the **EBIOS risk owner**
  (who accepts residual risk) *adjudicates and signs*. Emit the proposed delta inside the
  soft-residual packet (`framac-soft-residual.sh`); the sign-off is the campaign's DONE. Coverage
  check: every high-severity W1 feared event maps to ≥1 verified-or-residual scenario, else iterate.
- **Numbered, one per cycle (NOT consolidated):** persist each cycle's W5 proposal as
  `<prefix>-W5-ebios-feedback-NN.md` (zero-padded; next index after the highest existing — start
  `-01`). **Never overwrite a prior numbered W5 file** — the sequence is the continuous-improvement
  history (risk evolution across cycles; the W5-doctrine "residual mapping per SCIP milestone"). By
  contrast the report / found-issues / gaps / overlay are **consolidated** (single file, current
  truth). The forward-half proposal carries evidence for the risk owner; its return-safe, code-free
  projection (for a future code-blind `ebios-sl`) follows `ebios-feedback.md` § "The return half".

## 9. Compliance & execution order
- **C1 Disjointness:** ✓ scheduler / base instances / monitor / coordinator hold four
  distinct `(U,L)` bases; the monitor's base (guidance + gold + WP oracle) is disjoint from
  the base loop it audits.
- **C2 Catchability:** ✓ vacuous greens → the four gates; wrong-order verification →
  scheduler + cross-unit stub-implication; unsound Coq → the escalation audit.
- **C3 Physical barriers:** ✓ monitor never reads base rationale; faithfulness is a byte
  diff; base barriers inherited intact.
- **C4 Gate-defined done:** ✓ codebase done = all units base-verdicted + four gates +
  cross-unit gates + guidance honored + monitor verdicts; no self-report.
- **Execution order:** **leaf-first** (topo-sorted include/call graph), propagating proven
  `ensures` upward as stub `requires`/`ensures`; parallelize only across units sharing no
  dependency (via the Workflow `pipeline`) **and only in isolated worktrees** (§5 step 4 — a
  source-mutating sub-agent on a shared checkout corrupts its peers); sequence the rest by mechanism
  reuse. Commits
  are per-batch and ordered.

## Reference files
- `references/learned-coordinator.md`, `references/learned-scheduler.md`,
  `references/learned-monitor.md` — Gate-S-gated learned knowledge for the top agents.
- `references/stabilizers.md` — the anti-collapse rules (collapse-mode → symptom → blocking rule),
  the Frama-C specialization of the SL paper's stabilizer catalogue.
- `references/wp-gotchas.md` — consolidated Frama-C/WP tooling lore (the appendix; kept separate
  from per-campaign findings and from methodology).
- `references/stride-gates.md` — the extended-STRIDE gate specs (N-1 lock-order [WS1], N-4 boundary-
  contract propagation [WS8a], N-5 prover-ladder audit for new TCB classes [WS4/5/6], N-6 ATT&CK
  coverage view [WS9], N-7 Gate-S over new learned skills, N-8 sl-auditor re-audit triggers, N-9
  faithfulness preserved): **how each composes with — reuses, never reinvents — the four base gates
  (§6).** The N-1 WS1 stage-1 rule it documents is *enforced* by `ledger-ratchet.sh`.
- `ledger-ratchet.sh` (repo root) — the **cross-run ratchet CI gate** over the STRIDE coverage ledger
  (crosswalk-template §3.2): parses the six S,T,R,I,D,E columns from a crosswalk, freezes a
  `<crosswalk>.ledger-baseline.tsv` on first run (bootstrap PASS), and on later runs **FAILs only on
  regression** (a PROVED/TRUSTED cell now UNMODELED, or a high-value asset row now missing). Incomplete
  cells only WARN (Issue 2 — regression-only so the gate is not DOA); no ledger ⇒ SKIP. Enforces the
  WS1 stage-1 rule (`# ws1-stage: N`, default 1): a race/concurrency-family cell `PROVED` at stage 1
  FAILs. The single-file structural ledger check stays in `rmf-lint.sh`/`ebios-lint.sh` C9; this is the
  cross-run ratchet they defer to.
- **Verification depth ladder (§4b)** — RTE floor → formal tests → macsl/HAPPY policies: the per-unit
  depth policy set at Gate A_top by risk. Formal-test pattern: `../frama-c/SKILL.md` "A formal test".
  **Tier-3 tooling: `macsl`** — the canonical system-property framework (HAPPY policies). The recipe —
  policy syntax (`happy \prop, \targets, \context, P;`), the `\context` families
  (`\writing`/`\reading`/`\precond`/`\postcond`/`\total`/`\noninterference`) covering all six STRIDE
  letters, exemptions (`\fguard`/`\diff`), the **in-place** command line
  (`-no-autoload-plugins -load-module <macsl.cmxs> -macsl -wp`, **no `-then-last`**), and the
  **mandatory negative control** — is in `references/macsl-recipe.md`. macsl lives in the repo at
  `macsl/` (STRIDE coverage map: `macsl/tests/README.md`; policy language: `macsl.md`). **RUNS on this
  switch.** What still gates a real Tier-3 *result* is the **target code**: a logic-class risk in
  BLOCKED validation code (out of WP reach) must be lifted into scope first. Never trust a
  `[macsl] Will process N` + `Proved N/N` line without the negative control going red.
- `references/framac-workflow.md` — the runnable Workflow script: the JS coordinator + the exact
  framac-sl / monitor / committer / capitalize agent prompts + schemas + how to launch/watch/resume.
- `references/loops-design.md` — the two-loop design rationale (Creusot→Frama-C concept map, the
  depth-vs-breadth complementarity, the lace bug→RTE-goal mechanism, Frama-C-specific considerations).
- `framac-gen-report.sh` (repo root) — discipline-compliant report generator + report linter (§8b).
- `templates/squeeze-table.md` — the per-campaign `(U,L)` table template (WS2); fill at
  Gate A_top, audit with `framac-squeeze-audit.sh` (repo root) for C1/C3 disjointness.
- `framac-soft-residual.sh` (repo root) — emits `SOFT-RESIDUAL.md`, the human-terminus packet (WS3);
  a campaign is MACHINE-DONE until it is signed off, then DONE.
- `canaries/` + `framac-canary.sh` (repo root) — the seeded faithfulness + soft-side canaries (WS4);
  run once per campaign, both gates must fire, the table opens the report.
- `framac-consistency-probe.sh` (repo root) — the lower-bound-integrity gate for axiomatics (WS5);
  `framac-cost.sh` (repo root) — per-unit cost telemetry + H4 amortization (WS8).
- `getting-better/` — feature suggestions (`YYYYMMDD-hhmm-name.md`).
- `bugs-to-report/` — bug reports (`YYYYMMDD-hhmm-name.md`).
- Base loop: `../framac-sl/SKILL.md`; Workflow driver: `references/framac-workflow.md`;
  base learning + ACSL reference: `config/skills/frama-c/`.
- Monitor scripts: `framac-monitor-check.sh` (faithfulness), `framac-mutation-probe.sh`
  (non-vacuity), `framac-completeness.sh` / `framac-compare.sh` (gold), `framac-queue.sh`
  (queue), `framac-gold.sh` (gold mirror), `framac-corpus-db.sh`, `framac-gen-verdicts.sh`.
- Coq escalation: install + workflow + worked GCD example + proof patterns in
  `config/skills/frama-c/references/coq-escalation.md` (the `framac-coq8` opam switch).
- Upstream onboarding loop: `../frama-c-launch/SKILL.md` — derives the build flags, scope map,
  `<target>-acsl/` scaffold + faithfulness baseline, and a smoke proof; hands over the onboarding
  package this loop's Phase 0 / Gate A_top consumes.
- EBIOS bridge (when a risk study exists): `../frama-c-launch/templates/ebios-crosswalk.md`
  (upstream ranking) and `../frama-c-launch/references/ebios-feedback.md` (the §8e W5 risk-feedback
  this loop runs at close); the `ebios-risk-manager` skill is the risk study itself.
- Methodology: `sl-builder` (design), `sl-monitoring-sl` (monitor), `sl-internal`
  (theory), `sl-auditor` (audit an instance).

## ASSUMPTIONS & open questions
- `ASSUMPTION:` "in scope" = every `.c` translation unit under `dir yyy` that is part of
  library `xxx` (excluding generated/vendored code); RTE-safety always in scope, functional
  depth set by the guidance. Partial correctness unless the guidance asks for termination
  (then a `loop variant` / decreasing measure is required).
- **Guidance source.** **OPEN:** is the per-mission guidance free text the coordinator
  interprets at Gate A_top, or a structured policy file? It is the loop's `U` — it must be
  citable when the monitor carves a base skill.
- **Gold availability.** **OPEN:** Gate C′ (completeness) needs a `framac-gold/` reference;
  without one, completeness is a self-consistency check against the audit's claims only, and
  the loop should *say so* in each verdict rather than imply external conformance.
- **Per-unit flags.** **OPEN:** the scheduler needs `compile_commands.json` (via Bear/CMake);
  when absent, force-includes and `-cpp-extra-args` are hand-built and are a known source of
  parse-time surprises — treat a parse failure as a scheduler gap, not a unit FAILED.
- **Coq-escalation budget.** **OPEN:** how many units justify the (expensive) SMT→Coq
  escalation, and is the `framac-coq8` switch available in the run environment? Escalate only
  the residuals that genuinely need induction; record the rest as PARTIAL.
