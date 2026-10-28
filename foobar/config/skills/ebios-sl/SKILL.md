---
name: ebios-sl
description: >-
  A squeeze loop that AUTHORS an EBIOS Risk Manager (ANSSI) report as a
  trustworthy, code-disjoint deliverable — the upstream risk study that
  frama-c-launch consumes as its exogenous upper bound. Its upper bound U is
  EBIOS RM doctrine itself (the published ANSSI standard: the five workshops, the
  severity/likelihood/acceptability scales, the chaining rules, the vocabulary)
  plus the mission + threat intelligence; its lower bound L is a mechanical
  structure+coverage+endogeneity linter (ebios-lint.sh) over the report PLUS a
  human terminus (a disjoint completeness/realism reviewer and the risk owner who
  accepts residual risk). It is a soft-side, human-terminus SL: the dominant
  coherent-and-wrong it guards is a fluent, well-chained but threat-wrong report —
  a coverage gap masked by fluency, or scenarios silently shaped by reading the
  implementation (endogeneity). The single load-bearing invariant is that the
  scenario author is physically BARRIERED FROM THE CODE (W1-W3 code-blind), which
  is what makes the output a valid exogenous U for frama-c-launch. Use to produce
  an EBIOS RM report for a system under verification, to run a risk study whose
  ranking will drive frama-c-launch/frama-c-monitoring, or to author/audit EBIOS
  workshops 1-4 independently of the implementation. Built with sl-builder,
  monitored with sl-monitoring-sl; the method content is the ebios-risk-manager skill.
---

# ebios-sl — author an EBIOS RM report as a code-disjoint squeeze loop

`ebios-sl` produces the **EBIOS Risk Manager** report that `frama-c-launch` consumes as its
**exogenous upper bound** (the risk-level ranking). It is a **peer that runs first and
code-disjoint** — *not* a child of `frama-c-launch`. Authoring the risk study and consuming it must
live in **different, barriered** loops, or the bound collapses back to endogenous (self-certifying).
The EBIOS method content is the **`ebios-risk-manager`** skill; this skill is the *squeeze* that
makes the report trustworthy-by-construction. Built with `sl-builder`, monitored with
`sl-monitoring-sl`.

## When to run this loop — high-stakes / repeated risk studies, NOT every assessment
The squeeze is assurance machinery for the *risk study*, not a substitute for the method. Its cost
(author ⊥ reviewer ⊥ risk-owner + the linter) is justified when a **plausible-but-wrong study is
expensive** — and it is when the study **drives formal verification across many codebases**: a
coverage gap or an endogenous ranking silently mis-aims the whole downstream campaign. For a one-off,
low-stakes assessment, run the `ebios-risk-manager` skill directly. Reach for `ebios-sl` deliberately.

## 0. Deliverable & correctness
- **Deliverable:** an EBIOS RM report for a target system, **authored independently of the
  implementation**. For the verification-feeding use it produces **W1–W4** (scope & baseline; risk
  origins; strategic scenarios + attack paths; operational scenarios + likelihood). **W5 is not
  authored here** — it is fed downstream by `frama-c-monitoring`'s verdicts (its §8e feedback) and
  adjudicated by the risk owner.
- **"Correct" means (checkable):** (a) **structurally** EBIOS-conformant — workshops present for the
  goal, chaining well-formed, scales applied, coverage closed (mechanical, `ebios-lint.sh`); **and**
  (b) the scenarios/severities are a faithful reading of the **mission + threat model** that a
  *disjoint reviewer* does not refute and the *risk owner* signs (soft, human terminus).
- **Terrain archetype: A + B.** **A** (transcription of an external standard) for the *method/
  structure* — EBIOS doctrine is the published authority. **B** (authored authority) for the
  *content* — and **author independence *from the code* is the soundness argument**.
