---
name: rmf-sl
description: >-
  A squeeze loop that AUTHORS a NIST Risk Management Framework (RMF) risk
  assessment as a trustworthy, code-disjoint deliverable — the upstream risk
  study that frama-c-launch consumes as its exogenous upper bound, the faithful
  sibling of ebios-sl. Its upper bound U is NIST RMF doctrine itself (the
  published standards: SP 800-30 assessment mechanics, SP 800-37 the 7-step
  lifecycle Prepare/Categorize/Select/Implement/Assess/Authorize/Monitor, SP
  800-53 the control catalog) plus STRIDE as the threat-identification engine,
  plus the mission + threat intelligence; its lower bound L is a mechanical
  structure+coverage+endogeneity linter (bin/rmf-lint.sh) over the report PLUS a
  human terminus (a disjoint completeness/realism reviewer and the Authorizing
  Official who accepts residual risk and grants the ATO). It is a soft-side,
  human-terminus SL: the dominant coherent-and-wrong it guards is a fluent,
  well-chained but threat-wrong report — a coverage gap masked by fluency, or
  scenarios silently shaped by reading the implementation (endogeneity). Unlike
  EBIOS, 800-30 weights accidental and environmental threat origins alongside
  adversarial ones, so the report must cover all three. The single load-bearing
  invariant is that the assessment author is physically BARRIERED FROM THE CODE
  (R1-R4 code-blind), which makes the output a valid exogenous U for
  frama-c-launch / frama-c-monitoring. Use to produce a NIST RMF risk assessment
  for a system under verification, to run a risk study whose ranking will drive
  frama-c-launch, or to author/audit RMF sections R1-R4 independently of the
  implementation. Built with sl-builder, monitored with sl-monitoring-sl,
  grounded in sl-internal, audited with sl-auditor; the method content is the
  NIST corpus (nist/800-30.txt, nist/800-37.txt, nist/800-53.txt).
---

# rmf-sl — author a NIST RMF risk assessment as a code-disjoint squeeze loop

`rmf-sl` produces the **NIST Risk Management Framework** risk assessment that `frama-c-launch`
consumes as its **exogenous upper bound** (the risk-level ranking). It is a **peer that runs first and
code-disjoint** — *not* a child of `frama-c-launch`. Authoring the risk study and consuming it must
live in **different, barriered** loops, or the bound collapses back to endogenous (self-certifying).
The RMF method content is the **NIST corpus** (`nist/800-30.txt` assessment mechanics, `nist/800-37.txt`
the 7-step lifecycle / ATO governance, `nist/800-53.txt` the control catalog) with **STRIDE** as the
threat engine (`nist/sp-800-stride-link.txt`); this skill is the *squeeze* that makes the report
trustworthy-by-construction. It is the faithful sibling of `ebios-sl` (EBIOS W1-W5 -> RMF R1-R5; see
`nist/README.txt` for the crosswalk). **Built with `sl-builder`, monitored with `sl-monitoring-sl`,
grounded in the (U,L) theory of `sl-internal`, audited with `sl-auditor`.**

## When to run this loop — high-stakes / repeated risk studies, NOT every assessment
The squeeze is assurance machinery for the *risk study*, not a substitute for the method. Its cost
(author ⊥ reviewer ⊥ AO + the linter) is justified when a **plausible-but-wrong study is expensive** —
and it is when the study **drives formal verification across many codebases**: a coverage gap or an
endogenous ranking silently mis-aims the whole downstream campaign. For a one-off, low-stakes
assessment, run the NIST process directly. Reach for `rmf-sl` deliberately.

## 0. Deliverable & correctness
- **Deliverable:** a NIST RMF risk assessment for a target system, **authored independently of the
  implementation**. For the verification-feeding use it produces **R1-R5** (the crosswalk table in §1):
  R1 Prepare & Categorize; R2 threat sources & events; R3 vulnerabilities & predisposing conditions;
  R4 likelihood x impact -> risk; R5 select & implement 800-53 controls. **The Authorize step (800-37
  step 6) is the human terminus** — the Authorizing Official (AO) accepts residual risk and grants the
  ATO; **R5/Authorize is left PENDING** here (the AO signs). The downstream **Monitor** step (800-37
  step 7) is fed by `frama-c-monitoring`'s verdicts and re-adjudicated by the AO (see §8 loop-back).
