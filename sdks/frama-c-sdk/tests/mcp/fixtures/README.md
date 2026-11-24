# SYNTHETIC `-wp-report-json` fixtures

**These files are HAND-WRITTEN. They were NOT produced by Frama-C/WP.**
This host has no `frama-c` (see `../../mcp/MANIFEST.md`), so a real report
cannot be generated here. The records follow the shape the spec cites from
`frama-c-internals` SKILL.md section 6 and `spec/frama-c-mcp.md` section 0:
one record per goal with `file`, `function`, `property`, `line`, `passed`,
`verdict`, `provers` (per-prover sub-records with `name`/`verdict`/`time`,
including a `Coq:8.20.1` success entry as the spec cites).

- `report_run1.json` — object-envelope form (`goals` array + `wp:timeout` /
  `wp:model` run metadata). Goal names `typed_*`.
- `report_run2.json` — bare-array form. Same four goal **keys**
  `(file,function,property,line)` as run1 but goal names are `bytes_*` and
  **renumbered**, to exercise the key rule (goal names must be ignored).

Status changes run1 -> run2 (for the `wp_diff` renumbering test):
- `behaviors.c / bar / ensures / 30`: open (timeout) -> closed (valid, Coq) = **newly_closed**
- `behaviors.c / foo / ensures / 12`: closed (valid) -> open (timeout) = **regressed**
- `behaviors.c / foo / assigns / 10`: valid -> valid (unchanged)
- `loops.c / baz / loop invariant inv / 45`: unknown -> unknown (unchanged)

When a real `frama-c` is present, replace these with the SDK's own
`tests/run.sh` `behavior-goals` report (spec section 10 names it the fixture).
