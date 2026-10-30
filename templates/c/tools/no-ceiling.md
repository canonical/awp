# no-ceiling.md — a plan to stop the recurring "premature class-A / tool-ceiling" relabel

## 0. The failure, stated plainly
Repeatedly across this project, a **hard-but-closeable goal is relabeled a "tool ceiling"
(class-A / "WP can't", "out of reach", "store-bloat wall")** and parked — when it is actually
**class-C unfinished work**. Instances (same root cause):
- 2026-06-20 (already filed): "the system-property tool is a silent no-op" (false — invocation-order
  bug); "main.c's socket/string layer is out of WP's reach" (false — the ACSL libc specifies it all).
- 2026-06-30..07-01 (this session, libbpf): the `btf_type_size` `to_sint32` "wall" (was a switch-CFG
  artifact — `-simplify-cfg`); the member-array-validity "wall" (was a proven lemma that just didn't
  auto-fire); and W1 `btf_validate_type` tagged **class-A twice** (cycle-16, cycle-22) on store-bloat
  symptoms — then, when finally forced to **read the actual Coq goal**, it was a plain **memory-frame
  obligation**: class-C, and the **mandatory Coq escalation had never been run**.

Five instances. The verdict is always the same shape: *a fluent, plausible limitation asserted without
the specific probe that would refute it.*

## 1. Root cause — NOT a knowledge gap; a missing MECHANICAL, DISJOINT, LABEL-BLOCKING gate in the solo path
The discipline is already **maximally documented**: 9+ statements in `frama-c-monitoring`, plus
`time-loop`, `sl-internal`, `frama-c`, a dedicated **getting-better note (2026-06-20)**, a **memory**
(`framac-negative-claims-must-be-grounded`), and — decisively — **two executable gates already exist**:
`config/skills/sl-internal/scripts/refutation_probe.py` (the exemption-refutation gate) and
`triage_audit.py` (the triage flag-rate auditor). It recurred anyway. So more prose / another note is
**proven useless** — that layer has been tried five times and failed.

The real cause is three structural facts:

1. **The existing gate's soundness precondition is violated in a SOLO run.** `refutation_probe.py`'s own
   header says it trusts the *recorded* verdict and "is not a lower bound — it is the producer's own
   say-so" **unless a DISJOINT verifier the producer cannot influence attests the re-run.** In a solo
   `/time-loop` (single agent, no multi-agent workflow), **I am both the producer and the "disjoint"
   monitor.** So I self-certify "class-A, lever-attested" and nothing catches it. The gate exists but is
   *never wired into the solo path*, and its disjointness premise is structurally absent there.

2. **"Effort" is silently substituted for the SPECIFIC mandatory probe.** I try several levers
   (auto-strategies, a lemma, a checkpoint) and self-judge them "sufficient," while skipping the
   *specific* class-A discriminators: (a) **dump and read the actual goal**; (b) **minimal-reproducer
   bisect**; (c) **the Coq escalation, actually run**, residual recorded; (d) the **store-bloat check**.
   Nothing forces the class-A *row* to carry these artifacts, so "lever-attested" is unfalsifiable.

3. **The trigger is budget/terminus pressure.** The relabel clusters at "diminishing returns → declare
   done." Reaching the terminus by relabeling class-C as class-A is the exact `coherent-and-wrong (a)/(b)`
   the loop names — but the **terminus gate does not block on unattested class-A rows**, so the shortcut
   pays off (it *looks* done).

Contributing trap: **store-bloat is uniquely seductive** — a goal that *proves 1/1 in isolation* but
*times out in the big-function context* looks exactly like a ceiling yet is almost always class-C
(clear the context / Coq `assumption` / checkpoint-slice). It has no dedicated rule, so it reads as A.

## 2. The fix — make class-A EXPENSIVE and DISJOINTLY-ATTESTED; make class-C the DEFAULT
Design principle: **a "ceiling" is a CLAIM under review, never a verdict a single agent issues.** Flip
the burden of proof. The only interventions that change behavior under pressure are (i) a gate that
*mechanically blocks* the label and (ii) a check the producer *cannot self-satisfy*. Both already
half-exist; the plan wires them into the solo path and adds the artifact bundle + disjoint judge.