- **Dominant coherent-and-wrong:** a **fluent, EBIOS-conformant, well-chained but threat-wrong**
  report — (i) a **coverage gap masked by fluency**, and (ii) **endogeneity** (scenarios shaped by
  reading the implementation → self-consistent with the *code*, not the *threat*). (ii) is the
  failure that would void EBIOS as an exogenous bound for `frama-c-launch`.

## 1. Bounds
- **Upper bound `U`:** EBIOS RM **doctrine** (workshops, 4/4/3 scales, chaining + coverage rules,
  vocabulary — the `ebios-risk-manager` skill) **plus** the **mission + threat intelligence +
  stakeholder/ecosystem context**. Strongest claim a deliverable may make: *"a reading EBIOS doctrine
  + the mission/threat model do not refute."*
- **Lower bound `L`:** two-layer, honestly partial.
  - *Mechanical:* **`ebios-lint.sh`** — chaining well-formed (every strategic scenario → an RO/TO;
    every operational scenario → an attack path); severity on every feared event, likelihood on every
    operational scenario; **every high-severity feared event → ≥1 risk scenario**; scale/ID/volume
    sanity; and the **endogeneity tripwire** (no code artifacts in W1–W3).
  - *Human terminus:* content realism/completeness has **no machine oracle** — it terminates in the
    **disjoint reviewer** + the **risk owner**. Declared `DEPENDENCY: human reviewer`; never faked.

## 2. Actors and their disjoint `(U,L)` pairs

| Actor | Builds | U (above) | L (below) | Forbidden move | Must NOT see |
|---|---|---|---|---|---|
| **EBIOS coordinator** | framing (object/goal → workshop subset via the adaptation table), sequencing, Gate-A, gap adjudication, the handoff to `frama-c-launch` | EBIOS doctrine + the mission/scope | the linter output + reviewer/risk-owner verdicts | read the code; author what it grades; rubber-stamp; declare done on an author's say-so | the implementation source |
| **Scenario author** (risk analyst) | W1–W4 from the mission + threat intel + ecosystem | the mission + threat model + EBIOS doctrine | EBIOS structural conformance (each clause has a workshop home) | **read the implementation source** (the load-bearing exogeneity barrier); inflate past agile volume | the **codebase**; the verification scope map; the reviewer's critique |
| **Completeness/realism reviewer** (disjoint catcher) | an independent completeness+realism critique | EBIOS doctrine + mission + (if available) an external attack catalog (e.g. MITRE ATT&CK) as gold | the coverage linter + its **own** independent enumeration | read the author's rationale; read the code; rewrite the report (verdicts/carve-outs only) | the author's notes; the implementation |
| **Risk owner** (human terminus) | acceptance/refusal of residual risk | the org's risk appetite + mission | the report + the reviewer's verdicts | author the scenarios it accepts | — |
| **Probe** (opt.) | minimal method/tooling experiments | one design claim per probe | the linter's actual behaviour | implement a fix | — |

**Disjointness (C1):** author holds the mission/threat model (never the code, never the reviewer's
critique); reviewer holds doctrine+mission+an independent enumeration (never the author's rationale,
never the code); coordinator holds doctrine+mission+gate output (never authoring what it grades);
risk owner holds risk appetite (never authoring). **All content actors are barriered from the code —
that shared barrier *is* the exogeneity invariant.** Intersection = a report doctrine-conformant
**and** complete/realistic per an independent reviewer **and** accepted by the risk owner.

**Catchability (C2):** missed scenario / under-rated severity → reviewer (independent enumeration +
coverage linter); content shaped by code knowledge (endogeneity) → the physical **code barrier** +
the Gate-B endogeneity tripwire + the reviewer's **anchoring tell** (a scenario mirroring an
implementation quirk); reviewer rubber-stamps → coordinator Gate A + the risk-owner terminus;
mis-framed scope → Gate A vs the adaptation table; malformed chain / coverage gap → the linter.

