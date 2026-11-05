# macsl `\context(...)` catalog — the single source of truth

> **This file is the canonical list of HAPPY contexts macsl supports.** Every other skill
> (`time-loop`, `rmf-sl`, `ebios-sl`, `frama-c-monitoring`, `meta-penguin`) **links here** instead of
> re-listing tokens — that is what stops the catalog drifting (the failure that left `\authorized`
> unknown to every skill while it was implemented in the tool).
>
> **The tool is authoritative, not this file.** Regenerate from the plugin:
> ```
> frama-c -load-module $MACSL_CMXS -macsl-list-contexts
> ```
> (`MACSL_CMXS=macsl/_build/default/src/macsl.cmxs`, under the project root; in a workshop with
> the `frama-c-sdk` SDK, `MACSL_CMXS=$FRAMA_C_SDK_MACSL`, the prebuilt plugin, which the canary
> takes by default when it is set). The canary
> `config/skills/frama-c-monitoring/canaries/macsl-contexts-sync.sh` diffs this table against that
> output and FAILS on mismatch — when the tool gains/renames a context, this file must be updated in
> the same change. Source: `macsl/src/macsl.ml` (the `context` type + `run_policy`
> dispatch + `contexts_doc`); syntax in `macsl/docs/usage.md`.

## Soundness invariant (applies to EVERY context — never weaken it)
Every macsl obligation predicate is **UNINTERPRETED** (`\held`, `\stable`, `authorized`, `\hash`,
`\leq`, `\label`, `\secret` carry **no behavioural axiom**). A produced unit MUST have **0 `axiom`
clauses** (`grep -c '^\s*axiom '` = 0). macsl proves only the exact obligation; the trusted predicate
stays a declaration. A `\prop` proven on a **driver** is *not* done — the deliverable is the **in-situ**
proof on the real TU. Every `\prop` needs a **paired non-vacuity attack** (a mutation that violates
exactly that `\prop`, which macsl/WP then reddens); a policy nothing can violate is a REJECT.

## The catalog (token | mechanism | obligation | STRIDE / threat-row | kernel maturity)

| `\context(...)` | mechanism (`macsl.ml`) | obligation | STRIDE / RMF row | kernel maturity |
|---|---|---|---|---|
| `\writing` | H-T `writing_visitor` (assert at each write site) | no write to the guarded state violates P | **Tampering** / integrity | **exercised** (stackmap `sysctl_no_tamper`) |
| `\total` | H-D `emit_terminates` (attaches `terminates`) | the target always returns | **DoS / availability** | **exercised** (insn_array `insn_lookup_total`) |
| `\reading` | H-S `reading_visitor` | no read of the guarded state violates P | Info-disclosure (read-confinement) | latent |
| `\postcond` | H-R `emit_ensures` | P at every return | functional | exercised |
| `\precond` | H-S `emit_requires` | P on entry (checker called) | Spoofing (weak) | parse-gated on full-TU |
| `\noninterference \secret(p,…)` | H-I2 `emit_selfcomp` (self-comp twin) | a public output never depends on the secret(s) | **Info-disclosure / confidentiality** (IM3/TE3) | latent — *the plane WP can't express* |
| `\noninterference(\cost) \secret(…) [\declassify(…)]` | WS5 self-comp + ghost step/branch counter | step/branch count is secret-independent | timing / cost channel | latent |
| `\guarded_by` | WS1 write-site walk → `\held(L)` | every write site holds lock L | **concurrency / data-race** (Tampering·ACC) | latent (stage-1 per-site; lockset bridge = stage-2) |
| `\stable_check` | WS1 check-then-act walk → `\stable(G)` | guard G stable across check→act | **TOCTOU** | latent |
| `\authorized` | WS3 write-site walk → `authorized(principal,OP)` | every protected op has a GENUINE authorized principal | **Elevation-of-Privilege / authorization** (IM7/SA7/TE7) | latent — *was missing from all skills; the highest-value gap* |
| `\tamper_evident` | WS4 `emit_ensures` (hash-chain over `\hash`) | every log append extends the mac chain | **Repudiation / audit integrity** | latent |
| `\fuel` | WS6 ghost step counter (back-edges + calls) → `\fuel <= N` | per-site step counter never exceeds N | **DoS / bounded work** (RS5/IA5) | latent (counter impl; variant-less-loop hard error = TODO `macsl.ml:485`) |
| `\flow` | WS7 write-site walk over `\leq`/`\label` | no flow-up in the user lattice | RBAC + vertical EoP | latent |

"exercised" = discharged in-situ on a real kernel extraction in a campaign. "latent" = implemented and
wired in the tool (parser→dispatch→visitor/emit, non-stub) but **not yet proven on kernel code** — the
`happy-kernel.md` plan + probe upgrades these to "exercised". Keep this column HONEST: do not mark a
context exercised until a real kernel `\prop` discharges in-situ with its paired attack.

## Threat-row → context SELECTION (use this in Plane-H triage — do not default to `\writing`/`\total`)
- **EoP / authorization** (a capability/permission/principal gate) → `\authorized` (not a hand-rolled WP
  postcondition — that is a smell when `\authorized` applies).
- **Info-disclosure** (a secret/kernel-pointer must not leak) → `\noninterference \secret(…)` (or
  `\reading` for simple read-confinement). WP alone cannot express this.
- **Tampering / integrity** (protected state not corrupted) → `\writing`.
- **DoS** → `\fuel` (quantitative bound) or `\total` (termination only).
- **Concurrency / TOCTOU** → `\guarded_by` / `\stable_check`.
- **Repudiation / audit** → `\tamper_evident`.
- **RBAC / lattice** → `\flow`. **Timing channel** → `\noninterference(\cost)`.

## Driver invocation (per `verify-happy.sh`)
```
frama-c -no-autoload-plugins -load-module $MACSL_CMXS -load-plugin wp \
        -macsl -macsl-list-targets <unit.c> \
        -wp -wp-rte -wp-prover alt-ergo,z3 -wp-timeout 25
```
A file-level `//@ happy \prop \name(…) \targets(…) \context(…)[ \secret(…) ];` cannot name function
params → bind them through a request-scoped global. `\postcond` binds no `\result`.
