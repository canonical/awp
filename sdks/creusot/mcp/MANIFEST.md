# creusot-mcp — implementation manifest

Implements the testable core of `spec/creusot-mcp.md`: **Mode A** (read-only
over the committed why3find proof artifacts) plus the in-flight oracle-integrity
guard and the blocked-Mode-B path. Standard library only, `-I`-safe.

## What is implemented

### Mode A — read-only tools (`creusot_mcp/core.py`, served by `server.py`)
Backed entirely by committed `proof.json` / `why3session.xml` / `verdicts.tsv`;
**no prover and no Why3 process is ever spawned.** Every result carries
`provenance` (`commit`, `path`, `mtime`) and respects the in-flight guard.

| Tool | Status | Notes |
|---|---|---|
| `creusot_status` | done | modules / goals / leaves / discharged / unproved; refuses when in-flight |
| `creusot_remaining` | done | lists `null` (failed) leaves, filter by `unit`/`module`/`function`/`tactic`/`depth`; reports each leaf's positional path |
| `vc_goal(id)` | done | `Coma.vc_<fn>[.i.j]`; tactic path, prover, time, status; `expl`/`session_proved` when a `why3session.xml` exists |
| `vc_tree(module)` | done | reconstructs the `compute_specified`/`split_vc` tree with per-node status; merges session `expl` where present; `null` leaf = `unproved` |
| `vc_provenance(id)` | done | provers + total time that closed it, matching `verdicts.tsv` rows, commit |
| `vc_locate(id)` | done, **honestly PARTIAL** | `proof.json` children are positional — no source span. Returns `partial: true`, the session `expl` if any, and says a full `(file, line, clause)` needs the Why3 task (Mode B) |
| `creusot_diff(rev1, rev2)` | done | `regressed` / `newly_open` / `closed` / `added` / `removed` between two committed overlay revisions |

**In-flight guard (spec §3, §8).** `core.in_flight` reports `in_flight: true`
and the summarizing tools refuse when (a) a `why3find prove` is active on the
`verif/` tree (default: `pgrep -af "why3find prove"`, injectable for tests), or
(b) a run log is present but lacks a final summary line
(`Proved (N files)` / `unproved file` / `Error:` / `'why3find prove' failed`).
A missing run log is **not** a trigger — committed artifacts with no active run
are reproducible and summarizable.

### Mode B — blocked, never faked
`vc_split` / `vc_try` / `why3_task` are listed but return `isError: true` with
`banked: false` and the message
`prover unavailable (blocked: O-1 version lockstep, no why3find here) … This
adapter never fakes a discharge`. No prover output is ever fabricated.

## What is blocked, and why

- **Mode B interactive layer (O-1 / absent toolchain).** `cargo`, `creusot`,
  `why3`, `why3find` and the provers are absent on this host, and the SDK-pin
  lockstep (`f15b985`, Why3 `1.8.2+git`, why3find `1.3.0+dev`) is unverifiable.
  Per spec §7 a prover may run only through `bin/heavy`; none of that is present.
  The server refuses Mode B cleanly rather than inventing discharges.
- **`vc_locate` full source span (spec Con "thin Mode-A locations").**
  `proof.json` is positional with no span; only a `why3session.xml`'s `expl` is
  available in Mode A. Reported as `partial`.
- **Venv install path not exercised here.** `python3-venv` is not installed on
  this host (`ensurepip` unavailable), so `python3 -m venv` could not run. The
  hook edit follows the `sdks/lean/hooks/setup-base` precedent verbatim; the
  package builds (standard setuptools `pyproject.toml`), imports, and its console
  entry `creusot_mcp.server:main` runs (verified directly and under `python3 -I`).

## Provisioning (spec §5)

- `hooks/setup-base`: adds `python3-venv` and a pinned `creusot-mcp` venv at
  **`/opt/creusot-mcp/venv`** — outside the read-only `/opt/creusot` overlay
  (O-3; keeps the `sdk-untouched` test green), lean-lsp-mcp guard shape
  (`pip show … | grep -qx "Version: 0.1.0"`, re-created only on mismatch).
