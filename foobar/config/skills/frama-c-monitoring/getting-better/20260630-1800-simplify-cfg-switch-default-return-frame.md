# WP mis-frames `assigns \nothing` for a `return callee();` in a `switch` default — fix is `-simplify-cfg`

**Date:** 2026-06-30  **Context:** libbpf `/time-loop`, RS2 `btf_type_size` rigor-completion
(`btf.c`).

## Symptom
A function with `assigns \nothing` that does `return callee(args);` in a **`switch` default** branch
(callee also `assigns \nothing`) leaves one assigns goal unprovable by ANY prover. WP prints
`Prove: (ta_tmp_N = false)` where `ta_tmp_N` is a **free, unconstrained variable** — the callee's
`assigns \nothing` is never surfaced as a frame fact, so the goal is non-entailed *as generated*
(trivial counter-model `ta_tmp = true`). Z3 → "Failure", Alt-Ergo → "Timeout"; Coq cannot help (there
is nothing to prove from). Higher `-wp-timeout`, `\valid_read(...)`, `terminates`/`exits`,
`allocates \nothing`, a callee contract instead of inlining, and flipping `-wp-model` all do **not**
help.

## Trap (what the first pass got wrong)
Concluding "the property is true but no prover closes it → class-A WP frame quirk / tool ceiling."
**WRONG** — and it is the exempt-bucket relabel the §6 "no third bucket" rule forbids, one level down:
a *true-but-unprovable* goal is a defect to **diagnose to a minimal reproducer**, never a ceiling to
assert. (A user push — "unprovable though true ⇒ the spec/tool is wrong, investigate" — is what
forced the diagnosis; do it unprompted next time.)

## Diagnosis (the gate: bisect to a 6-line twin)
Rewrite the program structure to an equivalent and re-run with the *same contracts*:
- `switch{ case…; default: return unk(b,p); }` → **fails** `assigns_normal`;
- the byte-identical **`if`-chain** (`if(k==1)…; return unk(b,p);`) → **proves 11/11**, in *either*
  `-wp-model`.
A variant that proves with identical specs localizes the artifact to the `switch` CFG ⇒ it is a WP
**switch-framing bug**, NOT a contract defect and NOT a prover-strength limit.

## Fix
Add **`-simplify-cfg`** (Frama-C kernel option; semantics-preserving CFG normalization, source
untouched → faithfulness intact). It discharges the frame goal. BONUS on the same unit: it also closed
the `to_sint32(K + R*vlen) >= K` postcondition goals with **SMT alone** — i.e. an earlier bytes-model
"to_sint32 wall" that had been escalated to Coq was *also* a raw-switch-CFG artifact, not prover
strength. Net: `btf_type_size` 48/56 (Coq, partial) → **27/27 (pure SMT, no Coq)**.

## Rule to internalize
**Try `-simplify-cfg` early** when a `switch`/`break`/`goto`-heavy function leaves a frame or
postcondition goal that "no prover closes." Goal count drops (here 56→27) because `-simplify-cfg`
merges per-case goals — so **re-run the non-vacuity probe** (flip the ensures bound, confirm it
FAILS) since fewer/bigger goals can hide a vacuous pass. This is a sound-option / Frama-C-behaviour
gap, capitalized here; it is not a spec defect and not a prover limitation.