- **"Correct" means (checkable):** (a) **structurally** RMF-conformant — R1-R5 present for the goal,
  chaining well-formed, scales applied, coverage closed, all three threat origins present (mechanical,
  `bin/rmf-lint.sh`); **and** (b) the scenarios/impacts are a faithful reading of the **mission + threat
  model** that a *disjoint reviewer* does not refute and the *AO* signs (soft, human terminus).
- **Terrain archetype: A + B.** **A** (transcription of an external standard) for the *method/
  structure* — NIST 800-30/37/53 doctrine is the published authority. **B** (authored authority) for
  the *content* — and **author independence *from the code* is the soundness argument**.
- **Dominant coherent-and-wrong:** a **fluent, RMF-conformant, well-chained but threat-wrong** report —
  (i) a **coverage gap masked by fluency** (incl. the 800-30-specific gap: dropping the accidental /
  environmental origins and modelling adversarial-only), and (ii) **endogeneity** (scenarios shaped by
  reading the implementation -> self-consistent with the *code*, not the *threat*). (ii) is the failure
  that would void RMF as an exogenous bound for `frama-c-launch`.

## 1. Bounds
- **Upper bound `U`:** NIST RMF **doctrine** — 800-30 (threat sources -> threat events ->
  vulnerabilities/predisposing conditions -> likelihood -> impact -> risk), 800-37 (the 7-step
  lifecycle, FIPS-199 Low/Mod/High categorization, ATO governance), 800-53 (the control catalog) —
  **plus STRIDE** (the threat-discovery engine) **plus** the **mission + threat intelligence +
  ecosystem/supply-chain context**. 800-30 weights **adversarial, accidental, AND environmental**
  origins (the DNA difference from EBIOS). Strongest claim a deliverable may make: *"a reading of the
  NIST corpus + the mission/threat model do not refute."*
- **Lower bound `L`:** two-layer, honestly partial.
  - *Mechanical:* **`bin/rmf-lint.sh`** — chaining well-formed (every threat event -> a threat source;
    every risk scenario -> a threat event + a vulnerability + a 800-53 control; every Hi-impact element
    -> ≥1 risk scenario with a selected control); impact on every categorized element, likelihood on
    every risk scenario; all three origin classes (ADV/ACC/ENV) present; scale/ID/volume sanity; and
    the **endogeneity tripwire** (no code artifacts in R1-R4).
  - *Human terminus:* content realism/completeness has **no machine oracle** — it terminates in the
    **disjoint reviewer** + the **Authorizing Official**. Declared `DEPENDENCY: human reviewer`; never
    faked (the `sl-monitoring-sl` honesty rule).

## 2. Actors and their disjoint `(U,L)` pairs

| Actor | Builds | U (above) | L (below) | Forbidden move | Must NOT see |
|---|---|---|---|---|---|
| **RMF coordinator** | framing (object/goal -> RMF step subset), sequencing, Gate-A, gap adjudication, the handoff to `frama-c-launch` | NIST doctrine + the mission/scope | the linter output + reviewer/AO verdicts | read the code; author what it grades; rubber-stamp; declare done on an author's say-so | the implementation source |
| **Assessment author** (risk analyst) | R1-R5 from the mission + threat intel + the NIST corpus + STRIDE | the mission + threat model + NIST doctrine | RMF structural conformance (each clause has a section home) | **read the implementation source** (the load-bearing exogeneity barrier); model adversarial-only; inflate past agile volume | the **codebase**; the verification scope map; the reviewer's critique |
| **Completeness/realism reviewer** (disjoint catcher) | an independent completeness+realism critique | NIST doctrine + mission + STRIDE coverage + (gold) an external catalog (MITRE ATT&CK / 800-53 baselines) | the coverage linter + its **own** independent enumeration | read the author's rationale; read the code; rewrite the report (verdicts/carve-outs only) | the author's notes; the implementation |
| **Authorizing Official** (risk owner, human terminus) | acceptance/refusal of residual risk; grant/withhold the ATO (800-37 Authorize) | the org's risk appetite + mission | the report + the reviewer's verdicts | author the scenarios it accepts | — |
| **Probe** (opt.) | minimal method/tooling experiments | one design claim per probe | the linter's actual behaviour | implement a fix | — |

