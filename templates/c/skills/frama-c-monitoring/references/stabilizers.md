# Frama-C SL stabilizers — anti-collapse rules for `framac-sl` / `frama-c-monitoring`

A *collapse* is any event in which an actor relieves its own squeeze — severing, at that node,
the link between the soft authority it answers to (the requirement/gold) and the executable
ground truth it cannot touch (WP's verdict). This is the Frama-C specialization of the SL
paper's stabilizer catalogue (`paper.tex` §Stabilizers): the practitioner checklist that keeps
the construction's guarantee from eroding in practice. Each rule is distilled from a **real**
catch or near-miss in this project, not invented.

These are *operational lore*, not theorems. The hard gates (faithfulness, WP) are
by-construction; these rules keep the soft side and the disjointness honest.

## Collapse mode → symptom → blocked by

| Collapse mode | Symptom (seen in this project) | Blocked by |
|---|---|---|
| **Fabricated proof** | annotator edits executable C (a forward-decl, a changed statement) so WP goes green | **Faithfulness gate** — `bin/framac-monitor-check.sh` strips ACSL and requires byte-identical to git HEAD (the `ssl_ticket_parse` revert) — rules 1, 2 |
| **Over-promising stub** | an authored callee stub `ensures` stronger than the documented surface; caller "proves" against a fiction | **Gate B over-promise check** (WS5): a stub `ensures` must be implied by the real callee — rule 13 |
| **Vacuous axiomatic** | a definitional `axiomatic` whose axioms are mutually inconsistent → *every* goal proves, green means nothing | **Consistency probe**: a deliberately-false lemma against the axioms must NOT prove — rule 4 |
| **Sorting trap (coherent-and-wrong, soft side)** | `ensures Sorted` proved but permutation absent; a zero-fill body satisfies it | **Gate C′ trivial-witness probe** (`bin/framac-completeness.sh`): a constant/zero/identity artifact must NOT satisfy the spec; disjoint property-author — rules 8, 9, 13 |
| **Assume-the-attacker-away** | a `requires` that narrows the untrusted-input domain; green proof of a parser that ignored malformed input | **Security Gate C**: reject any `requires` restricting the adversarial input — rule 10 (safe direction) |
| **Self-declared done** | "the agent reported 56/67" ends the unit; counts trusted unread | **Gate-defined done** — coordinator re-verifies faithfulness + spot-checks WP; no self-report is evidence — rule 3 |
| **Honorary barrier** | the property-author/verifier has the implementation (or the annotator's rationale) in context | **Physical barriers** — fresh sub-agent context, surface + acceptance only — rule 2 |
| **Same-oracle re-verification mistaken for disjointness** | "independent re-verification" = re-running the *same* WP on the merged tree; can't catch a correlated wrong contract | **Disjoint completeness oracle** (WS2): a code-blind actor holding requirement/gold + WP goal list — the re-run catches faithfulness/concurrency only — (C1) audit |
| **Self-correction mislabeled as a disjoint catch** | an agent reverts its own unsound `ensures` (the `res_valid` revert) and it's reported as the gate working | **Guarantee-kind tagging** (WS3): tag `self-corrected` ≠ `by-construction` ≠ `disjoint-authority` — honest scope, rule 9 |
| **Absorbed surprise** | a WP/model limitation worked around locally (the `+cast` malloc-frame defect; the `\fresh` gap) instead of routed | **Surprise is routed** → `getting-better/` with a reproducer; never a silent local patch — rule 5 |
| **Coverage over-claim** | "machine-checked RTE-robust end-to-end" without the residual taxonomy adjacent | **Headline discipline** (WS6): denominator (amenable surface, not whole tree) + residual list in the same sentence — rule 9 |
| **Concurrent-edit corruption** | parallel agents edit shared headers (`asn1.h`, `x509_internal.h`); the merged tree differs from what each verified | **Re-verify on the merged tree** + leaf-coherence re-runs; faithfulness on every touched file — rule 11 |
| **Unpinned reality** | a flag set / model assumed rather than confirmed (the submodule/parse gate) | **Pin reality before building** — the parse/toolchain gate before any unit (the `gcd`/Coq coupling, the `tf-psa-crypto` submodule) — rule 6 |
| **Weakened clause to land** | "it proves now" after an obligation was quietly softened (e.g. dropping a functional `ensures`) | **Strictness has a safe direction** — record divergence-by-strictness; divergence-by-weakness is a bug — rule 10 |

## The rules (Frama-C form)

1. **Forbidden moves are load-bearing.** Annotator never rewrites behaviour; property-author
   never reads the code; verifier never reads the diff, only the WP verdict; probe writes a
   verdict, never a fix.
2. **Barriers are physical, not honorary.** Each `framac-sl` runs as a fresh sub-agent; a judge
   sees returned verdicts, never a producer's rationale or the implementation.
3. **Done is gate-defined.** Faithfulness ACCEPT + WP all-`Valid` for the claimed scope, witnessed
   by independently-authored ACSL; a self-reported count is never done — the coordinator
   re-verifies (faithfulness on every file; spot-check WP).
4. **Consistency-probe every axiomatic.** A false lemma against the defining axioms must NOT
   prove, or the green is vacuous (definitional-axiomatic carve-out: a recursive-`logic`
   definition is fine; an axiom mentioning the C function/`\result` is a Gate-B hatch).
5. **Route surprise, never absorb.** A WP/Coq limitation → `getting-better/` with a minimal
   reproducer (the two filed gaps); never a silent local workaround.
6. **Pin the toolchain before building.** The parse/flags/submodule/prover coupling is gated on a
   minimal instance first (the `gcd` Coq gate; the `asn1parse.c` parse gate) — not assumed.
7. **Specify the base before extending.** Adopt the gold/requirement as the upper bound; verify
   the transcription (the `reads`-footprint reformulation that dissolved `psum_frame`).
8. **Editorial Gate A before annotation.** The coordinator amends/cuts/sharpens the spec plan
   against the requirement; no annotation from an un-approved plan; a rubber stamp makes the
   upper bound fictional.
9. **Honest scope is a deliverable.** Fixed count convention, residual taxonomy, explicit
   NOT-claims, attribution (WP delivers robustness; the squeeze adds trustworthiness +
   disjoint adjudication); guarantee-kind tags.
10. **Strictness has a safe direction.** A spec/precondition may be stricter than reality, never
    weaker; never assume the attacker away.
11. **Sequence by mechanism reuse; parallelize only across independence.** Parallel `framac-sl`
    only across units sharing no file; when they touch shared headers, re-verify on the merged
    tree (concurrent-edit hazard).
12. **Traceability is an acceptance criterion.** Every annotation traces to an approved spec
    plan / `gap-N`; every artifact is captured as a patch in `mbedtls-acsl/` (or the corpus
    overlay); an unexplained change is a violation.
13. **Where authority is authored, independence is the soundness argument.** With no gold to diff
    against (Archetype B), the only defense against coherent-and-wrong is that the property-author
    and the completeness oracle never saw the implementation; name it explicitly and mark the
    verdict `authored-authority` (weaker guarantee).

See also: `../../frama-c/references/coq-escalation.md` (the WP/Coq operational appendix), `wp-gotchas.md` (consolidated
tooling gotchas), and `getting-better/` (the two filed WP tooling-gap reports).
