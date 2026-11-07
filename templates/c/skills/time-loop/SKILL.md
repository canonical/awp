---
name: time-loop
description: >-
  A time-boxed META squeeze loop that drives the existing `/rmf XXX XXX-analysis`
  campaign to MAXIMIZE HIGH-VALUE VERIFIED COVERAGE on a target `XXX` (any source
  directory at repo root) within an `N`-hour wall-clock budget — NOT to maximize
  raw PROVED-cell count. It is the generalized, parameterized form of `meta-penguin`
  (which is this loop specialized to two Linux subsystems over 6h). It does not
  verify code itself; it ORCHESTRATES and MONITORS the downstream squeeze
  (`rmf-sl` code-blind risk authoring → `frama-c-launch` onboarding →
  `frama-c-monitoring`/`framac-sl` verification convergence), so it IS an
  `sl-monitoring-sl` instance: it judges the base loops' coverage claims and
  residue classifications against U and L only — never their rationale. THE CORE
  LOGIC is a per-cycle RESIDUE-CLASS TRIAGE — class A (tool / U-ceiling: SKIP,
  retry only if the toolchain was enriched), class B (BLOCKED crypto/entropy:
  SKIP), class C (unfinished-contract: a refutation probe would flip it — the ONLY
  class budget is spent on) — prioritized by RMF risk rank across TWO finding-bearing
  security planes: Plane W (Tier-1 untrusted-input RTE/memory-safety via WP) AND
  Plane H (Tier-3 authorization/integrity LOGIC via macsl HAPPY system properties —
  EoP/Spoofing/Tampering invariants; a driver-only HAPPY prop is class-C-not-done,
  the in-situ proof is the lever). By DEFAULT within budget the loop delivers the full
  VALUE ORDER — (1) finding-bearing class-C both planes, (2) rigor-completion (close
  remaining class-C even with no new counterexample expected), (3) scope every
  OUT-OF-PLANE residual (liveness/DoS — neither plane can express; route to a named
  model-checker/schedulability tool) — NONE of it gated on the user asking.
  There is no diminishing-returns stop: the loop ends only at the true terminus
  (every goal PROVEN, VIOLATION reported, or BUG IN FRAMA-C filed, and Gate T
  passes) and pauses at the deadline; never terminate early (Plane-W
  exhaustion while Plane-H leverage remains = plane-blindness; stop-and-ask whether to
  do rigor / out-of-plane = premature-convergence). Bounds: L = the
  Frama-C/WP machine verdicts (+ provers) + the macsl HAPPY in-situ verdict + the
  faithfulness oracle + the refutation probe; U = the code-blind XXX-analysis-rmf-report.md risk-ranked coverage target,
  bounded by Frama-C's capability ceiling (the moving frontier of L). Dominant
  enemy: EXEMPT-BUCKET RELABELING — a cycle reporting "exhaustive/converged" while
  parking hard in-scope class-C work as residual/PARSE-BLOCKED/COQ-NEEDED without
  its mandatory probe. Inherited invariants: pure WP, NO EVA (TCB-minimization);
  admit-free audited Coq; XXX/ pristine (faithfulness baseline); honest residuals;
  R5/Authorize PENDING (human AO signs, the loop never does). Use when asked to run
  an N-hour exhaustive `/time-loop XXX N` campaign, or to drive `/rmf` to value-
  maximizing convergence under a wall-clock budget.
---

# time-loop — an N-hour high-value-coverage squeeze over any target `XXX`

This is a **meta / monitoring** Squeeze Loop. The *base* loop is the existing two-phase
`/rmf XXX XXX-analysis` campaign (code-blind `rmf-sl` → code-aware Frama-C verification).
`time-loop` does not author contracts or risk reports; it **triages, ranks, drives, and monitors**
that base loop over an `N`-hour horizon, and is the disjoint actor that catches its dominant failure
(relabeling unfinished work as an exemption) **and** the second failure this loop adds budget-
discipline against (burning the clock re-grinding the Frama-C ceiling). It is the `sl-monitoring-sl`
meta-pattern instantiated, time-boxed, for any target. **`meta-penguin` is the worked Linux instance
of exactly this design** — consult it for a concrete activation.

## The campaign driver — read the RMF wording through this table

`/time-loop` drives the project's campaign driver: the `driver` key of `config/auto-wp.json`
(what `auto-wp.py --driver` records). The wording of this skill is written for `rmf` — `/rmf`, the
RMF report names, `RS#` and the risk levels — and every occurrence below is read through this table.
Without a `driver` key (a project generated before the driver existed), assume `rmf`.

| | `rmf` | `fips` |
|---|---|---|
| base command | `/rmf` | `/fips` |
| report | `XXX-analysis-rmf-report.md` | `XXX-analysis-fips-report.md` |
| gaps | `XXX-analysis-rmf-gaps.md` | `XXX-analysis-fips-gaps.md` |
| feedback | `XXX-analysis-monitor-feedback-NN.md` | `XXX-analysis-fips-feedback-NN.md` |
| linter | `bin/rmf-lint.sh` | `bin/fips-lint.sh` |
| ranked item and scale | `RS#`, risk `High`/`Moderate`/`Low` | `VO#`, priority `P1`/`P2`/`P3` |
| Plane W (WP) | Tier-1 untrusted-input `RS#` | `VO#` of class `zeroize`, `no-plain-ssp-out` |
| Plane H (macsl system properties) | Tier-3 authorization/integrity `RS#` | `VO#` of the six system-level classes of `fips-sl/references/area-properties.md` |
| outside both planes | — | `approved-only` (a call-graph check, not a WP proof) |
| terminus | Authorizing Official | the owner of the protected information, or the agency's responsible authority (Ann. 13) |

The driving loop itself is the same under both drivers: the same deadline and `time-loop.state`, the
same A/B/C residue triage, the same heartbeat, the same per-cycle checkpoint + commit + Monitor-style
feedback packet. Only the names, the ranking scale and the terminus change.

## 0. Deliverable & correctness
- **Deliverable:** the **whole in-scope code + its non-vacuous contracts PROVEN** — produced by
  repeatedly driving `/rmf XXX XXX-analysis` *continue-converge* cycles until **every** in-scope goal
  reaches exactly one of **three terminal statuses (§6): (1) PROVEN · (2) VIOLATION (a bug in the code,
  reported) · (3) BUG IN FRAMA-C (a true goal the tool cannot prove, diagnosed to a reproducer and
  filed)**. There is no fourth status: no "reviewed-careful", no "carried residue", no
  "diminishing-returns stop". **A re-run keeps the original deadline:** the deadline is fixed by the
  FIRST invocation (`deadline = start + N hours`, stored in `XXX-analysis-acsl/time-loop.state`); a later
  `/time-loop XXX N` on the same campaign, after a stop, a crash or a reboot, **reuses the stored start and
  deadline** and does not compute new ones — the `N` it is given is ignored when a state file exists. If
  the stored deadline has already passed, the run does the terminus step (§4 step 6: final or interim
  report) straight away and stops. A new budget needs `--fresh`, which starts a new campaign. Within that
  budget, `N` does not bound the *ambition*: when `/time-loop
  XXX N` fires you **continue driving** the highest-value un-PROVEN goal — you never report "converged"
  and then propose next targets (if a next target is nameable, that is the trigger to drive it now).
- **Value objective (load-bearing — NOT raw cell count):** maximize **security-relevant verified
  coverage** per unit budget across the **TWO security planes the RMF report flags**, neither of which
  is rigor-only:
  - **Plane W — Tier-1 untrusted-input RTE/memory-safety (WP).** A new WITNESSED unit on a high-risk
    parser/decoder/map/record/cert/syscall-boundary path.
  - **Plane H — Tier-3 authorization / integrity LOGIC (HAPPY / macsl system properties).** The
    STRIDE Spoofing/Elevation/Tampering invariants per the STRIDE→AC-6 row (permission-gating,
    privilege-monotonicity, ownership, run-queue/scheduler integrity). **An authorization-bypass or
    privilege-escalation is a SECURITY FINDING, not rigor** — Plane H ranks WITH Plane W, above any
    rigor-only closure. `macsl` is THE tool for these (NOT MetAcsl/HILARE).
  - **PICK THE CONTEXT THE THREAT-ROW NAMES — macsl has ~13, not 2.** Plane H is **NOT `\writing`/
    `\total` by default.** The full `\context(...)` menu (the single source of truth, regenerable via
    `macsl -macsl-list-contexts`) is `config/skills/frama-c-api/references/macsl-contexts.md`. Select by
    threat row: **EoP / authorization → `\authorized`**; **info-disclosure / confidentiality →
    `\noninterference \secret(…)`** (the plane WP CANNOT express); DoS / bounded-work → `\fuel`;
    concurrency / TOCTOU → `\guarded_by` / `\stable_check`; audit → `\tamper_evident`; RBAC → `\flow`;
    integrity → `\writing`; availability → `\total`. **A hand-rolled WP postcondition for an
    authorization gate is a SMELL when `\authorized` applies** — the `bpf_token_capable` / LSM-hook
    no-bypass props were hand-rolled *only* because the skills never surfaced `\authorized`; don't repeat
    that. If the chosen context parse-gates on the real TU, that is the full-TU wall (see `happy-kernel.md`),
    recorded as the class-A residue — not a reason to silently fall back to `\writing`.
  Findings rank above rigor — but rigor is **not opt-out**. The expected quality of an N-hour run is a
  VALUE ORDER delivered **by default within budget**: (1) finding-bearing class-C on both planes, then
  (2) **rigor-completion** — close the remaining class-C (interface contracts behind sound-precond-
  unexpressible residue, partial in-situ proofs) even when no new counterexample is expected; raising
  proof completeness on the flagged surface is part of the deliverable, then (2.5) **TCB-minimization**
  (below — shrink the trusted base by verifying the *bodies* of trusted in-scope leaves), then (3) **scope
  every out-of-plane residual** (liveness/DoS — neither plane can express) to a named tool and route it to
  the AO. None of (2)/(2.5)/(3) is gated on the user asking — asking is `coherent-and-wrong (f)`.
  - **TCB-minimization is load-bearing rigor-completion — the trusted base is SOFT and EXTENSIBLE, exactly
    like the Frama-C ceiling (§1).** A verification's TCB is every fact it *trusts instead of proves*: a
    callee interface `assigns`/`ensures` whose body is not verified; a Plane-H **establishing-oracle ghost
    model** (`sc_model_drop_complete` `ensures priv_dropped==1`) that MODELS a leaf primitive's effect; a
    frontend shim; a sound stub. **Each such element is either REDUCIBLE or IRREDUCIBLE, and that
    classification is probe-gated exactly like class-A-vs-C:**
    - **REDUCIBLE** = the trusted fact has an **in-scope body** that WP/macsl could verify (e.g.
      `sc_privs_drop` is snap-confine-private C; its ghost model can be REPLACED by proving the real body
      establishes the postcondition). A reducible element is **class-C rigor-completion — verify the body,
      moving the fact TRUSTED→PROVEN and shrinking the TCB.** Parking a reducible leaf as "trusted base" is
      the TCB analog of a class-C-relabeled-as-class-A (coherent-and-wrong i): a fixed-point declared where a
      lever exists. Writing the verification kit while a reducible leaf sits trusted is **premature terminus**.
    - **IRREDUCIBLE** = the trust is genuinely unavoidable *for this loop*: the foundational base (the
      prover, the compiler/ABI machdep, Frama-C's WP/cbits/why3 memory model + its libc ACSL specs), an
      **out-of-scope** body (Go, another declared-out-of-scope TU), or a true **external boundary** (a real
      libc/libcap syscall whose body is not source you verify). An irreducible element is a **declared,
      enumerated TCB entry** in the trusted-base appendix — not a residue, but *named*, so the reader sees
      exactly what is assumed. (A too-narrow `assigns` on an irreducible leaf is still a smuggled axiom —
      irreducible ≠ unchecked; it must be a faithful over-approximation.)
    **The terminus is NOT reached while a REDUCIBLE TCB element remains** (Gate S): the trusted-base ledger
    must show every entry is either PROVEN-away (body verified) or classified IRREDUCIBLE-with-reason. The
    kit's trusted-base appendix is the *irreducible* set only. **Prefer shrinking the TCB near the security
    core first** — a Plane-H establishing-oracle ghost for an authorization primitive (verify the real
    drop/gate body ⟹ the whole gate rests on proven code, not a model) outranks a peripheral logging stub.
  - **Driver ≠ in-situ (load-bearing for Plane H).** A HAPPY `\prop` verified only on a macsl
    *compliant driver* (an abstraction, e.g. `tier3_compliant.c`) is **NOT done** — it is a
    self-consistency check on the model. The deliverable is the **in-situ** proof on the real kernel
    TU; a driver-only HAPPY property is **class-C unfinished work** (its in-situ proof is the missing
    lever), never a closed item.
  - **Plane-H gate-completeness (load-bearing — the intra-plane dual of plane-blindness).** Plane H is
    covered only when **every DISTINCT authorization gate** the threat model surfaces is WITNESSED
    in-situ or probe-classified — not when *one* gate is proven. "Distinct" = guards a **different
    sensitive resource or actor** (e.g. generic-env vs locale-path vs catalog-path vs TZ-path), tested
    operationally: *would a single shared HAPPY `\prop` FAIL on one of the sites?* If yes, the sites are
    distinct gates and **each is its own deliverable**. A distinct authorization gate is **high-value by
    definition** (it ranks WITH Plane-W findings) and is therefore **NOT** subject to the (b)
    budget-burning cut — "low marginal value" / "the host TU has heavy RTE" is **never** a sanctioned
    reason to skip it (only a genuinely *redundant re-proof* of the same policy on another site is
    skippable, and the FAIL-test above is exactly what distinguishes the two). **Enumerate gates** by
    tracing the integrity/authority flag to its use-sites (each distinct guarded resource = one gate
    candidate); target the **sensitive OPERATION**, not a shared primitive — e.g. a gate where
    `getenv("LANG")` is read benignly even when secure must target the file-load it guards
    (`__map_file`), not `getenv`.
- **"Correct" (checkable), the standing gate set:**
  1. **Monotone coverage** — the WITNESSED-unit / WITNESSED-RS# counts never regress across cycles.
     **`verdicts.tsv` is the single source of truth; any interim/summary report is a DERIVED view whose
     every asserted count must equal the `grep -c`-derived ledger count (Gate R, §4.5). Hand-bumping one
     number while the prose drifts is a REJECT.**
  2. **Every residue carries its class (A/B/C) + its discriminating evidence:** a class-C residue
     carries its **refutation-probe verdict**; a class-A residue carries the **tool-limit evidence**
     (the lever/lemma actually attempted, why it is a `U=Frama-C` boundary not unfinished work); a
     class-B residue cites the BLOCKED category. **No bare relabel.**
  3. **Faithfulness** — `strip(//@) == pristine` for every annotated overlay copy.
  4. **Code-blindness** — the `rmf-sl` risk study reads no implementation source (auditor green).
  5. **No EVA, pure WP, no smuggled axioms** (`\trusted`/`Admitted`/lemma-as-axiom beyond recorded
     sound patches); **R5/Authorize PENDING** (human AO).
  6. **Plane-H coverage (HAPPY/macsl).** Every Tier-3 authorization/integrity-logic RS# (the EoP /
     STRIDE-S/E/T row) AND **every distinct authorization gate** under it (the gate-completeness clause
     above) maps to a HAPPY `\prop` that is either **WITNESSED IN-SITU** on the real TU or a
     probe-classified residue — *driver-only is class-C, not done; one-gate-done is not plane-done.*
     **A gate's "done" = the macsl-instrumented policy assertion (`..._meta`) discharges + its paired
     attack flips it — NOT the host function's full Plane-W RTE.** macsl instruments the specific
     call-site, whose assertion discharges from the *local* gate condition; record the host TU's
     surrounding RTE as a **separate Plane-W residue**, never as a reason the gate was skipped. Plane H
     carries its own **non-vacuity**: a paired attack suite (each attack violates exactly one `\prop`,
     macsl catches it) — a HAPPY policy that nothing can violate is vacuous and is a REJECT.
