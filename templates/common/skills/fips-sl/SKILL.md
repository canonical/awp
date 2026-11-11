---
name: fips-sl
description: >-
  Author a code-blind FIPS 140-3 requirement study for a cryptographic module. Use the vendored standard and selected security level as authority, validate with fips-lint, and produce the upstream requirements consumed by verification launch and monitoring. Also defines the compliance dossier XXX-fips-compliance/ that every fips-driver report regenerates.
---

# fips-sl — author a FIPS 140-3 requirement study as a code-disjoint squeeze loop

A squeeze loop that AUTHORS a FIPS 140-3 requirement study of a cryptographic module as a trustworthy, code-disjoint deliverable — the upstream requirement study that the verification launch loop (frama-c-launch, then frama-c-monitoring) consumes as its exogenous upper bound, the faithful sibling of rmf-sl. Its upper bound U is the vendored standard itself (./NIST.FIPS.140-3.pdf — the only document the skill cites) plus the module's public description (purpose, services, documented interfaces, Security Policy if one exists) plus the target security level from the manifest; its lower bound L is a mechanical structure+coverage+source-honesty+endogeneity linter (bin/fips-lint.sh) over the report PLUS a human terminus (a disjoint completeness/realism reviewer and the owner of the protected information, or the agency's responsible authority, who accepts the residual risk — Ann. 13). It is a soft-side, human-terminus SL: the dominant coherent-and-wrong it guards is a fluent, well-chained report in which the requirements are INVENTED while stated as if sourced from the PDF (the PDF names the four levels and the eleven requirement areas but holds almost none of the requirements — rule F3 makes every requirement's source explicit, and src:UNSOURCED is the honest state of most of them). The single load-bearing invariant is that the study author is physically BARRIERED FROM THE CODE (F1-F4 code-blind), which makes the output a valid exogenous U for the launch and monitoring loops. Use to produce a FIPS 140-3 requirement study for a cryptographic module at a chosen target level (1-4, from config/auto-wp.json), to run a study whose ranking will drive the launch loop, or to author/audit FIPS sections F1-F4 independently of the implementation. Built with sl-builder, monitored with sl-monitoring-sl, grounded in sl-internal, audited with sl-auditor; the method content is the vendored NIST.FIPS.140-3.pdf.

`fips-sl` produces the **FIPS 140-3 requirement study** that the **launch loop** consumes as its
**exogenous upper bound** (the priority ranking). The launch loop is the language's
onboarding/verification entry: `frama-c-launch` (then `frama-c-monitoring`) for C,
`creusot-launch` / `creusot-monitoring` (its Phase 0) for Rust; below, `frama-c-launch` stands for
whichever is installed. The report is language-neutral: the same `<target>-analysis-fips-report.md`,
the same format contract and the same linter (`bin/fips-lint.sh`) serve both. It is a **peer that
runs first and code-disjoint** — *not* a child of the launch loop. Authoring the requirement study
and consuming it must live in **different, barriered** loops, or the bound collapses back to
endogenous (self-certifying).

The method content is the **vendored standard**: `./NIST.FIPS.140-3.pdf` (FIPS PUB 140-3, *Security
Requirements for Cryptographic Modules*, March 22, 2019 — US government work, shipped at the project
root). Read **"What the source document contains"** in
`references/report-format.md` **before authoring**: the PDF names the four security
levels and the eleven requirement areas, and holds almost none of the requirements themselves — what
each level requires in each area lives in ISO/IEC 19790 and the SP 800-140 series, which the PDF
names but does not reproduce. Honesty about that boundary is rule F3 (`src:` tokens; `src:UNSOURCED`
is allowed and expected) and is this loop's answer to its dominant coherent-and-wrong. It is the
faithful sibling of `rmf-sl` (NIST RMF → FIPS 140-3). **Built with `sl-builder`, monitored with
`sl-monitoring-sl`, grounded in the (U,L) theory of `sl-internal`, audited with `sl-auditor`.**

## When to run this loop — high-stakes / repeated requirement studies, NOT every study
The squeeze is assurance machinery for the *requirement study*, not a substitute for the standard.
Its cost (author ⊥ reviewer ⊥ terminus + the linter) is justified when a **plausible-but-wrong study
is expensive** — and it is when the study **drives formal verification across many codebases**: an
invented requirement or a coverage gap silently mis-aims the whole downstream campaign. For a
one-off, low-stakes reading of the standard, work from the PDF directly. Reach for `fips-sl`
deliberately.

## 0. Deliverable & correctness
- **Deliverable:** a FIPS 140-3 requirement study for a **cryptographic module** — its boundary,
  services, roles, SSPs, interfaces and states — **authored independently of the implementation**,
  at the target level recorded in `config/auto-wp.json` (`fips_level`). It produces **F1–F5** (§4.4
  of the pinned format): F1 module and target level; F2 the eleven requirement areas (`AR1`–`AR11`,
  each with requirement items `RQ#` or an `N/A` line with a reason); F3 failure modes (`FM#`) per
  requirement; F4 verification obligations (`VO#`) with a property class and a priority `P1`–`P3`;
  F5 the residual register (`RR#`) and sign-off. **The sign-off is the human terminus** — the owner
  of the protected information, or the agency's responsible authority, acknowledges and accepts the
  residual risk (Ann. 13); **F5 sign-off is left PENDING** here. Validation itself is the CST
  laboratory and the CMVP, **outside this loop** — a proof is evidence for the laboratory, never a
  validation.
- **Companion deliverable, always generated: the compliance dossier `XXX-fips-compliance/`**
  (§10). Every run that emits a report under the `fips` driver regenerates it in full. The
  verification coordinator writes it (it is code-aware); this loop's author and reviewer never read
  it.
- **"Correct" means (checkable):** (a) **structurally** conformant to the pinned format — F1–F5
  present, every tag with exactly one home line, every `RQ#` carrying exactly one source token,
  chaining well-formed, every area covered (requirement or `N/A` with a reason), the standing
  residuals present, no code artifacts in F1–F4 (mechanical, `bin/fips-lint.sh`); **and** (b) the
  requirements and failure modes are a faithful reading of the **PDF + the module's public
  description + the target level** that a *disjoint reviewer* does not refute and the *terminus*
  signs (soft, human terminus).
- **Terrain archetype: A + B.** **A** (transcription of an external standard) for what the PDF
  actually says — four levels, eleven areas, Approved security functions, conformance and residual
  risk. **B** (authored authority) for everything else — and **author independence *from the code***
  is the soundness argument, exactly as in `rmf-sl`.
- **Dominant coherent-and-wrong:** a **fluent, well-chained, all-eleven-areas-present** report in
  which **the requirements are invented while stated as if sourced from the PDF** — the linter's
  F-C5 bounds which PDF sections may back a requirement (Ann. 6, 7, 10, 13 only), and rule F3 makes
  the honest state (`src:UNSOURCED`) explicit, never hidden. Its sibling failure: a **coverage gap
  masked by fluency** (an area silently dropped, or an `N/A` without a real reason).

## 1. Bounds
- **Upper bound `U`:** `./NIST.FIPS.140-3.pdf` — the only standard the skill cites — **plus** the
  **module's public description** (purpose, services, documented interfaces, Security Policy if one
  exists) **plus** the **target level** from the manifest, **plus** the area→property mapping of
  `references/area-properties.md` (a declared design choice, not PDF text). What the PDF contains:
  the four levels (Ann. 3), the eleven requirement areas (Abstract, Ann. 3), the level-choice rule
  (Ann. 7), the Approved-security-functions requirement (Ann. 10), conformance and residual risk
  (Ann. 13), applicability (Ann. 6), and the ISO/IEC 19790 / 24759 + SP 800-140 incorporation
  (Sec. 2–3, Table 1). What it does **not** contain: the per-area, per-level requirements. Strongest
  claim a deliverable may make: *"a reading of the PDF + the public description do not refute."*