### Fix A — the `no-ceiling` pre-label gate (mechanical, blocks the label)
New: `config/skills/sl-internal/scripts/no_ceiling_gate.py` (extends `refutation_probe.py`). **No
residue may be recorded class-A / "ceiling" / "not closeable" until this gate returns PASS.** The gate
requires the row to carry a fixed **artifact bundle**, each independently checkable:
- **GOAL-DUMP** — the actual VC (`-wp-print`, or the generated Coq `Theorem wp_goal`), with the
  **precise obstacle named** (which term/hypotheses). "It timed out" is auto-REJECT. *(This one step
  alone would have caught W1 — the goal shows a memory-frame, not a ceiling.)*
- **REPRODUCER** — a ≤10-line twin verdict. **Twin proves ⇒ NOT a ceiling ⇒ auto-REJECT to class-C**
  (the artifact is localized elsewhere: CFG, model, context).
- **COQ-RESIDUAL** — the WP→Coq attempt output (`framac-coq8`), attempted-**and-failed**, residual goal
  recorded + `Print Assumptions`. **No Coq attempt recorded ⇒ not eligible for class-A.**
- **STORE-BLOAT VERDICT** — proves-in-isolation **∧** times-out-in-context ⇒ **class-C (store-bloat)**,
  never class-A; the levers to try first are named (Coq `clear` the bloat + `assumption`/frame,
  checkpoint-slice, context reduction).
Missing/failing any ⇒ the gate **refuses class-A and defaults the row to class-C**. Ships with a
`--selftest` seeding a fake ceiling (a store-bloat goal + no Coq) that the gate MUST catch (parity with
`conservation_gate.py`/`refutation_probe.py`).