- **Terrain archetype: C (split planes) + monitoring meta-SL** (= meta-penguin §0). Plane 1 =
  code-blind RMF (archetype B, independence load-bearing); Plane 2 = code-aware Frama-C (external
  requirement = the report). The two must never blend.
- **Dominant coherent-and-wrong:** (a) **EXEMPT-BUCKET RELABELING** — a cycle reporting
  exhaustive/converged while hard in-scope **class-C** work was reclassified residual/PARSE-BLOCKED/
  COQ-NEEDED **without** the refutation probe; (b) **budget-burning** — spending cycles re-grinding
  class-A (tool ceiling) / class-B (BLOCKED) to look productive when the high-value class-C thread is
  exhausted (the diminishing-returns trap the triage exists to prevent); (c) an **endogenous U** —
  an RMF report contaminated by reading the implementation; (d) **PLANE-BLINDNESS** — terminating on
  Plane W (Tier-1 RTE) exhaustion while Plane H (Tier-3 HAPPY/authorization) leverage remains
  un-driven, i.e. treating the authorization-logic plane as out-of-scope rigor when an EoP property is
  a finding; (e) **DRIVER-FOR-IN-SITU BLEND** — a HAPPY `\prop` proven on the macsl abstraction
  reported as if proven on the shipped kernel; (f) **PREMATURE-CONVERGENCE / STOP-AND-ASK** — treating
  "no finding-bearing class-C left" as the terminus, or **asking the user whether to spend remaining
  budget on rigor-completion / on the out-of-plane residual, instead of just doing both by default**.
  Findings first, THEN rigor-completion, THEN scoped out-of-plane routing is the **expected quality of
  an N-hour run** — deliver it within budget; a menu is not a deliverable; (g) **OUT-OF-PLANE ABSORPTION**
  — a flagged risk that NEITHER plane can express (liveness/availability/DoS — see the residual class)
  silently counted as "covered/exhausted" instead of named, scoped to the right tool, and routed to the AO;
  (h) **SINGLE-GATE COMPLACENCY** (the intra-plane form of plane-blindness) — driving ONE HAPPY `\prop`
  and treating Plane H as exhausted while other tractable, **distinct** authorization gates remain
  un-driven, justified by a coordinator "low marginal value" / "complex host RTE" self-judgment. A
  distinct authorization gate (one whose policy would FAIL on the already-proven site) is high-value by
  definition and is **not** subject to the (b) budget cut; parking it is the same exempt-bucket relabel
  as (a), one plane down. (The discriminator: re-proving the *same* policy on a redundant site is
  correctly cut by (b); a gate on a *different sensitive resource* is not.)
  (i) **TCB-FIXED-POINT / TRUSTING-A-VERIFIABLE-BODY** — assembling the kit / declaring terminus while a
  **REDUCIBLE** trusted-base element (a callee `assigns`/`ensures`, or a Plane-H establishing-oracle ghost
  model, whose body is **in-scope C**) sits TRUSTED, when verifying that body would move it TRUSTED→PROVEN
  and shrink the TCB. The trusted base is soft/extensible (like the Frama-C ceiling); treating it as a fixed
  boundary is the exempt-bucket relabel one layer below class-A — a lever (verify the leaf body) declared
  absent where it exists. Especially acute at the **security core**: a gate proven only against a *ghost
  model* of its leaf primitive (`sc_privs_drop`) is weaker than one proven against the leaf's *verified
  body*; leaving the model in place when the body is verifiable is (i). (Discriminator: an IRREDUCIBLE leaf
  — foundational base, out-of-scope/Go body, real external syscall — is correctly a declared TCB entry, not
  (i); a leaf with an in-scope verifiable body parked as trusted IS (i).)
  (j) **RECORD-FROM-ARTIFACT / MONITOR OVER-CLAIM** — recording a closure/verdict (a class-C goal marked
  CLOSED/PROVEN, a CEILING confirmed) by **INFERRING from a mid-run on-disk ARTIFACT** — the overlay / session
  file a verifier sub-agent is still writing — **before that verifier has DELIVERED its final report**. A
  verdict may be recorded ONLY from (1) the verifier's DELIVERED final report, or (2) the coordinator's OWN
  independent re-run — NEVER from a premature peek at a partial artifact while the run is live. The observed
  relapse: a class-C goal was booked CLOSED off the overlay-file-on-disk, then the verifier's real report
  **REFUTED** it (the added contract closed ZERO goals). This is a **monitor-discipline break** — the
  monitor's whole job is to judge DELIVERED verdicts, not to front-run them from disk residue — caught by
  **Gate T item 6** (verdict-provenance, §3) and the §7 verdict-provenance stabilizer.

## 1. Bounds (the squeeze)
- **Upper bound `U` = the code-blind `XXX-analysis-rmf-report.md` risk-ranked coverage target,
  bounded by Frama-C's capability ceiling.** The report (authored exogenously by `rmf-sl`) fixes
  *what* must be covered and its risk ranking; Frama-C 32.1 (WP/ACSL + the sound cbits/why3 trusted
  base + any patched frontend) fixes *how much* of it is reachable. The ceiling is **soft and
  extensible** — a new shim, contract, or sound lemma raises it; the loop pushes against it and
  **retries class-A residues when the toolchain is enriched**, never treating today's ceiling as
  fixed.
- **Lower bound `L` = the Frama-C/WP machine verdicts (+ provers) over `XXX`'s source, the
  faithfulness oracle, and the refutation probe.** The hard, interpretation-free floor: (a) the
  **prover verdicts** (WP discharge via Alt-Ergo / Z3 / **audited admit-free Coq** — **NO EVA**, a
  TCB-minimization rule), (b) the **faithfulness oracle** (`strip(//@) == pristine`), (c) the
  **refutation probe** (supply the antecedent a residue points at, re-run; instant-Valid ⇒
  missing-hypothesis, not a tool limit), and (d) the **macsl HAPPY in-situ verdict + its attack-suite
  non-vacuity** (Plane H: the `\prop` discharges on the *real TU*, and each paired attack is caught —
  a driver-only or non-vacuous-failing HAPPY policy is not a floor). The provers + source + macsl
  refuse every faked claim.
- **`L` is a TWO-ORACLE squeeze — `L` emits the alarm set AND discharges it (load-bearing; the
  completeness half is easy to skip and its absence is silent).** WP `-wp-rte` is two distinct
  oracles and a campaign needs BOTH:
  - **Oracle A — deductive discharge (`-wp -wp-rte` per unit, its contract driven).** *Proves each
    alarm false.* This is the half (a)–(d) above describe. It is SOUND but it **never certifies the
    alarm set is COMPLETE**: an un-driven path or an input value no contract reaches **emits no PO at
    all**, and *the absence of a PO is not a proof of safety* — it is silence. A green Oracle-A pass
    answers "is every alarm I generated discharged?", NOT "did I generate every alarm?".
  - **Oracle B — formal-test emission (the nondet harness; the half that is easy to MISS).** *Emits
    the complete alarm set* by exercising the **real entry** over the **whole admissible input space at
    once**.
    1. **WP-over-nondet-harness (PRIMARY, pure WP).** Write a driver that builds the entry's inputs
       with `Frama_C_make_unknown` / `Frama_C_interval` / `Frama_C_nondet_*` constrained by a
       `requires` envelope = the **deployment admissible-input contract**, then analyze the entry's
       **body** under that envelope with `-wp -wp-rte`. WP discharges the RTE POs **for ALL inputs the
       nondet precondition admits**, not just the per-unit contract's — pure WP, **no EVA**. This is
       alarm-completeness over the admissible space.
       **VACUOUS-HARNESS TRAP (coherent-and-wrong h — the load-bearing Oracle-B gotcha; zk37-verified).**
       In modular WP, `-wp-fct driver` proves the driver's body under the **callees' contracts, not their
       bodies** — a contract-less entry is havoc, so a driver that merely *calls* the entry passes
       **VACUOUSLY**. Two ways to fall in: (i) no inlining at all; (ii) `-inline-calls=<X>` with the WRONG
       `X` — **`-inline-calls=F` inlines calls *TO* F (the callee), NOT calls *within* F**, so inlining the
       *driver* is a no-op. Concrete (zk37): `ft_msgq_put` → "2/2" both bare and with
       `-inline-calls=ft_msgq_put` (wrong dir), while the real `z_impl_k_msgq_put` body has **24** RTE goals.
       **THE FIX:** `-inline-calls=<the entry>` (the callee) so the driver's nondet `requires` flow into the
       body's POs — then `ft_msgq_put` emits all **24** (15 discharged, 9 = pre-ledgered cast-wall/swap_data
       GAP). **EVIDENCE GATE (mandatory before any Oracle-B GREEN):** the driver's emitted goal count on the
       entry MUST equal the entry's **direct `-wp-fct <entry>`** count. A driver matching the trivial-call
       count analyzed NOTHING → REJECT. *(Caveat: many syscall entries are THIN dispatchers whose
       direct count is genuinely small — e.g. `z_impl_k_condvar_signal`/`k_heap_alloc` = 2 entry-local, real
       alarms leaf-delegated to `sys_heap_*`/`z_unpend_*`; there a 2==2 match is FAITHFUL, and the leaf
       callees need their own harnesses. The gate is count==direct, NOT count>large.)*
       **NON-VACUITY MASKING (second gotcha):** a seeded out-of-contract input only witnesses non-vacuity if
       the goal it breaks is **PROVED in the compliant run**. If that goal is already in the carried residue
       (cast-wall/GAP Timeout), the attack is **masked** — same verdict either way, no discrimination (zk37
       `ft_msgq_put_ATTACK` = 15/24 = compliant, masked). And if the compliant count equals the envelope-FREE
       direct count, the envelope is **not load-bearing** (the body self-guards) — also no non-vacuity witness
       on that entry. A clean discriminating witness needs an entry with an **envelope-dependent provable
       goal** (the pilot `oracle_b_pilot.c`: in-envelope all-Valid, widen → `requires_envelope` Unproved).
       The harness's distinct value over a hand-written per-goal precond is that the envelope is ONE
       deployment-faithful space grounded in a concrete separated backing store (demonstrably satisfiable =
       not vacuous, demonstrably not-narrower = not a smuggled axiom), discharging the WHOLE alarm set at
       once rather than per-goal preconds tuned to land each.
    2. **Concrete corroboration (secondary, OUT of the proof TCB).** A `clang -fsanitize=…`
       UBSan/ASan run of the same harness on seeded boundary inputs — corroborates, never substitutes,
       the WP verdict; recorded as test evidence, not a discharge.
    3. **Coverage accounting.** Which entries have a nondet harness vs which are still per-contract
       only (the latter are NOT alarm-complete — log them, never count them as covered).
  - **Oracle-B non-vacuity (its own floor):** a seeded **out-of-envelope** input MUST raise an alarm
    (else the harness proves nothing), and the nondet `requires` envelope must be **no narrower than
    the deployment contract** — a too-tight envelope is the formal-test analog of a **smuggled axiom**
    (it "proves" safety by refusing to admit the dangerous inputs). The envelope is itself a `U`-bound
    artifact, reviewed disjointly.
