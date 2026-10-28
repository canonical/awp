# Running `framac-monitoring` as a Workflow

This explains how to drive the `framac-monitoring` loop with the **Workflow** tool so it
runs **unsupervised** — processing the `framac/` corpus in batches of `framac-sl`
sub-agents, monitor-gating each for faithfulness, and committing every batch — without
filling the main conversation's context window. It is the Frama-C port of `workflow.md`.

## Why a Workflow (the one idea that matters)

When `framac-sl` sub-agents run *inline* (via the Agent tool), the **coordinator is the
chat itself**, so every sub-agent's returned summary piles up in my context and the run
caps out after a few batches.

A Workflow moves the **coordinator into deterministic JavaScript**:

| | inline (Agent tool) | Workflow |
|---|---|---|
| `framac-sl` instance | isolated context | isolated context (same) |
| `framac-monitoring` coordinator | **the chat (my context)** | **plain JS — zero LLM context** |
| per-unit results land in | my context (accumulate) | JS variables |
| scale | a few batches | the whole queue |
| runs | foreground, blocks | **background**, notifies on completion |

The sub-agents don't change; the *coordinator* stops competing for my window.

## Mental model

```
Workflow script (JS coordinator — not an LLM)
  queue = [{file, flags}, ...]   (from framac-queue.sh — flags carry -I/-D per unit)
  chunk the queue into batches of N:
     for each batch (sequential, so commits are ordered):
        pipeline over its N units (concurrent, capped ~min(16, cores-2)):
           stage 1  agent framac-sl  -> annotate + frama-c -wp -wp-rte   (isolated context)
           stage 2  agent monitor    -> faithfulness gate, revert if fabricated
        agent committer -> update verdict log + git commit this batch
```

- `agent(...)` = one isolated sub-agent. With a `schema` it returns a validated object.
- `pipeline(items, s1, s2)` = each unit flows s1→s2 independently, no barrier; the call
  resolves when all are done — *then* the batch commit runs.
- The script has **no filesystem access**, so the queue is passed in via `args`.

## Preparing the queue (passed as `args`)

Unlike the Creusot port, each item must carry its **preprocessing flags**. Build a
compilation database, then compute the remaining-units queue with `framac-queue.sh`:

```sh
# 1. produce a compile_commands.json (pick one):
bear -- make                                   # Bear intercepts the build
# cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..   # CMake emits it directly
# 2. mirror the pristine sources so the faithfulness gate has an original to diff:
rsync -a --include='*/' --include='*.c' --include='*.h' --exclude='*' src/ framac-orig/
rsync -a framac-orig/ framac/
# 3. emit the {file, flags} queue, skipping units already in the verdict log:
./framac-queue.sh compile_commands.json framac/.verdicts.tsv > /tmp/framac-queue.json
```

Then invoke the Workflow tool with:

```json
{
  "script": "<the script below>",
  "args": { "repo": "$HOME/git/use-frama-c",
            "batch": 8,
            "machdep": "gcc_x86_64",
            "units": [ { "file": "src/peimage.c", "flags": ["-Iinclude", "-DLACE"] },
                       { "file": "src/mbr.c",     "flags": ["-Iinclude"] } ] }
}
```

`args.units` is the verbatim queue (from `framac-queue.sh`); `args.batch` is the batch size.

## The workflow script

