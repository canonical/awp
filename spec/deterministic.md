# Deterministic vs. judgment steps in `time-loop`

A classification of the `time-loop` squeeze loop
(`templates/c/skills/time-loop/SKILL.md`, structure in
`templates/c/skills/time-loop/time-loop.sl.json`) into:

- **D — deterministic**: computable by shell/code from files + the clock, with
  **no model call**. The result is a pure function of `time-loop.state`,
  `verdicts.tsv`, the prover logs, the overlay tree, and `date +%s`. Two runs
  on the same inputs must give the same answer.
- **J — judgment**: requires the model. Reading risk rank *meaning*, deciding
  the A-vs-C class of a residue, authoring an ACSL overlay, detecting
  "coherent-and-wrong" relabeling. No deterministic oracle decides these.
- **H — hybrid**: a J decision wrapped in a D gate — the model proposes, a
  deterministic check accepts or refuses. These are where most of the loop's
  integrity lives (a J claim is never trusted on say-so; a D oracle confirms).

**Scope note.** `time-loop` runs inside a *generated campaign project*
(scaffolded by `auto-wp.py`), not in this `awp` repo. The mechanisms it names —
`time-loop.state`, `verdicts.tsv`, `bin/heavy`, `bin/mem-watchdog`,
`bin/rmf-lint.sh`, the campaign `verify.sh`, and
`config/skills/sl-internal/scripts/no_ceiling_gate.py` — live in that project at
runtime; here they exist only as templates (e.g.
`templates/common/skills/sl-internal/scripts/no_ceiling_gate.py`). This document
classifies the *steps*, which is independent of where those files sit.

