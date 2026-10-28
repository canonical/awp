# Learned knowledge — Mission coordinator (frama-c-monitoring)

Append-only, Gate-S-gated heuristics the **mission coordinator** capitalized while
running the `frama-c-monitoring` loop (see this skill's `SKILL.md` §7). Each entry
passed an `sl-monitoring-sl` Gate S audit **from a disjoint base** (a cross-provider
agent or a human — the coordinator may not audit its own skills) and carries
provenance.

**Scope / barrier:** mission-decomposition and guidance-interpretation heuristics —
how to turn a `verify library xxx in dir yyy` + guidance into a plan; when to cut a unit
from the plan; how to apply guidance like *"RTE-only for module Z; functional thoroughly
elsewhere; disregard concurrency"* uniformly. Judge against the guidance `U`; record no
sub-agent's private rationale and no per-unit implementation specifics. Future runs load
this file at delegation time.

**Entry format:**
```
### <title>
- Kind: ignore-signal | defer-to-oracle
- Gate S: PASS | CARVE-OUT
- Arose from: <mission / unit / gap-N>
- Heuristic: <rule>
- Carve-out: <exception → guidance clause>   (if any)
```

## Entries

### Piloting the SMT→Coq escalation — escalate only the irreducible kernel; otherwise record PARTIAL honestly
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: the gcd flagship gate + the StandardAlgorithms residuals
- Heuristic: the coordinator owns the *decision to escalate*, the base loop owns the proof, and
  the monitor audits its soundness (`learned-monitor.md`, "SMT→Coq escalation is sound
  only if cache-clean and zero-admit"). Pilot it so:
  0. **Classify the red goal FIRST — there is no "prover limitation" bucket (Curry–Howard).**
     A goal is provable iff it is true, so an un-green goal is EITHER (a) **entailed but
     SMT-incomplete** (needs induction / an un-triggered quantifier) → escalate to Coq (steps
     below); OR (b) **non-entailed** (a model of the hypotheses falsifies it) → a **specification
     defect**, NOT a prover limitation. Test by looking for a counter-model: if the spec admits a
     state where the goal is false (e.g. a postcondition `\result==1` while the callee only
     guarantees `\result!=0` — the model `\result==2` falsifies it), the coordinator must declare
     the SPEC the issue and route it (see the dedicated entry below), never escalate to Coq and
     never record "unprovable / not addressable." Escalating a non-entailed goal to Coq is a
     category error that wastes the budget and can never succeed.
  1. **Recognize the trigger (case a only).** A residual VC that survives `-wp-prover alt-ergo,z3`,
     is entailed, and needs **induction or non-linear reasoning** (a recursive-`logic`-function
     consequence, a greatest/maximality quantifier over a variable divisor, a divisibility/order
     fact). Loop preservation, RTE, and range goals are NOT escalation candidates — re-triage them
     as a spec gap first.
  2. **Insist the base loop isolates a named `lemma`** (never escalate a function postcondition VC
     directly — it is entangled with WP's memory model). Escalate the *smallest* lemma that lets
     SMT close the function; confirm it is load-bearing.
  3. **Check the prerequisite before spending the budget.** The matched `framac-coq8` opam switch
     must exist (Coq 8.20.1 + Why3 realizations) and `frama-c -wp-detect` must list `(coq)`. If the
     coupling is unavailable, do NOT loop on `why3 config detect` and do NOT paper over with an
     `axiom` — record the unit **PARTIAL** ("needs interactive proof — coupling unavailable") with a
     `gap-N`. (Install + workflow live in `config/skills/frama-c/references/coq-escalation.md`.)
  4. **Budget it.** Coq escalation is expensive (interactive scripts, brittle on encoding change).
     Escalate the high-value residuals the audit ranked; record the rest PARTIAL rather than stall
     the whole queue. A unit whose only shortfall is an un-escalated inductive lemma is PARTIAL, not
     FAILED.
- Carve-out: a mission whose guidance is **RTE-only** for a subsystem makes induction-heavy
  functional lemmas out of scope there — do NOT escalate; the SMT RTE result is the whole deliverable.

### A goal no prover can close means the SPECIFICATION is the issue — the coordinator must diagnose and route it, never park it as "unprovable"
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: Stack/StackWellDefinedness/stack_empty_wd.c (mis-labelled "not addressable by Coq" — a category error)
- Heuristic: by Curry–Howard a proposition is provable iff it is true, so "no prover (not even Coq)
  can prove it" is **impossible for a true goal** — it can only mean the goal is **not entailed by
  the current spec** (a model of the hypotheses falsifies it). That is a SPECIFICATION DEFECT, and
  deciding so is the **coordinator's job**, not a dead-end PARTIAL. Why the loop previously failed to
  decide this: it carried an illegitimate "prover/Coq limitation" bucket that absorbed non-entailment
  cases and let them sit as PARTIAL. **Delete that bucket.** Then every red goal classifies as exactly
  one of: (a) entailed-but-SMT-incomplete → Coq; (b) non-entailed → spec defect → the coordinator
  routes it:
  1. **Locate the missing/weak clause** via the counter-model. stack_empty_wd: postcondition
     `\result == true` (==1) is falsified by the model where the callee `stack_empty` returns 2,
     because its contract only guarantees `\result != 0`. The counter-model names the culprit: the
     callee's bool contract under-specifies the result.
  2. **Strengthen the spec.** Either tighten the unit's own contract to what is actually entailed,
     or — the usual fix — strengthen the *dependency's* ACSL (here `stack_empty.h`: `ensures
     \result == 1`). **A header's ACSL is editable**: faithfulness freezes only *executable C*, and a
     declaration header has none. "Uneditable sibling header" was the wrong call; only its C (there is
     none) is frozen, its contract is fair game. After strengthening, the goal becomes entailed and
     SMT (or Coq) closes it.
  3. If the dependency genuinely cannot be touched by mission policy, the honest verdict is **PARTIAL —
     specification defect in <dependency>: <clause>**, with a `gap-N` and a strengthening proposal —
     explicitly NOT "prover limitation" / "unprovable" / "needs Coq."
  This is distinct from "coupling unavailable" (the goal IS entailed and Coq *could* close it, but the
  toolchain isn't installed) — that is a tooling gap, route to getting-better/, not a spec defect.
- Carve-out: none — the rule is unconditional. A red goal is always either SMT-incompleteness (→Coq)
  or a spec defect (→strengthen/route); "prover limitation" is never a valid classification.

### Enumerate privilege-op sites across the WHOLE target before declaring Plane-H N/A
- Kind: ignore-signal
- Gate S: REJECT
- Arose from: a privilege-drop-before-exec authorization gate living in a helper the code-blind report scoped OUT
  ("no in-process authorization gate")
- Heuristic: "Plane H N/A" is a code-blind ARCHITECTURAL inference and is routinely WRONG — an authorization gate
  (a `setuid`/`setgid`/`setgroups` privilege drop, a `geteuid()!=0` must-be-root guard, a real-uid check gating a
  sensitive option) commonly lives in a HELPER the report bucketed as out-of-scope plumbing, or in a DIFFERENT binary
  than the one the report reasoned about. Before accepting Plane-H N/A, grep the WHOLE target (including "out-of-scope"
  TUs) for privilege-op sites (`geteuid|getuid|setuid|setgid|setgroups|initgroups|capable|CAP_|prctl`) and trace each
  to the sensitive OPERATION it guards. Reading code (not the report) is what finds these — the code-blind report
  structurally cannot. Each DISTINCT gate is high-value (ranks WITH Plane-W findings) and is NOT budget-cut. The
  recurring high-value shape is the privilege-drop-before-exec (`setgroups/initgroups → setgid → setuid → execve` on
  attacker-influenced data): witness it with macsl `\authorized`/`\precond` on the exec call-site (the sensitive op is
  reached only after the drop completed), paired with an attack mutant that ignores a `setuid` failure — it must flip
  the `\prop`. A second, distinct gate is often the drop-TARGET integrity (real-root required to choose the uid/gid).
