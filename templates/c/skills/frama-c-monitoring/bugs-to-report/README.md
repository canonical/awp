# bugs-to-report/ — bugs to report

One `*.md` per **bug** to report upstream (Frama-C / WP / Why3 / a prover) — a crash, an
unsound discharge, a goal that should prove but doesn't (or vice-versa), wrong diagnostics.
Filed by any `frama-c-monitoring` / `framac-sl` agent and **confirmed by the base-SL
monitor against `L`** (reproduced via the WP oracle). A surprise is *routed here, never
absorbed*.

**Filename:** `YYYYMMDD-hhmm-simple-name.md` — e.g. `20260618-1530-wp-rte-shift-false-alarm.md`.

**Each file should state:**
- **Trigger** — the unit / `gap-N` / mission that surfaced it.
- **Expected** — what should happen.
- **Actual** — what happens (error text / wrong verdict).
- **Minimal reproducer** — the smallest C + ACSL + the exact `frama-c -wp …` invocation
  (including `-machdep`, `-wp-prover`, `-wp-timeout`, and any `-cpp-extra-args`).
- **Versions** — Frama-C / WP / Why3 / prover versions (and the opam switch, e.g.
  `framac-coq8` for Coq-escalation bugs).

_(no bugs yet)_
