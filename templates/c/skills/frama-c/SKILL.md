---
name: frama-c
description: >-
  Annotate C programs with ACSL specifications for verification with Frama-C
  (the analysis platform whose WP plugin translates C + ACSL into verification
  conditions and discharges them with SMT solvers via Why3). Covers function
  contracts (requires/ensures/assigns), the memory predicates \valid/\valid_read/
  \separated, \result, \old/\at, behaviors and assumes/ensures, loop annotations
  (loop invariant/loop assigns/loop variant), assertions //@ assert and //@ check,
  ghost code /*@ ghost ... */, logic functions and predicates, lemmas and
  axiomatic blocks, the RTE plugin (-wp-rte: overflow/div-by-zero/mem-access/shift
  goals), EVA value analysis, ACSL stubs for external functions, the machine model
  (-machdep), prover/timeout selection (-wp-prover/-wp-timeout), and the escape
  hatches (Admitted, lemma-as-axiom, trusted stubs) with their soundness cost. Use
  whenever the user wants to "add an ACSL spec", "annotate this C for Frama-C",
  "add requires/ensures/assigns", "add a loop invariant", "prove this C function
  has no runtime errors", "prove absence of overflow / out-of-bounds", asks why a
  WP goal won't discharge, or asks what \valid, \result, \old, assigns, behavior,
  or \separated mean in an ACSL contract.
---

# Annotating C programs with ACSL

Frama-C verifies C by parsing it together with **ACSL** (ANSI/ISO C Specification
Language) annotations, and — through the **WP** plugin — computing verification
conditions (proof obligations) that it discharges with SMT solvers (Alt-Ergo, Z3,
CVC5) via the Why3 platform. You write specifications in ACSL, carried entirely in
special comments. This skill is the reference for *writing those annotations
correctly*.

Run the verifier with `frama-c -wp [FLAGS] FILE.c`; add `-wp-rte` to also generate
runtime-error goals (overflow, division-by-zero, invalid memory access, bad shift).
A function is verified when every goal reports **`Valid`**.

## Installing the toolchain

The campaign needs **Frama-C 32.1 built from source with `frama-c-patches/`
applied**, not the stock opam package, in the opam switch **`framac-coq8`**
with Coq 8.20.1, Why3 1.8.x, Alt-Ergo and Z3. In short, from the project
root:

```sh
opam init --disable-sandboxing -y --bare
opam switch create framac-coq8 ocaml-base-compiler.4.14.2 -y
eval "$(opam env --switch=framac-coq8 --set-switch)"
opam pin add -y coq 8.20.1                                  # Coq FIRST, PINNED (not Rocq 9)
opam install -y "why3>=1.8.0" "why3<1.9" "why3-coq>=1.8.0" "why3-coq<1.9" alt-ergo z3 && why3 config detect
opam install -y yaml ppx_deriving_yaml ocamlgraph ppx_inline_test unionFind dune
opam install -y --deps-only frama-c.32.1                    # dependencies only
bin/fetch-sources.sh                                        # patched framac-src/, macsl/
(cd framac-src && dune build @install && dune install --prefix "$(opam var prefix)" \
    frama-c frama-c-wp frama-c-rtegen frama-c-region frama-c-server qed)
frama-c -version && frama-c -wp-detect                      # 32.1; Alt-Ergo, Z3, Coq
```

The system packages, the AppArmor fix needed inside an LXD container, the
macsl build, the check that the patches are in the installed binary, and the
pitfalls are in **`references/install.md`**. `frama-c-launch` runs this
recipe itself on a first run when the toolchain is missing.

## Where ACSL lives (load-bearing for the faithfulness gate)

ACSL is confined to comments and never changes executable C:
- **Function/statement contracts and clauses:** `/*@ ... */` before a declaration.
- **Line annotations:** `//@ assert ...;`
- **Ghost code:** `/*@ ghost ... */` (logical-only statements).

The base-SL faithfulness gate (`bin/framac-monitor-check.sh`) strips exactly these and
requires the remaining C to be byte-identical to the original. So: only ever **add**
ACSL; never edit a statement, `#define`, or `#include` to make a goal pass — that is
the FABRICATED failure.