**Disjointness (C1):** author holds the mission/threat model (never the code, never the reviewer's
critique); reviewer holds doctrine+mission+an independent enumeration (never the author's rationale,
never the code); coordinator holds doctrine+mission+gate output (never authoring what it grades); AO
holds risk appetite (never authoring). **All content actors are barriered from the code — that shared
barrier *is* the exogeneity invariant.** Intersection = a report doctrine-conformant **and**
complete/realistic per an independent reviewer **and** authorized by the AO.

**Catchability (C2):** missed scenario / under-rated impact / dropped origin class -> reviewer
(independent enumeration + STRIDE/800-30 coverage + the C6 origin check); content shaped by code
knowledge (endogeneity) -> the physical **code barrier** + the Gate-B endogeneity tripwire + the
reviewer's **anchoring tell** (a scenario mirroring an implementation quirk); reviewer rubber-stamps ->
coordinator Gate A + the AO terminus; mis-framed scope -> Gate A; malformed chain / coverage gap ->
the linter.

## 3. Gates
- **Gate A — editorial.** Coordinator judges framing + report against doctrine + mission: right RMF
  steps for the goal; object/scope correct; scales applied but the **Lo/Mod/Hi + L1..L4 + ADV/ACC/ENV**
  structure kept; **agile volume** (≈5-10 information assets, 3-6 threat sources, 1-3 risk scenarios
  per high-impact element); **all three origin classes covered** (not adversarial-only). Amend/cut/
  sharpen, never rubber-stamp.
- **Gate B — machine.** `bin/rmf-lint.sh` passes (all §1 mechanical invariants) **including the
  endogeneity tripwire** (no code artifacts in R1-R4). The RMF analogue of "all VCs discharged."
- **Gate C — coverage / no-blend / coherent-and-wrong.** The reviewer's **independent enumeration**
  covers every high-impact element + plausible threat source across **all three origins** (the
  completeness critic); the report is the **intended threat model, not a vacuous one** (a
  single-trivial-scenario report passes B but fails C realism); **no-blend** — the linter (form) never
  substitutes for the reviewer (realism), and neither substitutes for the AO (acceptance);
  **endogeneity flag** — content traceable to code-reading => discount and re-author code-blind.

## 4. Loop steps (per study)
1. **Coordinator** frames: object + goal -> RMF step subset + barriers (author ⊥ code) + the volume
   budget + the requirement that R2 cover ADV/ACC/ENV.
2. **Assessment author** drafts R1 `@ DRAFT` from the mission/threat model only -> **Gate A**; then R2
   (threat sources via STRIDE, all three origins) -> R3 (vulnerabilities) -> R4 (likelihood x impact ->
   risk, chained) -> R5 (select 800-53 controls via the STRIDE->family map, Authorize PENDING);
   iterate R3/R4 **≤ 2x**.