```javascript
export const meta = {
  name: 'framac-monitoring',
  description: 'Drive framac-sl over framac/: annotate+prove each C unit with WP, monitor-gate, commit per batch',
  phases: [
    { title: 'Prove',   detail: 'framac-sl: add ACSL + frama-c -wp -wp-rte' },
    { title: 'Monitor', detail: 'faithfulness gate (strip ACSL == original), revert fabrications' },
    { title: 'Commit',  detail: 'update verdict log + git commit per batch' },
    { title: 'Capitalize', detail: 'distill heuristics -> Gate S audit -> append to learned-*.md' },
  ],
}

const REPO     = (args && args.repo)     || '$HOME/git/use-frama-c'
const BATCH    = (args && args.batch)    || 8
const MACHDEP  = (args && args.machdep)  || 'gcc_x86_64'
const UNITS    = (args && args.units)    || []
// Extra preprocessor args appended to -cpp-extra-args. The StandardAlgorithms
// corpus needs `-include typedefs.h` because the ACSL strip removed the .acsl
// chain that used to pull in the value_type/size_type typedefs.
const CPP_EXTRA = (args && args.cppExtra) || '-include typedefs.h -include size_type_pair.h -include Stack.h'

// --- structured outputs (agents are forced to return these) ---
const VERDICT = {
  type: 'object', additionalProperties: false,
  required: ['file', 'verdict'],
  properties: {
    file:    { type: 'string' },
    verdict: { type: 'string', enum: ['PROVED', 'PARTIAL', 'FAILED', 'TRIVIAL'] },
    goals:   { type: 'string' },   // e.g. "31/31 Valid" or "30/31 (1 Unknown: -x overflow)"
    spec:    { type: 'string' },
    learned: { type: 'string' },
    bug:     { type: 'string' },   // a localized undischarged RTE goal => candidate bug
  },
}
const GATE = {
  type: 'object', additionalProperties: false,
  required: ['file', 'faithful', 'gateB', 'gateC', 'finalVerdict'],
  properties: {
    file:         { type: 'string' },
    faithful:     { type: 'boolean' },                                  // strip ACSL == framac-orig
    gateB:        { type: 'string', enum: ['CLEAN', 'HATCH'] },         // no smuggled escape hatch
    gateC:        { type: 'string', enum: ['TEETH', 'VACUOUS', 'INCONCLUSIVE', 'NA'] }, // mutation probe (non-vacuity)
    gateCp:       { type: 'string', enum: ['COMPLETE', 'INCOMPLETE', 'NOGOLD'] },       // completeness vs gold
    finalVerdict: { type: 'string' },    // PROVED only if faithful && CLEAN && TEETH && gateCp in {COMPLETE,NOGOLD}
    note:         { type: 'string' },
  },
}

function chunk(a, n) { const o = []; for (let i = 0; i < a.length; i += n) o.push(a.slice(i, i + n)); return o }
function rel(f)  { return f.replace(/^framac\//, '') }
function flags(u) { return (u.flags || []).join(' ') }

// --- the framac-sl sub-agent (annotate + prove ONE unit) ---
function provePrompt(u) {
  const f = u.file
  return `You are a framac-sl sub-agent. Add ACSL specs to ONE C translation unit and prove it with Frama-C/WP.
TARGET: ${REPO}/framac/${rel(f)}   PREPROCESS FLAGS: ${flags(u)}

CRITICAL FAITHFULNESS RULE: do NOT add/remove/rename/modify ANY executable C — no statement,
declaration, #define, or #include change. ONLY add ACSL, which lives entirely in /*@ ... */ and
//@ ... comments (function contracts requires/ensures/assigns, loop invariant/assigns/variant,
//@ assert, /*@ ghost ... */, predicate/logic/lemma). Stripped of every ACSL comment your file MUST
be byte-identical to ${REPO}/framac-orig/${rel(f)}. If nothing can overflow/divide/index/deref out of
bounds (no-op / decl-only), return verdict TRIVIAL and change NOTHING. NEVER use Admitted, a
lemma-as-axiom, or a stub 'ensures' stronger than the callee proves.

GOAL: specify for TOTAL ROBUSTNESS first — run with -wp-rte so every runtime-error (overflow,
div-by-zero, mem-access, shift) becomes a goal. An undischarged RTE goal that cannot be closed
WITHOUT restricting the input is a candidate BUG — report it in 'bug' with the goal and the source
line; do not paper over it with a narrowing requires.

RUN (pin the model/prover/timeout so it is deterministic). NOTE: Frama-C rejects bare -I/-D;
preprocessor flags MUST go inside -cpp-extra-args:
  cd ${REPO} && frama-c -machdep ${MACHDEP} \\
       -cpp-extra-args="${flags(u)} ${CPP_EXTRA}" \\
       -wp -wp-rte -wp-prover alt-ergo,z3,cvc5 -wp-timeout 10 framac/${rel(f)}
Iterate <=3 times. Reference ${REPO}/config/skills/frama-c/SKILL.md and
.../references/learned-annotator.md. If ALL goals are Valid, leave the annotated file in place and
return PROVED; if some stay Unknown, return PARTIAL with the goal list. Return the structured verdict.`
}

// --- the monitor for ONE unit: faithfulness + Gate B + Gate C ---
function gatePrompt(u, v) {
  const r = rel(u.file)
  const h = r.replace(/\.c$/, '.h')
  return `You are the framac-monitoring base-SL monitor. Verify unit ${r} (framac-sl said: ${JSON.stringify(v)}).
Run THREE checks against the disjoint oracle, never the prover agent's notes.

(1) FAITHFULNESS (only-ACSL-added): cd ${REPO} && ./framac-monitor-check.sh ${r} ; ./framac-monitor-check.sh ${h}
    Both ACCEPT -> faithful=true. EITHER FABRICATED -> revert it (cp framac-orig/<rel> framac/<rel>),
    faithful=false, gateB/gateC=NA, finalVerdict=FAILED (TRIVIAL if original is a no-op); drop any 'bug'.

