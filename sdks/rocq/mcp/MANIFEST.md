# rocq-mcp (Mode A) — implementation manifest

Scope of this delivery: the **testable core** of `spec/rocq-mcp.md` — the Mode A
adapter logic, the SDK provisioning edits, the skill capability row, and
harness-free unit tests — on a host with **no Rocq toolchain** (`coqc`, `rocq`,
`pet-server`, `pet`, `coq-lsp` all absent; `mcp`/`pytanque` not installed).
Nothing here runs a real prover or fabricates prover output.

## What is implemented (and tested here)

### 1. Mode A adapter — `sdks/rocq/mcp/rocq_mcp/`
A thin, standard-library-only stdio MCP server. No proving logic; it maps the
skill's tool surface onto Petanque (spec §2/§3) and degrades honestly when no
backend is reachable.

| File | Role |
|---|---|
| `tools.py` | The 8-tool registry (names, JSON schemas, backend class). `tools/list` is fully functional offline. |
| `parse.py` | Pure logic: `rocq_start` mode precedence (theorem > position > preamble), `rocq_step_multi` cap of 20, Petanque `Run_result`/`goals`/`toc`/`premises`/feedback parsers, and `StateStore` (handle→state map, tactic lineage, `state/hash` dedup). |
| `backend.py` | `probe_backend()` (detects reachable backends; finds none here) and `pet_launch_plan()` — the §7.2 marks a `pet-server` child must carry: own process group, `oom_score_adj=1000`, `ulimit -v` from `ROCQ_PET_MEM_KB`/`HEAVY_MEM_KB`. |
| `dispatch.py` | Validates args, then routes by backend class. With no backend it returns a **structured** `backend_unavailable` error naming the blocking open points — never a crash, never a fake result. A *reachable* backend fails closed with `not_implemented_mode_a` (O-1), never fabricates. |
| `server.py` / `__main__.py` | Line-delimited JSON-RPC loop (`initialize`, `notifications/initialized`, `tools/list`, `tools/call`) — the server mirror of `sdks/lean/tests/lib/mcp_probe.py`. Console script `rocq-mcp` + `python3 -m rocq_mcp`. |
| `pyproject.toml` | Installable package; `rocq-mcp` entry point; `pytanque`/`mcp` as an optional `live` extra (blocked, not resolved here). |

**What Mode A actually does on this host:** serves the MCP handshake and the
full tool list, validates every tool call, and answers each `tools/call` with a
clear structured "backend unavailable" error — e.g. the skill's canary
`rocq_query("Check nat.")` returns `{"error":"backend_unavailable",
"backend":"petanque","blocked":["O-1","O-2"]}` with a human-readable message,
rather than erroring out or inventing goals. `coqc`-class tools
(`rocq_compile`, `rocq_verify`) report `blocked:["toolchain"]`.

### 2. Provisioning
- `sdks/rocq/hooks/setup-base`: adds `python3-venv` and the pinned venv install
  at **`/opt/rocq-mcp/venv`** (outside the read-only `/opt/rocq` switch link, as
  §4/open-points mandate), re-created only on a version mismatch — the
  `sdks/lean/hooks/setup-base` shape. `bash -n` clean.
- `sdks/rocq/files/rocq.profile`: puts the venv bin on `PATH` and exports the
  probe marker `ROCQ_MCP_BIN=/opt/rocq-mcp/venv/bin/rocq-mcp` (§4).

### 3. Skill capability row — `templates/common/skills/rocq/SKILL.md`
The "Rocq MCP" row is now canary-gated: probe `$ROCQ_MCP_BIN`, then canary
`rocq_query("Check nat.")` (explicitly **not** `rocq_compile`, which waits on
the heavy slot — spec §6), falling back to `scripts_only` (`$ROCQ_SCRIPTS` +
`coqc`, file-level). One-line, surgical.

### 4. Tests + fixtures — `sdks/rocq/tests/mcp/`
`python3 -m unittest`, standard library only, harness-free. SYNTHETIC Petanque
fixtures under `tests/mcp/fixtures/` (clearly labelled — no real capture is
possible without a prover). `test_hooks.py` runs `bash -n` on the edited hooks.

## What is blocked (and why)

| Item | Blocked on | Note |
|---|---|---|
| Live Petanque wiring (pytanque SOCKET/STDIO, real `rocq_start`/`check`/…) | **O-1** + no toolchain | Adapter fails closed (`not_implemented_mode_a`); no fabrication. |
| `pet-server` build + pin | **O-2** | No `+9.2` coq-lsp release; `PYTANQUE_COMMIT` left empty in `setup-base`, pytanque install guarded on it. |
| `pet_launch_plan` actually spawning a child (setsid, real `oom_score_adj`) | no `pet-server` | The *plan* is unit-tested; the spawn is not reachable here. |
| Shipping `mcp/` into the SDK at `$SDK/rocq-mcp` (sdkcraft `config` dump) | sdkcraft/pack absent | `setup-base` references `$SDK/rocq-mcp` per §4 and guards on `[ -d "$SDK/rocq-mcp" ]`; wiring the dump is a pack-time step (O-1), untestable here. |
| `check-health` `pet-server --help` probe (§4) | O-2 | Deliberately **not** added — a hard probe would fail health while `pet-server` is unbuilt. |
| T-mcp-1..7 container checks (§8), `tests/test_templates.py` venv-pin assertion | no workshop/prover here; repo-root `tests/` out of scope | Left for the real pack; the Mode A unit tests cover the adapter-side logic those would also touch. |
| `references/subagent-workflows.md` canary alignment (§6/§11) | out of scope | Scope limits skill edits to the SKILL.md capability row; flagged for follow-up. |

## Test commands and output (observed, verbatim)

```
$ bash -n sdks/rocq/hooks/setup-base && echo OK
OK
$ bash -n sdks/rocq/hooks/check-health && echo OK
OK

$ cd sdks/rocq/tests/mcp && python3 -I -m unittest discover -s . -p 'test_*.py'
----------------------------------------------------------------------
Ran 46 tests in 0.103s

OK
```

Per module (`python3 -m unittest <mod>`):

```
test_parse:    Ran 19 tests  OK
test_dispatch: Ran  9 tests  OK
test_backend:  Ran  6 tests  OK
test_server:   Ran  8 tests  OK
test_hooks:    Ran  4 tests  OK
```

Total: **46 passed, 0 failed.**

## Honesty notes
- No prover was run and no Petanque/`coqc` output was invented. Every fixture is
  marked `_synthetic` and documented as hand-written in `fixtures/README.md`.
- The backend-unavailable error is the real, observed behaviour on this host,
  not a stand-in for a success path.
- `PYTANQUE_COMMIT` is left empty rather than filled with a fabricated SHA
  (O-2 is unresolved); the pytanque install is guarded on it being set.
