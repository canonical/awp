# Learned knowledge — Coordinator (framac-sl)

Append-only, Gate-S-gated judgment/gate heuristics the **coordinator** capitalized while
running the `framac-sl` loop (see `../../framac-sl/SKILL.md` §11). Each real entry passes an
`sl-monitoring-sl` Gate S audit by a disjoint monitor (the verifier or a human — the
coordinator never self-audits its own heuristics) and carries provenance.

**Scope / barrier:** gate-judgment patterns only — clause-typing, NOT-claim patterns, when
a DRAFT must be cut/sharpened, how to recognize a vacuous contract at Gate A before WP runs.
Never records implementation specifics.

**Entry format:**
```
### <title>
- Kind: ignore-signal | defer-to-oracle
- Gate S: PASS | CARVE-OUT
- Arose from: <file / gap-N>
- Heuristic: <rule>
- Carve-out: <exception → requirement clause>   (if any)
```

## Seed entries (PROVISIONAL — confirm via Gate S on first real use)

### A robustness item with no external functional requirement is still terrain A, not B
- Kind: defer-to-oracle
- Gate S: PROVISIONAL (seed)
- Arose from: seed (porting `creusot-sl` §0 to Frama-C)
- Heuristic: when the only goal is "no runtime error for any input" via `-wp-rte`, the
  upper bound `U` is the **C language standard**, which is *external* — so the item is
  terrain A (transcription), and author independence is less load-bearing than for a
  functional contract. Approve an RTE-only plan against the standard's UB list, not against
  a body-derived summary.

### Reject any `requires` that narrows the adversarial input on an attack-surface unit
- Kind: ignore-signal
- Gate S: PROVISIONAL (seed)
- Arose from: seed (lace-run security Gate C, ported)
- Heuristic: on an untrusted-input parser, a `#[requires]`/`requires` that restricts the
  input is a Gate-C violation — the proof must come from the parser's own runtime checks,
  not from assuming the attacker is polite. The only admissible preconditions constrain the
  *type/structure* (e.g. a struct-field relation as a type invariant), never the attacker's
  bytes. An undischarged goal that needs an input restriction is a candidate **bug**, not a
  missing annotation.

## Verified entries (Gate S — from batch-4 verification)

### A "PROVED" with a range-only / shape-only ensures is under-specified — require Gate C′ vs gold
- Kind: ignore-signal
- Gate S: PASS
- Arose from: batch 4 — find_first_of (ensures only `\result<=m`), is_heap_until (only `0<=\result<=n`),
  the sorts (Sorted but no permutation), remove_copy (bound+no-v only) all passed faithful+B+C yet were
  under-specified; the machine probe could not catch it.
- Heuristic: do NOT accept PROVED on the strength of faithful + Gate B + mutation-TEETH alone — those
  bound NON-VACUITY, not COMPLETENESS. Add **Gate C′**: compare the loop's `ensures` to the intended
  property (the requirement, or the human `gold` spec via `bin/framac-completeness.sh` + an editorial
  gold-vs-loop diff). Tell-tale of an under-specified "proof": the only `ensures` is a **result bound**
  (`\result <= n`) or a **target-shape** predicate (sorted/heap) with no functional/relational clause
  tying the result to the input. Such a unit is PARTIAL. The completeness hint OVER-flags (a loop that
  INLINES a gold predicate via `\forall`/`\exists` under a different name — SomeEqual≡`\exists k;a[k]==v`,
  FindNotEqual≡the first-mismatch `\forall`+boundary — is COMPLETE); resolve naming by editorial judgment,
  never by the token match. (See [[learned-spec-author]] permutation entry, [[learned-verifier]] sorting trap.)

### A wrapper's ensures may never exceed what the in-scope callee contract proves — else green is vacuous-by-opacity
- Kind: ignore-signal
- Gate S: PASS
- Arose from: framac/Stack/stack_equal.c forwards to `equal` (framac/Nonmutating/equal.h) and stack_equal's `\result <==> (sz_eq && \forall elementwise)` is exactly equal's `\forall`-equality plus the size guard; find4's contract is identical to find3's. The proofs hold only because each callee contract is in scope. (capitalization, this batch)
- Heuristic: At Gate-A/Gate-C judgment for a thin delegating unit (body forwards to one callee, or restates a callee result), check that the wrapper's `ensures` is IMPLIED by the in-scope callee `ensures` — not stronger. If the wrapper claims a property the callee never establishes, one of two failures is hiding: either the callee contract is absent and WP closed the goal vacuously by modelling the call opaquely (coherent-and-wrong green), or the wrapper spec is an escape-hatch overclaim. The honest move is to confirm the callee contract is in scope AND that removing it flips the wrapper goal to `Unknown` (a real teeth check on the dependency). A wrapper that stays green with its callee unspecified is a rubber stamp; treat its verdict as PARTIAL until the callee guarantee is shown to carry the postcondition. This is the gate-judgment dual of the spec-author 'stub ensures may never exceed the callee guarantee' rule, applied to in-scope (not stubbed) callees. (Confirmed on L: with equal's ensures in scope stack_equal.c proves 16/16; stripping it flips typed_stack_equal_ensures to not-Valid at 13/14. "Unknown" covers Timeout / any non-Valid outcome. Apply the teeth check only to the part of the wrapper post that depends on the callee — wrapper-body facts like a size guard may legitimately add to the callee guarantee.)

### A well-definedness (_wd) wrapper attaches its contract at the .c DEFINITION, not the header, to keep the header byte-identical under the faithfulness gate
- Kind: ignore-signal
- Gate S: CARVE-OUT
- Arose from: framac/Stack/StackWellDefinedness/stack_top_wd.c attaches its contract to the definition (`ensures \result <==> (ternary over s->data == ternary over t->data)`) because the TU does not include the header; the stack_top.h-side header documents the intended contract in an ACSL-only comment and notes the byte-identical-stripped rationale; preconditions require valid_read over `data+(0..cap-1)` and `cap>=1` so the empty-case fallback read is valid. PROVED, gateB clean, gateC teeth. (capitalization, this batch) (capitalization, this batch)
- Heuristic: When judging a well-definedness / determinism wrapper unit (a `_wd` function that calls a queried operation on two inputs and returns whether the two results agree), do NOT require the contract to live in the sibling header. If the translation unit does not #include that header in the original, adding an #include is a non-ACSL change to executable C and breaks the faithfulness gate; the correct, gate-legal placement is the contract directly above the function definition in the .c, with the header kept ACSL-only (or mirroring the contract in a comment) so that, stripped of ACSL, it is byte-identical to the original. At Gate A/C, accept the body-attached contract and verify the header still strips clean; flag a FABRICATION only if an actual C token (#include, #define, type) was added. The well-definedness postcondition itself should be a single biconditional comparing the two calls' results — `ensures \result <==> (call(s) == call(t));` — with read-validity required over the full extent every branch of the callee may touch (including any defensive empty-case fallback slot).
- Carve-out: original TU already #includes a header where placing the contract keeps the stripped source byte-identical (e.g. the operation's own declaration header) -> defer to the faithfulness gate, not to "definition only": put the contract wherever preserves byte-identity-after-ACSL-stripping; definition-attachment is mandatory only when no such already-included header exists. (And the placement rule never licenses an admit/axiom/trusted/vacuous spec: the real, non-vacuous biconditional must sit where WP actually checks it.)