- `files/creusot.profile`: exports
  `CREUSOT_MCP_BIN=/opt/creusot-mcp/venv/bin/creusot-mcp` (the skills' canary).
- `sdkcraft.yaml`: a `mcp` dump part ships this directory as `$SDK/mcp`.

## Skill rows (spec §6)

Canary-gated (`creusot_status`) MCP capability rows added to
`templates/rust/skills/creusot/`, `creusot-sl/`, `creusot-monitoring/` SKILL.md,
each stating the MCP **NEVER banks a verdict** (Gate B stays `cargo creusot`)
with fallback to the `proofjson-check.py`-shaped `proof.json` / `cargo creusot`
summary parsing.

## Fixtures (`tests/mcp/fixtures/`)

Minimal **real** why3find `proof.json` trees copied out of the 2026-11 httparse
campaign overlay (`serde_json-analyze/httparse-creusot/`):
- `overlay_rev1/` — a passing snapshot: a leaf-only module
  (`default_config_is_strict`), a passing `split_vc` tree (`offsetnz`), a module
  with a real `why3session.xml` (`parse_reason`), plus a `verdicts.tsv`.
- `overlay_rev2/` — rev1 with one `offsetnz` leaf regressed to `null` and a
  trimmed-but-real failing `parse_chunk_size` (real nested `split_vc` chain
  ending in a `null` leaf, position `0.2.0.0.0`).
- `overlay_inflight/` — run log without a summary. `overlay_complete/` — run log
  with `Proved (4 files) ✔`.

## Test commands and output

```
$ python3 -m unittest discover -s sdks/creusot/tests/mcp -p 'test_*.py' -v
```

```
test_active_prove_is_in_flight (test_mode_a.InFlightGuard.test_active_prove_is_in_flight) ... ok
test_completed_run_log_is_not_in_flight (test_mode_a.InFlightGuard.test_completed_run_log_is_not_in_flight) ... ok
test_run_log_without_summary_is_in_flight (test_mode_a.InFlightGuard.test_run_log_without_summary_is_in_flight) ... ok
test_status_refuses_while_in_flight (test_mode_a.InFlightGuard.test_status_refuses_while_in_flight) ... ok
test_diff_flags_regression_and_new_open (test_mode_a.ModeADiff.test_diff_flags_regression_and_new_open) ... ok
test_vc_goal_leaf (test_mode_a.ModeAGoalProvenanceLocate.test_vc_goal_leaf) ... ok
test_vc_goal_positional_with_session_expl (test_mode_a.ModeAGoalProvenanceLocate.test_vc_goal_positional_with_session_expl) ... ok
test_vc_locate_is_honestly_partial (test_mode_a.ModeAGoalProvenanceLocate.test_vc_locate_is_honestly_partial) ... ok
test_vc_provenance_reports_prover_and_ledger (test_mode_a.ModeAGoalProvenanceLocate.test_vc_provenance_reports_prover_and_ledger) ... ok
test_remaining_filter_by_function (test_mode_a.ModeARemaining.test_remaining_filter_by_function) ... ok
test_remaining_filter_by_unit (test_mode_a.ModeARemaining.test_remaining_filter_by_unit) ... ok
test_remaining_lists_exactly_the_null_leaves (test_mode_a.ModeARemaining.test_remaining_lists_exactly_the_null_leaves) ... ok
test_status_counts_rev1 (test_mode_a.ModeAStatus.test_status_counts_rev1) ... ok
test_status_counts_rev2_has_unproved (test_mode_a.ModeAStatus.test_status_counts_rev2_has_unproved) ... ok
test_status_reproducible_by_reference_script (test_mode_a.ModeAStatus.test_status_reproducible_by_reference_script) ... ok
test_tree_marks_null_leaf_unproved (test_mode_a.ModeATree.test_tree_marks_null_leaf_unproved) ... ok
test_tree_merges_session_expl (test_mode_a.ModeATree.test_tree_merges_session_expl) ... ok
test_tree_reconstructs_nesting (test_mode_a.ModeATree.test_tree_reconstructs_nesting) ... ok
test_vc_split_and_why3_task_blocked (test_mode_a.ModeBUnavailable.test_vc_split_and_why3_task_blocked) ... ok
test_vc_try_blocked_and_not_banked (test_mode_a.ModeBUnavailable.test_vc_try_blocked_and_not_banked) ... ok
test_initialize_list_and_status (test_mode_a.StdioServerSmoke.test_initialize_list_and_status) ... ok

----------------------------------------------------------------------
Ran 21 tests in 0.189s

OK
```

```
$ bash -n sdks/creusot/hooks/setup-base      # -> OK
$ bash -n sdks/creusot/files/creusot.profile  # -> OK
```

Map to spec §10: T-A1 (`ModeAStatus`, `ModeARemaining`), T-A2 (`ModeATree`),
T-A3 (`ModeADiff`), T-A4 (`test_status_reproducible_by_reference_script`),
T-A5 (`InFlightGuard`), Mode-B-unavailable (`ModeBUnavailable`), stdio server
(`StdioServerSmoke`). T-B1..B4 (scratch isolation, under-heavy, yield,
version-match) require the toolchain and are out of reach on this host.