- **The squeeze:** drive the WITNESSED set **UP toward the report's coverage target** (within the
  Frama-C ceiling), spending only on closable class-C residue, while the source + provers keep every
  step honest — and **close BOTH oracles**: Oracle B emits the complete alarm set over the admissible
  space, Oracle A discharges it. Done is gate-defined and budget-bounded — never self-declared.

## 2. Actors and their disjoint `(U,L)` pairs
The meta-loop **triages, drives, and monitors** the base `/rmf` loop from a disjoint base. (This is
meta-penguin §2 generalized; the **base-SL monitor + the triage** are the load-bearing additions.)

| Actor | Builds | U (above) | L (below) | Forbidden move | Must NOT see |
|---|---|---|---|---|---|
| **time-coordinator** | the N-hour schedule; the per-cycle **residue triage** (A/B/C) + value/exposure ranking; the coverage ledger + gate verdicts + the self-justification log | the report's coverage target + Frama-C's ceiling | the gate machine output (`verdicts.tsv`, prover logs, faithfulness diff) | edit source/ACSL; rubber-stamp; spend a cycle on class A/B while class-C-on-valued-surface remains; declare done while any exemption is un-probed | — |
| **risk-author** = `rmf-sl` (**code-blind**) | `XXX-analysis-rmf-report.md`, R1–R5, R5 PENDING | NIST RMF doctrine + the architectural threat model | `bin/rmf-lint.sh` (exit 0) + the code-blindness check | read the implementation; inflate scope | the implementation source |
| **onboarder/verifier** = `frama-c-launch` + `frama-c-monitoring`/`framac-sl` (Plane W) **+ `macsl`** (Plane H) | the build/onboarding context, ACSL contracts, WP convergence (W); **HAPPY `\prop` + its attack suite, driven IN-SITU on the real TU** (H) | the report's ranked scenarios + ACSL/HAPPY expressibility | WP discharge + macsl HAPPY in-situ verdict + the faithfulness gate | weaken a contract to land; classify a goal residual without the probe; touch the report; use EVA; **report a macsl DRIVER verdict as in-situ; use MetAcsl/HILARE for a HAPPY `\prop`** | the report's *rationale* (consumes only its ranking) |
| **base-SL monitor** = `sl-monitoring-sl` (the meta-loop's watching role) | per-classification verdicts on the base loop's coverage claims + **the A/B/C residue triage**; the Monitor packets keyed to RS# | `U_top` = the report target + Frama-C's ceiling (a "tool limit" must *be* a frontier, not laziness) | `L_top` = prover verdicts + the **refutation probe** (the A-vs-C discriminator), used as differential comparators | edit the base loop's work; accept an exemption without probe evidence; let a class-C residue be parked as class-A | the base loop's *account of why* it classified a goal |
| **probe** | one experiment, one recorded verdict (the refutation probe = the A↔C discriminator; the lever probe for PARSE-BLOCKED) | one design claim per probe | the tool's actual behaviour | implement a fix | — |

**Disjointness (C1):** `rmf-sl` holds doctrine + threat-model, never the code; the verifier holds the
report + WP, the report is exogenous to it; the monitor holds the ceiling + prover verdicts + the
probe and **never** the verifier's "I tried, it's hard" rationale; the coordinator holds the schedule
+ triage + gate output and **never** edits. **No actor relieves its own exemption:** a residue's
class (esp. the A-vs-C call) is set by the monitor's probe, from a base the verifier does not hold.

**Catchability (C2):**
- verifier's blind spot — *relabel a true-but-unproven goal as an acceptable "reviewed-careful/carried"
  residue to look done* → the monitor's mandatory **refutation probe + the 3-status gate** (it is PROVEN,
  a reported VIOLATION, or a FILED Frama-C bug — nothing else; an un-probed relabel ⇒ REJECT).
- coordinator's blind spot — *spin re-grinding a timing-out goal without advancing it* → the escalation
  ladder toward status 3 (name the obstacle → minimal reproducer → `no_ceiling_gate.py` → file) + the
  per-cycle self-justification (a cycle must either advance a goal toward PROVEN or advance the
  file-the-Frama-C-bug ladder — spinning that does neither is the budget-burn to catch).
- `rmf-sl`'s blind spot — *endogenous U* → the code-blindness auditor.

## 3. Gates
- **Gate A (editorial):** the coordinator judges each cycle's plan — the **triage verdict** (which
  class-C thread, ranked by RMF risk on attack surface; what is skipped as A/B and why) — against U.
  No source edit from a `DRAFT`. Amend/cut/sharpen, never rubber-stamp.
- **Gate B (machine):** for the cycle's targeted goals — WP **discharge** (pure WP, **no EVA**) and/or
  the **macsl HAPPY in-situ verdict + attack-suite non-vacuity**; the **faithfulness** gate; **no
  smuggled axioms**; the **monotone-coverage** invariant; `verdicts.tsv` updated; every residue row
  carries its class + discriminating evidence.
- **Gate C (coverage / no-blend / anti-relabel):** every targeted RS# maps to a WITNESSED proof **or**
  a probe-classified residue; the **proved theorem is the intended property** (non-vacuity — a
  mutation/attack violating the scenario is caught). **Non-vacuity has TWO independent oracles;
  `false_probe` alone is NOT enough (cycle-440):** an `ensures \false` that stays UNPROVED rules out
  *global* vacuity but NOT **path-local vacuity** — a frame/loop goal that discharges ONLY because an
  added invariant/precond made the relevant code (a loop body, a branch) DEAD. That "closure" proves
  nothing. **After ANY frame- or loop-goal closure, run `-wp-smoke-tests`: a Doomed `dead_code`/`dead_call`
  where the pristine unit smoked clean means the closure is VACUOUS — REJECT it** (the annotation is
  unsound, or the goal is genuinely status-3, not proven). A clean smoke run is the discriminator between a
  real proving-twin (class-C, drive it) and a vacuous false-twin (do not record it as PROVEN). **And the
  attack's PREMISE is itself falsifiable (cycle-443):** when you drop precond `P` to show goal `G` depends
  on it and `G` does NOT flip, that is evidence your *hypothesis was wrong* (`G` never rested on `P`), not
  that the attack under-reached — never premise a non-vacuity attack on an unverified arithmetic/bitwise
  claim (e.g. "a non-power-of-two size ⇒ OOB slot read", when `x & (size-1) ≤ size-1` holds for ALL sizes
  ≥ 1). The disjoint verifier is entitled to REFUTE the coordinator's load-bearing premise; a refuted
  premise, recorded, is a real deliverable, not a failed cycle. **No-blend, now across THREE separations:** the
  RMF plane ⊥ the Frama-C plane; **Plane W (WP RTE/functional) ⊥ Plane H (HAPPY authorization logic)**
  — a WP RTE proof never stands in for a HAPPY `\prop`; and **a macsl DRIVER verdict ⊥ an in-situ
  verdict** — a property proven on the abstraction never counts as proven on the shipped TU. **Every
  exemption is evidence-bearing** (class A: tool-limit lever/lemma attempted; class C: refutation
  probe; **driver-only HAPPY: the in-situ macsl attempt**) or it is a REJECT. **A class-A label is
  itself probe-gated** — the probe must have been *attempted and failed to flip* (else it is disguised
  class C). **Plane-H gate-enumeration is a Gate-C closure condition:** the cycle MUST enumerate the
  distinct authorization gates (trace the integrity/authority flag to its use-sites), and each maps to
  a WITNESSED-in-situ `\prop` or a probe-classified residue — an un-enumerated or undriven distinct gate
  is an open Gate-C item, exactly as an un-driven Plane-W unit is (coherent-and-wrong h).
- **Gate S (the terminus + stabilizer):** each cycle persists state and drives the highest-value
  unfinished goal. **DONE (the ONLY terminus) = every in-scope goal is in one of the three statuses:
  PROVEN · VIOLATION (reported) · BUG IN FRAMA-C (filed) (§6).** There is no "converged with carried
  residue", no "diminishing-returns stop", no "class A/B remain" terminus — a goal that is not PROVEN is
  either a code bug to report or a Frama-C bug to file, and until it is one of those the loop is NOT done.
  **The `N`-hour deadline and budget exhaustion PAUSE the loop, they do not finish it:** on `now >
  deadline` / budget out, persist state + emit an **interim** progress report (goals Proven / Violations
  reported / Frama-C bugs filed / goals still open with the next action for each) and RESUME on the next
  wake — never relabel an open goal to reach a fake terminus. **No stop-and-propose:** if you can name the
  next goal to drive, DRIVE it now; do not report "converged" and hand the user a to-do list. **A "BUG IN
  FRAMA-C" is UNWRITABLE by say-so (`no-ceiling.md`):** before filing status 3, run
  `config/skills/sl-internal/scripts/no_ceiling_gate.py <claim.json>` — a claim that does not PASS
  defaults back to unfinished work (it is really PROVEN-if-you-try-harder), so keep driving. On the true
  terminus, emit the **final report** (every goal's status; the reproducers filed; what remains only if it
  is genuinely OUT-OF-SCOPE-by-declaration) + the cumulative Monitor history. R5 PENDING. **Gate S DEFINES
  the terminus; Gate T (below) is the MECHANICAL checklist that must log PASS before any stop enacts it.**