3. **Reviewer** independently authors the completeness/realism critique from doctrine+STRIDE+mission
   (not the author's notes, not the code).
4. **Gate B** (`bin/rmf-lint.sh`) -> **Gate C** (reviewer coverage/realism + origin-coverage + endogeneity
   flag).
5. **MACHINE-DONE** (structure+coverage) -> **Authorizing Official adjudicates** content/residual risk
   (human terminus, the 800-37 Authorize step) -> **DONE** (R5/Authorize PENDING until the AO signs).
6. Divergence (coverage gap, dropped origin, malformed chain, endogeneity detected, scenario mirrors
   code) -> `gap-N` -> re-plan (re-author code-blind).
7. **Capitalize (Gate S):** reusable risk-analysis heuristics, audited by a disjoint monitor
   (`sl-monitoring-sl`) and the Gate-S audit (`sl-auditor`).
8. **Handoff:** approved R1-R5 -> `frama-c-launch` consumes them (the `rmf-crosswalk.md` ranking);
   later `frama-c-monitoring` verdicts -> the **Monitor** step (its §8e-style feedback), the AO
   - **`--linux` / `--full-tu` (spec: repo-root `linux-analysis.md`).** Accepted on the `/rmf`
     invocation when the target is Linux kernel code. They do **not** affect the code-blind risk
     study (R1–R4 stay barriered; at most set `system-type=linux-kernel` for the threat model).
     They are **forwarded to the `frama-c-launch` handoff** as onboarding profile `linux`, which
     registers the `linux/linux-acsl/` modeled-runtime overlay via `onboard-linux.sh`.
     `--full-tu` engages the gated kernel-TU parse layer (loud-fail; harness mode is the default).
   re-adjudicates ongoing authorization — closing the cycle between disjoint loops.

## 4b. Re-authoring an existing assessment (event-driven; the contaminated-context rule)
A re-author is worthwhile **only on a real trigger** — otherwise it reproduces the report (a flat
no-delta cycle; don't). The triggers:
- **Control-baseline / categorization change** — e.g. the system impact level is re-categorized
  Mod->Hi, or a 800-53 baseline (Low/Moderate/High) selection pulls a previously **BLOCKED/
  config-excluded** unit into the shipped scope -> add a new **supporting asset** + its categorized
  elements/scenarios (R1->R5). (Worked example: `CONFIG_PIPES` on -> the pipe IPC asset + OOB/
  accounting scenarios + the matching SI/SC controls.) This is the cleanest, most self-contained
  trigger.
- **New threat intel / CVE** for the target line -> new threat sources / events / scenarios.
- **Mission scope change** — new subsystems named in the mission -> new assets + scenarios.
- **Environmental/accidental reassessment** — a new operating environment or fault model -> new
  ENV/ACC threat sources (the 800-30 origins EBIOS would omit).

**The contaminated-context rule (the operational form of author ⊥ code).** Once an agent has read the
implementation *or any verification artifact* (found-issues, the overlay, goal dumps), its context is
**contaminated** — it can no longer author code-blind, because it now knows implementation quirks the
scenarios would anchor to (endogeneity). So the orchestrator (whose context is usually contaminated by
Phase-2 work) **MUST delegate the re-author to a FRESH agent** whose context never saw the code, and
**MUST NOT leak implementation detail into that agent's prompt** — give it only: mission/threat model,
PUBLIC API/docs, the existing (code-blind) report to extend, and the method/format/linter. **The
delegation boundary IS the physical barrier** (the same principle `frama-c-launch` uses for its
provers; the same `sl-monitoring-sl` rule that the observed loop runs one delegation level deeper).

**Endogeneity nuance — don't over-sanitize scope/control language.** A 800-53 control ID (`SI-7`,
`AC-6`) or a build-config token (`CONFIG_PIPES`) is legitimate *scope/baseline/control* language in R1
/R5, **not** a code artifact; the `bin/rmf-lint.sh` endogeneity tripwire correctly passes it (C8 flags
`.c`/`.h`/`.cpp`/`.cc`/`.rs`/`#include`/`#define`/`0x...`/`::`/`->`, i.e. source artifacts, not control
or config tokens; and R5 is not scanned at all). What stays banned in R1-R4: translation-unit names,
function names, ACSL, WP goal counts. In R1-R4 prose use the unicode arrow `→` or "then", never `->`.

## 5. Executable oracle setup
- **`bin/rmf-lint.sh REPORT.md`** (repo root) — the mechanical `L`. Parses a report written to the
  **pinned format contract** (`references/report-format.md`) and checks the §1 invariants + the
  endogeneity tripwire; exit 0 = pass, 1 = violations, 2 = usage/format. **Content realism is *not* in
  scope — that is the human terminus.** The author writes to the same pinned contract, so the report
  and the linter cannot drift.
- **Pilot + canary:** run it on a **known-good** report (transcribed to the convention -> must pass)
  and a **deliberately broken** copy (drop a chaining link / inject a code artifact in R2 -> must
  fail) — the RMF analogue of the frama-c canary.
- **Human-terminus parts** (reviewer realism, AO acceptance) have **no machine `L`** — declared
  `DEPENDENCY: human reviewer`, never faked.

## 6. Done criteria
`bin/rmf-lint.sh` green (Gate B) + reviewer completeness/realism PASS with no open carve-outs (Gate C) +
endogeneity flag clear + all three origins covered + RMF steps appropriate to goal + agile volume
respected + capitalized heuristics Gate-S'd, **and the Authorizing Official signs** (human terminus,
the 800-37 Authorize step). **MACHINE-DONE** = linter+coverage; **DONE** = AO sign-off (R5/Authorize
PENDING until then). No self-report ends the study.