The point of this document: **which steps can leave the prompt and run as
deterministic code** (via the repo's own `Workflow` tool + shell), so the model
is invoked only at the J and H-propose nodes. This is *not* an argument for
LangChain — see `spec/` discussion; the deterministic parts are already shell,
and the orchestration schema already exists in `time-loop.sl.json`.

---

## 1. The per-wake loop (§4), step by step

| § | Step | Class | Deterministic mechanization (the D part) |
|---|---|---|---|
| 4.0 | Load state; keep stored `start`/`deadline`; **`now > deadline` → terminus** | **D** | `grep '^deadline=' time-loop.state`; compare to `date +%s`. Pure arithmetic. |
| 4.0 | Append `wake=<epoch>` as the first action of every wake | **D** | `echo "wake=$(date +%s)" >> time-loop.state`. |
| 4.0 | Reconcile existing `/rmf` artifacts (report lint, overlay verdicts, gaps) | **D** | `bin/rmf-lint.sh` (exit 0), re-read `verdicts.tsv`, parse `*-gaps.md` / `*-found-issues.md` into the residue ledger. |
| 4.1 | **TRIAGE**: assign each residue class A/B/C/out-of-plane | **H** | *Propose* = J (model reads the residue). *Accept class A* = D gate: `no_ceiling_gate.py <claim.json>` must PASS, else it **defaults to class C** — a pure predicate over the dumped VC + the ≤10-line twin + the WP→Coq escalation log. |
| 4.1 | The **refutation probe** (the A↔C discriminator) | **H** | The *construction* of the antecedent is J; the *verdict* is D: supply the antecedent, re-run WP; **instant-Valid ⇒ class C** is a mechanical read of the prover exit. |
| 4.1 | Value-order ranking (finding-bearing → rigor → out-of-plane) | **J** | Risk rank is read from `rmf-report.md`; which thread is "highest-value" is model judgment. (The *tie-break* by `RS#` risk level is D, but the plane/thread choice is J.) |
| 4.2 | **Drive one `/rmf` continue-converge cycle in a sub-agent** | **J** (authoring) under **D** guards | Authoring the overlay + running WP/macsl is J, and **must** run in a spawned sub-agent (the delegation barrier). The guards around it are D: see §2. |
| 4.3–4.5 | Record the returned verdicts; checkpoint; commit; arm next wake | **D** | `verdicts.tsv` append; `git commit`; `ScheduleWakeup`. See §3. |

---

## 2. The R6 resource guard and the time box — fully deterministic

Every item here is mechanical and already lives in shell. None needs the model;
all of it can run outside the prompt.

| Mechanism | Class | Mechanization |
|---|---|---|
| `bin/heavy <cmd>` — slot pool, `ulimit -v`, `oom_score_adj=1000`, process-group kill, nesting-depth guard | **D** | flock + ulimit + setsid; a pure wrapper. |
| `bin/mem-watchdog start/status` — kill heaviest `bin/heavy` group below 1 GiB `MemAvailable` or above 1500 tasks | **D** | background poller; `status` re-`start`s if dead. |
| Concurrent-agent cap `min(nproc/2, floor(RAM_GiB/3))` | **D** | computed from `nproc` / `/proc/meminfo`. |
| 45-min verifier time box; `TaskStop` at +15 min past box | **D** | compare sub-agent start to `date +%s`; stop + re-queue narrower. |
| `verify.sh` forces `-wp-par 2` after caller args | **D** | fixed argument rewrite. |
| Build-in-a-copy; `git -C XXX status --short` empty after any build | **D** | checksum / `git status` compare; non-empty = incident. |

**Lift candidate.** This whole block is the strongest case for moving out of the
prompt: it is safety-critical, purely mechanical, and must run *even when the
model is mid-judgment*. A watchdog process + a `heavy` wrapper already realize
it; the prompt only needs to *know they are armed*, not *perform* them.

---

## 3. Gates — which are machine, which are editorial

From §3 and the Gate-T checklist (§4 Gate T). The loop already labels these
"machine" vs "editorial"; that label *is* the D/J split.

| Gate | Class | Deterministic content |
|---|---|---|
| **Gate A (editorial)** | **J** | The coordinator judges the triage plan. No oracle. |
| **Gate B (machine)** | **D** | WP discharge (pure WP, **no EVA**); no-blend/no-smuggled-axiom check; monotone-coverage invariant; `verdicts.tsv` updated. All mechanical reads of prover exit + ledger. |
| **Gate C (coverage / anti-relabel)** | **H** | Every targeted `RS#` maps to a WITNESSED proof **or** a probed exemption — the *mapping completeness* is D (`{in-scope} ∖ {covered} == ∅`); the *judgment that an exemption is honest* is J, gated by the probe (D verdict). |
| **Gate R (ledger reconciliation)** | **D** | **`verdicts.tsv` is the single source of truth**; every asserted count in any report **must equal** `grep -c`. A one-line diff check; hand-bumped counts fail. |
| **Gate S (terminus definition)** | **J** | "No reducible TCB entry / no class-C remains" is a judgment over the ledger. |
| **Gate T (pre-stop checklist)** | **D** | The *mechanical* gate: six items, each **run THIS cycle** and logged PASS with its command/evidence in `time-loop.state`. Any single FAIL ⇒ not done. This is a checklist executor — pure D — deliberately added because prose forbids (J) failed to stop a premature terminus. |

**Key observation.** Gate T exists precisely because the J-level prose
("don't stop early") was insufficient, and a **deterministic** six-item
checklist was needed as the hard precondition of `ScheduleWakeup({stop:true})`.
That is the pattern this whole document recommends generalizing: **where a J
rule is load-bearing, back it with a D gate.**

---

## 4. The heartbeat and state machine — deterministic

| Concern | Class | Mechanization |
|---|---|---|
| `start` / `deadline` pinned once, never recomputed | **D** | written on first invocation; resumes parse them verbatim. |
| `wake=<epoch>` appended every wake | **D** | first action of each wake. |
| Re-arm next wake (heartbeat) | **D** | `ScheduleWakeup` / cron; a reboot-survivable timer. |
| Deadline / budget-out → PAUSE (interim report), not finish | **D** | `now > deadline` ⇒ emit interim, persist, re-arm. |
| Push-by-hash verification | **D** | every `checkpoint <hash> pushed` must exist in the remote (`git cat-file -e` / `~/remote.git`). |
| Explicit-user STOP | **D** (input) | a sentinel, not a judgment. |

---

## 5. The deterministic core worth lifting out of the prompt

Ordered by payoff. Each is **D**, already shell-shaped, and currently narrated
inside a 1062-line prompt where it costs context and invites drift:

1. **The R6 guard + time box (§2).** Safety-critical, must run during model
   turns. Keep as standing processes (`bin/heavy`, `bin/mem-watchdog`,
   `TaskStop` on box overrun); the prompt only checks they are armed.
2. **Gate R + Gate T (§3).** Two pure checkers:
   `report-counts == grep -c verdicts.tsv`, and the six-item PASS ledger. A
   script returns PASS/FAIL + evidence lines; the model reads the verdict, does
   not perform the count.
3. **State-file discipline + heartbeat (§4).** `start`/`deadline`/`wake`
   parsing, deadline comparison, push-by-hash — a small state module.
4. **`no_ceiling_gate.py` as the class-A admission predicate (§1 triage).**
   Already a script; make it the *only* way a residue becomes class A, so the
   A-vs-C relabel (the dominant coherent-and-wrong) cannot pass on say-so.
5. **`bin/rmf-lint.sh` / `verify.sh` / faithfulness diff (`strip(//@) ==
   pristine`).** Existing oracles; the loop consumes exit codes.

**Wiring.** Express the above as deterministic nodes of the repo's native
`Workflow` orchestrator (same harness, same `.sl.json` vocabulary), calling the
existing shell. The model is invoked only at: triage *proposal* (J), overlay
*authoring* in the sub-agent (J), and value-order *thread choice* (J) — each
immediately squeezed by a D gate (`no_ceiling_gate`, the refutation probe, Gate
B/R/T). No third-party agent framework is introduced; adding one would compete
with `time-loop.sl.json` and the two-harness (Claude Code + OpenCode) parity the
repo already standardizes on.

---

## 6. What must NOT be lifted (irreducibly J)

So the split is not over-claimed — these are the loop's reason to use a model at
all, and have no deterministic oracle:

- **Residue class *proposal*** (A/B/C/out-of-plane) — the probe confirms, but
  the model must first read the residue and propose.
- **ACSL/HAPPY overlay authoring** and the construction of the refutation
  probe's antecedent.
- **Value-order thread selection** across planes W and H under budget.
- **Detecting exempt-bucket relabeling** as *coherent-and-wrong* — the monitor's
  core act; it is caught structurally (disjoint `(U,L)`, the barrier from
  `base_rationale`), not by a decidable check.
- **Terminus *definition*** (Gate S): "no reducible TCB entry remains" is a
  judgment the mechanical Gate-T checklist only *enforces*, never *makes*.

The design rule this yields: **keep J where no oracle exists, and back every
load-bearing J with a D gate.** `time-loop` already does this (Gate T over the
stop decision, `no_ceiling_gate` over class A, the refutation probe over A-vs-C);
the lift simply moves the D gates out of the prompt into executable nodes.