## 3. Gates
- **Gate A — editorial.** Coordinator judges framing + report against doctrine + mission: right
  workshops for the goal (adaptation table); object/scope correct; scales adapted but **4/4/3**
  structure kept; **agile volume** (≈5–10 business assets, 3–6 RO/TO, 1–3 attack paths each);
  accidental/environmental risk → the baseline, not scenarios. Amend/cut/sharpen, never rubber-stamp.
- **Gate B — machine.** `ebios-lint.sh` passes (all §1 mechanical invariants) **including the
  endogeneity tripwire** (no code artifacts in W1–W3). The EBIOS analogue of "all VCs discharged."
- **Gate C — coverage / no-blend / coherent-and-wrong.** The reviewer's **independent enumeration**
  covers every high-value asset + plausible RO (the completeness critic); the report is the
  **intended threat model, not a vacuous one** (a single-trivial-scenario report passes B but fails
  C realism); **no-blend** — the linter (form) never substitutes for the reviewer (realism), and
  neither substitutes for the risk owner (acceptance); **endogeneity flag** — content traceable to
  code-reading ⇒ discount and re-author code-blind.

## 4. Loop steps (per study)
1. **Coordinator** frames: object + goal → workshop subset (adaptation table) + barriers (author ⊥
   code) + the volume budget.
2. **Scenario author** drafts W1 `@ DRAFT` from the mission/threat model only → **Gate A**; then W2 →
   W3 (severity flows from W1) → W4 (likelihood), chained; iterate W3/W4 **≤ 2×**.