## 7. Stabilizers engaged
- **Endogenous `U` / unpinned reality** -> *the* one: author physically barriered from the code;
  Gate-B endogeneity tripwire; the reviewer's anchoring tell.
- **Self-judging** -> author ⊥ reviewer ⊥ AO, physical barriers.
- **Coherent-and-wrong (fluent-but-threat-wrong)** -> reviewer realism + completeness critic + the C6
  origin-coverage check; strictness has a safe direction (over-cover OK, under-cover is the bug).
- **Rubber-stamp** -> Gate A amend/cut; reviewer must discriminate; the AO is a disjoint terminus.
- **Self-declared done** -> gate-defined + human terminus.
- **Absorbed surprise** -> gap doc.
- **Over-exhaustiveness** -> agile volume; cap R3/R4 at 2 iterations.
- **No-blend** -> structure (linter) vs realism (reviewer) vs acceptance (AO) never substitute.
- **Adversarial-only tunnel vision** (the 800-30 trap) -> the C6 origin check + Gate-A's all-three
  requirement.

## 8. Execution order & topology
- **Pilot** `bin/rmf-lint.sh` on a known-good report first.
- Run `rmf-sl` as a **code-disjoint PEER that precedes `frama-c-launch`** — *not* a child of it.
  Orchestration: a thin top driver, **or** the `frama-c-launch` *coordinator* (itself code-barriered)
  spawns it with a **threat-model-only context** — never the architect, never the source.
- **Cadence:** author on RMF's strategic / ongoing-authorization cycle; **consume across many
  verification runs** — don't regenerate per onboarding.
- Within: R1->R2->R3->R4->R5 chained; iterate R3/R4 ≤ 2x.
- **Downstream loop-back (the Monitor step, 800-37 §7):** verification verdicts feed the **Monitor**
  step as control-effectiveness evidence + POA&M updates, emitted as `PREFIX-monitor-feedback-NN.md`;
  the AO re-adjudicates ongoing authorization; that feeds the **next `rmf-sl` cycle**:

  ```
  rmf-sl (code-blind: R1-R5, R5 Authorize PENDING)
     |  exogenous risk bound + STRIDE->800-53->property crosswalk
     v
  frama-c-launch -> frama-c-monitoring  (verify the risk-ranked queue; verdicts)
     |  feedback: verdicts -> control-effectiveness signals (rmf-feedback.md)
     v
  RMF Monitor step (800-37 step 7, ongoing authorization) --> PREFIX-monitor-feedback-NN.md
     |  AO adjudicates ongoing authorization / POA&M (human terminus)
     v
  next rmf-sl cycle  <-- consumes the return-safe Monitor packet (code-free, scenario-keyed)
  ```