- **Lower bound `L`:** two layers, honestly partial.
  - *Mechanical:* **`bin/fips-lint.sh`** — the F-C0..F-C9 gates of the pinned format (home lines,
    sections, the level line against the manifest, area coverage, one `AR#` + one `src:` per
    requirement, the allowed source-token set, chaining with the `VO#`↔`FM#` set equality,
    min-level applicability, the six standing residuals, the endogeneity tripwire), plus F-C10
    (volume, WARN) and F-C11 (`src:UNSOURCED` count, INFO).
  - *Human terminus:* content realism/completeness — including whether a `src:PDF-…` requirement
    really says what the cited section says — has **no machine oracle**; it terminates in the
    **disjoint reviewer** + the **residual-risk owner** (Ann. 13). Declared `DEPENDENCY: human
    reviewer`; never faked (the `sl-monitoring-sl` honesty rule).

## 2. Actors and their disjoint `(U,L)` pairs

| Actor | Builds | U (above) | L (below) | Forbidden move | Must NOT see |
|---|---|---|---|---|---|
| **FIPS coordinator** | framing (module, goal → F1–F5 subset), sequencing, Gate-A, gap adjudication, the handoff to `frama-c-launch` | the PDF + the module description + the target level | the linter output + reviewer/terminus verdicts | read the code; author what it grades; rubber-stamp; declare done on an author's say-so | the implementation source |
| **Study author** (requirement analyst) | F1–F5 from the PDF + the public description + the target level + `area-properties.md` | the PDF + the module description + the target level | format conformance (each tag has a home line, each requirement a source) | **read the implementation source** (the load-bearing exogeneity barrier); state an invented requirement as PDF-sourced; inflate past the level's volume budget | the **codebase**; the verification scope map; the reviewer's critique |
| **Completeness/realism reviewer** (disjoint catcher) | an independent completeness+realism critique, and the honesty audit of every `src:` token | the PDF + the module description + the eleven areas + (gold) ISO/IEC 19790 / SP 800-140 if supplied | the coverage linter + its **own** independent per-area enumeration | read the author's rationale; read the code; rewrite the report (verdicts/carve-outs only) | the author's notes; the implementation |
| **Residual-risk owner** (human terminus, Ann. 13) | acceptance of the residual risk; the F5 sign-off | the owner's acceptance duty + the mission (the protected information) | the report + the reviewer's verdicts | author the requirements it accepts | — |
| **Probe** (opt.) | minimal method/tooling experiments | one design claim per probe | the linter's actual behaviour | implement a fix | — |