- **Gate T — the PRE-STOP TERMINUS CHECKLIST (mechanical, mandatory before `ScheduleWakeup({ stop: true })`).**
  Gate S / §6 / the §7 stabilizers already forbid a premature terminus **in prose** — yet in ONE long campaign
  the loop still hit **THREE distinct premature-halt near-misses**, each caught only by luck/re-check. Prose
  alone is not enough. So the true-terminus stop (§6, Invocation reason (a)) is **UNREACHABLE** until EVERY
  item below has been **run THIS cycle and logged PASS in `time-loop.state`** with its command/evidence (not a
  bare "✓"). **A self-declared terminus that has not passed Gate-T is the premature-terminus loop-behaviour
  bug — it is NOT a stop.** Any single FAIL ⇒ you are not done: drive the exposed work this cycle and arm the
  next wake (never `stop: true`). Cross-refs, not restatements — each item points at the gate it mechanizes:
  1. **ENUMERATION-COMPLETE — `{in-scope .c} ∖ {covered} == ∅`, re-run THIS cycle (never cached).** Every
     in-scope `.c` file — **INCLUDING the ENCODE / serialize / output-sizing side (not just decode/parse),
     macro-instantiation units, thin wrappers, and every "trivial-looking 4-line" file** — is either
     **covered-by-driven-verdict** or **OUT-OF-SCOPE-BY-ROLE with a written reason**. "Looks trivial" / "macro
     only" / "wrapper" is **NOT a coverage class** — a file is covered only by a verdict or an explicit
     justified out-of-scope declaration. (Observed near-miss: a "trivial 4-line macro" file instantiated the
     encode-side serializers — the RS10 flagged untrusted-output-sizing surface — and hid a CWE-787 heap-OOB
     VIOLATION.) §8's "coverage as a fraction of the high-value surface" ranks *effort*; it is **NOT a licence
     to leave an in-scope file un-classified.** Under `--dir`, intersect with the subtree (Invocation §).
  2. **GOAL-STATUS-COMPLETE — no bare class-C, no CEILING-PENDING (§6 trichotomy).** Every open goal is
     EXACTLY one of: **PROVEN** · **VIOLATION-reported** (in found-issues.md) · **status-3 FILED** (with its
     ≤10-line non-proving twin + `no_ceiling_gate.py` PASS) · **OUT-OF-PLANE-routed** (named tool + AO, §4.1) ·
     **class-B BLOCKED** (RR#). A **bare class-C**, a **`CEILING-CLAIM (PENDING)`** (bundle-unattested class-A,
     §4.1), or any un-probed relabel is an OPEN goal ⇒ FAIL.
  3. **GATE-S TCB-CLEAN — no REDUCIBLE trusted-base entry (§0 tier 2.5, §6).** Re-scan
     `…-analysis-acsl/trusted-base.md`: every entry is PROVEN-away or IRREDUCIBLE-with-reason. A reducible leaf
     / transcription-faithfulness assumption / un-onboarded real TU is class-C rigor-completion ⇒ FAIL
     (coherent-and-wrong i).
  4. **TWO-ORACLE — discharge-complete ≠ alarm-complete (§1 two-oracle squeeze).** `…-kit/formal-tests.tsv`
     **EXISTS**, and **every in-scope Tier-1 untrusted-input entry** is Oracle-B-harnessed (a
     `Frama_C_make_unknown` nondet harness over the deployment envelope, satisfying the EVIDENCE-GATE
     `count == direct -wp-fct`, §1) **or** OUT-OF-SCOPE-declared. An entry with only an Oracle-A per-contract
     pass and NO nondet harness is a class-C completeness row ⇒ FAIL. (Observed near-miss: terminus declared on
     an Oracle-A all-green with **no `formal-tests.tsv` at all** — alarm-completeness never certified.)
  5. **GATE-R RECONCILED (§4.5).** The interim/summary report was REGENERATED from `verdicts.tsv` this cycle;
     every asserted count `== grep -c` ledger count; `git diff` on the report is empty except this cycle's
     legitimate additions; ALL VIOLATIONS are consolidated into `…-found-issues.md`. A report that changes on
     regeneration ⇒ FAIL.
  6. **VERDICT-PROVENANCE — every recorded verdict traces to a DELIVERED verifier report OR the coordinator's
     OWN re-run — NEVER a mid-run artifact (coherent-and-wrong j, §7 stabilizer).** No CLOSED/PROVEN/CEILING
     row may be recorded by inferring from a partial on-disk ARTIFACT (an overlay/session file a sub-agent is
     still writing) while its verifier is still running. (Observed near-miss: a class-C goal was recorded CLOSED
     off the overlay-file-on-disk *before* the verifier delivered — and the delivered report REFUTED it, the
     added contract closed ZERO goals.) A verdict whose provenance is a still-running verifier's disk snapshot
     ⇒ FAIL; re-record only from the delivered report or your own re-run.

  **Log the Gate-T run in `time-loop.state` (six PASS lines + evidence) as the immediate precondition of a
  true-terminus `ScheduleWakeup({ stop: true })`.** The **deadline** / **explicit-user-STOP** stops (Invocation
  reasons (b)/(c)) still emit an interim report but do **not** require Gate-T PASS — they **PAUSE**, they do not
  claim the terminus. The stop is UNREACHABLE (for reason (a)) until every Gate-T item logs PASS.

## 4. The N-hour loop (resumable, idempotent, deadline-aware) — THE CORE LOGIC IS STEP 1 (triage)
State lives in `XXX-analysis-acsl/time-loop.state` (campaign start, `deadline = start + N·3600 s`, the
unit/residue work-list with status + class, the next-wake time, cumulative coverage counts, the
per-cycle self-justification log). **Pinned lines** (`key=value`, one per line, epoch seconds from
`date +%s`; tests and resumes parse them, so never reword them): `start=<epoch>` and
`deadline=<epoch>` once, written on the first invocation and never changed; then **`wake=<epoch>`
appended as the first action of every wake** (heartbeat or report-driven), never rewritten or
removed; and each cycle's log entry starts `cycle <n>: ` (a space before the number). Free text goes
on other lines. Each wake:

0. **Reconcile (Phase-0, idempotent).** Load state; if a state file exists, keep its stored start and
   deadline (never recompute them from this invocation's `N`, §0). If `now > deadline` → terminus (step 6). Else
   reconcile the existing `/rmf` artifacts (report lint, overlay verdicts, gaps) exactly as the `/rmf`
   Phase-0 does, and load the current residue ledger from `XXX-analysis-rmf-gaps.md` /
   `XXX-analysis-found-issues.md`.
1. **TRIAGE (the load-bearing step) → Gate A.** Classify every open residue:
   - **Class A — tool / `U`-ceiling:** genuine Frama-C/prover limits (cbits/Zbits SMT incompleteness,
     a frontend parse wall, a model limitation). **Not unfinished work — a `U=Frama-C` boundary.**
     **SKIP.** Retry one *only* if the toolchain was enriched since it was last attempted (a new sound
     lemma/shim/model raised the ceiling). **MANDATORY GATE — class-A is UNWRITABLE by say-so
     (`no-ceiling.md`; recurred 5×):** before recording class-A, run
     `config/skills/sl-internal/scripts/no_ceiling_gate.py <claim.json>`. A claim that does not PASS
     **defaults to CLASS-C** — PASS requires all of: the actual VC dumped with its obstacle **named**
     (not "timeout"); a minimal ≤10-line twin that does **not** prove (a proving twin ⇒ class-C); the
     **WP→Coq escalation actually run** and attempted-**and-failed** (skipping it ⇒ class-C — Coq's
     `assumption`/frame tactics beat store-bloat); **not store-bloat** (proves-in-isolation ∧
     times-out-in-context ⇒ class-C); **and a DISJOINT attestation** (cross-provider judge
     `$(cat ~/.local-llm-machine-ip.txt)`, or the AO). Bundle-complete-but-unattested ⇒ `CEILING-CLAIM (PENDING)` — an open
     class-C row that **BLOCKS the terminus** (Gate S). "lever-attested" by the producer alone is
     exactly the say-so this gate refuses.
   - **Class B — BLOCKED:** crypto/entropy/side-channel/supply-chain. Residual-by-design, never WP.
     **SKIP** (it is a residual-risk RR#, the AO's terrain).
   - **OUT-OF-PLANE — neither plane can EXPRESS it:** a flagged property that is **safety-inexpressible**
     — **liveness / availability / DoS** (deadlock-freedom, wakeup-liveness, resource-bound/quota,
     schedulability). Plane W (WP) and Plane H (HAPPY) both prove *safety* ("a bad thing never happens");
     neither can prove *liveness* ("a good thing eventually happens"). **NOT class A** (not a Frama-C
     ceiling on an expressible goal — it is inexpressible in the safety planes) and **NOT covered**.
     The loop MUST **name the right technique** (a model-checker / schedulability analysis — e.g. TLA+ or
     a CBMC/Kani-style bounded check on the scheduler/sync state machine), **scope the effort**, and route
     it to the AO. Silently folding it into "exhausted" is coherent-and-wrong (g).
   - **Class C — unfinished contract work:** a residue a **refutation probe would flip** — needs a
     missing `\valid`/nonzero/length precondition, a callee/TCB interface contract, or a loop
     invariant/variant. **The ONLY class budget is spent on.** *Class C spans BOTH planes:* a Plane-W
     WP residue **and** a **Plane-H HAPPY property that is driver-only** (its in-situ proof on the real
     TU is the missing lever). The **HAPPY refutation probe**: run the `\prop` IN-SITU on the real TU
     (with the per-object request-scoped GLOBAL — a file-level `happy \prop` cannot name function
     params, so the in-situ form is a global the macsl policy reads); if it discharges, the
     driver-only label was class-C unfinished work (drive it). If macsl returns one of its *documented
     honest partials* — `\fuel` loop-bound or `\guarded_by` atomicity — that is a **CARVE-OUT to WP per
     use** (not a tool ceiling and not unfinished — a recorded macsl scope boundary).
     **A THIRD class-C subtype — the COMPLETENESS gap (Oracle-B-missing):** an in-scope Tier-1
     untrusted-input entry that has an Oracle-A per-contract discharge but **no nondet harness** is
     class-C unfinished work — the **WP-over-nondet-harness is the missing, closeable lever** (§1
     Oracle B). The probe here is *constructive*: write the `Frama_C_make_unknown` driver over the
     admissible-input envelope and run `-wp -wp-rte` on it; if it emits-and-discharges POs the
     per-contract pass never generated, the per-contract "covered" was incomplete (drive the harness).
     This is alarm-completeness, the half the deductive pass cannot supply — it ranks WITH
     finding-bearing class-C on the highest-exposure entries (a missing harness on a parser is a
     completeness hole exactly where a finding would hide).
   - **Spend in this VALUE ORDER, all by default within budget — never stop-and-ask between tiers:**
     1. **Finding-bearing class-C FIRST**, by RMF risk rank across BOTH planes — Plane W (untrusted-input
        parsers/decoders/map/record/cert/syscall paths) **and** Plane H (EoP/authorization invariants:
        permission-gating, privilege-monotonicity, ownership, scheduler integrity). A driver-only HAPPY
        property on a flagged scenario is finding-bearing (its in-situ proof is the lever).
     2. **THEN rigor-only class-C — by default, NOT opt-in.** When the finding-bearing surface is
        exhausted, the loop **continues** on the remaining class-C closures even though no new
        counterexample is expected: a cross-TCB **interface contract** that closes a sound-precond-
        unexpressible residue (e.g. the syscall-dispatch contract behind `z_mrsh_*`), completing a
        partial in-situ HAPPY proof, etc. Raising **proof completeness on the flagged surface is the
        expected quality of an N-hour run**, not a thing to ask permission for. (You only skip rigor if
        the *budget* is better spent on a still-open finding-bearing thread, or budget is out.)
     3. **THEN scope + route every OUT-OF-PLANE residual** (below) to a named technique. Do not leave it
        as a bare "AO terrain" flag.
   - **Terminus only when ALL of the following hold — and NEVER by stop-and-ask:** (i) no finding-bearing
     class-C on either plane; (ii) no rigor-only class-C left (closed, or budget genuinely better spent /
     exhausted, with that judgement logged); (iii) every out-of-plane residual is scoped to a named tool;
     **(iv) the trusted-base ledger contains NO REDUCIBLE entry — every entry is PROVEN-away or classified
     IRREDUCIBLE-with-reason (§0 tier 2.5, §6).** Stopping at (i) alone, or **asking the user whether to do
     the rigor / address the out-of-plane gap / reduce the TCB**, is **premature-convergence
     (coherent-and-wrong f)**, and stopping while (iv) is unmet is the **TCB-fixed-point (coherent-and-wrong
     i)** — both are the default quality, delivered, never prompted for. Plane-W exhaustion while Plane-H
     leverage remains is **plane-blindness (d)**. Do NOT manufacture work from class A/B. The coordinator
     judges this triage (Gate A) and logs the **self-justification** (tier + thread + plane chosen + why;
     what is genuinely exhausted + why).
   - **TCB-REDUCTION IS SELF-GENERATING — the loop asks itself "how to reduce the TCB?" EVERY cycle; the
     user must NEVER have to ask it.** Once finding-bearing and rigor-only class-C are exhausted, the loop's
     standing next-target generator is the trusted-base ledger itself: re-scan `…-analysis-acsl/trusted-base.md`
     (and every trusted callee `assigns`/`ensures`, every ghost model, every transcription-faithfulness
     assumption), pick the **highest-value REDUCIBLE entry security-core-first** (a leaf on the untrusted-input
     / authorization path before a peripheral one), and DRIVE its body-proof this cycle — moving it
     TRUSTED→PROVEN. A REDUCIBLE entry parked as "trusted base" is a nameable next target, so by Gate S its
     naming IS the trigger to drive it — the loop keeps sweeping reducible leaves until only IRREDUCIBLE ones
     remain. Enumerating the reduction levers and picking the most relevant is the loop's OWN job, done by
     default; a turn where the human had to ask "what's next / how to reduce the TCB" is a loop-behaviour bug.
     (Transcription-faithfulness — proofs run on `attacks/*.c` transcriptions rather than the pristine TU
     because of a `-nostdinc`/third-party-header wall — is itself a REDUCIBLE TCB element: the standing lever
     is to onboard the real TU via `frama-c-launch`, retiring the "transcription matches source" assumption.)
2. **Drive ONE targeted `/rmf XXX XXX-analysis` continue-converge cycle as a sub-agent** (the
   delegation barrier — the monitor sees the returned verdicts, never the sub-agent's rationale)
   scoped to the chosen class-C thread.
   **MANDATORY — NEVER VERIFY INLINE (the coordinator NEVER holds the pen; user directive 2026-08-15).**
   The per-cycle verification WORK — authoring the ACSL overlay, running `frama-c`/WP/macsl, the
   refutation probes, the smoke run, the faithfulness diff — is done **ONLY inside a spawned sub-agent**
   (`Agent`/`Task`), NEVER by the coordinator (time-coordinator) directly in its own turn. This is not a
   stylistic preference or a "when disjointness matters" judgment call — it is an ABSOLUTE hard rule:
   the whole `(U,L)` disjointness (C1) collapses the moment the coordinator both authors the proof and
   judges it, because the monitor can no longer be a disjoint actor over work it produced itself. A cycle
   in which the coordinator edits a `units/*.c`, invokes `frama-c`, or reads a prover verdict off its own
   run is a **loop-behaviour bug** — the same class as skipping the heartbeat. The coordinator's ONLY
   moves are: triage (Gate A) → **spawn the verifier sub-agent** with the target + envelope → yield until
   its DELIVERED report → monitor/record that report (§3–§5, verdict-provenance §7) → checkpoint → arm
   the next wake. If you catch yourself about to run `frama-c` or Write a `units/*.c` file yourself,
   STOP: that is the relapse — spawn the sub-agent to do it instead. (The sub-agent may itself be a
   `fork` that inherits context, or a fresh general-purpose/verifier agent; either way the authoring +
   the prover invocation happen in the sub-agent, and the coordinator consumes only the delivered
   verdict — never a mid-run artifact.)
   **TIME BOX — every verifier delivers within 45 min of wall clock (default; state it in its prompt).**
   One hard function must never hold the campaign (observed: a single verifier ground on `huft_build`
   for 5 h while the coordinator recorded "still running; nothing recorded" at every wake). At the box
   the verifier STOPS and DELIVERS what it has: each finished function with its verdict, each unfinished
   one as `RESIDUE(C)` with its last `valid/total` goal count, the obstacle, and the next lever. The
   coordinator records that report and re-queues the residue as a fresh, narrower thread (§4 triage),
   rather than letting the same verifier run on. A verifier still running 15 min past its box is stopped
   (`TaskStop`) and its thread re-spawned narrower.
   **PARALLEL — never wait on one verifier while a disjoint target is nameable.** Run verifiers on
   independent units side by side, but keep the machine's load below `nproc`: at most `nproc / 2`
   concurrent verifiers (solver timeouts under overload are flaky verdicts, not residue).
   **BUILD IN A COPY — the code under study `XXX/` is read-only, for builds too.** Never run
   `configure`, `make`, a compiler, `cargo` or any tool that writes inside `XXX/` (object files, a
   regenerated `Cargo.lock`, `config.status`); copy it first (`cp -a XXX build_XXX-analysis/…`) and
   build there. Check `git -C XXX status --short` (or the checksum manifest) is still empty after any
   build step.
   The sub-agent runs the base `/rmf` Phase-2: author the missing
   contract, WP, **refutation-probe every non-discharged goal**, escalate probe-confirmed true-but-
   hard goals to **audited admit-free Coq** (NO EVA) before tagging residue. **For a Plane-H thread:**
   author/extend the HAPPY `\prop` and drive it **in-situ** with `macsl` — `frama-c -no-autoload-plugins
   -load-module <macsl>/macsl.cmxs -macsl -wp -wp-rte ...` (`-no-autoload-plugins` because stock MetAcsl
   clashes with macsl on `\prop`); the policy reads a **request-scoped GLOBAL** (params are unnameable
   in a file-level `happy \prop`); `\postcond` binds no `\result`. Pair each `\prop` with its attack
   variant (non-vacuity). Carve `\fuel`/`\guarded_by` partials to WP per use. NEVER MetAcsl/HILARE.
3. **Monitor (`sl-monitoring-sl`).** Judge this cycle's classifications against `U_top`/`L_top` only:
   **PASS** (a WITNESSED proof, or a residue with a passing probe of the right class) · **CARVE-OUT**
   (a claim over-/under-reaching → narrow, cite the clause) · **REJECT/loud-fail** (an un-probed
   exemption, a class-C residue parked as class-A, a faithfulness break, a coverage regression, an
   endogenous-U leak, a smuggled axiom, or **any EVA use**) → discard, gap doc, re-plan.
4. **Record the value delta** — new class-C closures + which attack surface they cover (NOT raw cell
   count). Emit `XXX-analysis-monitor-feedback-NN.md` (next index) keyed to RS#/CTL#/SA# **only on a
   verdict delta** (no flat cycles); scenario-keyed control-effectiveness signal **only** (no proof
   internals — keeps the next code-blind `rmf-sl` re-run exogenous).
5. **Gates B/C/S → checkpoint (commit + push) + persist.** Update `verdicts.tsv`, the consolidated
   gaps/found-issues, the coverage ledger, and `time-loop.state`. **This IS a crash-safe checkpoint:**
   **invoking `/time-loop` is the user's standing request to commit and push to `origin` at every
   cycle boundary**: do it without asking, and do not skip it on the general rule of committing only
   when asked (a run with no pushed commit per cycle is a loop-behaviour bug; the level 3 tests check
   it). Commit + push every cycle (rebase-before-push; never stage SMT caches `.lia/.nia.cache`; keep
   `XXX/` pristine; kill stray solver/`verify.sh` processes you spawned). Never clobber a committed
   artifact (full redo only under `--fresh`). **RE-ARM the self-firing `ScheduleWakeup`** (the same
   `delaySeconds: 120, prompt: "/time-loop XXX N"` call from Invocation) so the heartbeat persists to the
   next cycle — unless this cycle reached the terminus (§6) or `now > deadline`, in which case call
   `ScheduleWakeup({ stop: true })` instead. Reserve the last ~15–20 min for the terminus.
   - **Gate R — REPORT/LEDGER RECONCILIATION (mandatory before every push; the anti-drift gate).**
     `verdicts.tsv` is the SINGLE SOURCE OF TRUTH; any interim/progress/summary report is a **derived
     view** that must be **MECHANICALLY REGENERATED** from the ledger every cycle — **never hand-bump one
     number (e.g. the `+N` headline) while its prose sections drift.** The failure this gate exists to
     catch (observed 2026-07-18): the report's flagged-hazards / self-overturn / area / unit counts and
     lists were last refreshed N cycles ago, only the headline `+N` was `sed`-bumped, so the report
     silently contradicted the ledger (said "2 flagged hazards" while `verdicts.tsv` recorded 3; a
     just-witnessed unit was in the ledger but absent from the report; the hand-maintained "+136" had
     drifted from the true computed 152). **The mechanism (mandatory, not optional):** the summary report
     MUST be produced by a **checked-in generator script** (`XXX-analysis/gen-interim-report.py` or
     equivalent) that PARSES `verdicts.tsv` and COMPUTES every count + the per-area unit table. All
     row-derivable facts (total WITNESSED units, per-subsystem coverage + the unit list, distinct
     flagged-hazard functions, active-vs-overturned CLASS-A status rows, duplicate detection) are COMPUTED
     by the script and are authoritative; the small residue of genuinely-editorial facts (banked-lever
     names, self-overturn list) is a clearly-LABELLED "curated" section kept minimal. **Before `git
     push`:** re-run the generator, overwrite the report, and confirm `git diff` on the report is empty
     *except* for content the current cycle legitimately added — a report that changes when regenerated
     was STALE, which is a **push-blocking REJECT** until reconciled. The generator itself must key
     WITNESSED strictly on the STATUS column (`WITNESSED` or `NN/NN`) — **never** infer from the
     description prose (a CLASS-A row whose text says "NOT WITNESSED" or "OVERTURNS ... class-A" must NOT
     be counted; a later WITNESSED row for the same `(area,fn)` means an earlier CLASS-A was OVERTURNED),
     and must **dedup by `(area, function)`** so a re-proposed duplicate is counted once and surfaced.
     (Dedup sub-case: a verifier sub-agent's own novelty check must likewise grep the ledger by **function
     name**, `grep -icE '\bFN\b' verdicts.tsv`, NOT by unit filename — the same function under a different
     filename prefix is still a duplicate and is NOT counted.)
   - **Gate ND — CUMULATIVE-ARTIFACT NON-DESTRUCTION / APPEND-ONLY (mandatory before every push; the
     anti-clobber gate; observed clobber 2026-08-15 destroyed FI-7…FI-23).** Every **cumulative append-only
     artifact** — `…-found-issues.md` (the finding ledger FI-1…FI-N), `verdicts.tsv`, `time-loop.state`, the
     trusted-base ledger — is a **monotone log: prior rows/findings are NEVER lost, only appended-to or
     surgically Edited.** Two mechanical rules, both hard:
     1. **NEVER recreate a cumulative artifact with a whole-file `Write` (it OVERWRITES).** Add to it with a
        shell append (`cat >> file`, `printf … >> file`) or a targeted `Edit` on the exact old→new hunk —
        NEVER `Write file` on a path that already exists. If you believe the file is new, **prove it with an
        ABSOLUTE-PATH check that is immune to `cd`** — `git ls-files --error-unmatch <path>` (exit 0 ⇒ it is
        tracked ⇒ it EXISTS ⇒ append, do not Write), or `test -f "$PWD/<abs path>"`. **A bare `ls
        <relative>/*glob*` AFTER a `cd` in the same compound command is a FALSE-NEGATIVE trap** — the `cd`
        shifts the directory so the glob looks in the wrong place and reports "none", and you then Write-clobber
        a file that was there all along (exactly the 2026-08-15 root cause: `cd linux-sec-analysis && … ls
        linux-sec-analysis/*found-issues*` searched `linux-sec-analysis/linux-sec-analysis/…`). Use absolute
        paths for existence checks, or `git ls-files`.
     2. **Pre-push NON-DESTRUCTION check (push-blocking REJECT):** for every cumulative artifact this cycle
        touched, run `git diff --stat <artifact>` (staged) and confirm it is **net-additive** — insertions
        for this cycle's new row/finding, and deletions ONLY for a deliberate, named surgical edit of an
        existing entry (an overturn/correction you can point at). **A large deletion count / a drop in the
        FI-count or ledger row-count / any prior finding vanished = a CLOBBER ⇒ do NOT push. Restore the
        artifact from git first** (`git show HEAD:<path> > <path>` or `git checkout HEAD -- <path>`), then
        **re-apply your intended change by APPEND** and re-run the check. (Mechanical count invariants:
        `grep -c '^## FI-' found-issues.md` never decreases across cycles; `grep -c … verdicts.tsv` monotone —
        this is the finding-ledger analog of the monotone-coverage invariant, §0.1.) A cycle that shrank a
        cumulative artifact and pushed anyway is the **cumulative-artifact-clobber loop-behaviour bug** — the
        same severity class as skipping the heartbeat or recording from a mid-run artifact.
6. **Terminus / pause.** If the whole in-scope goal set is PROVEN / VIOLATION-reported / FRAMA-C-bug-filed
   (§6), emit the **final report per plane** (Plane W + Plane H goals PROVEN in-situ; VIOLATIONS with
   triggers; the filed Frama-C-bug reproducers; anything OUT-OF-SCOPE-by-declaration) + the cumulative
   Monitor history. Otherwise — deadline hit / budget out with goals still open — this is a **PAUSE, not a
   terminus**: emit an *interim* progress report (per-goal status + the next action for each open goal),
   persist state, and RESUME on the next wake. **Never emit "converged, next budget should target …": if
   you can name the next goal, drive it (do not stop-and-propose).** R5/Authorize PENDING — the human AO.
   **Report file:** the final or interim report is written to `XXX.md` in the project root, next to
   `XXX/` (`/time-loop toto 72` → `toto.md`). When `XXX` is a path, the file name uses the same root-safe
   slug as the artifact prefix (`zephyr/kernel` → `zephyr-kernel.md`), so the report is never written
   inside the source tree. Each new report replaces the previous one in that file; git history keeps the
   earlier versions.

## 5. Executable oracle setup
`L` is invoked as the base campaign's `XXX-analysis-acsl/verify.sh` (or the `--linux` generated
`<adir>/verify.sh`) → per-unit verdict; the **faithfulness** oracle
`diff <(sed '/^[[:space:]]*\/\/@/d' <annotated>) <pristine>`; the **refutation/lever** probes (re-run
with the supplied antecedent / applied lever); and the **Plane-H macsl HAPPY oracle** — `frama-c
-no-autoload-plugins -load-module <macsl>/macsl.cmxs -macsl -wp -wp-rte <real TU>` returning the
`\prop` discharge IN-SITU (not on a driver) plus the attack-suite catch. A "verdict" is the per-goal
WP discharge status + the per-`\prop` `HAPPY-WITNESSED(in-situ)|HAPPY-DRIVER-ONLY(class-C)|RESIDUE` row
+ the per-unit `VERIFIED|PARSE-BLOCKED|RESIDUE(class)` row. **`verdicts.tsv` schema (pinned;
`bin/crosswalk-gen.sh` and the tests read it by column name):** tab-separated, first line the header
`unit	SA#	function	verdict	goals	notes`, one row per unit or per function. `verdict` is one of
`VERIFIED` (every goal of the row Valid), `PARSE-BLOCKED`, `RESIDUE(A)`, `RESIDUE(B)`, `RESIDUE(C)`;
`goals` is `<valid>/<total>` for that row (e.g. `131/136`), or empty when WP did not run; `SA#` names
the code-blind report's assets the row covers (`SA1/SA3`), or `-`. Never rename a column or add a
status word; put everything else in `notes`. **NO EVA** — every Plane-W verdict is pure
WP+SMT (+ audited admit-free Coq); Plane-H is macsl (never MetAcsl/HILARE). **Pilot first** is already
done by the base `/rmf` campaign (its smoke proof); time-loop reconciles that state rather than
re-piloting.

## 6. Done criteria (gate-defined, never self-declared) — DONE = whole code + non-vacuous contracts PROVEN (3 statuses only)
The terminus DELIVERABLE is a **verification kit** (the standard verification-kit shape), NOT a goal count.
**Naming conventions for the kit and any report (MANDATORY):** (1) the methodology tagline is written
positively and **target-conditionally** — **"PURE WP and MACSL"** ONLY when a macsl/HAPPY Plane-H
property was actually driven in-situ on this target (Plane H live), else **"PURE WP"** alone (Plane H
N/A or not exercised — e.g. a target with no in-process authorization gate); **never** "PURE WP, NO EVA"
as the headline (the positive form already implies no EVA, which the gates still enforce). Do not
advertise macsl on a target where macsl never fired. (2) **No vendor name
in a kit** — describe the kit purely as a "verification kit" / by its section structure
(scope+config · property→CWE→coverage · reviewed-residue ledger · trusted-base/deployment appendix);
do **not** write "TrustInSoft", "TIS", "tis-interpreter", or "PolarSSL-kit".
**DONE = the whole code and its non-vacuous contracts are PROVEN.** Every goal (each `-wp-rte` PO and
each macsl `\prop` goal on every in-scope function, under non-vacuous contracts) has EXACTLY ONE of
**three** terminal statuses — there is NO fourth:
1. **PROVEN** — the machine discharged it (WP `Valid` / macsl witnessed in-situ). This is the target
   state for every goal.
2. **VIOLATION** — the goal is FALSE: a real **bug in the code**. Report it in
   `XXX-analysis-found-issues.md` with the concrete counterexample / trigger. A Violation is a finding to
   surface, never a reason to stop working the rest of the surface.
3. **BUG IN FRAMA-C** — the goal is TRUE (non-vacuous, entailed) yet Frama-C cannot prove it. By
   Curry–Howard a true entailed goal HAS a proof; if WP/macsl cannot produce one, that is a **Frama-C
   defect** (incompleteness, a frame/store-bloat gap, a macsl scope/granularity gap, a frontend wall) —
   DIAGNOSE it to a minimal reproducer and FILE it under `bugs-to-report/` (e.g. `wp-collapse-frame`).
   Filing the reproducer IS the completing work; a filed Frama-C bug is a finished goal.

**DISCRIMINATOR — "WP cannot prove goal X" is a TRICHOTOMY, never *automatically* status-3 (cycle-441,
recurred).** Before tagging any un-discharged goal, decide WHICH of the three it is by asking *why* WP
failed — status-3 is the RAREST answer, not the default:
- **status-3 (BUG IN FRAMA-C)** ⟺ the goal is **TRUE and ENTAILED** by the current hypotheses, yet WP
  cannot produce the proof (a frame-VC generation gap; store-bloat that Coq *also* cannot beat; a
  frontend/`calls`-placement wall). ONLY here is filing the completing work — and only after the
  `no_ceiling_gate` (a proving twin ⇒ it was class-C).
- **class-C (missing precondition)** ⟺ the goal is **NOT entailed** by the current contract; it becomes
  provable once a *faithful* missing hypothesis is supplied (a `\valid`/length/nonzero precond, a callee
  contract, an upstream invariant). The refutation probe FLIPS it. Unfinished work — supply the lever or
  name it; do NOT file it as a Frama-C bug.
- **VIOLATION** ⟺ the goal is **FALSE** with a reachable trigger. Report it.
The classic trap (seen twice): an unbounded `int` accumulation emits a signed-overflow alarm. That goal is
not TRUE without a bound, so it is **class-C** (missing the upstream total-size bound) or a **VIOLATION**
(if the overflow is reachable) — it is **NEVER status-3**, because WP is *correct* to refuse a non-entailed
goal. Mislabeling non-entailment as a Frama-C bug is the anti-relabel failure one level up, and the monitor
REJECTS it.

**The old "fourth-status" escape hatches are ABOLISHED — there is NO `REVIEWED-CAREFUL`, NO
`CARRIED-to-trusted-base-as-acceptable`, NO `class-A tool ceiling we accept`, NO `diminishing-returns
stop`, NO `next-budget hand-off`.** A goal you "reviewed by hand and believe is fine" is not a status:
either PROVE it (status 1) or, if it is true and the machine still cannot, FILE the Frama-C bug
(status 3). Hand-waving, "carried residue", and "reviewed-careful" are REJECTS. (Genuinely
non-WP/macsl-expressible matter — crypto-primitive *correctness*, liveness/availability/DoS — is not a
*contract* and carries no status: it is declared **OUT-OF-SCOPE** in the scope statement and routed to
the right tool. That is a scoping decision made up front, not a residue produced at the end.) The kit
ships: §scope+config, §property→CWE→coverage, §reviewed-residue ledger, §trusted-base/deployment appendix
(`zk37-verification-kit.md` is the worked instance). **Per-loop ownership:** `rmf-sl`/`ebios-sl` authors the
SCOPE + CWE/threat table **code-blind** (deployment preconditions are *risk decisions*, exogenous — must NOT
see the ledger); `frama-c-monitoring` owns the ALARM SET + DISCHARGE (emits every un-discharged PO, drives
class-C, *proposes* class+justification, never signs REVIEWED-FALSE); `time-loop` owns the LEDGER + TERMINUS
(computes closure, assembles the kit, routes every REVIEWED-FALSE to a disjoint reviewer / the AO).

**TCB-minimization is a CLOSURE condition (§0 tier 2.5) — the trusted-base appendix ships the IRREDUCIBLE
set only.** Before terminus, `time-loop` enumerates the TCB (every trusted callee `assigns`/`ensures`, every
Plane-H establishing-oracle ghost model, every shim/stub) and tags each REDUCIBLE (in-scope C body →
verifiable) or IRREDUCIBLE (foundational base / out-of-scope body / real external syscall, with the reason).
**A REDUCIBLE entry BLOCKS the terminus** — it is class-C rigor-completion (verify the body, PROVEN-away),
not a trusted-base entry; assembling the kit with it still trusted is coherent-and-wrong (i). The kit's
`§trusted-base/deployment appendix` lists **only the IRREDUCIBLE entries**, each named with its
irreducibility reason (so the reader sees exactly what is assumed and *why it cannot be verified in this
scope*). Drive TCB-reduction security-core-first (a leaf under an authorization gate before a logging stub).
The trusted-base ledger (`…-analysis-acsl/trusted-base.md`) records, per entry: the trusted fact · REDUCIBLE
(→ the verifying-unit, then its PROVEN status) or IRREDUCIBLE(reason) · faithfulness of the `assigns`
(non-vacuity — a too-narrow assigns is a smuggled axiom even on an irreducible leaf).

**Closure requires BOTH oracles (§1 two-oracle squeeze) — discharge-complete is NOT alarm-complete.** A
ledger where every *generated* PO is DISCHARGED/REVIEWED-FALSE/CARRIED is only **discharge-complete** — it
answers "every alarm I emitted is resolved." Closure additionally requires **alarm-completeness**: for every
Tier-1 untrusted-input entry in scope, the alarm set was **emitted by Oracle B** (a WP-over-nondet-harness
over the deployment admissible-input envelope — §1), not merely by the entry's hand-written contract. An
in-scope entry that has **only** an Oracle-A per-contract pass and **no nondet harness** is **NOT covered** —
it is a **class-C completeness row** (the harness is the missing, closeable lever; build it), and a class-C
row blocks closure. The kit therefore ships `…-kit/formal-tests.tsv` (one row per entry: harness path ·
admissible envelope · Oracle-B WP verdict · non-vacuity seed caught Y/N · UBSan corroboration) alongside the
reviewed-alarms ledger; an entry absent from BOTH the harness table and the OUT-OF-SCOPE statement is the
silent-completeness-gap coherent-and-wrong. (`frama-c-monitoring` builds the harnesses + runs Oracle B;
`rmf-sl`/`ebios-sl` authors the admissible-input envelope **code-blind**, as a deployment-contract risk
decision; `time-loop` checks every in-scope Tier-1 entry is harnessed-or-OUT-OF-SCOPE before declaring the
ledger CLOSED.)

Every reachable in-scope goal is **PROVEN**, a reported **VIOLATION**, or a filed **BUG IN FRAMA-C**;
the coverage ledger is complete; Gates B/C green; monotone coverage held; code-blind barrier intact; no
EVA, no smuggled axioms; R5 PENDING. **The campaign is DONE only when every in-scope goal has reached one
of the three statuses — nothing else counts as done — and that terminus is enacted only after the mechanical
Gate T (§3) logs all six PASS (a self-declared terminus that skipped Gate-T is the premature-terminus bug).** The `N`-hour deadline and budget exhaustion are
**hard interrupts that PAUSE the loop, not a done-state**: on a pause you persist state + emit an interim
progress report and RESUME from the checkpoint on the next wake — you do NOT declare convergence or a
"diminishing-returns terminus" while any goal is still un-PROVEN/un-reported/un-filed. **There is no
stop-and-propose.** When `/time-loop XXX N` fires and the highest-value unfinished goal is identifiable,
**DRIVE it this cycle** — never emit "the campaign has converged" followed by "the next budget's natural
targets are …". If you can name the next target, that naming IS the trigger to do it now. The only report
that says "done" is the one where the whole in-scope goal set is Proven / Violation-reported /
Frama-C-bug-filed.

## 7. Stabilizers engaged
- **Anti-relabel (load-bearing):** every residue is class-tagged + evidence-bearing — class-C carries
  a passing refutation probe, class-A carries an attempted-and-failed lever/lemma; an un-probed
  exemption or a class-C-parked-as-class-A is a REJECT. *A principle satisfiable by relabeling is not
  enforced.*
- **No soft residue / no stop-and-propose (the terminus discipline):** the loop keeps driving until every
  in-scope goal is PROVEN, a reported VIOLATION, or a filed BUG IN FRAMA-C (§6). It NEVER stops at a
  "diminishing-returns" / "converged with carried residue" state, and it NEVER reports "done, here are the
  next targets" — if a next target is nameable, it is driven this cycle. Budget is still ordered (findings
  first, then the rest of the un-PROVEN surface), but "low marginal value" is never a licence to leave a
  goal un-PROVEN-and-un-filed: park it only by PROVING it or FILING the Frama-C bug. Re-grinding a claim
  that keeps timing out is fine ONLY as the escalation ladder toward status 3 (name the obstacle → minimal
  reproducer → `no_ceiling_gate.py` → file) — spinning without advancing that ladder is the budget-burn to
  avoid.
- **CHAIN-WITHIN-TURN — a recorded checkpoint is NOT a pausing point (background-orchestration discipline;
  cycle-448 relapse).** When cycles run as background sub-agents, the flow is: scout → spawn verifier →
  yield (async, unavoidable) → completion-notification re-invokes you → monitor + record → **immediately
  scout + spawn the NEXT cycle in the SAME turn** → then re-arm the watchdog → yield. **The ONLY legitimate
  yield is while a spawned verifier is actively running.** The gap between *recording* cycle N and *spawning*
  cycle N+1 is NOT a place to yield — there is nothing to wait for, and a nameable next target means you
  MUST spawn it now (§0, Gate S). Ending a turn with a status summary that *names* the next target/direction
  ("next wake steers toward …", "next up is …") but does not spawn it IS stop-and-propose (coherent-and-wrong
  f) wearing a watchdog costume — the naming is the trigger to spawn, not a to-do note. Re-arming the
  fallback heartbeat is a crash-survival backstop, never the mechanism that advances a nameable cycle.
- **A "CONTINUE" / SINGLE-CYCLE USER INSTRUCTION DOES NOT CAP THE CHAIN, AND A COMPLETED-CYCLE REPORT MUST
  NEVER END WITH AN INVITATION TO RESUME (cycle-633 relapse, 2026-07-31).** When a human says "continue",
  "continue with cycle-N", "do the next one", or resumes the loop in any bounded-sounding phrasing, that is a
  RESUME of the autonomous loop, **not a one-shot**: after completing cycle N you IMMEDIATELY scout + drive
  cycle N+1 in the SAME turn, exactly as CHAIN-WITHIN-TURN mandates. Reading "continue with cycle-N" as "do
  only N, then hand control back" is the relapse. **Ending a completed-cycle report with ANY invitation to
  resume — "say continue whenever you want", "tell me to proceed", "the loop stands ready", "cycle-N+1 is
  queued in the state file", "let me know if you want it to chain onward" — IS stop-and-propose
  (coherent-and-wrong f) wearing a politeness costume:** it hands the drive-decision back to the user, which
  the loop must never do. The ONLY things that legitimately halt the chain mid-turn are (1) a spawned
  verifier actively running (yield until its notification), (2) the `N`-hour deadline / genuine
  budget-exhaustion (PAUSE with an interim report), or (3) an EXPLICIT user STOP / pause / "that's enough"
  instruction. **A user QUESTION mid-loop** ("what are you doing?", "how long is the gap?", "why…?") **is
  ANSWERED inline and then the chain RESUMES in the SAME turn** — a question is not a stop instruction, and
  answering it is not a licence to park at the checkpoint. Concrete tripwire: if you catch yourself typing
  "whenever you want", "stand ready", "say continue", "queued for next time", or any hand-back phrasing at
  the END of a cycle report, DELETE it and scout+drive the next cycle instead — the report of cycle N ends
  by *starting* cycle N+1, never by asking permission to.
- **"THE SESSION IS LONG" IS NOT A YIELD LICENCE (fatigue is coherent-and-wrong f).** Session length, a
  "natural pausing point", a clean checkpoint, "I've delivered a lot", or self-assessed budget fatigue are
  NEVER sanctioned reasons to stop driving. Budget bounds the *ambition per invocation* (§0), not the
  drive-the-next-nameable-goal discipline; the loop pauses ONLY on the actual `N`-hour deadline or genuine
  budget-exhaustion (`budget.remaining()` truly out), and even then it PAUSES with an interim report, it does
  not stop-and-propose. If you catch yourself narrating "this session is extraordinarily long" as a lead-in
  to yielding at a checkpoint, that is the relapse signal — scout and spawn the next cycle instead.
- **SELF-PERPETUATION — THE LOOP ARMS ITS OWN HEARTBEAT; IT NEVER WAITS TO BE POKED (the 6-hour-idle
  relapse, 2026-08-01).** CHAIN-WITHIN-TURN keeps the loop moving *while a turn is live*; but a turn
  eventually ENDS (compaction, context-limit, a completed cycle, a genuine pause). If nothing is scheduled
  to RE-INVOKE the loop when the REPL goes idle, it sits DEAD until a human happens to re-engage — the
  autonomous campaign silently degrades into "advances one step per human poke." **The fix is a self-armed
  heartbeat (Invocation §): `CronCreate` a recurring re-invocation (fires only while idle = restarts the
  chain at the turn-END), VERIFIED live via `CronList` at the start of every cycle and re-armed if absent
  (cron is session-only + 7-day-expiring).** Concrete tripwire: sensing "the turn is about to end" WITHOUT
  a confirmed-live heartbeat this turn IS the relapse — `CronList`/arm before yielding. A live heartbeat is
  what makes the word "autonomous" true; relying on the human's next `/time-loop` or "continue" is the
  failure this abolishes. (Distinct from stop-and-propose, which is a *phrasing* relapse at the turn-end;
  this is a *mechanism* relapse — even a perfectly-phrased "the loop carries forward" is a silent death if
  no wakeup is armed to carry it.)
- **VERDICTS COME FROM DELIVERED REPORTS OR OWN RE-RUNS, NEVER MID-RUN ARTIFACTS (verdict-provenance;
  coherent-and-wrong j; Gate T item 6).** A CLOSED/PROVEN/CEILING verdict is recorded ONLY from (1) a verifier
  sub-agent's **DELIVERED final report**, or (2) the coordinator's OWN independent **re-run** — NEVER inferred
  from a partial on-disk artifact (an overlay/session file) while its verifier is still running. Front-running a
  live run off disk residue is a **monitor-discipline break**: the observed relapse booked a class-C goal CLOSED
  off the overlay file, and the delivered report REFUTED it (the added contract closed ZERO goals). The monitor
  judges DELIVERED verdicts, it does not front-run them from disk. Gate T item 6 is the mechanical enforcement
  before any stop.
- **PRE-STOP GATE-T (mechanical terminus enforcement; §3).** Prose anti-premature-terminus (Gate S, §6, the
  stabilizers above) proved insufficient — one campaign hit THREE premature-halt near-misses. **No
  `ScheduleWakeup({ stop: true })` for a self-declared terminus until all six Gate-T items log PASS in
  `time-loop.state`:** enumeration-complete (incl. encode-side + "trivial" files) · no bare class-C / no
  CEILING-PENDING · no REDUCIBLE TCB entry · `formal-tests.tsv` exists + every Tier-1 entry harnessed-or-OUT ·
  Gate-R reconciled · every verdict traces to a delivered report or own re-run. A stop that skipped Gate-T IS
  the premature-terminus bug.
- **Value order (drive, don't menu):** findings first (a VIOLATION outranks a rigor PROVEN), then the
  remaining un-PROVEN goals by RMF risk, then diagnose-and-file the true-but-unprovable ones as Frama-C
  bugs. This is an ordering over what to DRIVE, never a menu handed to the user.
- **No EVA / pure WP / minimal TCB**; **admit-free audited Coq**; **faithfulness gate**; **monotone
  coverage**; **code-blind barrier** (rmf-sl fresh sub-agent); **emergent-obligation awareness** (the
  verifier's move-set includes cross-callee invariants threaded `requires`→`ensures` leaf-first, not
  only local fixes); **crash-safe per-cycle checkpoint** (commit+push, rebase-before-push); **three-status
  terminus** (every goal PROVEN / VIOLATION-reported / FRAMA-C-bug-filed — no soft residue); **human-AO
  terminus** (R5 PENDING).
- **Report/ledger reconciliation (Gate R, anti-drift):** `verdicts.tsv` is the single source of truth;
  the interim/summary report is a DERIVED view, re-derived-and-verified against the ledger EVERY cycle —
  never hand-bump the headline `+N` while the prose sections (flagged hazards, self-overturns, areas,
  levers, monitor-corrections) drift. Before every push, every count the report asserts must equal its
  `grep -c` count from the ledger; a mismatch is a push-blocking REJECT. Prefer a regenerated summary
  over a hand-edited one. **Dedup by function NAME (`grep -icE '\bFN\b' verdicts.tsv`), not by unit
  filename** — the same function under a different filename is still a duplicate and is not counted.
- **Cumulative-artifact non-destruction / append-only (Gate ND, anti-clobber; observed clobber 2026-08-15).**
  `…-found-issues.md` (FI-1…FI-N), `verdicts.tsv`, `time-loop.state`, the trusted-base ledger are MONOTONE
  append-only logs — prior findings/rows are NEVER lost. NEVER recreate one with a whole-file `Write` (it
  overwrites); ADD to it via `cat >>`/`printf >>`/targeted `Edit`. Check existence with `git ls-files
  --error-unmatch <path>` or an ABSOLUTE-PATH `test -f`, NEVER a relative `ls *glob*` after a `cd` (the `cd`
  shifts the dir → false "none" → Write-clobber; that was the exact root cause). Pre-push: `git diff --stat`
  each touched cumulative artifact must be NET-ADDITIVE (deletions only for a named surgical overturn); a
  drop in `grep -c '^## FI-'` / ledger row-count / any vanished prior finding ⇒ push-blocking REJECT —
  restore from git (`git checkout HEAD -- <path>`), re-apply by APPEND, re-check.
- **Dedup blind-spot #4 — SCOUTING with an AREA-filtered grep misses OLD bare-name-format rows.** When
  picking the next target, enumerating an area's already-witnessed leaves via `awk '$1 ~ /area/'` (col1
  contains the area path) SILENTLY MISSES ledger rows whose col1 is a **bare function name with no area
  prefix** (early-campaign format, e.g. `cap_inode_setxattr<TAB>VERIFIED<TAB>...`). A mature ledger mixes
  `area/file.c fn`, `area/file.c::fn`, AND bare-`fn` rows. So an area-scan can report a function "fresh"
  when it is already VERIFIED under a bare-name row — and you waste a spawn on a duplicate (the verifier's
  mandatory first-step hardened dedup catches it and ABORTS, but that is a burned cycle). **RULE: before
  spawning, run the hardened per-function dedup on the CHOSEN candidate itself —
  `awk -F'\t' -v fn=FN '$1 ~ ("\\<" fn "\\>"){print NR": ["$2"] "$1}' verdicts.tsv` (word-boundary match,
  format-agnostic) — and require it to print NOTHING. The area-scan is fine for BROWSING candidates; it is
  NOT sufficient to certify freshness. Companion to blind-spots #1 (header-comment `FN (` false-match),
  #2 (unit-filename ≠ function), #3 (VIOLATION/FI/CLASS-A rows invisible to a keyed awk).**

## 8. Execution order
Reconcile the base `/rmf` state → triage → sweep highest-value class-C first: the report's
**untrusted-input attack surface** (parsers, decoders, length/bounds arithmetic, map/record/cert
operations) before breadth; within a thread, sequence by contract reuse (a shared callee contract
discharged once benefits later units). Report coverage as a fraction of the **high-value** surface,
not the whole tree; enumerate the rest by class.

## Invocation / activation
Entry point: `/time-loop XXX N` (see `config/commands/time-loop.md`). `deadline = start + N hours`,
enforced by the resumable `time-loop.state` deadline + a **pinned, checkpoint-driven cadence**:

**MANDATORY: EVERY `/time-loop XXX N` invocation MUST end by arming the self-firing wakeup — but
`ScheduleWakeup` ENDS THE TURN, so it is the LAST action of the cycle, never the first.** The correct
per-wake sequence is: (1) reconcile → (2) drive the cycle's work (the WP/macsl proofs, ledger, checkpoint)
→ (3) **as the final tool call**, arm the next wake:
```
ScheduleWakeup({
  delaySeconds: 120,                 // the 2-min heartbeat (clamped to [60,3600]); until `now > deadline`
  prompt: "/time-loop XXX N",        // the SAME invocation verbatim, so the wake re-enters this skill
  reason: "time-loop heartbeat: re-fire the XXX campaign to drive/monitor the next cycle"
})
```
This is not optional: a `/time-loop XXX N` turn that does not arm a `ScheduleWakeup` before yielding is a
**loop-behaviour bug** — the campaign silently stalls, waiting on a human it must never wait on (§7). But
arming it FIRST is the mirror bug: because `ScheduleWakeup` ends the turn, an arm-first turn yields before
doing any work, so the loop arm-and-yields forever without driving a single cycle. **Drive the cycle first,
arm last.** (One `ScheduleWakeup`-scheduled turn drives ONE cycle — this is the scheduling analog of
CHAIN-WITHIN-TURN, whose multi-cycle back-to-back form applies when cycles are background SUB-AGENTS whose
completion notifications re-invoke you within one turn; with the `ScheduleWakeup` heartbeat it is one cycle
per wake.) **Arm every cycle** so the heartbeat persists across the whole `N`-hour horizon. **The default
is to KEEP the self-fire going — `ScheduleWakeup({ stop: true })` is reachable ONLY three ways:** (a) the
**true terminus (§6)** — and that is UNREACHED while any nameable next target remains, INCLUDING a REDUCIBLE
trusted-base entry (§4.1(iv)/coherent-and-wrong i): **before ever calling `stop: true` you MUST run Gate T
(§3 — the mechanical PRE-STOP TERMINUS CHECKLIST) and log all six items PASS in `time-loop.state`.** That
INCLUDES re-scanning the trusted-base ledger to confirm every entry is IRREDUCIBLE-with-reason; if ANY
Gate-T item FAILs (a still-REDUCIBLE entry, an un-enumerated in-scope / encode-side / "trivial" file, a
missing `formal-tests.tsv`, a bare class-C, a Gate-R drift, or a verdict recorded off a mid-run artifact),
you do NOT stop — you drive it this cycle and arm the next wake; (b) `now > deadline`;
(c) an EXPLICIT user STOP / pause / "that's enough". (Reasons (b)/(c) PAUSE with an interim report and do NOT
require Gate-T PASS; only reason (a), the true terminus, does.) A `stop: true` at a *self-declared*
"gate-defined terminus" that has not passed Gate T — a still-reducible TCB entry, an un-enumerated in-scope
file, a missing `formal-tests.tsv`, or a verdict inferred from a mid-run artifact — forcing the human to
re-ask "what's next", is the premature-terminus loop-behaviour bug this rule exists to kill. On a legitimate
stop, emit the terminus/interim report.
- **State checkpoint — per cycle:** the PRIMARY cadence, event-driven. Persist `time-loop.state` +
  run Gates B/C/S + commit/push at every cycle boundary. (One `/rmf` continue-converge cycle is many
  minutes — pace at cycle granularity, never poll faster than a cycle finishes.)
- **Self-perpetuation heartbeat — MANDATORY, SELF-ARMED, VERIFIED EVERY CYCLE (the loop keeps ITSELF
  alive; a turn that ends with no live heartbeat is a SILENT DEATH — the 6-hour-idle relapse,
  2026-08-01).** The loop does **NOT** depend on the human re-invoking `/time-loop` or typing "continue":
  it arms its own re-invocation. **Mechanism:** on activation, `CronCreate` a recurring re-invocation of
  this loop — a cron job fires its prompt **only while the REPL is IDLE**, i.e. exactly when a turn has
  ENDED (checkpoint / compaction / context-limit / completed cycle), so it **restarts the chain
  autonomously** the moment the loop would otherwise sit idle. Pick an **~8–12 min off-minute** recurrence
  (e.g. `6,16,26,36,46,56 * * * *`); the cron is a *restart-after-idle watchdog*, not a per-cycle poll —
  CHAIN-WITHIN-TURN drives the cadence while a turn is live, the cron only catches the turn-END.
  **GATE (run at the START of EVERY cycle):** `CronList` (or the harness equivalent — "The heartbeat
  on each harness" below); if no live
  heartbeat exists, **RE-ARM it immediately** — it may have been cleared, expired, or never set. Cron jobs
  are **session-only and auto-expire after 7 days**, so on a long campaign re-arm proactively. The heartbeat
  also survives a hung WP/prover/sub-agent (re-invoke → reconcile from the last checkpoint → continue).
  (`ScheduleWakeup delaySeconds=120` is the equivalent primitive inside a `/loop` dynamic session; use
  whichever the session supports — but **ARMING ONE IS NOT OPTIONAL**. Relying on manual re-engagement is
  the failure this gate abolishes. When the session uses `ScheduleWakeup`, it MUST be armed as the cycle's
  LAST action — it ends the turn, so arm-first would arm-and-yield without driving a cycle; arm-last =
  one cycle per wake.)
- **Deadline — `start + N h`:** at `now > deadline`, go straight to the terminus; reserve the last
  ~15–20 min for the report — never a last-minute dump. At the terminus/deadline call
  `ScheduleWakeup({ stop: true })` so no further self-fire occurs.

**The heartbeat on each harness.** The contract above is harness-neutral: arm the next wake as the
cycle's LAST action, keep an idle watchdog live, verify both at the start of every cycle, and stop by
not re-arming. The primitives differ:
- **Claude Code:** `ScheduleWakeup` (arm-last, ends the turn) and `CronCreate`/`CronList` (the idle
  watchdog), as written above.
- **OpenCode:** there is no in-session wakeup, but the loop is resumable from `time-loop.state` (§0 —
  a fresh `/time-loop XXX N` reuses the stored start and deadline), so the heartbeat is an EXTERNAL
  watchdog the loop arms once at activation and re-arms if absent — a detached shell loop that
  re-invokes the campaign headlessly when the state file has gone quiet (a live turn refreshes it
  every cycle, so a quiet state file means no session is driving):
  ```bash
  # armed from the project root; STOPFILE removed/created by the loop itself
  setsid nohup bash -c 'cd "$(pwd)"; while [ ! -e .time-loop-watchdog.stop ]; do
      sleep 480;
      s=$(stat -c %Y XXX-analysis-acsl/time-loop.state 2>/dev/null) || continue;
      [ $(( $(date +%s) - s )) -ge 600 ] || continue;             # idle >= 10 min
      [ "$(date +%s)" -ge DEADLINE_EPOCH ] && touch .time-loop-watchdog.stop && continue;
      opencode run "Load the time-loop skill and run its next cycle for XXX \
          (budget N hours) from XXX-analysis-acsl/time-loop.state";
  done' >/dev/null 2>&1 &
  ```
  Each wake is a fresh `opencode run` session that re-enters this skill, reconciles from the last
  checkpoint and drives ONE cycle (arm-last is then implicit: the watchdog IS the armed wake). At the
  terminus or the deadline the loop creates `.time-loop-watchdog.stop` and removes it on a fresh arm.
  Verify the watchdog at the start of every cycle: a live process is not enough on its own — check
  the state file is being refreshed and, if the watchdog died (container restart), re-arm it.

**`--dir=<subdir>` — focus an EXISTING campaign on a subdirectory (a scope filter, not a new campaign).**
When present, `XXX` still names the existing campaign — its `XXX-analysis-rmf-report.md`, onboarding,
build, and harness are REUSED, never re-bootstrapped — and `--dir` narrows the loop's own working set to
the in-scope C under the source-root-relative path `XXX/<subdir>` (verify `ls -d` first; stop if absent).
Every place the loop computes a set is intersected with that subtree: **§0 Phase-0 reconcile**, the **§4.1
residue TRIAGE**, the **§6 coverage ledger / `formal-tests.tsv`**, and the **terminus enumeration
cross-check** (`{in-scope C functions under <subdir>} ∖ {covered} == ∅` — see the monitor's enumeration
gate). Persist the scope in `time-loop.state` so re-invocations stay focused. Load-bearing interaction
with the code-blindness barrier: the code-blind RMF report names surfaces **by role**, so a file under
`<subdir>` the report never enumerated is **NOT out-of-scope — it is an in-scope class-C scope-gap to
DRIVE** (Plane-W memory-safety, plus any Plane-H gate the whole-file privilege-op enumeration surfaces).
`--dir` is the intended lever for exactly that case (a subsystem the report ranked only generically);
it is NOT forwarded to `/rmf` (the whole build still onboards — the filter acts on which units the loop's
cycles target). Value order and gates are unchanged, just computed over the narrowed surface.

**ONBOARDING SOUNDNESS — the preprocessing context is REAL or you STOP; NEVER hand-synthesize it.** A
unit is verifiable only under its REAL compilation context: the actual `-I` include paths, `-D` defines,
force-includes, and — critically — the **real headers that define its structs / unions / enums / macros /
`__packed` layouts**. When a unit depends on a header or module that is NOT in an existing build (e.g. a
`--dir` file whose subsystem was never onboarded, or an external module the build pulls in — MCUboot's
`bootutil`, a west module, a vendor HAL), there are **exactly TWO options**:
1. **Produce a REAL build that compiles it.** Explore the **WHOLE source hierarchy** under the target
   (`./XXX/` — its Kconfig fragments, `west.yml` / module manifests, `CMakeLists.txt`, `modules/`,
   submodules, and the dependency's own tree) to find or enable the config that pulls the dependency and
   compiles the unit; take the `-cpp-extra-args` from **that real `compile_commands.json` entry**. This is
   `frama-c-launch`'s job — drive it, do not shortcut it.
2. **STOP and report the onboarding blocker honestly** — record it as a **class-A onboarding wall** (the
   module/headers are genuinely absent and cannot be built here) routed to `frama-c-launch`, and pause the
   loop. An un-onboardable unit is NOT a terminus and NOT a residue to fake past.

**NEVER hand-synthesize the missing header, nor "faithful-looking" stub structs / enum values / macro
constants / packed type definitions.** At the precision WP's byte-level memory model needs, a hand-written
struct or enum (a wrong field offset, a wrong size, a wrong `__packed`/alignment, a wrong endian or magic
constant) is **silently WRONG**: it yields an UNSOUND or VACUOUS proof about a *fabricated* data layout,
not the shipped one — and the faithfulness gate (`strip(//@)==pristine`) **cannot catch it**, because the
defect lives in the *harness/headers*, not the annotated overlay. Fabricating the data-layout context is
the onboarding analog of a smuggled axiom, and is a hard REJECT. (This is DISTINCT from — and does not
forbid — a faithful `assigns`/`ensures` **contract on an external FUNCTION** whose *body* is the
out-of-scope trusted boundary: that remains the legitimate TCB pattern, but the types that contract ranges
over must still come from the REAL headers. The rule bans fabricating the *type / data-layout context*,
never contracting an external function's behavior over real types.)

**On every `/time-loop XXX N` (re-)invocation, CONTINUE — do not stop-and-propose.** Reconcile state,
pick the highest-value goal that is not yet PROVEN / VIOLATION-reported / FRAMA-C-bug-filed, and drive it.
Reporting "the campaign has converged" and then listing "the next budget's natural targets" is a bug in
the loop's behavior: if you can name the target you must drive it (§0, §6, Gate S). Only report done when
the whole in-scope goal set is in one of the three statuses.

**SELF-PERPETUATION IS MANDATORY AND GATED — the loop keeps ITSELF alive; it NEVER waits for the human to
re-invoke it (the 6-hour-idle relapse, 2026-08-01).** The **FIRST action on activation** is to ARM a
self-re-invoking heartbeat — `CronCreate` a recurring re-invocation of this loop (or `ScheduleWakeup` in a
`/loop` session; on OpenCode, the external `opencode run` watchdog of "The heartbeat on each harness"
below) — and to **VERIFY it is live
(`CronList`) at the start of every cycle**, re-arming if absent. A turn that ENDS (checkpoint, compaction,
context-limit, or a completed cycle) while **no heartbeat job is armed** is a **SILENT DEATH**: the loop
sits idle until a human happens to re-engage — which is exactly the failure this gate abolishes.
**Concrete tripwire:** if you catch yourself finishing a cycle report — or sensing the turn/context is
about to end — WITHOUT having confirmed a live heartbeat this turn, that IS the relapse; run `CronList`
(or re-arm the `ScheduleWakeup`) and arm/re-arm BEFORE the turn ends. The heartbeat is the mechanism
that makes "autonomous N-hour campaign" true; without it the loop is merely "advances one step each time a
human pokes it." Activating an N-hour autonomous campaign is a deliberate, resource-significant step —
arrange the schedule explicitly AND keep it armed until the deadline, then let each wake run steps 0–6.
Inherited from the `/rmf` campaign: **pure WP, NO EVA; `XXX/` pristine; R5/Authorize PENDING (human AO).**

## Pairs with
`config/commands/time-loop.md` (the `/time-loop XXX N` entry point), the driver's own campaign
command (`config/commands/rmf.md` or `config/commands/fips.md`, per the driver table above),
`meta-penguin` (the worked Linux instance of this exact design), `rmf-sl` and `fips-sl`,
`frama-c-launch`, `frama-c-monitoring`/`framac-sl`, `sl-monitoring-sl` (the meta-pattern this
instantiates), `bin/crosswalk-gen.sh` + `bin/ledger-ratchet.sh` (the ledger/coverage gates), the
`never-use-eva` rule, `bugs-to-report/wp-bitwise-smt-incompleteness/` (the canonical class-A residue).