- **Return half (re-running this loop after a verification cycle):** the feedback re-enters **code-
  blind** — re-author R1-R5 from the threat model only; the verification packet enters the **Monitor**
  status as a typed, scenario-keyed **control-effectiveness signal** (no TU names / ACSL / proof
  internals — the same shape as a pentest result / a control-assessment finding), never as code-derived
  scenarios or re-rated impact. A confirmed bug re-enters via **R2 threat events / R1 categorization**
  from its *finding statement*, not its reproducer. Consume the **latest numbered** Monitor packet
  (`<prefix>-monitor-feedback-NN.md`, highest `NN`) — emitted **one per cycle and never overwritten**,
  so the series is the ongoing-authorization history; this loop's own `<prefix>-rmf-report.md` is
  **consolidated** (re-authored in place). Carried disciplines (verbatim in spirit from
  `ebios-feedback.md`): a **machine-checked control** -> a control-effectiveness **upgrade /
  likelihood ↓**; a **second-method 0-counterexample corroboration** -> a **residual-weight ↓** only
  (corroboration ≠ control); impact (R1 categorization) **never** set by a verdict. Full rules:
  `../frama-c-launch/references/rmf-feedback.md` § "The return half". This is what keeps the *next* `U`
  exogenous; a packet carrying code/proof content is the cycle's endogeneity breach.

## 9. Compliance check
- **C1 Disjointness:** ✓ four `(U,L)` pairs; no actor relieves its own bound; **all content actors
  share the code barrier** (the exogeneity invariant). Sound only if the barriers are physical
  (author/reviewer contexts hold mission+threat model, never the source).
- **C2 Catchability:** ✓ coverage gap / dropped origin -> reviewer+linter (C6); endogeneity ->
  barrier+tripwire+anchoring tell; rubber-stamp -> Gate A+AO; malformed -> linter.
- **C3 Physical barriers:** ✓ author/reviewer built from mission+threat model, never the code —
  **including on feedback re-runs**: the verification packet enters the Monitor status as a code-free
  control signal, so the code barrier holds across cycles (return half, §8 / `rmf-feedback.md`).
- **C4 Gate-defined done:** ✓ linter + reviewer + origin-coverage + endogeneity-clear + AO sign-off;
  no self-report.

## Reference files
- The **NIST corpus** — the RMF method content: `nist/800-30.txt` (assessment mechanics), `nist/
  800-37.txt` (the 7-step lifecycle / ATO governance), `nist/800-53.txt` (control catalog), `nist/
  sp-800-stride-link.txt` (STRIDE->800-53-family map), `nist/README.txt` (the EBIOS↔NIST crosswalk).
  This loop is the *squeeze* around them, the way `ebios-sl` defers method to `ebios-risk-manager`.
