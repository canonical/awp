# Onboarding package — handoff contract (frama-c-launch → frama-c-monitoring)

The validated deliverable of a `frama-c-launch` run. Fill one per target; `frama-c-monitoring`
consumes it at Phase 0 / Gate A_top (and **re-judges** it against the verification guidance — a
launch PASS is not a verification claim). Every row's evidence is an **oracle result**, not a
self-report. Mark any unmet oracle `DEPENDENCY UNMET` (never fake a PASS).

```
TARGET:           <library name> @ <version>
DIR:              <vendored clone path>        (its own git repo; in-place overlay)
OVERLAY:          <target>-acsl/               REPORT: <target>-report.md
PROFILE (U):      <the shipped/named feature profile — configure line / user_settings.h / guidance>
GUIDANCE:         <verification target the downstream loop pursues, e.g. RTE-robustness on parsers>
```

## 1. Preprocess context  (prober — Gate B_launch: parse oracle)
- compile_commands.json: <path | hand-built>     (`framac-onboard.sh` / `bear -- make`)
- -machdep: <e.g. gcc_x86_64>
- Flag sets (wrap every `-I`/`-D` in `-cpp-extra-args="…"`):
  - PARSER (leaf): `<-I … -D…>`
  - FULL (cascade units): `<PARSER + …>`
  - force-includes: `<-include …>`              (if a stripped type chain needs them)
  - per-unit scoping: `-wp-fct <fn>` / `-wp-model +cast`  where the queue records them
- Parse-oracle result: <N/M sample units parse clean; "ignoring"/`unbound` warnings: none | …>

## 2. Toolchain  (prober — Gate B_launch: toolchain oracle)
- `frama-c -wp-detect`: <provers listed>
- `framac-coq8` switch: <present | DEPENDENCY UNMET>   (Coq needed for bitmask/induction residue)

## 3. Scope map + attack-surface ranking  (architect — Gate C_launch: completeness)
| Subsystem | WP-amenable (ranked, input-exposure first) | BLOCKED (reason) | scope kind |
|---|---|---|---|
| … | … | inline asm / syscall / crypto / concurrency / float | exogenous-RTE / endogenous-functional |
- Completeness-critic verdict (vs documented attack surface / gold): <COVERS | missing: …>
- Endogenous claims flagged: <list — self-consistency, not conformance>

## 4. Overlay scaffold + faithfulness baseline  (scaffolder — Gate B_launch: round-trip)
```
<target>-acsl/
  patches/    git-apply'able ACSL overlays (NNNN-<unit>-….patch)
  harness/    verification drivers (not target source)
  sessions/   saved WP/Coq scripts
  setup.sh    init submodules + apply patches (idempotent: git apply --reverse --check)
  verify.sh   reproduce verified units
  README.md   layout + toolchain/flags + unit-status table
  verdicts.tsv  <unit>\t<PROVED|PARTIAL|FAILED|TRIVIAL>\t<note>
```
- Faithfulness baseline pins (PER OWNING REPO — submodules separately):
  - <clone> HEAD: <commit>
  - <submodule> HEAD: <commit>     ← the submodule-vs-parent trap; check the OWNING repo
- Round-trip oracle: strip-ACSL == git HEAD per repo: <PASS | …>; setup.sh apply+reverse: <clean>

## 5. Feasibility smoke proof  (one framac-sl instance — Gate B_launch: smoke oracle)
- Unit: <highest-value amenable leaf>   Result: <WP all-Valid N/N (+ Coq lemma if any, 0 admits)>
- Captured: patches/<…>.patch (+ sessions/<…> if Coq)

## 6. Monitor verdicts  (onboarding monitor — Gate C_launch)
| Artifact | Check | Verdict | Carve-out / note |
|---|---|---|---|
| prober flag-set | trigger-test (profile match) | PASS/CARVE-OUT/REJECT | … |
| scope map | completeness-critic | PASS/CARVE-OUT/REJECT | … |
| baseline pin | conservative-transformation (per repo) | PASS/REJECT | … |
| smoke proof | no-blend (parse ≠ proof) | PASS | … |

## 7. Handoff status
- [ ] Gate A_launch (profile + scope + baseline plan judged)
- [ ] Gate B_launch (all oracles green)
- [ ] Gate C_launch (profile-match + scope-coverage + baseline-correct + endogenous flagged)
- [ ] squeeze-audit (C1/C3 of the launch cast: `framac-squeeze-audit.sh`)
READY FOR frama-c-monitoring: <yes | blocked on: …>
```
