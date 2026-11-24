# SYNTHETIC Petanque fixtures

**These are hand-written, NOT captured from a real coq-lsp/pet-server.** This
host has no Rocq toolchain (no `coqc`, `rocq`, `pet-server`, `pet`, `coq-lsp`),
so a genuine Petanque capture is impossible here. Each fixture is a plausible
shape per `spec/rocq-mcp.md` §1 (pytanque JSON) and carries a `_synthetic` key
to make its origin unmistakable. They exercise the adapter's *pure parsing*
(`rocq_mcp.parse`), never a prover.

| File | Shape | Used for |
|---|---|---|
| `run_result_finished.json` | `Run_result`, `proof_finished=true` | proof-finished parse |
| `run_result_open.json` | `Run_result`, open, no error | advancing-state parse |
| `run_result_error.json` | `Run_result` with level-1 feedback | error detection |
| `goals_two.json` | `goals` envelope, two goals | hypotheses/conclusion parse |
| `toc.json` | nested `toc` outline | outline flattening |
| `premises.json` | `premises` list | qualified-name parse |

When a real `+9.2` coq-lsp exists (O-2) and the live backend is wired (O-1),
replace these with captures from `pet` and drop the `_synthetic` markers.