- `references/report-format.md` — the **pinned** report-format tag convention (the linter's contract +
  the author's spec; one source of truth).
- `bin/rmf-lint.sh` (repo root) — the mechanical `L` (structure + coverage + endogeneity linter), parses
  the pinned format.
- Downstream consumer: `../frama-c-launch/SKILL.md` + `../frama-c-launch/templates/rmf-crosswalk.md`
  (the report becomes the ranking `U`) and `../frama-c-launch/references/rmf-feedback.md` (verdicts ->
  the Monitor step, the cycle's downstream half).
- Methodology: **`sl-builder`** (design the loop), **`sl-monitoring-sl`** (monitor + the endogenous-`U`
  discipline), **`sl-internal`** (the (U,L) theory), **`sl-auditor`** (the Gate-S disjoint audit).
- Sibling: `../ebios-sl/SKILL.md` — the EBIOS RM twin (W1-W5); `rmf-sl` mirrors it 1:1, NIST-instantiated.

## The STRIDE -> 800-53 -> verification-property table (drives frama-c-monitoring)
Each discovered STRIDE threat maps to a control family and a verification property the monitoring loop
can discharge (the engine that makes the report drive `frama-c-monitoring`):

| STRIDE | Property | 800-53 family (example) | What `frama-c-monitoring` verifies |
|---|---|---|---|
| Tampering | Integrity | SI-7 / SC / CM | RTE + functional integrity (no OOB write, invariant preserved) |
| Information Disclosure | Confidentiality | SC-8 / AC / MP | no OOB read / no leak across a boundary; separation |
| Denial of Service | Availability | SC-5 / CP | termination / bounded resource (loop variants, `terminates`) |
| Elevation of Privilege | Authorization | AC-6 / IA | privilege/permission invariants (HAPPY/MAcsl system props) |
| Spoofing | Authentication | IA / AC | (often BLOCKED — crypto/runtime; residual risk) |
| Repudiation | Non-repudiation | AU | (BLOCKED — audit/logging; residual risk) |

Memory-safety / RTE (what WP discharges) maps to **Tampering (SI/SC)** + **Information Disclosure
(SC/AC)**; DoS to **SC-5/CP** via `terminates`/variants; EoP to **AC-6** via system invariants.
Spoofing/Repudiation are typically BLOCKED (crypto/audit) -> recorded residual (`RR#`), routed to
non-formal treatment — same discipline as EBIOS BLOCKED.

### The EoP / integrity rows are SYSTEM-level — macsl is imperative, and each scenario is a UNIVERSAL
The authorization/integrity rows (EoP → AC-6; Tampering-as-invariant) are **not** memory-safety. They are
**system-level properties** — universals over *all* attack vectors ("privilege, once dropped, is
unrecoverable **by any means**"; "the confinement cannot be escaped **by any path**") — which per-function
`requires`/`ensures` **cannot express**. Verifying them **imperatively requires** the Tier-3 macsl/HAPPY
system-property tool (`frama-c-monitoring §4b`); a campaign that reports only RTE + functional contracts on
such a scenario has **not** verified the risk it named. This has two consequences for the risk study:

1. **Author each such scenario as a universal, and enumerate its vectors.** An EoP/integrity scenario is a
   *ranked head* whose body is the set of ways the property can fail (for "root unrecoverable": setresuid-back,
   suid-exec, ambient/inheritable caps, ptrace, keyring, fd-passing, securebits — eight). The downstream proof
   must close **each vector** (PROVED or explicitly CARVED/REFUTED, none silently green), so the study must
   surface the vector list, not a one-line property — else coverage looks complete while a vector is untouched.
2. **Warn the monitor of the ghost-fiat trap (do not let a fiat count as verified).** A HAPPY "EoP invariant"
   proved via a **ghost model function with a postulated `ensures`** is **semantically vacuous** — green while
   nothing backs the ghost; macsl's own non-vacuity gate misses it. The study's acceptance of an EoP row as
   *treated* must require the monitor's ghost-antecedent audit (derived leaf `ensures` or a NAMED TCB axiom),
   not a bare macsl green. The **risk owner** (the AO, W5 sign-off) is the terminus that decides whether the
   universal is the intended strength — a REJECT there converts a by-design partial into an open finding.

*Worked reference: the snapd RS1 "root unrecoverable" study — one EoP scenario, eight regain vectors, a
`sc_model_drop_complete` ghost fiat that made it look proven, and the AO verdict that turned two by-design
partials into findings. See `the-snap-story.md`, `recover-root.md`, `ghost-fiat-pattern.md`.*

## ASSUMPTIONS & open questions
- **Report format: PINNED** in `references/report-format.md` (the stable tag set + locality/chaining
  rules + scales — the linter's contract and the author's spec). No longer an open question.
- **OPEN — reviewer gold:** is there an external attack catalog (MITRE ATT&CK / 800-53 baselines /
  sector threat reports) to make the completeness critic genuinely exogenous, or is the reviewer
  mission-only? (Extreme cases: a cross-provider reviewer for decorrelation.)
- **OPEN — the accidental/environmental gradient:** 800-30 origins (ACC/ENV) often map to controls
  outside WP's reach (CP contingency, PE physical). Default: enumerate them in R2 and route to
  non-formal treatment as residual (`RR#`), the same as BLOCKED STRIDE classes.
- **OPEN — reviewer is agent or human:** the AO is human (terminus); the reviewer may be a disjoint
  agent (ideally a different provider family).