(2) GATE B (no smuggled hatch): grep -nE 'admit|Admitted|\\\\trusted|assert[[:space:]]*\\\\false|assumes[[:space:]]*\\\\false' framac/${r} framac/${h}
    Any hit -> gateB=HATCH, finalVerdict=FAILED. CARVE-OUT: a DEFINITIONAL axiomatic/axiom (only defines a
    logic/predicate via its base/step equations) is legitimate; flag an axiom only if it references the C
    function name or \\result (a behavioral fact). Else gateB=CLEAN.

(3) GATE C (non-vacuity): ./framac-mutation-probe.sh ${r}
    TEETH -> gateC=TEETH (also confirms any axiomatic is consistent). VACUOUS/INCONCLUSIVE is NOT
    terminal — the generic probe (it only flips +/-/<=/==, skipping ACSL spans) can miss a real spec.
    You MUST then author ONE targeted mutation of the BODY (perturb a returned expr / assigned var /
    call arg) in place, re-run WP, then restore by `cp` from a UNIQUE-per-unit /tmp backup (e.g. /tmp/mp_bak.$(echo rel|tr / _)) made BEFORE mutating (NOT git checkout — the prover's ACSL is uncommitted, so git checkout would wipe it to the stripped baseline). Fewer goals -> TEETH. Only if even a
    targeted body mutation cannot break a goal (postcondition trivially true for any run, e.g.
    'ensures \result==0||\result==1') -> gateC=VACUOUS, finalVerdict=FAILED + "strengthen the spec".

(4) GATE C' (completeness vs gold — catches what the probe cannot: a spec with teeth that omits the
    intended property): hint = ./framac-completeness.sh ${r}; then judge editorially (spec text only),
    diff gold ensures vs loop ensures: for each property the GOLD ensures, is an EQUIVALENT in the loop
    (an inlined \forall/\exists of a gold predicate counts)? gateCp=COMPLETE / INCOMPLETE(name the miss)
    / NOGOLD. The hint over-flags inlined predicates — editorial judgment overrides.

finalVerdict = the framac-sl verdict ONLY IF faithful && gateB==CLEAN && gateC==TEETH && gateCp in
{COMPLETE,NOGOLD}; gateCp==INCOMPLETE downgrades PROVED -> PARTIAL ("gold ensures <prop>, loop omits it").
Return the structured gate result (put gate outputs in 'note').`
}

// --- the per-batch committer ---
function commitPrompt(n, results) {
  return `You are the framac-monitoring committer for batch ${n}. In ${REPO}:
1. Append one TSV line per result to framac/.verdicts.tsv as "<file>\\t<finalVerdict>\\t<note>" using: ${JSON.stringify(results)}.
2. Run ./framac-gen-verdicts.sh to regenerate framac/VERDICTS.md.
3. For any result carrying a 'bug', draft a report under framac-issues/ (minimal adversarial input + a draft patch),
   following framac-issues/README.md.
