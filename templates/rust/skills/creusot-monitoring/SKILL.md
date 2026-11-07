---
name: creusot-monitoring
description: >-
  A top-level Squeeze Loop that drives the creusot-sl loop across a whole crate.
  Given a mission like "analyze the crate xxx in directory yyy", it builds the
  file/dependency graph, schedules the *.rs files in the right order (leaf files
  first, propagating each proven callee #[ensures] as the caller's #[requires]),
  and instantiates a creusot-sl sub-loop (with its own coordinator/spec-author/
  annotator/verifier sub-agents) on each file. It is itself a squeeze loop
  MONITORING a squeeze loop (the sl-monitoring-sl meta-pattern): its lower bound /
  ground truth is the creusot-sl loop's own machine verdicts, and its upper bound
  is compliance with the mission guidance (e.g. "specify thoroughly the Rust file
  but disregard network access"). It audits creusot-sl's accumulated learned
  skills and inferred contracts against that guidance from a disjoint base, routes
  tooling gaps to getting-better/ and bugs to bugs-to-report/, and capitalizes its
  own learning under config/skills/creusot-monitoring/. Before analysing, it runs a
  Phase-0 generic architectural audit (fan-out read-only sub-agents -> an architecture
  report) whose extracted claims become the upper bound and whose value/risk ranking
  focuses the schedule (e.g. attack-surface-first for a security audit). Use to verify a crate (not
  a single file) with Creusot, to orchestrate/monitor many creusot-sl runs, to
  schedule files leaf-first, or to collect Creusot feature requests and bug
  reports surfaced during verification.
---

# creusot-monitoring — a Squeeze Loop driving and monitoring `creusot-sl`

`creusot-monitoring` is the **top** loop; `creusot-sl` (the `creusot-sl` skill (`config/skills/creusot-sl/SKILL.md`))
is the **base** loop it drives, one `*.rs` file at a time. It is built with the
`sl-builder` methodology and monitored with the `sl-monitoring-sl` meta-pattern
("a squeeze loop monitoring a squeeze loop"). It launches sub-agents: for each file
it instantiates a full `creusot-sl` (coordinator + spec author + annotator +
verifier + probe), and it adds its own top-level cast on top.

> Drafted with `sl-builder`; monitoring discipline from `sl-monitoring-sl`. Slots the
> mission did not fix are marked `ASSUMPTION:`; unresolved forks are in *Open
> questions*. Run the C1/C2 checks before trusting an instance.

## 0. Mission & deliverable
- **Mission shape:** `analyze the crate <xxx> in directory <yyy>` + **guidance** (the
  upper bound — see §1), e.g. *"specify thoroughly the Rust file but disregard
  network access."*
- **Deliverable:** every in-scope `*.rs` file of the crate carried to a `creusot-sl`
  **DONE** verdict, in dependency order, consistently honoring the guidance — plus a
  recorded monitor verdict on each base-loop skill/inferred contract, and any tooling
  gaps / bugs routed to `getting-better/` and `bugs-to-report/`.
- **Dominant coherent-and-wrong to guard:** a crate that *looks* verified because each
  file's `creusot-sl` went green, but where the base loop **strengthened a contract
  for local convenience that is globally or guidance-wrong** (e.g. specified network
  behaviour the guidance said to disregard, or inferred a callee `#[ensures]` that
  over-constrains a caller). That cross-file / vs-guidance error is exactly what the
  monitor is positioned to catch.

## 1. Bounds
- **Upper bound `U` (soft, normative):** the **mission guidance** — the citable
  instruction on *what and how much* to verify ("specify thoroughly … disregard
  network access …"), plus the mission scope (`crate xxx`, `dir yyy`). The strongest
  claim any base-loop output may make is "a reading the guidance does not refute."
  `U` is **seeded and sharpened by the Phase-0 architectural audit** (§ before Loop
  steps): the audit's extracted *claims* about the system become citable, per-file
  obligations the loop must check — turning vague guidance ("specify thoroughly") into a
  concrete upper bound to verify against.
- **Lower bound `L` (executable, ground truth):** the **`creusot-sl` loop itself** —
  its machine gate verdicts per file (`DONE` with Gate B/C passed, or a `gap-N`),
  which `creusot-monitoring` **cannot alter**. The base loop *is* the runnable oracle
  for the monitor; cross-file, `L` also includes `cargo creusot` discharge **across
  units** (a callee `#[ensures]` actually proves; the caller's assumed `#[requires]`
  is established at the call site) and the linked crate's `cargo test`.

## 2. Actors and their disjoint `(U,L)` pairs

The base-loop cast lives in `creusot-sl`; this table is the **top** cast added on top.

| Actor | Builds | U (above) | L (below) | Forbidden move | Must NOT see |
|---|---|---|---|---|---|
| **Mission coordinator** | the per-crate plan, the file schedule, gate verdicts, gap-doc adjudication, routing of suggestions/bugs | the mission guidance + scope | the aggregated `creusot-sl` verdicts + cross-unit `cargo creusot`/test output | edit Rust/Pearlite; declare the crate done on a sub-loop's say-so; absorb a tooling surprise locally | — (judges against the guidance, never a sub-agent's rationale) |
| **Architect / auditor** (Phase 0) | the **architectural audit** — fan-out read-only deep-read → a report yielding the *claim set*, the Creusot-amenability *scope map*, and the value/risk *ranking* | the mission + the system's own documented intent | the actual source (read-only) | edit the target; verify anything itself; assert a claim it did not read out of the code | — |
| **Scheduler / graph planner** | the module+call graph of `dir yyy`; the **leaf-first** topo-order *refined by the audit's value/risk ranking*; the parallelizable-independent set | the mission scope + the audit ranking | the *actual* dependency graph (`cargo metadata`, module/use graph, compile) | skip a file silently; verify anything itself | — |
| **Base-SL monitor** (`sl-monitoring-sl`) | per-skill / per-inferred-contract verdicts on what `creusot-sl` learned or strengthened | `U` (the guidance the skill/contract must not contradict) | `L` (the `creusot-sl` oracle + cross-unit discharge), used as a differential comparator | edit `creusot-sl`'s implementation; read a producing agent's rationale; fake a PASS for an un-runnable sub-loop | the base agents' private notes |
| **creusot-sl instances** | per-file verified Rust + specs (the base deliverable) | the file's requirement (from the guidance) | the per-file `creusot-sl` gates | (the base loop's own forbidden moves) | (the base loop's own barriers) |

**Disjointness (C1):** the scheduler holds "what the dependency graph is" (never the
specs); the base `creusot-sl` instances hold "what discharges within a file"; the
**monitor holds "what the guidance mandates across files" + "what the base oracle
actually returns"** — a *disjoint* evidence base from the base loop that produced the
skill/contract; the coordinator holds the guidance + aggregated verdicts (never
producing a file's artifact). **Intersection** = a crate whose every file is
base-DONE *and* whose inferred contracts/skills survive the guidance + cross-unit
oracle from outside the base loop.

**Catchability (C2):** a base loop that strengthens a contract for *local* convenience
in a way that is *globally* or *guidance*-wrong is caught by the monitor (it holds
`U_guidance` and the cross-unit `L`, which the base agents do not). A file verified
in the wrong order (a callee not yet proven) is caught by the scheduler's leaf-first
order + cross-unit Gate B.

## 3. Physical barriers
- **Monitor ⊥ base rationale.** The monitor judges each base-loop skill/contract only
  against `U` (guidance) and `L` (the base oracle) — never the base agent's account of
  *why* it learned the skill. It emits a verdict and a carve-out, never a silent fix.
- **Coordinator judges against the guidance**, not a sub-agent's self-report; the
  crate is never "done" because a sub-loop reported success.
- **Base barriers are inherited, not weakened.** Driving `creusot-sl` as a sub-loop
  must not hand a barriered base role (spec author, verifier) anything it is forbidden
  to see; the monitoring layer adds barriers, it never removes the base's.

- **The crate under study is read-only, for builds too.** Never run `cargo` (build, check,
  test, update) inside `dir yyy`: cargo rewrites its `Cargo.lock` (a global `[patch]`, such as the
  creusot SDK's, adds `[[patch.unused]]`; resolution may change versions), and the original cannot
  be recovered without a commit. Copy it first (`cp -a yyy <scratch>/yyy`) and build the copy; check
  `git -C yyy status --short` is still empty afterwards.

## 4. Gates (top level)
- **Gate A_top — editorial.** The coordinator judges the per-crate plan + file
  schedule + the *interpretation of the guidance* against `U`: is "disregard network
  access" actually applied (no network preconditions specified), is "specify
  thoroughly" met (no file silently under-specified), is the leaf-first order sound?
  Amend / cut / sharpen; no delegation from a `DRAFT`.
- **Gate B_top — machine.** Every scheduled file's `creusot-sl` reaches **DONE** (its
  Gate B/C pass); the **leaf-first order held** (each callee proven before its
  callers; proven `#[ensures]` propagated as caller `#[requires]`); cross-unit
  `cargo creusot` discharges and the linked `cargo test` passes; **no file in scope
  skipped**.
- **Gate C_top — coverage / no-blend / coherent-and-wrong.** Every in-scope file has a
  base verdict; the guidance was honored **uniformly** (no file over- or
  under-specified relative to it); a base-inferred contract that contradicts the
  guidance or another unit is caught by the monitor (§6); a base **local** WP verdict
  never stands in for the **cross-unit** obligation (no plane blend); every tooling
  surprise was **routed** (§7), never absorbed.
- **Gate S — skill-consistency (both levels).** The base loop's learned skills are
  audited by the monitor (§6). The monitoring loop's **own** learned skills are
  audited from a *disjoint base* (a cross-provider agent or a human — the recursion
  must stop at an external reviewer, per `sl-auditor` Dimension 8); never self-audited.

## Phase 0 — architectural audit (run this before §5, to *focus* the loop)

**Before delegating any file, run a generic architectural audit of the target so the loop
is aimed, not blind.** Fan out read-only sub-agents (one per subsystem/crate — the
`sl-monitoring-sl` sub-agent isolation keeps the coordinator's context clean), each
deep-reading its area, then synthesize one **architecture report**. The audit produces the
three things the rest of the loop runs on:

1. **An upper bound (`U`).** The report's **claims** — the properties the system asserts
   about itself (e.g. "these parsers bounds-check and never panic", "`unsafe` is confined to
   the firmware boundary") — become part of `U`. The loop's job becomes *check those claims
   hold*, per file, rather than the vaguer "specify thoroughly."
2. **A scope map.** Which files are Creusot-amenable (pure, few deps) vs **blocked**
   (FFI / external crates / firmware or runtime state Creusot can't model). The loop
   concentrates on the amenable set and *records* the rest as out-of-reach — never failing
   on, or faking, what Creusot cannot model.
3. **A value/risk ranking that focuses the schedule.** Leaf-first order is *refined by
   importance*: for a security audit, rank by **input-exposure** so the parsers of untrusted
   input (the attack surface) are proven first, and coverage is reported as a fraction of the
   *high-value* surface, not of the whole tree.

**Exogenous ranking from a risk study (when the mission asks for one, or
`<target>-analysis-rmf-report.md` already exists).** The `rmf-sl` skill
(`config/skills/rmf-sl/SKILL.md`) authors a **code-blind** NIST RMF risk assessment of the
target, `<target>-analysis-rmf-report.md` at the project root, whose R4 risk levels
(likelihood x impact) and R5 controls give the ranking of item 3 an **exogenous** origin
instead of "input-exposure read off the code". Rules: (a) the study is written **before**
the audit, by a **fresh sub-agent that never sees the crate** — give it only the mission,
the threat model and the crate's public documentation, never a source path (`rmf-sl` §4b:
the delegation boundary is the barrier); (b) it must pass `bin/rmf-lint.sh
<target>-analysis-rmf-report.md` (exit 0), whose C8 tripwire fails on any Rust or C code
artifact in R1-R4; (c) the architect then reads the report and refines the value/risk
ranking with it: a file is ranked by the highest-risk `RS#` whose supporting asset it
implements, and the scope map records, per `RS#`, whether its control is amenable to
Creusot (panic/overflow/bounds freedom, functional contracts) or out of reach (FFI, PAM,
process state), as a named residual. Record the mapping file -> `RS#` in the architecture
report, so that the proofs can be read back as control-effectiveness evidence (the RMF
Monitor step). The audit's own, endogenous ranking stays the fallback when no study exists.

**Gate A_top** then judges the audit + the resulting `U`/scope/ranking before any file is
delegated. The architecture report is a first-class output (alongside the verdicts).

**Honesty — endogenous vs exogenous `U`.** The audit reads the *implementation*, so any
*functional* claims it extracts are an **endogenous** upper bound: verifying them is a
**self-consistency** check (the same caveat as the lightweight `creusot-sl` variant), not
conformance to an external spec. **Safety/robustness** properties the audit *motivates* (no
panic / overflow / out-of-bounds for **any** input) are **exogenous** — universal, not
derived from the code — so proving those is genuinely sound. The audit's load-bearing jobs
are therefore to **focus** the loop and **surface scope**; its functional claims are checked
as self-consistency unless an external requirement is also supplied.

## 5. Loop steps (per mission)
0. **Architect/auditor** runs the **Phase-0 architectural audit** → the claim set (folded
   into `U`), the Creusot-amenability scope map, and the value/risk ranking. Read-only.
1. **Coordinator** parses the mission + guidance + **audit** → `U`; opens the crate plan @
   `STATUS: DRAFT`.
2. **Scheduler** builds the module/call graph of `dir yyy`, topo-sorts **leaf-first**
   *refined by the audit's value/risk ranking* (highest-value / most-exposed first), marks
   the independent (parallelizable) set.
3. **Gate A_top** → `APPROVED` (coordinator judges plan + schedule + guidance reading).
4. **For each file, in order** (parallel only across independent files): instantiate a
   **`creusot-sl`** sub-loop, threading the guidance into the spec author/annotator
   (e.g. "specify thoroughly; disregard network access"). Propagate each proven callee
   `#[ensures]` as the caller's `#[requires]` (bottom-up).
   **Time box:** each sub-loop delivers within 45 min of wall clock (say so in its prompt):
   finished items with their verdict, unfinished ones as open with the last goal count, the
   obstacle and the next lever. Re-queue the open part as a narrower item; never wait on one
   sub-loop while an independent file is nameable (run them side by side, at most `nproc / 2`).
5. **Base-SL monitor** audits that sub-loop's *soft outputs* — its newly written
   `config/skills/creusot/references/learned-*.md` entries and any
   inferred/strengthened contracts — against `U` and `L` (§6): **PASS / CARVE-OUT /
   REJECT**.
6. **Gate B_top** (cross-unit discharge + tests) → **Gate C_top** (coverage / no-blend
   / guidance honored).
7. Divergence (a file won't reach DONE; a cross-unit `#[requires]` isn't established; an
   inferred contract contradicts the guidance; a Creusot limitation blocks "thorough")
   → a `gap-N` doc → re-plan. If the surprise is a **tooling gap or bug**, route it
   (§7) — never absorb it with a local workaround.
8. **Capitalize (§7):** the top agents distill role heuristics under
   `config/skills/creusot-monitoring/` (Gate-S gated); base agents continue to
   capitalize under `config/skills/creusot/`.
9. Crate `DONE` when every in-scope file is base-DONE, cross-unit contracts are
   consistent, the guidance is honored uniformly, and every base skill/inferred
   contract has a monitor verdict.

## 6. Monitoring `creusot-sl` (the `sl-monitoring-sl` discipline)
The base loop accumulates **soft outputs** — the `learned-*.md` skills (coordinator /
spec-author / annotator / verifier) and the contracts it *infers or strengthens* to
make a file discharge. These can be **coherent-and-wrong**: right for one file, wrong
against the guidance or another unit. The monitor squeezes each, from a base it does
not share:

- **Monitor's `U`** = the mission guidance (the skill/contract must not contradict it).
- **Monitor's `L`** = the `creusot-sl` oracle + cross-unit `cargo creusot`, as a
  differential comparator.
- **Classify and check** (Gate S):
  - **ignore-signal** ("treat signal X as noise" — e.g. *"ignore network-related
    preconditions"*): the **high-risk** kind. **Trigger test:** does the guidance make
    X relevant? Under *"disregard network access"* the skill **PASSES**; under a
    mission that required network specs the *same* skill over-reaches → **CARVE-OUT**
    deferring to the guidance clause. This is how guidance (`U`) governs the audit.
  - **defer-to-oracle** ("on case S take the oracle-sanctioned action"): consistent by
    construction. **Validity test:** does the base oracle actually distinguish S? PASS,
    or **prune** if spurious.
- **Verdicts:** PASS / CARVE-OUT / REJECT, each grounded in the guidance clause and
  traceable to the file/`gap-N` that surfaced it. The monitor **discriminates** —
  leaves defer-to-oracle skills untouched, flags only over-reaching ignore-signal
  skills. A monitor that flags everything or nothing is miscalibrated.
- A confirmed mismatch between the base loop's needs and the tool/guidance is **routed**
  (§7), not patched in place.

**Calibrate the loop's own coverage against ground truth.** Gate S audits the base loop's
*skills and inferred contracts* — but **not the coordinator's triage/coverage decisions**,
above all the fast-path that marks a file `TRIVIAL` and never spawns a sub-agent. Those
decisions need a separate check: when a **reference / gold annotation set** exists,
periodically **diff the loop's outputs against it**. A class of units the loop marked
done-or-trivial that the reference actually annotates is a *systematic triage error*, not
noise — feed it back as a carve-out to the triage rule (`references/learned-monitor.md`).
Concretely, the 241-file comparison against the Creusot reference suite
(`annotate/COMPARISON-SUMMARY.md`) found **188/241 faithful but ~44 `TRIVIAL` files missing
the reference's `#[logic]`/law/`impl` scaffolding**: the "no safety VC ⇒ trivial" triage was
sound for safety yet blind to spec-demonstration content. Ground-truth comparison is the
calibration that catches an over-broad triage; without it, a fast-path that silently drops a
whole category *looks like clean progress*.

## 7. Knowledge capitalization & routing — `config/skills/creusot-monitoring/`
Append-only, **Gate-S-gated** (per the `creusot-sl` skill (`config/skills/creusot-sl/SKILL.md`) §11 and `sl-monitoring-sl`).

**What the top agents learn** (under `references/`, drafted by the role, audited from a
disjoint base, committed only on PASS/CARVE-OUT, with provenance):
- `references/learned-coordinator.md` — mission-decomposition & guidance-interpretation
  heuristics; when to cut a crate plan.
- `references/learned-scheduler.md` — dependency-graph & leaf-first ordering heuristics
  (what makes a clean topo-order; when files are truly independent).
- `references/learned-monitor.md` — base-loop audit heuristics (which base skills tend
  to over-reach; ignore-signal vs defer-to-oracle tells).

**Routed surprises** (a surprise is *routed, never absorbed*):
- `getting-better/` — one `*.md` per **feature suggestion** that would make files easier
  to verify (a missing Creusot capability, a helpful lemma/template, a tooling
  improvement). Surfaced by any agent, confirmed by the monitor against `L` (the gap is
  real — `creusot-sl` actually couldn't express/discharge it).
- `bugs-to-report/` — one `*.md` per **bug to report** (Creusot/Why3/tooling
  misbehaviour) with a minimal reproducer, confirmed against `L`.

**Filename format (both dirs):** `YYYYMMDD-hhmm-simple-name.md` — e.g. today,
`20260616-1547-handle-reference.md`. Each file states: the trigger (file/`gap-N`), the
observed behaviour, the desired behaviour, and a minimal example.

## 8. Done criteria
Crate-level: every in-scope file base-DONE in leaf-first order; cross-unit
`#[requires]`/`#[ensures]` consistent and cross-unit-discharged; `cargo test` green;
the guidance honored uniformly (Gate C_top); every base skill/inferred contract has a
monitor verdict; routed suggestions/bugs filed; top-agent skills Gate-S-gated. **No
sub-loop's self-report ends the mission — only the top gates.**

## 9. Compliance & execution order
- **C1 Disjointness:** ✓ scheduler / base instances / monitor / coordinator hold four
  distinct `(U,L)` bases; the monitor's base is disjoint from the base loop it audits.
- **C2 Catchability:** ✓ local-but-global/guidance-wrong contracts → monitor;
  wrong-order verification → scheduler + cross-unit Gate B.
- **C3 Physical barriers:** ✓ monitor never reads base rationale; base barriers
  inherited intact.
- **C4 Gate-defined done:** ✓ crate done = all files base-DONE + cross-unit gates +
  guidance honored + monitor verdicts; no self-report.
- **Execution order:** **leaf-first** (topo-sorted call/module graph), propagating proven
  `#[ensures]` upward as `#[requires]`; parallelize only across files sharing no
  dependency; sequence the rest by mechanism reuse.

## Reference files
- `references/learned-coordinator.md`, `references/learned-scheduler.md`,
  `references/learned-monitor.md` — Gate-S-gated learned knowledge for the top agents.
- `getting-better/` — feature suggestions (`YYYYMMDD-hhmm-name.md`).
- `bugs-to-report/` — bug reports (`YYYYMMDD-hhmm-name.md`).
- Base loop: the `creusot-sl` skill (`config/skills/creusot-sl/SKILL.md`); base learning: `config/skills/creusot/`.
- Methodology: `sl-builder` (design), `sl-monitoring-sl` (monitor), `sl-internal`
  (theory), `sl-auditor` (audit an instance).

## ASSUMPTIONS & open questions
- `ASSUMPTION:` "in scope" = every `*.rs` under `dir yyy` that is part of crate `xxx`
  (excluding generated/vendored code); partial correctness unless the guidance asks for
  termination.
- **Guidance source.** **OPEN:** is the per-mission guidance free text the coordinator
  interprets at Gate A_top, or a structured policy file? It is the loop's `U` — it must
  be citable when the monitor carves a base skill.
- **Requirement per file.** **OPEN:** `creusot-sl`'s full form needs an external
  requirement per file; does the guidance supply it, or do docstrings / original
  contracts serve as ground truth? Without one, base files fall back to the lightweight
  variant.
- **Sub-agent fan-out.** **OPEN:** how many `creusot-sl` instances run in parallel
  (independent leaves), and what is the per-mission budget?
