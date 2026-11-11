# The FIPS 140-3 compliance dossier — `XXX-fips-compliance/`

The dossier is the reader-facing view of a FIPS campaign. A reviewer, an
integrator or a testing laboratory reads it to learn what the campaign
established about the module against FIPS 140-3. It is **always
generated**: every run that emits a report under the `fips` driver (each
`/fips` run, each `/time-loop` interim or final report) regenerates it, in
full, at the project root, next to `PREFIX-fips-report.md`.

`XXX` is the root-safe slug of the **source directory** (`mbedtls` → `mbedtls`,
`zephyr/kernel` → `zephyr-kernel`), whichever entry point runs: the `XXX` of
`/time-loop XXX N`, or the slug of `DIR` for `/fips DIR PREFIX`. It is not the
campaign's artifact prefix (`PREFIX`, often `XXX-analysis`), so a `/fips` run
and a `/time-loop` run on the same source write the same dossier. Below,
`PREFIX` still names the campaign's other artifacts.

## Who writes it, and the code barrier

The dossier is **code-aware**: it quotes findings, functions and
reproducers. So:

- the **coordinator** of the verification campaign writes it (the
  `/fips` Phase 2 agent, or the time-loop coordinator), from the files listed
  under "Sources";
- the **code-blind `fips-sl` author and reviewer never read it**. A re-run of
  the study consumes the code-free feedback packet
  (`PREFIX-fips-feedback-NN.md`) only, as §8 of the skill says. Reading the
  dossier would make the next study endogenous.

## Rules

1. **Derived, never primary.** Every count is recomputed from the ledgers
   (`PREFIX-acsl/verdicts.tsv`, `trusted-base.md`, `formal-tests.tsv`,
   `scope-classification.tsv`) at generation time. The dossier adds no
   verdict, severity or proof of its own. Where it adds an interpretation,
   such as the FIPS relevance of a finding that has no `RQ#`, it says so.
2. **Complete every time.** All nine files below exist after every
   generation, even when a section is empty ("No violation found." is a
   valid `XXX-found-violations.md`). A stale file is worse than none:
   regenerate the whole directory.
3. **Honest sources.** The study's requirements are mostly `src:UNSOURCED`
   paraphrases (rule F3). The dossier repeats that, and marks the ISO/IEC
   19790 clause mapping below as unchecked against the standard's text.
4. **No validation claim.** The README says, in its first paragraph, that
   the dossier is evidence for a laboratory, not a validation, and that the
   residual-risk sign-off is PENDING until a human signs.
5. **Interim is labelled.** When the campaign has not reached its terminus,
   the README and `residuals-and-signoff.md` say "paused at the deadline"
   and list the open items.
6. **Every finding lands in exactly one file**: a violation of a study
   requirement in `XXX-found-violations.md`; a requirement whose mechanism
   is absent in `design-gaps.md`; everything else, FIPS-related or not, in
   `other-findings.md`.

## Sources

| File | Gives |
|---|---|
| `PREFIX-fips-report.md` | F1 (module), F2 (requirements), F3 (failure modes), F4 (obligations), F5 (residuals, sign-off) |
| `PREFIX-fips-gaps.md` | requirements without a code mechanism |
| `PREFIX-found-issues.md` | every finding, by cycle |
| `PREFIX-acsl/verdicts.tsv` | the verdicts per obligation and function |
| `PREFIX-acsl/trusted-base.md` | the trusted base |
| `PREFIX-acsl/formal-tests.tsv` | differential (Oracle-B) tests |
| `PREFIX-acsl/scope-classification.tsv` | per-file scope and open classes |
| `PREFIX-acsl/time-loop.state` | campaign dates, cycles, stop reason (time-loop only) |
| the campaign report (`XXX.md`) | Gate-T status and the open items |
| `config/auto-wp.json` | target level |

## The nine files

| File | Content |
|---|---|
| `README.md` | target (name, version, commit, configuration), target level, method, campaign dates and stop reason, a one-paragraph verdict, the file index, the FIPS-reference caveat, the source files |
| `module-definition.md` | F1 transcribed: MOD, SV, RL, SSP, IF, ST, with the level; then how the code maps to the model (which states, roles and mechanisms exist) |
| `requirements-matrix.md` | one row per `RQ#`, grouped by area: requirement, ISO/IEC 19790 clause, `VO#` and priority, status (vocabulary below), evidence (verdict-row counts by status, the functions, the `RR#`); then totals per status |
| `XXX-found-violations.md` | each VIOLATION: functions, kind, `RQ#`/`VO#`/`FM#`, clause, effect, configuration; the defect; the reproduction (exact calls, controls, file paths); the formal evidence (goal counts, the repaired proof); **the clause explained** (what the requirement demands, why this code contradicts it); precondition and severity; fix |
| `design-gaps.md` | each requirement group whose mechanism is absent: requirements and obligations, what is missing and how that was established, the proposed treatment (design model, wrapper property, test), and the consequence for a module built on the code |
| `other-findings.md` | (1) code defects without a requirement, each with reproduction, effect, a FIPS-relevance line marked as the dossier's reading, fix; (2) observations; (3) tool defects; (4) errors in the campaign's own annotations, caught and fixed; (5) campaign hygiene |
| `proof-evidence.md` | what `PROVED` means here; the method (planes, provers, faithfulness, replay, non-vacuity, differential tests); the headline counts; proved functions by file; what was not covered |
| `trusted-base.md` | counts by class; the irreducible entries with why; the reducible entries still open with where a proof would come from; the retired ones; which proofs rest on which entries |
| `residuals-and-signoff.md` | the F5 residual register; open items; Gate T item by item; what the campaign did not do; the sign-off, PENDING, with what the authority must weigh |

## Status vocabulary of the matrix

| Status | When |
|---|---|
| **VIOLATED** | a `VIOLATION` verdict row cites the requirement's obligation |
| **GAP** | the obligation's rows are `GAP-CANDIDATE`, or `PREFIX-fips-gaps.md` routes it out of plane for a missing mechanism |
| **PROVED** | every obligation row is `PROVED`, none open, and the scope covers every entry the obligation enumerates |
| **PARTIAL** | some `PROVED` rows, and some `OPEN`/`PARTIAL` rows or uncovered entries |
| **NOT STARTED** | only `OPEN` rows |
| **RESIDUAL** | no obligation; an `RR#` names the other technique |
| **N/A** | the area's `N/A` line in F2 |

A requirement can be VIOLATED and have many PROVED rows besides; the matrix
shows both.

## ISO/IEC 19790:2012 clause of each area

FIPS 140-3 adopts ISO/IEC 19790:2012 for the technical requirements; its
clause 7 holds one sub-clause per area. This mapping is from general
knowledge of that standard, which is not vendored (it is paid). Print it with
the caveat, and never present a sub-clause as checked unless the user
supplied the standard.

| Area | ISO/IEC 19790:2012 |
|---|---|
| AR1 module specification | §7.2 |
| AR2 interfaces | §7.3 |
| AR3 roles, services and authentication | §7.4 |
| AR4 software/firmware security | §7.5 |
| AR5 operational environment | §7.6 |
| AR6 physical security | §7.7 |
| AR7 non-invasive security | §7.8 |
| AR8 SSP management | §7.9 |
| AR9 self-tests | §7.10 |
| AR10 life-cycle assurance (including the finite state model) | §7.11 |
| AR11 mitigation of other attacks | §7.12 |
