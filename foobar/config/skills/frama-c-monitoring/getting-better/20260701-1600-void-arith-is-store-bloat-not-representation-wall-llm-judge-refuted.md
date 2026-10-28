# The `void*`/char-range→typed-access "representation wall" is STORE-BLOAT, not a class-A ceiling — and the mechanical twin overrides an LLM judge

**Date:** 2026-07-01 (libbpf `/time-loop` cycle-29). **Bottom line:** a claim I was about to record
class-A — *"the WP bytes model cannot bridge `\valid_read((char*)p+(0..N-1))` to typed-field access"* —
turned out FALSE. Three minimal twins prove it in isolation; the residual is store-bloat.

## What happened (the full anti-pattern, caught)
1. `btf_new`'s parse-glue residuals (`strs_data = raw_data + hdr_len + str_off`, `raw_data` a `void*`)
   would not discharge in-context; weakening `btf_parse_hdr`'s precond to a char-range envelope made the
   whole-function WP not complete in 300s. I framed this as the RS2 `void*`-arith **representation wall**.
2. I routed the claim to the **cross-provider LLM judge** (`gemma4:26b-mlx` @$(cat ~/.local-llm-machine-ip.txt), non-Anthropic)
   per the solo-collapse rule. It ruled **CLASS-A**: *"a fundamental limitation in how the bytes-model
   represents raw memory vs typed pointer validity."* A disjoint attestation — seemingly the green light.
3. The `no_ceiling_gate` still demanded a **minimal non-proving twin**. I built three
   (`reproducers/reprwall{,2,3}.c`): base char-range→typed access; + symbolic offset; + the EXACT
   `btf_new` form `(struct hdr*)((char*)p + hdr_len + str_off)` under `\valid_read((char*)p+(0..n-1))`
   and `hdr_len+str_off+sizeof<=n`. **ALL THREE PROVE 4/4.**
4. Twin proves ⇒ the bridge is closeable ⇒ **CLASS-C (store-bloat)**, not class-A. The LLM attestation
   was **wrong**; the gate (twin-proves checked before the attestation) rejected the class-A correctly.

## The two lessons
- **The `void*`/char-range→typed-access bridge is NOT a bytes-model limitation.** It discharges in
  isolation, including the two-symbolic-add `raw_data + hdr_len + str_off` shape. When it fails in a real
  parser it is **store-bloat** (the big-function context), class-C — the same family as the W1
  `btf_validate_type` switch-dispatch residual. Reach for context reduction / checkpoint-slice / Coq
  `clear`, never a class-A label.
- **An LLM disjoint judge is ADVISORY ONLY for a tool-capability claim — the mechanical minimal twin is
  DECISIVE and overrides it.** The judge cannot run Frama-C; it ruled from the producer's framing, so it
  inherited the producer's error. `no-ceiling.md` Fix B lists the cross-provider judge as the disjoint
  attestor, but for a *mechanical* tool-limit claim the twin is the ground truth and the gate must check
  it FIRST (it does: `_mechanical_failures` runs before the attestation branch). Never let an LLM
  attestation stand in for the twin. (Matches [[cross-provider-judge-ollama]]: "advisory only.")

## Action item — re-check the terminus report's ONE class-A (RS2 `btf_parse_type_sec` `void*`-arith)
The c1–c10 terminus recorded the RS2 residual as **class-A, lever-attested** (base_addr/raw-vs-cast/
void*-form/scaffold all failed). But those levers were tried on the FULL store-bloated function, never a
minimal twin — and the twin here proves. **RS2's class-A is now suspect: likely store-bloat (class-C),
mis-labeled.** Re-run the minimal-twin + `no_ceiling_gate` on it before the next kit ships. This means
libbpf may have **zero** genuine class-A residues — all the "representation walls" are store-bloat.
See [[no-ceiling-gate]], [[wp-typed-ptr-cmp-no-baseaddr]], [[wp-uint8-memcpy-shift-gotchas]].

## RS2 RE-CHECK CLOSED (cycle-30) — bytes-model-specific void*-arith; Typed proves it; REVIEWED-FALSE, not class-A
Ran the twin on the ACTUAL RS2 residual. It is NOT the char-range bridge (that was store-bloat) — it is the
**void*-arith identity** `(char*)(void*+n) == (char*)void*+n` (from `end_type = next_type + type_len`,
`next_type` a `void*`). Findings:
- The bytes-model Coq goal reduces to `valid_rd t (shift a 0) i -> i=0` — **WP models `void*+n` as
  shift-by-0 in the BYTES model** (it does not equate `void*` arith with `char*` arith).
- `reproducers/voididentity.c`: the identity **times out in bytes (3/4)** but **PROVES 4/4 in the TYPED
  model** (with a "void object" warning); the cast-first form `(char*)p+n` proves in bytes (control).
So RS2 is **bytes-model-SPECIFIC**, not a tool ceiling. `no_ceiling_gate` REJECTs the class-A (twin proves
in Typed). **Resolution: REVIEWED-FALSE — the Typed-model 4/4 discharge is the DISJOINT WITNESS that the
identity holds** (the bytes-model timeout is a model-choice artifact; the property is TRUE in GCC
semantics). Same family as [[wp-sint-conversion-wrapper-wall-headless]] ("the wall is BYTES-MODEL-specific
— try Typed before Coq").

**CAMPAIGN CONSEQUENCE: libbpf has ZERO genuine class-A residues.** Both recurring "representation walls"
are closeable — the char-range→typed-access bridge is store-bloat (class-C), and the void*-arith identity
is bytes-model-specific (Typed-witnessed, REVIEWED-FALSE). The terminus report's lone class-A (RS2) was
mis-labeled: its lever-attestation tried bytes-model levers, never the Typed model. Update the kit: RS2 row
class-A → REVIEWED-FALSE (Typed witness); class-A count 1 → 0.
