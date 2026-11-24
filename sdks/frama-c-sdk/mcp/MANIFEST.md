# framac-mcp — implementation manifest

Read-only MCP query surface over the Frama-C/WP property database, per
`spec/frama-c-mcp.md`. This manifest records **what is implemented and tested
here**, and **what is blocked and why** — claimed only from observed output.

## Host reality (why Mode B is not runnable here)

This host has **no Frama-C**: `frama-c` and `frama-c-server` are absent. Only
`python3` is present (3.14 on this machine); `pytest` and `shellcheck` are not
installed, so tests use `python3 -m unittest` and hooks are checked with
`bash -n`. WP cannot be run, so **no real `-wp-report-json` exists here** — the
fixtures are clearly-labelled SYNTHETIC (see `../tests/mcp/fixtures/README.md`).
Nothing below fabricates WP output or Frama-C Server-protocol responses.

## Implemented (Mode A — static artifact reader, no process)

`framac_mcp/` (standard library only, `-I`-safe):

- `report.py` — pure Mode A logic over a parsed `-wp-report-json` table.
  Goal key is the tuple `(file, function, property, line)` (spec §1/§3); the
  model-prefixed, renumbering WP goal *name* is never used as a key.
  Tools: `wp_status`, `wp_remaining(filters)`, `wp_goal(key)`, `wp_locate`,
  `wp_provenance(key)`, `wp_diff(run1,run2)`. Accepts both the bare-array and
  the `{goals:[…], "wp:timeout", "wp:model"}` envelope forms.
- `server.py` — stdio MCP server skeleton (raw JSON-RPC 2.0, harness-free, the
  `sdks/lean/tests/lib/mcp_probe.py` style). `initialize` / `tools/list` /
  `tools/call`. Resolves a report from an explicit `run`/`run1`/`run2` arg or
  the newest `*.json` in `$FRAMAC_MCP_REPORTS`. The Mode-B tools `wp_query`,
  `wp_property` return a **structured "live server unavailable (blocked: O-1
  schema, no frama-c here)" error, never faked data**. `wp_query` enforces the
  Server's GET-only naming rule (SET/EXEC/compute refused by string check
  before any server contact, spec §3 / T-B4).
- `__main__.py`, `pyproject.toml` — `framac-mcp` console entry point.

What is **deliberately absent** (spec §3): any tool that runs WP, schedules
units, writes ACSL, or mutates the overlay.

## Blocked (not testable on this host)

- **Mode B (live Frama-C Server).** `wp_query`, `wp_property`, live goal text,
  AST locations, on-demand property status. Blocked by **open point O-1** (the
  exact kernel/WP Server request names and the WP-goal/property-status JSON
  schema are version-specific to Frama-C 32.1 and not in public docs) **and**
  by the absence of `frama-c`/`frama-c-server` here. The adapter returns a
  clear refusal for these; it does not invent request names or schemas.
- **The §7 R6 resource-guard behaviours** (one bounded server, `oom_score_adj`,
  yield-to-batch via `bin/heavy` slot probe, idle reap, lifecycle T-B2/T-B3):
  these are Mode-B-only and need a live server + `bin/heavy` on a real host,
  so they are **not implemented/tested here**. `bin/heavy` is out of scope
  (forbidden to edit) and unchanged.
- **T-B0 (Server plugin present)** and **T-B1 (schema/version match)**: the
  `check-health` probe `frama-c -plugins | grep -qi server` is added (§5), but
  can only run where `frama-c` exists.
- **P-A / O-7** (the per-run `-wp-report-json` path the launch skill's
  `verify.sh` should emit, and `-wp-timeout` recovery): the `frama-c-launch`
  skill `verify.sh` edit is **out of this agent's scope**. `wp_provenance`
  reports `wp_timeout` from report metadata when present, else honestly `None`
  with `timeout_source: "unknown (O-7)"` — it does not fabricate a timeout.

## Provisioning changes

- `hooks/setup-base`: adds `python3-venv`; installs `framac-mcp` pinned
  (`pip show framac-mcp | grep -qx "Version: 0.1.0"` guard, re-created only on
  mismatch — the Lean SDK shape) into a venv at `/opt/frama-c-mcp/venv`,
  **outside** the read-only `/opt/frama-c-sdk` switch (O-3).
- `files/frama-c-sdk.profile`: exports the probe marker
  `FRAMAC_MCP_BIN=/opt/frama-c-mcp/venv/bin/framac-mcp` (§5).
- `hooks/check-health`: adds `frama-c -plugins | grep -qi server` (§5, T-B0).
- `sdkcraft.yaml`: a `mcp` dump part ships the adapter source at `$SDK/mcp`,
  which `setup-base` pip-installs from.
- `templates/c/skills/frama-c-monitoring/SKILL.md` §4b: a minimal canary-gated
  (`wp_status`) MCP capability row with mandatory fallback to the existing
  `-wp-report-json`/console parsing (spec §6).

The MCP protocol-library pin (spec §4/§5) is intentionally deferred: Mode A is
stdlib-only and the adapter speaks raw JSON-RPC, so no external lib is needed
to run it; a protocol-lib pin belongs with Mode B (O-1).

## Test commands and verbatim output

`bash -n` on every edited hook/profile (all clean):

```
$ bash -n sdks/frama-c-sdk/hooks/setup-base      && echo OK
OK
$ bash -n sdks/frama-c-sdk/hooks/check-health    && echo OK
OK
$ bash -n sdks/frama-c-sdk/files/frama-c-sdk.profile && echo OK
OK
```

Unit tests (22 tests — T-A1 status, T-A2 diff incl. renumbering, T-A3
reproducibility, T-B4 GET-only, Mode-B-unavailable, dispatch, stdio smoke):

```
$ python3 -I -m unittest discover -s sdks/frama-c-sdk/tests/mcp -p 'test_*.py'
......................
----------------------------------------------------------------------
Ran 22 tests in 0.043s

OK
```

or, verbose, from the test dir:

```
$ cd sdks/frama-c-sdk/tests/mcp && python3 -I -m unittest -v
... (22 tests) ...
Ran 22 tests in 0.044s

OK
```