## Core function contract

```c
/*@ requires n >= 0 && \valid(a + (0 .. n-1));
  @ assigns a[0 .. n-1];
  @ ensures \forall integer k; 0 <= k < n ==> a[k] == 0;
  @*/
void zero(int *a, int n);
```

- `requires` — precondition (the caller must establish it).
- `assigns` — the write footprint; **`assigns \nothing;` means the function writes no
  non-local state**. A missing or too-loose `assigns` is a classic vacuous-spec hole.
- `ensures` — postcondition; `\result` denotes the return value; `\old(e)` / `\at(e, Pre)`
  the pre-state value of `e`.
- `\valid(p)` / `\valid_read(p)` — `p` points to writable / readable memory; range form
  `\valid(a + (0 .. n-1))`. `\separated(p, q)` — disjoint memory.

## Loop annotations

WP needs a loop invariant to reason past a loop:
```c
/*@ loop invariant 0 <= i <= n;
  @ loop invariant \forall integer k; 0 <= k < i ==> a[k] == 0;
  @ loop assigns i, a[0 .. n-1];
  @ loop variant n - i;
  @*/
for (int i = 0; i < n; i++) a[i] = 0;
```
- `loop invariant` — holds before and after every iteration.
- `loop assigns` — what the loop body may modify (required for soundness of the frame).
- `loop variant` — a non-negative integer expression that strictly decreases — proves
  **termination**.

## Behaviors

Split a contract by case:
```c
/*@ behavior pos: assumes x >= 0; ensures \result == x;
  @ behavior neg: assumes x <  0; ensures \result == -x;
  @ complete behaviors; disjoint behaviors;
  @*/
```

## Robustness (RTE) — the bug-finding lever

`-wp-rte` emits a goal for each potential runtime error. An RTE goal that **cannot be
discharged without restricting the input** localizes a latent bug:
- signed overflow on `a + b`, `a * b`, `-x` (at `INT_MIN`);
- division/modulo by zero;
- out-of-bounds access (`\valid` fails);
- shift amount out of range.

Specify the parser/boundary function for *total robustness* and read the one
undischarged goal — adding the missing guard closes it. (This is the mechanism that
found the `lace` bugs for the Creusot loop; see `../frama-c-monitoring/references/loops-design.md` §5.)

## A "formal test" — an operational spec proven over all inputs (the SL framing)

A bridge for people who think in **tests**, and the SL technique for getting a *functional* result
**without** hand-writing a brittle, complex declarative `ensures`. A *formal test* is a contract
verified by WP whose inputs are **symbolic** (the parameters), bounded by `requires`, and checked
over the whole domain. The quantifier shift vs a unit test:

| | unit test | formal test (contract + WP) |
|---|---|---|
| inputs | one literal (`f(7)`) | **all** values `requires` admits (∀, symbolic) |
| oracle | runtime `assert` | the postcondition, discharged by WP |
| verdict | pass/fail on that input | `Valid` = holds over the whole domain; an undischarged goal = a class of inputs that breaks it |

### The canonical pattern — broad precondition, simple postcondition, the property in the BODY
The functional property is **not** carried by a complex `ensures`; it lives in a small **test
driver**, and the postcondition is deliberately trivial:
```c
/*@ requires 0 <= a <= 4294967295;   // as BROAD as the function supports — wider = stronger claim
  @ ensures \result == 1;            // deliberately simple: "this test always passes"
  @*/
int formal_test_f(uint32_t a) {
    uint32_t r = function_under_test(a);
    if ( /* the intended property of r w.r.t. a fails */ ) return 0;   // a real check
    return 1;
}
```
`ensures \result == 1` is **correct by design, not vacuous.** Because the body branches, proving
`\result == 1` over the broad `requires` forces WP to prove **every failure branch is unreachable**
— i.e. the checks hold for *every* `a` in the domain. A `function_under_test` that misbehaved on some
input would drive the body to a non-`1` branch and the proof would fail. This **moves the hard part
from "state a correct complex ACSL specification" to "write a test"** (operational, familiar); **WP
supplies the ∀.** It is property-based testing that is *proven*, not sampled — the "demand-driver"
for the function's correctness.