**Disjointness (C1):** author holds the PDF + public description + level (never the code, never the
reviewer's critique); reviewer holds the PDF + public description + the area vocabulary + its own
enumeration (never the author's rationale, never the code); coordinator holds the same U + gate
output (never authoring what it grades); the terminus holds the acceptance duty (never authoring).
**All content actors are barriered from the code — that shared barrier *is* the exogeneity
invariant.** Intersection = a report format-conformant **and** complete/realistic per an independent
reviewer **and** signed by the terminus.

**Catchability (C2):** an invented requirement stated as PDF-sourced → the reviewer's `src:` audit +
F-C5 (the four allowed sections); missed area / vacuous `N/A` → reviewer (independent enumeration +
F-C3); content shaped by code knowledge (endogeneity) → the physical **code barrier** + the F-C9
tripwire + the reviewer's **anchoring tell**; reviewer rubber-stamps → coordinator Gate A + the
terminus; mis-framed scope or level → Gate A; malformed chain / missing source / level-line drift →
the linter.

## 3. Gates
- **Gate A — editorial.** Coordinator judges framing + report against the PDF + public description
  + level: right sections for the goal; the module boundary correct (a module, not a whole system);
  the level line matches the manifest; **every area covered** (requirement items or `N/A` with a
  real reason — never a silent drop); **the level's volume budget** (level 1 ≈ 1–3 `RQ#` per
  applicable area, rising to 3–6 at level 4 — placeholders, see ASSUMPTIONS); `min-level K`
  monotone within an area (a `min-level 3` item is not weaker than a `min-level 2` one). Amend/
  cut/sharpen, never rubber-stamp.
- **Gate B — machine.** `bin/fips-lint.sh` passes (F-C0..F-C9), **including the endogeneity
  tripwire** (no code artifacts in F1–F4) and F-C2 (the level line equals the manifest's
  `fips_level`). The FIPS analogue of "all VCs discharged."
- **Gate C — coverage / no-blend / coherent-and-wrong.** The reviewer's **independent enumeration**
  covers every area and every plausible service/interface across the module's public description
  (the completeness critic); the report is the **intended study, not a vacuous one** (a
  single-trivial-requirement report passes B but fails C realism); the **honesty audit** — every
  `src:PDF-…` requirement is checked against the section it cites, and every `src:UNSOURCED`
  requirement is *surfaced* in the critique and in F5, never disguised; **no-blend** — the linter
  (form) never substitutes for the reviewer (realism), and neither substitutes for the terminus
  (acceptance); **endogeneity flag** — content traceable to code-reading ⇒ discount and re-author
  code-blind.

## 4. Loop steps (per study)
1. **Coordinator** frames: module + goal → F1–F5 subset + barriers (author ⊥ code) + the level's
   volume budget + the requirement that F2 cover `AR1`–`AR11` (item or `N/A`+reason each).
2. **Study author** drafts F1 `@ DRAFT` from the public description + the manifest level → **Gate
   A**; then F2 (`AR1`–`AR11`, each `RQ#` with exactly one `src:` token) → F3 (failure modes per
   requirement) → F4 (obligations with property class + priority, `RQ#` set equal to its `FM#`s')
   → F5 (residuals incl. the six standing planes, sign-off PENDING); iterate F3/F4 **≤ 2x**.
3. **Reviewer** independently authors the completeness/realism critique from the PDF + public
   description + its own per-area enumeration (not the author's notes, not the code) — and audits
   every `src:` token for honesty.
4. **Gate B** (`bin/fips-lint.sh`) → **Gate C** (reviewer coverage/realism + honesty audit +
   endogeneity flag).
5. **MACHINE-DONE** (structure+coverage) → **the residual-risk owner adjudicates** content/residual
   risk (human terminus, Ann. 13) → **DONE** (F5 sign-off PENDING until then).
6. Divergence (coverage gap, dishonest source, malformed chain, endogeneity detected, requirement
   mirrors code) → `PREFIX-fips-gaps.md` → re-plan (re-author code-blind).
7. **Capitalize (Gate S):** reusable requirement-study heuristics, audited by a disjoint monitor
   (`sl-monitoring-sl`) and the Gate-S audit (`sl-auditor`).
8. **Handoff:** approved F1–F5 → the launch loop consumes them (`frama-c-launch`: the
   `fips-crosswalk.md` ranking by `P1`–`P3`, the `VO#` → translation-unit join; `creusot-monitoring`:
   the Phase-0 ranking); later the monitoring loop's verdicts → the **return half** (below), the
   owner re-adjudicates the residual risk — closing the cycle between disjoint loops.

## 4b. Re-authoring an existing study (event-driven; the contaminated-context rule)
A re-author is worthwhile **only on a real trigger** — otherwise it reproduces the report (a flat
no-delta cycle; don't). The triggers:
- **Target-level change** — the module is re-targeted (e.g. level 2 → level 3): rule F5 pulls
  previously out-of-scope requirements in (everything with `min-level` ≤ the new level) and the
  volume budget rises. This is the cleanest, most self-contained trigger.
- **New module description / Security Policy revision** — new services, roles, interfaces or SSPs
  named publicly → new `SV#`/`RL#`/`IF#`/`SSP#` home lines and their requirements (F1→F5).
- **Module scope change** — the boundary moves (a component leaves or enters the module) → F1 and
  the affected areas.
- **New threat intel / CVE** in the module's dependencies → new failure modes in F3 for the
  affected requirements.

**The contaminated-context rule (the operational form of author ⊥ code).** Once an agent has read the
implementation *or any verification artifact* (found-issues, the overlay, goal dumps), its context is
**contaminated** — it can no longer author code-blind, because it now knows implementation quirks the
requirements would anchor to (endogeneity). So the orchestrator (whose context is usually contaminated
by Phase-2 work) **MUST delegate the re-author to a FRESH agent** whose context never saw the code,
and **MUST NOT leak implementation detail into that agent's prompt** — give it only: the PDF, the
module's public description, the target level, the existing (code-blind) report to extend, and the
method/format/linter. **The delegation boundary IS the physical barrier** (the same principle
`frama-c-launch` uses for its provers; the same `sl-monitoring-sl` rule that the observed loop runs
one delegation level deeper).

**Endogeneity nuance — don't over-sanitize module language.** A standard citation (`Ann. 10`) or a
module-vocabulary token (`SSP`, `CSP`, `crypto officer`) is legitimate *module/standard* language in
F1–F5, **not** a code artifact; the linter's endogeneity tripwire correctly passes it (F-C9 flags
source artifacts — C: `.c`/`.h`/`.cpp`/`.cc`/`#include`/`#define`/`0x…`/`::`/`->`; Rust: `.rs`,
`fn name(`, `impl X`, `unsafe {`, `#[attr]`, `&mut`, `Vec<`/`Option<`/`...`, `macro!(`, `.unwrap()`).
What stays banned in F1–F4: translation-unit, module or crate-path names, function names, ACSL or
Pearlite, goal counts. In F1–F4 prose use the unicode arrow `→` or "then", never `->`.

## 5. Executable oracle setup
- **`bin/fips-lint.sh REPORT.md`** (project root) — the mechanical `L`. Reads the target level from
  `config/auto-wp.json` (`fips_level`; `FIPS_LEVEL=N` overrides it, a test hook only), parses a
  report written to the **pinned format contract** (`references/report-format.md`) and checks the
  F-C0..F-C9 gates; exit 0 = pass, 1 = violations, 2 = usage/format. **Content realism and source
  honesty are *not* in scope — that is the human terminus.** The author writes to the same pinned
  contract, so the report and the linter cannot drift.
- **Pilot + canary:** run it on the **known-good** fixture (`references/skeleton.md` → must pass)
  and on one **deliberately broken** copy per check (each must fail with that check's ID and no
  other) — the FIPS analogue of the frama-c canary.
- **Human-terminus parts** (reviewer realism, the owner's sign-off) have **no machine `L`** —
  declared `DEPENDENCY: human reviewer`, never faked.

## 6. Done criteria
`bin/fips-lint.sh` green (Gate B) + reviewer completeness/realism PASS with no open carve-outs (Gate
C) + the `src:` honesty audit clear + endogeneity flag clear + every area covered (item or justified
`N/A`) + the level's volume budget respected + `min-level` monotone + the six standing residuals
present + capitalized heuristics Gate-S'd, **and the residual-risk owner signs** (human terminus, the
Ann. 13 acknowledgment). **MACHINE-DONE** = linter+coverage; **DONE** = the owner's sign-off (F5
PENDING until then). No self-report ends the study — and no proof inside it replaces CMVP validation.

## 7. Stabilizers engaged
- **Endogenous `U` / unpinned reality** → *the* one: author physically barriered from the code;
  F-C9 endogeneity tripwire; the reviewer's anchoring tell.
- **Invented-but-attributed requirements (the FIPS coherent-and-wrong)** → rule F3's `src:` tokens +
  F-C5's four-section allowlist + the reviewer's honesty audit + F-C11's `UNSOURCED` count surfaced;
  strictness has a safe direction (more `UNSOURCED` is honest, a fake `src:PDF-…` is the bug).
- **Self-judging** → author ⊥ reviewer ⊥ owner, physical barriers.
- **Coherent-and-wrong (fluent-but-thin)** → reviewer realism + completeness critic + F-C3's
  area-coverage check; over-covering is safe, dropping an area is the bug.
- **Rubber-stamp** → Gate A amend/cut; reviewer must discriminate; the owner is a disjoint terminus.
- **Self-declared done** → gate-defined + human terminus.
- **Absorbed surprise** → gap doc (`PREFIX-fips-gaps.md`).
- **Over-exhaustiveness** → the level's volume budget; cap F3/F4 at 2 iterations.
- **No-blend** → structure (linter) vs realism (reviewer) vs acceptance (owner) never substitute.
- **Validation confusion** → a `PROVED` `VO#` is evidence for its `RQ#`, never a validation; the
  CMVP/CST step stays outside the loop (the standing `validation` residual).

## 8. Execution order & topology
- **Pilot** `bin/fips-lint.sh` on `references/skeleton.md` first.
- Run `fips-sl` as a **code-disjoint PEER that precedes the launch loop** (`frama-c-launch`, or
  `creusot-launch` / `creusot-monitoring` for Rust) — *not* a child of it. Orchestration: a thin top
  driver, **or** the launch loop's *coordinator* (itself code-barriered) spawns it with a
  **public-description-only context** — never the architect, never the source. For Rust there is no
  `/fips` command: the mission asks for the study by name, and `creusot-monitoring` delegates it to a
  fresh agent before its Phase-0 audit reads the crate.
- **Cadence:** author on the module's procurement / revalidation cycle; **consume across many
  verification runs** — don't regenerate per onboarding.
- Within: F1→F2→F3→F4→F5 chained; iterate F3/F4 ≤ 2x.
- **Downstream loop-back (the return half):** verification verdicts feed the **next study cycle** as
  typed, code-free evidence keyed by requirement, emitted as `PREFIX-fips-feedback-NN.md`; the owner
  re-adjudicates the residual risk; that feeds the next `fips-sl` cycle:

  ```
  fips-sl (code-blind: F1-F5, F5 sign-off PENDING)
     |  exogenous requirement bound + areas→properties crosswalk
     v
  frama-c-launch -> frama-c-monitoring  (verify the priority-ranked queue; verdicts)
  [Rust: creusot-launch -> creusot-monitoring, the same two halves]
     |  feedback: verdicts -> requirement evidence (fips-feedback.md)
     v
  the owner re-adjudicates the residual risk (Ann. 13) --> PREFIX-fips-feedback-NN.md
     |  human terminus adjudicates
     v
  next fips-sl cycle  <-- consumes the return-safe feedback packet (code-free, RQ#-keyed)
  ```

- **Return half (re-running this loop after a verification cycle):** the feedback re-enters **code-
  blind** — re-author F1–F5 from the PDF + public description + level only; the verification packet
  enters as a typed, requirement-keyed **evidence signal** (no TU names / ACSL / proof internals —
  the same shape as a laboratory report), never as code-derived requirements. A confirmed bug
  re-enters via **F3 failure modes** from its *finding statement*, not its reproducer. A `PROVED`
  `VO#` is **evidence for its `RQ#`**, never a validation; a `VIOLATION` is a finding, never a
  re-rated priority. Consume the **latest numbered** feedback packet
  (`<prefix>-fips-feedback-NN.md`, highest `NN`) — emitted **one per cycle and never overwritten**,
  so the series is the revalidation history; this loop's own `<prefix>-fips-report.md` is
  **consolidated** (re-authored in place). Full rules: `../frama-c-launch/references/fips-feedback.md`
  § "The return half". This is what keeps the *next* `U` exogenous; a packet carrying code/proof
  content is the cycle's endogeneity breach.

## 9. Compliance check
- **C1 Disjointness:** ✓ four `(U,L)` pairs; no actor relieves its own bound; **all content actors
  share the code barrier** (the exogeneity invariant). Sound only if the barriers are physical
  (author/reviewer contexts hold PDF+public description+level, never the source).
- **C2 Catchability:** ✓ invented/mis-sourced requirement → reviewer+F-C5; coverage gap / vacuous
  N/A → reviewer+linter (F-C3); endogeneity → barrier+F-C9+anchoring tell; rubber-stamp → Gate A +
  owner; malformed → linter.
- **C3 Physical barriers:** ✓ author/reviewer built from PDF+public description, never the code —
  **including on feedback re-runs**: the verification packet enters as a code-free, requirement-keyed
  evidence signal, so the code barrier holds across cycles (return half, §8 / `fips-feedback.md`).
- **C4 Gate-defined done:** ✓ linter + reviewer + area-coverage + honesty + endogeneity-clear +
  owner sign-off; no self-report.

## 10. The compliance dossier — always generated
The study (F1–F5) says what the module must do; the verification ledgers say what the code does. The
**compliance dossier** joins them for a reader: a directory `XXX-fips-compliance/` (`XXX` = the source directory's root-safe slug) at the project
root with nine files — `README.md`, `module-definition.md`, `requirements-matrix.md`,
`XXX-found-violations.md`, `design-gaps.md`, `other-findings.md`, `proof-evidence.md`,
`trusted-base.md`, `residuals-and-signoff.md`. Contents, sources, status vocabulary and the ISO/IEC
19790 clause table: **`references/compliance-dossier.md`**.

- **Always.** Every `/fips` run, and every `/time-loop` interim or final report under the `fips`
  driver, regenerates the whole directory from the ledgers. All nine files exist after each
  generation, even when one has nothing to report. It is committed with the cycle's checkpoint.
- **Every finding, FIPS or not.** A violation of an `RQ#` goes to `XXX-found-violations.md`, with
  the clause explained; a requirement whose mechanism is absent goes to `design-gaps.md`; every other
  finding — code defects without a requirement, observations, tool defects, errors in the campaign's
  own annotations — goes to `other-findings.md`.
- **Code barrier.** The dossier is code-aware, so the verification coordinator writes it, and the
  `fips-sl` author and reviewer never read it. The return half stays the code-free feedback packet
  (§8).
- **No validation claim; sign-off PENDING.** Like F5, the dossier is evidence for the laboratory, and
  says so in its first paragraph.

## Reference files
- **The standard** — the only source document: `./NIST.FIPS.140-3.pdf`, vendored at the project root
  (US government work). Its §1 table in `references/report-format.md` says exactly what it does and
  does not contain; the skill never presents a requirement as coming from the PDF when it does not.
- `references/report-format.md` — the **pinned** report-format convention (the tag set + home-line /
  source / chaining rules + scales — the linter's contract + the author's spec; one source of truth).
- `references/skeleton.md` — the minimal conformant report; the linter's known-good fixture.
- `references/area-properties.md` — the eleven areas → verification properties (the engine that
  makes the report drive `frama-c-monitoring`; a declared design choice, not PDF text).
- `references/compliance-dossier.md` — the always-generated compliance dossier
  `XXX-fips-compliance/` (§10): its nine files, sources, rules, status vocabulary and the ISO/IEC
  19790 clause of each area.
- `references/crosswalk-format.md` — the thin pointer to the canonical crosswalk schema with the
  FIPS tag bindings.
- `bin/fips-lint.sh` (project root) — the mechanical `L` (structure + coverage + source honesty +
  endogeneity linter), parses the pinned format.
- Downstream consumer, C: `../frama-c-launch/SKILL.md` +
  `../frama-c-launch/templates/fips-crosswalk.md` (the report becomes the priority ranking) and
  `../frama-c-launch/references/fips-feedback.md` (verdicts → requirement evidence, the cycle's
  downstream half).
- Downstream consumer, Rust: `../creusot-monitoring/SKILL.md` Phase 0 (the study's priorities refine
  the value/risk ranking and the scope map).
- Methodology: **`sl-builder`** (design the loop), **`sl-monitoring-sl`** (monitor + the
  endogenous-`U` discipline), **`sl-internal`** (the (U,L) theory), **`sl-auditor`** (the Gate-S
  disjoint audit).
- Sibling: `../rmf-sl/SKILL.md` — the NIST RMF twin (R1–R5); `fips-sl` mirrors it 1:1,
  FIPS-140-3-instantiated (and `../ebios-sl/SKILL.md`, the EBIOS RM twin).

## The eleven areas → verification-property table (drives frama-c-monitoring)
Each requirement maps to a verification property the monitoring loop can discharge, or to a plane
that stays residual (the engine that makes the report drive `frama-c-monitoring`; the full table
with its rationale is `references/area-properties.md` — **a design choice of this skill, not text
from the PDF**):

| Area | Property class (token) | What is checked, and how | Residual (plane) |
|---|---|---|---|
| AR1 module specification | `approved-only` | in the approved mode, every service reaches only the module's Approved security functions — a **call-graph check**, not a WP proof | the list itself (`validation`) |
| AR2 interfaces | `output-inhibit` | no data output while the module is in an error or self-test state | — |
| AR3 roles, services, authentication | `role-gate` | each service runs only with an authenticated, authorized role | strength of the authentication mechanism (`crypto`) |
| AR4 software/firmware security | `integrity-first` | the integrity test runs, and passes, before any service | the integrity technique (`crypto`) |
| AR5 operating environment | — | — | `ENV` |
| AR6 physical security | — | — | `physical`; a software-only module marks AR6 `N/A` in F2 and still writes the standing `physical` residual in F5 |
| AR7 non-invasive security | — | — | `side-channel`: constant-time tools, not WP |
| AR8 SSP management | `zeroize`, `no-plain-ssp-out` | SSPs zeroized after use and on every error path; no plaintext SSP leaves through a data output — the `zeroize` proof is on the source, a compiler can remove it | removed zeroization (`supply-chain`) |
| AR9 self-tests | `selftest-order`, `error-state` | pre-operational and conditional self-tests run before first use; a failure enters the error state and stays there | the test vectors (`crypto`) |
| AR10 life-cycle assurance | `fsm` | the transitions the code allows are those of the documented finite state model | configuration management, delivery (`logic`) |
| AR11 mitigation of other attacks | — | — | `side-channel` or `logic`, per item |

**System-level classes.** `output-inhibit`, `role-gate`, `integrity-first`, `selftest-order`,
`error-state` and `fsm` are properties over every path or over the order of events in the whole
module. Per-function `requires` and `ensures` cannot express them without ghost state; they need
macsl or a whole-module invariant, and a ghost function with a postulated `ensures` does not count as
verified (the same warning `rmf-sl` carries for its system-level rows).

**Standing residuals (ALWAYS named, NEVER proved).** Every report names these in F5, one `RR#` line
per plane, even if no requirement surfaced them — each naming its area or `STANDING` (rule F4):
- strength of the cryptographic primitives (plane `crypto` → `STANDING`) — KAT vectors / libcrypto
  trust, non-formal treatment;
- the AR5, AR6 and AR7 planes (`ENV` → `AR5`, `physical` → `AR6`, `side-channel` → `AR7`) — out of
  formal reach by design;
- compiler correctness, including removed zeroization, and supply chain (plane `supply-chain` →
  `STANDING`) — SLSA / reproducible build;
- the CMVP validation itself (plane `validation` → `STANDING`) — a proof is evidence for the
  laboratory, not a validation.

## ASSUMPTIONS & open questions
- **Report format: PINNED** in `references/report-format.md` (the tag set + home-line/source/
  chaining rules + scales — the linter's contract and the author's spec).
- **OPEN — the corpus is thin:** the PDF names the areas and the levels but holds almost none of the
  requirements; most `RQ#` will be `src:UNSOURCED`, which is honest but weak. Adding SP 800-140A–F
  (free, public) or accepting a user-supplied ISO/IEC 19790 (paid, cited `src:19790-…`) would
  strengthen it — decided per project, not in this skill.
- **OPEN — per-level requirements:** every `min-level` choice is `UNSOURCED` unless the corpus
  grows; the reviewer checks only monotonicity within an area.
- **OPEN — the module boundary:** a whole system (GRUB) is not a module; the study names the module
  (`MOD#` by role) and its boundary in F1. A library target (e.g. a crypto library) is the cleaner
  default; the `/time-loop --dir=<subdir>` filter scopes the verification to it.
- **OPEN — volume per level:** the Gate-A budgets (1–3 `RQ#`/area at level 1 to 3–6 at level 4) are
  placeholders until a first campaign calibrates them.
- **OPEN — reviewer is agent or human:** the terminus is human (Ann. 13); the reviewer may be a
  disjoint agent (ideally a different provider family).
