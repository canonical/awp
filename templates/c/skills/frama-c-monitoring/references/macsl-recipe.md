# macsl / HAPPY recipe — Tier-3 system-property policies (with the mandatory negative control)

The Tier-3 tier of the depth ladder (§4b): **global / policy meta-properties** stated once and
instrumented at every matching program point, discharged by WP. **macsl is the canonical tool for
this** — the standalone HAPPY policy framework (a self-contained re-spin that instruments **in place**,
so there is no separate-project / `-then-last` / file-position dance). Use macsl for every system
property (STRIDE: confidentiality, integrity, availability, authorization, …). It runs on this switch
(Frama-C 32.1).

> macsl lives in the repo at `macsl/` (built plugin: `macsl/_build/install/default/lib/macsl/core/macsl.cmxs`).
> Its full STRIDE coverage map + per-letter test fixtures are in `macsl/tests/README.md`; the property
> language + STRIDE↔HAPPY table are in `macsl.md` and `macsl/happy-roadmap.md`.

> **Why macsl over stock Frama-C — two independent wins.** (1) The HAPPY policy language below.
> (2) **A strictly smaller Coq TCB:** macsl vendored + hardened WP's Coq realization library
> (`macsl/axiom-wp/coqwp/`) so the trust surface stock Frama-C leaves admitted — **57 trust-bearing
> lemmas** — is machine-checked to **0** (admit-free `*_hardened.v` twins, CI-gated `check.sh` → exit
> 0; only standard `functional_extensionality`/`sig_forall_dec` for the ℝ-based float lemmas, no custom
> axioms). When a `-wp-prover coq` green is load-bearing, use macsl's hardened `coqwp`. Details +
> stock-vs-macsl table: `../../frama-c/references/coqwp-trust-root.md` §8; classification:
> `macsl/axiom-wp/coqwp/AUDIT.md`. (All 58 trust-bearing lemmas now proven, incl.
> `Pi_double_precision_bounds` via CoqInterval; the parallel Lean cross-check is the remaining work.)

## HAPPY policy syntax
A policy is a global annotation introduced by the `happy` command:
```c
/*@ happy \prop,
      \name(<id | "string">),     // names the generated assertions: "<name>: meta: ..."
      \targets(<TS>),             // \ALL  |  a function-set {f, g}  |  \diff(\ALL, {exempt})
      \context(<C>),              // see below
      P ;                          // an ACSL predicate over the context's meta-variables
*/
```
- **`\targets`** — the functions the policy ranges over (`\diff(\ALL,{gate})` exempts a function).
- **`\context(C)`**, its meta-variables (what `P` may refer to), and the STRIDE letter it serves:

  | context | meaning | meta-variable | STRIDE / family |
  |---|---|---|---|
  | `\writing` | every memory write in the targets | **`\written`** | **T** Tampering — write confinement (`\separated(\written, R)`) |
  | `\reading` | every memory read | **`\read`** | **I** Info-disclosure — read confinement (`\separated(\read, R)`) |
  | `\precond` | injected `requires` on each target | — | **S** Spoofing — check-before-use capability |
  | `\postcond` | injected checked `ensures` on each target | `\old(...)` | **R** Repudiation / **E** Elevation (monotonicity, audit completeness) |
  | `\total` | a `terminates` clause + `-wp-rte` bundle | — | **D** Denial of service — totality + no-fault |
  | `\noninterference` | synthesized self-composition twin | `\secret(p)` | **I** Info-disclosure — noninterference (scoped: parameters) |

  (See `macsl/tests/README.md` for the shipped, prove/fail-tested fixture of each — `phase0`=T,
  `phase1`=I-read, `phase2`=R, `phase3`=E, `phase4`=S, `phase5`=I-noninterference, `phase6`=D.)

## Exemptions
`\fguard(F, P)` / `\diff(\ALL,{F})` carve trusted functions out of a policy (the setter that *may*
write the protected region, the gate that *may* raise privilege). **Every exemption is a residual-risk
entry** (an assumption transferred to that function's own contract), never a silent pass — route it to
the EBIOS W5 register.

## Command line — instruments IN PLACE (no `-then-last`)
macsl instruments the current project directly, so you run `-wp` straight after `-macsl`. Because the
installed stock MetAcsl (if present in the switch) registers the same `\prop`/`\written` builtins,
**load macsl with autoload OFF**:
```sh
MACSL=macsl/_build/install/default/lib/macsl/core/macsl.cmxs
frama-c -no-autoload-plugins -load-module "$MACSL" -load-plugin wp \
        <preprocess flags> -macsl -wp -wp-rte -wp-prover alt-ergo,z3 file.c
```
Diagnostics: `-macsl-print` shows the generated `/*@ assert <name>: meta: … */`; `-macsl-list-targets`
reports how many sites each policy expanded over; `-macsl-set <name>` selects a subset. A zero-expansion
policy **warns** (the non-vacuity gate, below).

## THE VALIDATION DISCIPLINE (mandatory — a green is not evidence by itself)
A `[macsl] Will process N policies` + `[wp] Proved goals N/N` line **proves nothing on its own** — a
policy that expands to *zero* sites lets WP vacuously "pass". Before trusting any macsl result you MUST:
1. **Confirm instrumentation:** `-macsl-print` must show a generated `/*@ assert <name>: meta: … */` at
   the expected program points (and `-macsl-list-targets` a non-zero count). Zero expansion → STOP.
2. **Run a negative control:** a program point that **violates** the policy must turn its generated
   assertion `Unknown`/red. If it still proves, the policy has no teeth → STOP.
Only a policy whose negative control goes red is admissible — the Gate-C non-vacuity rule for
system-property policies. (Negative-control reds often land as `[Timeout]` — fine and
machine-INDEPENDENT for a genuinely-false goal; the determinism concern is about timeout-based GREENs.)

## HAPPY policy-authoring gotchas (verified on macsl/tests/small_example)
When authoring policies on realistic code, four constraints bite (all hit closing EBIOS FE2/FE10/FE11):
- **No function parameters.** A file-level policy CANNOT name a target's PARAMETER — WP aborts
  `LogicTypeError "unbound logic variable <p>"`. Model the request-scoped value as a GLOBAL capability
  set before the call and reference the global (the `session_authenticated` / `caller_acct` /
  `token_active` pattern). This is *why* an authn (`\precond`) policy needs a session global.
- **`\postcond`/`\precond` bind no `\result`.** Using `\result` in `P` gives `LogicTypeError
  "\result meaningless"`. State the property UNCONDITIONALLY — it holds on every path (reject path
  changes nothing; success-path guards establish it), like `priv_monotonic`'s `role >= \old(role)`.
- **String-keyed properties on big libc functions context-bloat.** The caller-lookup loop + libc
  `strcmp`/`strlen` inflate every split goal; SMT won't close it cleanly. Isolate the fact on a CLEAN
  integer-model driver, put the matching RED in the attacks file, and document the real function
  carrying the behaviour (the "isolate a driver" remedy, see wp-gotchas).
- **`if (flag)` is `flag != 0`, not `== 1`.** If a policy asserts `flag == 1`, the gate must be
  `if (flag == 1)` or the call-site goal won't discharge.

## What still gates a real Tier-3 result
Not the tool — the **target code**: a logic-class risk (cert-validation, TLS state machine) the scope
map marks **BLOCKED** (out of WP reach) must be lifted into scope before a policy over it can discharge.
The crypto-math underneath a use-gate stays BLOCKED (residual); macsl proves the *discipline* around it
(check-before-use, validate-before-accept), not the primitive's correctness — record that boundary.