### The cast (why it is sound) — disjoint authorship
- **Agent A** writes an English description of what `function_under_test` does — the requirement (`U`).
- A **disjoint Agent B** writes the driver **from that description, never from the implementation**:
  the broadest precondition + the checks + `return 1` on success.
- **WP** proves `\result == 1` over the domain (`L`).

The barrier is load-bearing: B encodes **intent** (from `U`), not the code's behaviour — without it
the test would mirror the implementation (endogenous → coherent-and-wrong). This is the same
spec-author/verifier ⊥ body barrier as the rest of the loop; the formal test *is* the verifier's
acceptance artifact, lifted from sampled adversarial checks to a **universally-proven** test.

### Where the real risk lives (and how the loop already guards it)
The risk is **not** "the postcondition is too weak" (the simple `\result == 1` is the design). It is
**"does the driver body genuinely test the intended property?"** — and that is exactly the loop's
non-vacuity machinery, not a new concern:
- **author independence** — B writes from `U`, blind to the code, so the test reflects intent;
- **non-vacuity (mutation probe / Gate C)** — mutate `function_under_test`; if `\result == 1` *still*
  proves, the driver has no teeth (e.g. it `return 1`s with no real check) → reject;
- **intent capture (Gate C′ / human terminus)** — did A's English `U` capture the intent, and did B's
  driver faithfully check A's `U`? That chain ends, as always, at a human reading the description.

