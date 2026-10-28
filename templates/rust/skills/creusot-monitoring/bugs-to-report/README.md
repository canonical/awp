# bugs-to-report/ — bugs to report

One `*.md` per **bug** to report upstream (Creusot / Why3 / the tooling) — a crash,
an unsound discharge, a spec that should prove but doesn't (or vice-versa), wrong
diagnostics. Filed by any `creusot-monitoring` / `creusot-sl` agent and **confirmed by
the base-SL monitor against `L`** (reproduced via the `creusot-sl` oracle). A surprise
is *routed here, never absorbed*.

**Filename:** `YYYYMMDD-hhmm-simple-name.md` — e.g. `20260616-1547-handle-reference.md`.

**Each file should state:**
- **Trigger** — the file / `gap-N` / mission that surfaced it.
- **Expected** — what should happen.
- **Actual** — what happens (error text / wrong verdict).
- **Minimal reproducer** — the smallest Rust + Pearlite + the exact `cargo creusot`
  invocation.
- **Versions** — from `cargo creusot version` (Creusot, Why3, provers).

_(no bugs yet)_