3. **Reviewer** independently authors the completeness/realism critique from doctrine+mission (not the
   author's notes, not the code).
4. **Gate B** (`ebios-lint.sh`) → **Gate C** (reviewer coverage/realism + endogeneity flag).
5. **MACHINE-DONE** (structure+coverage) → **risk owner adjudicates** content/acceptance (human
   terminus) → **DONE**.
6. Divergence (coverage gap, malformed chain, endogeneity detected, scenario mirrors code) → `gap-N`
   → re-plan (re-author code-blind).
7. **Capitalize (Gate S):** reusable risk-analysis heuristics, audited by a disjoint monitor.
8. **Handoff:** approved W1–W4 → `frama-c-launch` consumes them (the crosswalk ranking); later
   `frama-c-monitoring` verdicts → **W5** (its §8e feedback), risk owner adjudicates — closing the
   cycle between disjoint loops.

## 4b. Re-authoring an existing study (event-driven; the contaminated-context rule)
A re-author is worthwhile **only on a real trigger** — otherwise it reproduces the report (a flat
no-delta cycle; don't). The triggers:
- **Config/deployment-profile change** — e.g. a build flag flips ON, pulling a previously
  **BLOCKED/config-excluded** unit into the shipped scope → add a new **supporting asset** + its feared
  events/scenarios (W1→W4). (Worked example: `CONFIG_PIPES` on → the pipe IPC asset + OOB/accounting
  scenarios.) This is the cleanest, most self-contained trigger.
- **New threat intel / CVE** for the target line → new risk origins / scenarios.
- **Mission scope change** — new subsystems named in the mission → new assets + scenarios.

**The contaminated-context rule (the operational form of author ⊥ code).** Once an agent has read the
implementation *or any verification artifact* (found-issues, the overlay, goal dumps), its context is
**contaminated** — it can no longer author code-blind, because it now knows implementation quirks the
scenarios would anchor to (endogeneity). So the orchestrator (whose context is usually contaminated by
Phase-2 work) **MUST delegate the re-author to a FRESH agent** whose context never saw the code, and
**MUST NOT leak implementation detail into that agent's prompt** — give it only: mission/threat model,
PUBLIC API/docs, the existing (code-blind) report to extend, and the method/format/linter. **The
delegation boundary IS the physical barrier** (the same principle `frama-c-launch` uses for its provers).

**Endogeneity nuance — don't over-sanitize scope language.** A build-config flag NAME in W1
(`CONFIG_PIPES`) is legitimate *scope/baseline* language, **not** a code artifact; the `ebios-lint.sh`
endogeneity tripwire correctly passes it (C8 flags `.c`/`.h`/`.cpp`/`.cc`/`.rs`/`#include`/`#define`/`0x…`/`::`/`->`,
i.e. source artifacts, not config flags). What stays banned in W1–W3: translation-unit names, function
names, ACSL, goal counts.

## 5. Executable oracle setup
- **`ebios-lint.sh REPORT.md`** (repo root) — the mechanical `L`. Parses a report written to the
  **pinned format contract** (`references/report-format.md`) and checks the §1 invariants + the
  endogeneity tripwire; exit 0 = pass, 1 = violations, 2 = usage/format. **Content realism is *not* in
  scope — that is the human terminus.** The author writes to the same pinned contract, so the report
  and the linter cannot drift.
- **Pilot + canary:** run it on a **known-good** report (ANSSI's worked example, transcribed to the
  convention → must pass) and a **deliberately broken** copy (drop a coverage link / inject a code
  artifact in W1 → must fail) — the EBIOS analogue of the frama-c canary.
- **Human-terminus parts** (reviewer realism, risk-owner acceptance) have **no machine `L`** —
  declared `DEPENDENCY: human reviewer`, never faked (the `sl-monitoring-sl` honesty rule).

## 6. Done criteria
`ebios-lint.sh` green (Gate B) + reviewer completeness/realism PASS with no open carve-outs (Gate C)
+ endogeneity flag clear + workshops appropriate to goal + agile volume respected + capitalized
heuristics Gate-S'd, **and the risk owner signs** (human terminus). **MACHINE-DONE** = linter+coverage;
**DONE** = risk-owner sign-off. No self-report ends the study.

## 7. Stabilizers engaged
- **Endogenous `U` / unpinned reality** → *the* one: author physically barriered from the code;
  Gate-B endogeneity tripwire; the reviewer's anchoring tell.
- **Self-judging** → author ⊥ reviewer ⊥ risk-owner, physical barriers.
- **Coherent-and-wrong (fluent-but-threat-wrong)** → reviewer realism + completeness critic;
  strictness has a safe direction (over-cover OK, under-cover is the bug).
- **Rubber-stamp** → Gate A amend/cut; reviewer must discriminate.
- **Self-declared done** → gate-defined + human terminus.
- **Absorbed surprise** → gap doc.
- **Over-exhaustiveness** → agile volume; accidental/env risk → baseline; cap W3/W4 at 2 iterations.
- **No-blend** → structure (linter) vs realism (reviewer) vs acceptance (risk owner) never substitute.

## 8. Execution order & topology
- **Pilot** `ebios-lint.sh` on a known-good report first.
- Run `ebios-sl` as a **code-disjoint PEER that precedes `frama-c-launch`** — *not* a child of it.
  Orchestration: a thin top driver, **or** the `frama-c-launch` *coordinator* (itself code-barriered)
  spawns it with a **threat-model-only context** — never the architect, never the source.
- **`--linux` / `--full-tu` flags (spec: repo-root `linux-analysis.md`).** Accepted on the
  `/ebios` invocation for Linux kernel targets. They leave the code-blind workshops (W1–W3)
  **untouched** — the source barrier is preserved (at most `system-type=linux-kernel` informs
  the threat model). They are **forwarded to the `frama-c-launch` handoff** as onboarding
  profile `linux`, which registers the `linux/linux-acsl/` overlay via `onboard-linux.sh`
  (`--full-tu` = the gated kernel-TU parse layer; harness mode is the default).
- **Cadence:** author on EBIOS's strategic (~3 yr) / operational (~1 yr) cycles; **consume across
  many verification runs** — don't regenerate per onboarding.
- Within: W1→W2→W3→W4 chained; iterate W3/W4 ≤ 2×.
- **Downstream:** W5 fed by `frama-c-monitoring` verdicts (its §8e), risk owner adjudicates — the
  continuous-improvement cycle closing *through* formal verification, between disjoint loops.
- **Return half (re-running this loop after a verification cycle):** the feedback re-enters **code-
  blind** — re-author W1–W4 from the threat model only; the verification packet enters **W5** as a
  typed, scenario-keyed **control-effectiveness signal** (no TU names / ACSL / proof internals — the
  same shape as a pentest result), never as code-derived scenarios or re-rated severity. A confirmed
  bug re-enters via **W1 feared events** from its *finding statement*, not its reproducer. Consume the
  **latest numbered** W5 feedback (`<prefix>-W5-ebios-feedback-NN.md`, highest `NN`) — these are
  emitted **one per cycle and never overwritten**, so the series is the risk-evolution history; this
  loop's own `<prefix>-ebios-report.md` is **consolidated** (re-authored in place). Full rules:
  `../frama-c-launch/references/ebios-feedback.md` § "The return half". This is what keeps the *next*
  `U` exogenous; a packet carrying code/proof content is the cycle's endogeneity breach.

## 9. Compliance check
- **C1 Disjointness:** ✓ four `(U,L)` pairs; no actor relieves its own bound; **all content actors
  share the code barrier** (the exogeneity invariant). Sound only if the barriers are physical
  (author/reviewer contexts hold mission+threat model, never the source).
- **C2 Catchability:** ✓ coverage gap → reviewer+linter; endogeneity → barrier+tripwire+anchoring
  tell; rubber-stamp → Gate A+risk owner; malformed → linter.
- **C3 Physical barriers:** ✓ author/reviewer built from mission+threat model, never the code —
  **including on feedback re-runs**: the verification packet enters W5 as a code-free control signal,
  so the code barrier holds across cycles (return half, §8 / `ebios-feedback.md`).
- **C4 Gate-defined done:** ✓ linter + reviewer + endogeneity-clear + risk-owner sign-off; no
  self-report.

## Reference files
- **`ebios-risk-manager`** skill — the EBIOS RM method content (workshops, scales, chaining, coverage,
  adaptation table); this loop is the *squeeze* around it. Invocable via the Skill tool.
- `references/report-format.md` — the **pinned** report-format tag convention (the linter's contract
  + the author's spec; one source of truth).
- `ebios-lint.sh` (repo root) — the mechanical `L` (structure + coverage + endogeneity linter), parses
  the pinned format.
- Downstream consumer: `../frama-c-launch/SKILL.md` + `../frama-c-launch/templates/ebios-crosswalk.md`
  (the report becomes the ranking `U`) and `../frama-c-launch/references/ebios-feedback.md` (verdicts
  → W5, the cycle's downstream half).
- Methodology: `sl-builder` (design), `sl-monitoring-sl` (monitor + the endogenous-`U` discipline),
  `sl-internal` (theory).

## ASSUMPTIONS & open questions
- **Report format: PINNED** in `references/report-format.md` (the stable tag set + locality/chaining
  rules + scales — the linter's contract and the author's spec). No longer an open question.
- **OPEN — reviewer gold:** is there an external attack catalog (MITRE ATT&CK / sector threat reports)
  to make the completeness critic genuinely exogenous, or is the reviewer mission-only? (Extreme
  cases: a cross-provider reviewer for decorrelation.)
- **OPEN — W4 gradient:** does W4 (operational scenarios, which legitimately touch supporting-asset
  *interfaces*) get a separate impl-blind-but-architecture-aware author, or stay with the code-blind
  author? Default: one author; W4 may read the *interface*, never the implementation.
- **OPEN — reviewer is agent or human:** the risk owner is human (terminus); the reviewer may be a
  disjoint agent (ideally a different provider family).