RTE-robustness is the **safety instance** of the same idea (`-wp-rte` = "no runtime error for *any*
input"), and the **boundary harness** is a concrete symbolic-input formal test: `fc_harness_recv_asn1.c`
(mbedtls §7) splices `read()` → an ASN.1 parser, WP proves safety against the **arbitrary** bytes
`read()` may return, and **EVA exhibits the `[0..255]` domain** — the symbolic "any value" made visible
(harness recipe + `-wp-model +cast`: `../frama-c-monitoring/references/wp-gotchas.md`).

## Logic functions, predicates, lemmas

```c
/*@ predicate sorted(int *a, integer n) =
  @   \forall integer i, j; 0 <= i <= j < n ==> a[i] <= a[j];
  @*/
/*@ logic integer sum(int *a, integer n) = n <= 0 ? 0 : a[n-1] + sum(a, n-1);
  @*/
/*@ lemma sum_nonneg: \forall int *a, integer n;
  @   (\forall integer k; 0 <= k < n ==> a[k] >= 0) ==> sum(a, n) >= 0;
  @*/
```
A `lemma` is itself a proof obligation WP must discharge. An `axiomatic { ... }` block
can declare logic symbols **and axioms** — an axiom is *assumed, never checked*, so an
axiom that encodes a behavioral fact is an escape hatch (the C analogue of an unproven
assumption) and is banned on the target by Gate B.

## A goal that won't close is never a "prover limitation" (Curry–Howard)

Before reaching for Coq, classify *why* a goal is red. By the Curry–Howard isomorphism a
proposition is provable **iff** it is true (the proof type is inhabited iff the proposition
holds in the context). A theorem prover therefore never "fails to prove something true."
There is **no such thing as "not addressable by Coq"** — there are exactly two cases:

1. **SMT incompleteness — the goal IS entailed, the solver just didn't find the proof.** A
   proof term exists (e.g. it needs induction, or a quantifier with no e-matching trigger), but
   SMT's heuristic search gives up. This is the *only* legitimate reason to escalate: Coq
   *constructs* the proof that is provably there. "SMT can't" ≠ "unprovable."
2. **Non-entailment — NO proof exists from the current spec.** There is a model of the
   hypotheses in which the goal is *false*, so even Coq cannot (and must not — it would be
   unsound) prove it. This is **never** a prover limitation; it is a **specification defect**:
   the contracts (the unit's, or a dependency's) are too weak or wrong to entail the intended
   property. The fix is to **strengthen/correct the spec**, never to record the goal as
   "unprovable" and never to escalate hoping Coq will close it.

**Diagnostic — exhibit a counter-model.** If you (or WP) can show hypotheses-consistent state
where the goal is false, it is non-entailed → a spec defect. Example: a unit whose
postcondition is `\result == 1` while the callee it returns only guarantees `\result != 0` —
the model `\result == 2` satisfies every hypothesis and falsifies the goal. The goal is not
"hard"; it is simply not a theorem of the spec, and the callee contract must be strengthened to
`ensures \result == 1` (ACSL additions to a header are faithful — only *executable C* is
frozen). If no counter-model exists and the obstruction is induction/a quantifier, it is
case 1 → Coq. Record a verdict only after this classification; "PARTIAL — prover limitation"
is not a valid outcome.

## When SMT can't (case 1): escalating a lemma to Coq/Rocq

These are the goals **entailed but needing induction or non-linear reasoning**. The canonical
case is proving the Euclidean algorithm returns the *greatest* common divisor:
`∀k. k>0 ∧ k|a ∧ k|b ⇒ k ≤ gcd(a,b)` quantifies over a variable divisor with no e-matching
trigger. Escalate **only the irreducible kernel**, and do it the disciplined way:

- **Isolate the hard fact as a named `lemma`** — never point Coq at a
  function's postcondition VC (it's entangled with WP's memory model). WP makes the lemma its
  own VC; prove that, and the postcondition closes under SMT.
- **Matched toolchain is the prerequisite.** Why3 1.8.2 needs **Coq 8.20.1** (not Rocq 9.x —
  it fails detection, the binary names, and the realization ABI). Use a dedicated opam switch
  `framac-coq8`, **Coq first then Why3/Frama-C**.
- **Generate + replay:** `-wp-interactive update -wp-prover coq` writes `.v` skeletons;
  prover name is lowercase `coq` (confirm via `frama-c -wp-detect`). Put `Require` imports
  **inside `Proof.`** (WP regenerates the prelude), and replay with **`-wp-cache none`** (the
  SMT cache masks new Coq scripts). Audit with `Print Assumptions`: only definitional axioms,
  **0 admits**.
- **Lemmas, not axioms.** Reserve `axiom` for genuine *definitions* (a logic function's
  recurrence); every consequence is a `lemma` and must be proved. A definitional axiom set still
  joins the TCB — consistency-probe it (a deliberately false lemma must NOT prove).

Full install commands, the verified WP interactive-Coq workflow, the GCD worked example, the
`Z.rem`-based proof patterns (C `%` is `Z.rem`, not `Z.modulo`), and the gate checklist are in
**`references/coq-escalation.md`**.

### The trust root underneath a coq green — `coqwp`
A `Print Assumptions`-clean script is necessary but **not sufficient**: `-wp-prover coq`
**inlines** WP's Coq *realization library* `coqwp` (`$(frama-c -print-share-path)/wp/coqwp/`)
into every goal, and those files themselves ship ~57 `Admitted` **lemmas** — the actual TCB of
the Coq backend. For "extreme rigor" work, vendor `coqwp`, classify its unproved items (benign
`WhyType` axioms / sound opaque-symbol Admitteds / trust-bearing lemma Admitteds), and **harden**
the lemmas into machine-checked theorems (self-contained `*_hardened.v` + `Print Assumptions`
whitelist + a `check.sh` CI gate). The rule that governs it — *never realize an abstract Why3
symbol with content to close a goal* (that smuggles an axiom) — and the full witness-model /
axiom-bar / Coq-8.20 recipe are in **`references/coqwp-trust-root.md`**.

## The ACSL standard library — Frama-C ships contracts (check before you stub)

Frama-C bundles an **ACSL-annotated standard library** at `$(frama-c -print-share-path)/libc`,
**included by default** (`-no-framac-stdlib` disables it). So most libc calls a real program makes
are *already specified* — you neither stub them nor treat them as out of scope:
- **`string.h`** — `strcmp`/`strncpy`/`strchr`/`strstr`/`memcpy`/… with `assigns`/`\from` footprints;
  `strlen` and `strcmp` are exposed as ACSL **logic functions**; `strtok` is modelled stateful (a
  ghost `__fc_strtok_ptr`).
- **`unistd.h` / `sys/socket.h`** — `read`/`write`/`close`, `socket`/`bind`/`listen`/`accept` carry
  contracts (named behaviors, bounded `\result`, `\from` deps). **Syscalls are not automatically
  "out of reach."**
- **`stdio.h` variadics** (`snprintf`/`sscanf`/`printf`) carry **no direct contract** — the header
  says so — they go through the **Variadic plugin**, which rewrites each call to a specialized,
  specified function. Reachable, just via that transformation.

These specs are deliberately **coarse** (mostly `assigns`/`\from` + bounded result, not full
input→output semantics), so proving deep functional properties *through* them still needs your own
loop invariants and contracts — **effort, not impossibility**. Verbatim contract excerpts (grounded
in this install) and the grep recipe are in **`references/acsl-stdlib.md`**.

### ⚠ Grounding rule — never assert a negative capability claim from memory
"WP can't prove this", "this is out of WP's reach", "this function is unspecified", "this plugin is a
no-op", "this unit is BLOCKED" are all **claims about the installed tool**, and they have been *wrong*
here before (a meta-property tool wrongly called a "no-op" — really an invocation-order mistake, since
moot under macsl which instruments in place; "main.c's libc is out of reach"
when it is fully specified). **Before stating any such limitation, get evidence:** `grep` the function
in `$(frama-c -print-share-path)/libc`, check `-wp-detect` / the plugin's own test, or run a one-file
probe. This is the same discipline as "a goal that won't close is never a *prover limitation*" (above)
and the non-vacuity gate: a *negative* claim about what the tool can do is as much an evidence claim as
a *positive* one. When unsure, say "I have not checked" — do not assert.

## External functions — ACSL stubs (only when nothing specifies them)

When neither a body in scope nor the libc (above) specifies a call, model it by an ACSL stub written
from the *documented surface* (never the body):
```c
/*@ requires \valid_read(s + (0 .. n-1));
  @ assigns \nothing;
  @ ensures \result <= n; @*/
size_t scan(const char *s, size_t n);
```
A stub `ensures` **stronger** than the real callee guarantees is unsound — when the
callee is in scope, its proven `ensures` must imply the stub.

## Invocation knobs that affect soundness / determinism

- `-machdep gcc_x86_64` — the machine model (integer widths, `sizeof`, endianness).
  Overflow bounds depend on it; fix it so re-runs agree.
- `-wp-prover alt-ergo,z3,cvc5` and `-wp-timeout 10` — prover set and per-goal timeout.
  A goal that only closes at a longer timeout is a probe finding, not a silent win.
- `-wp-rte` — add runtime-error goals (above).
- `-eva` — the abstract-interpretation plugin; whole-program, automatic, sound but
  approximate. **Not used in this methodology** — the no-EVA / TCB-minimization rule
  (verdicts are pure WP; see `frama-c-monitoring` "No EVA" and `loops-design.md` §6.2).
  Risk-ranking comes from the Phase-0 architectural-audit attack-surface ranking, **not**
  an EVA sweep — EVA is excluded both as an oracle and as a triage plane.

## Escape hatches and their soundness cost (banned on the target)

- `Admitted` / admitting a goal in the proof session — discharges nothing.
- An `axiomatic` **axiom** asserting a behavioral fact — assumed, not proved.
- A `lemma` left unproved but used as a hypothesis.
- A trusted/over-promising stub `ensures`.
- `assigns \nothing;` on a function that *does* write — drops the frame, vacuous.

Each makes WP report `Valid` while proving less than intended (coherent-and-wrong).
The loop forbids them on the target and routes the gap to a `gap-N` document instead.

## The per-unit squeeze loop this skill serves

This skill is the ACSL/WP **authoring** reference. The per-unit **squeeze loop** that consumes it — the actor cast and their disjoint `(U,L)` pairs, the physical barriers, Gates A/B/C/C′/S, the loop steps, the executable-oracle setup, the worked pilot, the compliance checks, and the knowledge-capitalization discipline (§11, which the `learned-*.md` files implement) — is specified in **`../framac-sl/SKILL.md`**. The outer loop that drives it over a whole codebase, and the two-loop design rationale, live in the sister skill (`../frama-c-monitoring/references/framac-workflow.md` and `.../loops-design.md`).