### Fix B — supply the DISJOINT attestor in the solo path (the core structural fix)
`refutation_probe.py` is only a lower bound with a disjoint attestor. Provide one for every class-A
**candidate**, so I cannot self-certify:
- **Primary — cross-provider judge.** Route {GOAL-DUMP + the ceiling claim + the artifact bundle, and
  *nothing else* — no rationale} to the **non-Anthropic judge on $(cat ~/.local-llm-machine-ip.txt)** (memory
  `cross-provider-judge-ollama`). It rules independently: *non-entailed/ceiling* vs *missing-hypothesis
  (class-C)*. A different provider family is genuinely disjoint from me (advisory-but-recorded, per that
  memory's routing).
- **Fallback — human/AO attestation.** If the judge is unavailable, a class-A row is **PENDING**: it may
  not be counted closed and **cannot end the campaign** (§Fix D). Never silently self-attest.
- **The LLM judge is ADVISORY, the mechanical twin is DECISIVE (2026-07-01, libbpf cycle-29).** For a
  *tool-capability* claim ("WP can't represent X"), a cross-provider LLM judge **cannot run the tool** —
  it rules from the producer's framing and inherits the producer's error. A real case: I framed a
  `void*`/char-range→typed-access residual as a bytes-model "representation wall"; `gemma4:26b-mlx` ruled
  CLASS-A — but three minimal twins proved 4/4, so it was **store-bloat (class-C)**. The gate handles this
  correctly by construction (the REPRODUCER/twin-proves check runs *before* the attestation branch), so a
  proving twin REJECTS to class-C **regardless of the LLM verdict**. Rule: **never let an LLM attestation
  substitute for the minimal twin**; the twin is the disjoint mechanical ground truth, the judge is a
  secondary opinion for cases the twin cannot settle.

### Fix C — reframe the vocabulary so the default is class-C
Retire the self-applied phrase "class-A tool ceiling." In state/report/ledger a ceiling is written
**`CEILING-CLAIM (PENDING: <missing artifacts>)`** until Fix A+B pass, then **`CEILING-ATTESTED
(<judge/AO> + bundle)`**. The word "ceiling" never appears as a bare verdict. Class-C is the assumed
class for any timeout until the bundle proves otherwise.

### Fix D — block the terminus on any unattested ceiling
`time-loop` Gate S / §4 terminus and `frama-c-monitoring` §8/§8b: **the diminishing-returns / ledger-
CLOSED terminus MUST NOT fire while any residue is `CEILING-CLAIM (PENDING)`.** A pending ceiling is an
*open class-C row* by definition (Fix C), and a class-C row blocks closure (already the rule) — this just
makes it un-bypassable: you cannot reach "done" by relabeling, because the relabel is now PENDING, not
class-A, until disjointly attested.

## 3. Where each change lands
- **New script:** `config/skills/sl-internal/scripts/no_ceiling_gate.py` (Fix A+B; `--selftest`).
- **`time-loop/SKILL.md`** §4 (triage: class-A definition) + Gate S/terminus: "class-A" → run
  `no_ceiling_gate.py`; terminus blocked on `CEILING-CLAIM (PENDING)` (Fix C/D). Wire the gate into the
  per-cycle checkpoint (§4 step 5), not just the final report.
- **`frama-c-monitoring/SKILL.md`** §6 "Classify every red goal" (add the artifact-bundle requirement +
  the store-bloat rule as case (b″)) and §8b reporting-lint (a `CEILING-*` row without its bundle fails
  `framac-gen-report.sh --lint`). Cross-link the existing §6 (b′) I already added.
- **`framac-gen-report.sh`** (repo root): extend `--lint` to reject any ledger/report row tagged
  class-A/ceiling that lacks the GOAL-DUMP + COQ-RESIDUAL + judge/AO attestation.
- **A short operator checklist** `config/skills/frama-c-monitoring/references/no-ceiling.md` (the
  in-loop version of this plan): *before you type "ceiling", run `no_ceiling_gate.py`.*
- **Memory:** update `framac-negative-claims-must-be-grounded` to point at the gate (the note+memory
  layer demonstrably didn't hold on its own — the memory now says "this is gate-enforced, not
  honor-system").

## 4. Acceptance test (how we know it works — not "it reads well")
1. **Regression on the real miss:** feed the **cycle-22 W1 class-A** through `no_ceiling_gate.py`. It
   MUST **REJECT** → class-C (evidence: the goal-dump is a memory-frame; no Coq attempt was recorded;
   store-bloat verdict = proves-in-isolation). If the gate does not reject it, the gate is wrong.
2. **Seeded-ceiling selftest** (calibration, per the other gates): a fabricated ceiling with no Coq
   residual must be caught; a *genuinely* attested one (Coq-attempted + judge concurs) must pass. Assert
   the discriminating band `0 < rejected < total`.
3. **Cross-provider disjointness live-check:** the judge on $(cat ~/.local-llm-machine-ip.txt) answers on a held-out
   goal; if unreachable, the row is PENDING (never silently PASS).
4. **Terminus block:** a campaign with one `CEILING-CLAIM (PENDING)` row must NOT reach terminus.

## 5. Why this will hold where five prior attempts did not
Every prior fix operated on the **documentation/prohibition** layer — a rule I must *remember and
choose to obey under pressure*. This plan moves enforcement to the **mechanical + disjoint** layer: the
class-A label is *unwritable* without an artifact bundle a script checks, and *unattestable* without a
judge I cannot collude with. The producer's incentive at the terminus (relabel to look done) is
neutralized because the relabel no longer counts as done — it counts as an open, PENDING class-C row.
The lesson is the meta-lesson: **against a recurring self-serving misclassification, add a gate, not a
sentence.**

## 6. Immediate follow-through (this repo, this campaign)
- The libbpf W1 residue is, as of cycle-23, correctly reopened as **class-C (memory-frame closure, Coq
  escalation owed)** — that is the corrected state; do NOT re-tag it class-A without the bundle+judge.
- Next libbpf cycle: run the owed frame-Coq escalation on `btf_validate_type` (clear the string-`Init`
  bloat, prove the `t2==t3`/`t==t1` frame equalities + the `to_sint32` identity) — the concrete class-C
  work, not a wall.