4. git add the batch files (${results.map(r => 'framac/' + rel(r.file)).join(' ')}) + framac/VERDICTS.md + framac/.verdicts.tsv + any framac-issues/*.md.
5. Commit: git commit -m "framac-monitoring batch ${n}: <PROVED/PARTIAL/FAILED/TRIVIAL counts>\\n\\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>".
Report the commit hash.`
}

const batches = chunk(UNITS, BATCH)
const all = []
for (let b = 0; b < batches.length; b++) {
  phase('Prove')
  log(`Batch ${b + 1}/${batches.length} — ${batches[b].length} units`)

  const gated = await pipeline(
    batches[b],
    (u)    => agent(provePrompt(u),    { label: `sl:${rel(u.file)}`,  phase: 'Prove',   schema: VERDICT }),
    (v, u) => agent(gatePrompt(u, v),  { label: `mon:${rel(u.file)}`, phase: 'Monitor', schema: GATE }),
  )
  const results = gated.filter(Boolean)
  all.push(...results)

  phase('Commit')
  await agent(commitPrompt(b + 1, results), { label: `commit:b${b + 1}`, phase: 'Commit' })

  phase('Capitalize')
  await capitalize(results.filter(r => r.finalVerdict === 'PROVED').map(r => r.file))  // see below

  if (budget.total && budget.remaining() < 60_000) { log('budget reached — stopping'); break }
}
return { processed: all.length, proved: all.filter(r => r.finalVerdict === 'PROVED').length }
```

## Capitalization (Gate S) phase

After each batch's verdicts are committed, the loop must **leave the next batch smarter** —
otherwise enrichment is read-only and the skill never grows from running. This is the
`sl-monitoring-sl` Gate S step, wired as a sub-phase with **three disjoint roles** (the prove
agents — the producers — never write their own skills):

1. **distiller** — reads the batch's *PROVED* units and proposes ≤4 generalizable, role-tagged
   heuristics (never a verbatim copy; spec-author/verifier entries carry **no** implementation
   specifics).
2. **Gate S monitor** (disjoint) — audits each candidate against `U` (ACSL/Frama-C semantics)
   and `L` (frama-c's *actual* behaviour, run if unsure), judging the heuristic **text only**,
   not the distiller's rationale. ignore-signal → trigger test → CARVE-OUT; defer-to-oracle →
   validity test → PASS; escape-hatch-as-fix / barrier leak / too-specific / contradicts `U` →
   REJECT. It must *discriminate*, not rubber-stamp.
3. **appender** — appends only PASS/CARVE-OUT entries (with provenance + Gate S verdict) to the
   right `config/skills/frama-c/references/learned-*.md`, append-only, and commits.

```javascript
const CANDIDATES = { type:'object', additionalProperties:false, required:['skills'], properties:{
  skills:{ type:'array', items:{ type:'object', additionalProperties:false,
    required:['targetFile','kind','title','heuristic','evidence'], properties:{
      targetFile:{ type:'string', enum:['learned-annotator.md','learned-spec-author.md','learned-verifier.md','learned-coordinator.md'] },
      kind:{ type:'string', enum:['ignore-signal','defer-to-oracle'] },
      title:{ type:'string' }, heuristic:{ type:'string' }, evidence:{ type:'string' } } } } } }
const GATES_S = { type:'object', additionalProperties:false, required:['title','targetFile','verdict'], properties:{
  title:{type:'string'}, targetFile:{type:'string'},
  verdict:{ type:'string', enum:['PASS','CARVE-OUT','REJECT'] }, entry:{type:'string'}, reason:{type:'string'} } }

async function capitalize(provedFiles) {
  if (!provedFiles.length) return
  const cand = await agent(distillPrompt(provedFiles), { label:'distill', phase:'Capitalize', schema:CANDIDATES })
  const audited = (await parallel((cand?.skills||[]).map(s => () =>
    agent(gateSPrompt(s), { label:`gateS:${(s.title||'').slice(0,18)}`, phase:'Capitalize', schema:GATES_S })))).filter(Boolean)
  const approved = audited.filter(a => a.verdict === 'PASS' || a.verdict === 'CARVE-OUT')
  if (approved.length) await agent(capCommitPrompt(approved), { label:'capitalize-commit', phase:'Capitalize' })
}
// distillPrompt / gateSPrompt / capCommitPrompt: see the demo script
// framac-monitoring-smallbatch-*.js for the exact prompt text.
```

## Bounding cost

## Bounding cost

Pass a token target with the run (e.g. prefix your request with `+800k`); then `budget.total`
is set and the `budget.remaining()` guard stops the loop cleanly before it overruns. With no
target it runs the whole queue.

## Running, watching, resuming

- **Launch:** call the Workflow tool with `{ script, args }` (or save the script and pass
  `{ scriptPath, args }`). It returns a `runId` immediately and runs in the **background**.
- **Watch live:** `/workflows` shows the phase tree (Prove / Monitor / Commit) and which
  units are in flight.
- **Resume after a stop/edit:** relaunch with `{ scriptPath, resumeFromRunId: "<runId>" }`
  — completed `agent()` calls return cached results; only new/edited units re-run. The
  on-disk verdict log also re-queues the unprocessed units next time.

## What stays true to the loop design

- **Isolated contexts:** each `framac-sl` and each monitor check is its own agent — the JS
  coordinator holds only small structured results.
- **Monitor runs three gates unattended:** (1) **faithfulness** — `framac-monitor-check.sh`
  (stripping the ACSL must reproduce the original C) rejects/reverts fabrications; (2) **Gate B**
  — grep for smuggled escape hatches (`admit`/`Admitted`/`\trusted`/`assert \false`), with a
  carve-out for *definitional* `axiomatic`/`axiom` (the standard way to define a recursive logic
  function — legitimate; only a behavioral axiom mentioning the C function or `\result` is a
  hatch); (3) **Gate C** — `framac-mutation-probe.sh` mutates the body and requires the proof to
  break (`TEETH`), which also exposes a vacuous spec or an inconsistent axiomatic; and (4) **Gate C'**
  — completeness vs the human gold (`framac-completeness.sh` hint + an editorial gold-vs-loop ensures
  comparison), which catches a spec that has teeth but omits the *intended* property (a sort proving
  sortedness but not permutation; a search proving only a result-bound). A unit is only PROVED if
  faithful && gateB CLEAN && gateC TEETH && gateCp ∈ {COMPLETE, NOGOLD}; gateCp INCOMPLETE → PARTIAL.
- **Gate-defined done & per-batch commits:** verdicts come from `frama-c -wp` + the three gates,
  and every batch is committed.
- **Bugs surface as undischarged RTE goals:** the `bug` field carries a localized,
  unprovable runtime-error goal; the committer turns it into a `framac-issues/` report —
  exactly the mechanism that produced the four `lace` issues for the Creusot loop.
- **Capitalization (now wired in):** the **Capitalize** phase (above) distills heuristics from
  the batch's PROVED units, Gate-S-audits them with a *disjoint* monitor, and appends only
  PASS/CARVE-OUT entries to `config/skills/frama-c/references/learned-*.md` with provenance —
  so each batch leaves the next smarter. The three roles (distiller / Gate-S monitor / appender)
  are disjoint from the prove agents, so no producer commits its own skill. Without this phase,
  enrichment is **read-only** (agents consult the learned files but never grow them).

## Frama-C-specific caveats (vs the Creusot workflow)

- **Preprocessing flags are mandatory, and go through `-cpp-extra-args`.** Frama-C rejects a
  bare `-Ifoo` (`option -Ifoo is invalid; use -cpp-extra-args="-Ifoo"`). So the queue's
  `flags` (derived from `compile_commands.json` by `framac-queue.sh`) must be wrapped:
  `-cpp-extra-args="<flags> <CPP_EXTRA>"`. A unit that still won't preprocess (a generated
  header, a missing define) is a `gap`, not a proof failure.
- **The StandardAlgorithms corpus needs `-include typedefs.h`** (the `CPP_EXTRA` default).
  Its `value_type`/`size_type` typedefs reached the units *through* the `.acsl` include chain
  (`min_element.h` → `ArrayExtrema.acsl` → … → `typedefs.h`), which the ACSL strip removed.
  Force-including `typedefs.h` via the preprocessor restores them **without editing the
  source** (so the faithfulness gate still passes); some headers include `typedefs.h`
  directly and are unaffected.
- **Pin the machine model** (`-machdep`). `sizeof`, integer widths, and overflow bounds
  depend on it; a different `-machdep` between the local run and the re-run breaks
  determinism and can flip an RTE goal.
- **WP is per-function and modular.** Schedule **leaf functions first** and propagate each
  proven callee `ensures` as the caller's assumption (bottom-up), exactly as the Creusot
  loop propagated `#[ensures]`.
- **One oracle — WP only (no EVA).** WP goal discharge is the sole executable lower bound
  (TCB-minimization; see `loops-design.md` §6.2). Risk-rank the corpus from the Phase-0
  architectural-audit attack-surface ranking, **not** a `frama-c -eva` sweep — EVA is not used,
  not even to triage. Gate C still forbids substituting a runtime test pass for a WP proof.

## Field lessons — faithfulness gate + verdict discipline (Mbed TLS 4.1.0)
- **The faithfulness strip can FALSE-positive `FABRICATED` on non-ACSL prose comments.** `framac-monitor-check` /
  strip-ACSL removes ACSL comments (`//@`, `/*@ … */`), **not** arbitrary prose `/* … */`. A unit a prior
  campaign annotated with explanatory prose then reads `FABRICATED` even though its **executable C is
  byte-identical to HEAD**. Before reverting on a `FABRICATED`, confirm with a strip-*all*-comments diff
  (e.g. `gcc -fpreprocessed -dD -E -P` on the working tree vs `git show HEAD:<rel>` of the **owning** repo
  *or submodule*). Only a difference in *executable* C is a real fabrication; prose-only differences are not.
- **Residual *classifications* drift — re-derive the class on revisit, don't trust the stored label.** Two
  mbedtls verdicts were mislabelled: CSR's "termination" residual was actually a `+cast`/libc
  `memset_requires_valid_s` `[Timeout]` (there was **no** failing termination goal — the `terminates`
  lines were kernel warnings on uncontracted callees), and CRL's "gap#1 alloc" residual was the same
  `memset` timeout. When you revisit a PARTIAL, re-classify each open goal from the actual WP output
  (counter-model? `[Timeout]`? which tooling defect — `+cast`-frame / `\fresh` / libc-init? crypto-oos?)
  rather than carrying the old label forward. And `[Timeout]` ≠ refutation: **no counter-model = no bug.**
