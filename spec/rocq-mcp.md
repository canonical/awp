# A Rocq MCP server on coq-lsp — specification

This document specifies how to give the `rocq` skill a real **interactive
proof-state server**, exposed to the agent harness as an **MCP server** and
backed by **coq-lsp**'s Petanque protocol. It mirrors the Lean arrangement
that already ships (`lean` SDK → `lean-lsp-mcp` → `lake serve`), adapted to
Rocq's session-based proof model.

## 0. Why this spec exists

The `rocq` skill is **already written MCP-first**: its `SKILL.md` says it
"prioritizes MCP-based interactive proving", and
`references/rocq-mcp-tools-api.md` documents a full tool surface
(`rocq_start`, `rocq_check`, `rocq_step_multi`, `rocq_compile`,
`rocq_query`, `rocq_toc`, `rocq_notations`, `rocq_verify`). But **no server
is provisioned**: the `rocq` SDK (`sdks/rocq/`) ships only the Rocq opam
switch and `coqc` on `PATH`, so every MCP-first path in the skill currently
falls through to the `scripts_only` fallback. This spec closes that gap: it
names the backend, the adapter, how the SDK installs it, how the harness
registers it, and how it coexists with the R6 resource guard.

It is also the first deliberate answer to the "should we add an MCP server
for the provers?" question: **yes for the interactive, LSP-shaped provers
(Lean, done; Rocq, here), no for the batch provers** (Frama-C/WP, Creusot),
where the committed-CLI model stays. See §9.

## 1. Background facts the design relies on

coq-lsp (read 2026-11-24, `github.com/LLM4Rocq/coq-lsp`, OCaml package
`coq-lsp`, latest release line `0.2.5+9.0`):

- coq-lsp is a language server for the Rocq Prover. Beyond editor LSP it
  bundles **Petanque**, a machine-to-machine **JSON-RPC** protocol that
  exposes proof state. Petanque's server binary is **`pet-server`** (built
  in the coq-lsp tree; `dune exec -- pet-server`).
- **Petanque core calls** (confirmed from the pytanque client,
  `github.com/LLM4Coq/pytanque`, docs `llm4rocq.github.io/pytanque`):
  - `start(file, theorem)` → a `state` handle for a proof session;
  - `run(state, command)` → execute a tactic/command, returns the next
    state and whether the proof finished;
  - `goals(state)` → the open goals at a state;
  - `premises(state)` → accessible lemmas/premises;
  - `state_equal(st1, st2, kind)`, `state_hash(state)` → state identity, for
    non-destructive branching and caching;
  - `ast_at_pos(file, line, char)`, `get_state_at_pos(file, line, char)` →
    position lookups, **dev-build only**. LSP positions are **0-based**.
- **Version support.** `0.2.5+9.0` supports Rocq 9.1, Rocq 9.0, Coq 8.20 and
  Rocq `master`. The upstream notes mention an **MCP protocol as upcoming** —
  i.e. not relied on here; we build the adapter ourselves (§3).
- **`pet-server` is stateful and long-lived**: it holds session states in
  memory and is slow to warm (document elaboration, imports). This is the
  property that makes it worth an MCP wrapper — and the property the R6
  guard must account for (§7).

The Lean precedent this spec copies (grounded in the repo):

- `sdks/lean/hooks/setup-base` installs `lean-lsp-mcp` **pinned**, in a
  **venv at a fixed path** (`/opt/lean/venv`), re-created only on a version
  mismatch; `ripgrep` and `python3-venv` are apt-installed for it.
- The server is **registered with the harness**, user-scoped, as a stdio
  MCP: `claude mcp add --transport stdio --scope user lean-lsp -- …`
  (`templates/common/skills/lean/references/subagent-workflows.md`:
  "user-scoped servers have been more reliable").
- The skill degrades cleanly when the MCP is absent (`scripts_only` mode).

## 2. Architecture

```
agent harness (claude | opencode | copilot)
        │  MCP (stdio, JSON)
        ▼
  rocq-mcp  ──────────────┐   thin adapter: MCP tools  →  Petanque JSON-RPC
        │                 │   (one process per workspace; spawned by harness)
        │  JSON-RPC        │
        ▼                 │
   pet-server  ───────────┘   coq-lsp Petanque: holds session state
        │
        ▼
   coqc / Rocq 9.x        the rocq SDK's read-only opam switch (/opt/rocq)
```

Two processes are introduced into the workshop: the **`rocq-mcp` adapter**
(stdio MCP ⇄ Petanque client) and the **`pet-server`** it drives. Both are
spawned by the harness's MCP launch (stdio), not by `workshop launch`, so
they live for the duration of an agent session, not the container.

**Adapter, not a fork.** `rocq-mcp` is a small program that maps the tool
names the skill already documents onto Petanque calls. It is **not** a
reimplementation of Rocq, and it adds no proving logic. The mapping:

| Skill MCP tool | Petanque backing | Notes |
|---|---|---|
| `rocq_start(file, theorem)` | `start(file, theorem)` | returns `state_id` = Petanque state handle |
| `rocq_check(body, from_state?)` | `run(state, body)` | `from_state` ⇒ run from a prior handle (backtrack) |
| `rocq_step_multi(tactics[])` | N× `run` from one state, non-destructive | fan out on `from_state`, discard child states; cap 20 |
| `rocq_query("Search …", preamble?)` | `run` of `Search`/`Check`/`Print`/`About` in a scratch state | read-only vernac |
| `rocq_compile(source)` | full-document check via coq-lsp | file-level gate, no session |
| `rocq_toc(file)` | document symbols (LSP) | outline |
| `rocq_notations(statement, preamble?)` | `Locate`/`Print` vernac via `run` | disambiguation |
| `rocq_verify(proof, name, statement)` | fresh `pet-server` workspace, `start`+`run`+goal-empty check | sandboxed; see §6 degraded note |

**State identity.** `rocq_step_multi`'s non-destructiveness and the skill's
`from_state` backtracking are implemented with Petanque `state_hash` /
`state_equal`, so the adapter is stateless beyond a handle→Petanque-state
map it keeps for the session.

## 3. The `rocq-mcp` adapter

- **Language/transport.** Python, stdio MCP (matches `lean-lsp-mcp` and the
  harness registration already used). It depends on **`pytanque`** (the
  Petanque Python client) and an MCP server lib (`mcp`/`fastmcp`).
- **Pinning.** Pin `rocq-mcp`, `pytanque`, and the `mcp` lib to exact
  versions, installed in a venv at **`/opt/rocq/venv`** (parallel to
  `/opt/lean/venv`), re-created only on version mismatch — the exact shape of
  `sdks/lean/hooks/setup-base`.
- **`pet-server` lifecycle.** The adapter spawns one `pet-server` as a child
  on first tool call and reuses it for the session; it exits when the adapter
  exits. The adapter owns the child's process group so it can be reaped
  cleanly (§7).
- **Rocq discovery.** The adapter inherits `/etc/profile.d/rocq.sh` (coqc,
  `ROCQ_PYTHON_BIN`) and `_CoqProject`/workspace from the project root, as
  the skill's capability table expects.

**Build vs. vendor.** If an upstream `rocq-mcp` matching this tool surface
does not exist at implementation time, it is a ~300-line adapter in
`sdks/rocq/` (or a small repo pinned by commit), analogous to how the Lean
SDK consumes a pinned `lean-lsp-mcp`. Treat "does a suitable upstream MCP
exist?" as **open point O-1**.

## 4. Provisioning in the `rocq` SDK

Extend `sdks/rocq/hooks/setup-base` (today it only links `/opt/rocq`, apt-
installs run-time libs, and installs `rocq.profile`). Add, in the
`lean-lsp-mcp` style:

```sh
# coq-lsp / Petanque: the pet-server binary.  Built into the opam switch at
# pack time (part: coq-lsp, pinned), exposed on PATH by rocq.profile.
# rocq-mcp + pytanque: pinned, in a venv at a fixed path.
apt-get install python3-venv          # (python3, ripgrep, make, gcc already present)
ROCQ_MCP_VERSION=<pin>
PYTANQUE_VERSION=<pin>
if ! /opt/rocq/venv/bin/pip show rocq-mcp 2>/dev/null | grep -qx "Version: $ROCQ_MCP_VERSION"; then
    rm -rf /opt/rocq/venv
    python3 -m venv /opt/rocq/venv
    /opt/rocq/venv/bin/pip install --quiet \
        "rocq-mcp==$ROCQ_MCP_VERSION" "pytanque==$PYTANQUE_VERSION"
fi
```

- **`pet-server` belongs in the SDK's opam switch**, built from the pinned
  coq-lsp part at pack time (not apt / not a user opam install — the switch
  is read-only). Add `coq-lsp` to the `rocq` SDK's `parts` and expose
  `pet-server` through `/opt/rocq/env.sh`.
- **`rocq.profile`** gains the venv bin and a marker the skill can probe,
  e.g. `export ROCQ_MCP_BIN=/opt/rocq/venv/bin/rocq-mcp`.
- **Version compatibility is the sharp edge.** The `rocq` SDK ships **Rocq
  9.2**; coq-lsp `0.2.5+9.0` lists support through **9.1 / master**. The pin
  must be a coq-lsp release (or `master` commit) built against the SDK's
  exact Rocq version, or the two disagree at the AST level. This is **open
  point O-2** and must be resolved before the part is added, not after.

## 5. Harness registration

Register `rocq-mcp` the way the Lean skill registers its server — **stdio,
user-scoped** — so it is available to the main thread and to subagents:

```sh
claude mcp add --transport stdio --scope user rocq -- \
    /opt/rocq/venv/bin/rocq-mcp --workspace "$PWD"
```

- **Where it is run.** Registration is a per-environment step, like the Lean
  one: documented in the generated project's `README.md` step 2 and/or wired
  by the harness install snippet. It is **not** `auto-wp.py`'s job to edit a
  harness MCP config — generated projects stay stand-alone and the three
  harnesses differ. `auto-wp.py` only ships the skill (which already
  references the tools) and the SDK (which ships the binaries).
- **Harness portability.** `claude mcp add` is Claude Code syntax. For
  OpenCode and Copilot the equivalent config differs; the spec requires the
  skill to **detect availability by canary** (`rocq_compile` or a trivial
  `rocq_query`) and fall back, exactly as the Lean skill's capability table
  does — never to assume the server is present. Harness-specific
  registration lines live in the skill's references, not in auto-wp.py.

## 6. Degraded mode

The skill already defines `scripts_only`. This spec only pins the contract:

- **Canary on entry.** Before relying on MCP, the skill runs one cheap tool
  call; on failure it drops to `coqc`/scripted primitives (Admitted
  analysis, axiom checking, error parsing) — the current behaviour.
- **`rocq_verify` sandbox.** The sandboxed-verification tool must run in a
  **fresh `pet-server` workspace** (or a fresh process) so a poisoned
  session state cannot pass a proof. If the adapter cannot guarantee
  isolation, `rocq_verify` must fall back to a clean `coqc` compile in a
  scratch dir rather than trust session state.

## 7. R6 resource-guard integration (mandatory)

This is the part that distinguishes a Rocq MCP from a batch `coqc` call, and
the part that, done wrong, re-introduces the 2026-11-15 OOM/fork-bomb class
of failure. `pet-server` is **long-lived and memory-hungry** (it holds
elaborated session states; large dependent contexts OOM, exactly as the Lean
LSP does — see `lean/references/compilation-errors.md`).

Requirements:

1. **Known, bounded processes.** Exactly one `rocq-mcp` and one `pet-server`
   per agent session. The adapter must **not** spawn `pet-server` per tool
   call, and must reap its child's process group on exit (`setsid` + group
   kill), so no orphan `pet-server` survives a crashed adapter.
2. **Watchdog awareness.** `bin/mem-watchdog` hunts `bin/heavy` process
   groups (`oom_score_adj=1000`). A `pet-server` is **not** launched through
   `bin/heavy` (it is a persistent session server, not a batch job), so the
   watchdog must either (a) leave a correctly-bounded `pet-server` alone, or
   (b) learn it as a named, memory-capped long-lived server. The spec
   chooses **(b)**: `rocq-mcp` sets its and `pet-server`'s `oom_score_adj`
   high and applies a `ulimit -v` cap, and the watchdog treats a
   `pet-server` over the cap as a kill candidate by RSS, same policy as a
   runaway `heavy` group. The watchdog log gains a line per Rocq kill.
3. **Never under `bin/heavy`.** Batch `coqc`/`rocq_compile` file gates still
   run under `bin/heavy` like any verifier job. Only the **session server**
   is the exception, and it is memory-capped instead.
4. **Restart, don't leak.** On `pet-server` OOM the adapter reports the tool
   error and restarts a fresh server on the next call; it never silently
   re-attaches to a dead one.

## 8. Testing

Extend `sdks/rocq/tests/` (which already has `cases/` and `check.sh`):

- **T-mcp-1 (canary).** `rocq_start` on a trivial theorem returns goals;
  `rocq_check("reflexivity.")` finishes it; `goals` is then empty.
- **T-mcp-2 (backtrack).** `rocq_step_multi` over three candidate tactics
  from one state leaves the parent state unchanged (`state_hash` equal
  before/after).
- **T-mcp-3 (version match).** `pet-server` and the SDK's `coqc` agree:
  compile a file both ways, assert identical success/goal counts (guards
  O-2).
- **T-mcp-4 (lifecycle).** Kill the adapter mid-session; assert no
  `pet-server` survives (process-group reaping, §7.1).
- **T-mcp-5 (degraded).** With the venv removed, the skill's canary fails and
  `scripts_only` still proves a trivial file via `coqc`.
- **Template test.** `tests/test_templates.py` already pins the SDK list and
  hook contents; add assertions that `rocq.profile` exports `ROCQ_MCP_BIN`
  and that `setup-base` pins `rocq-mcp`/`pytanque`, mirroring the lean
  checks.

## 9. Pros and cons (recap, scoped)

**Pro — fits Rocq's shape.** Rocq is interactive: goal state after each
tactic is the unit of work, and `coqc` rebuild cycles (10–30 s) are the wrong
granularity. Petanque gives sub-second goal feedback and non-destructive
multi-tactic trials — the "30×" regime the Lean skill already banks on.
**Pro — structured state, fewer tokens.** The agent reads goals/premises as
data instead of scraping `coqc` stderr. **Pro — reuses a proven pattern.**
The Lean SDK is the template; this is the same wiring with a different
backend.

**Con — a long-lived process in a guard-sensitive environment** (§7); the
whole of §7 is the cost of admitting it. **Con — version lockstep** (O-2):
the MCP binary, coq-lsp, and the SDK's Rocq must be built together. **Con —
harness portability**: stdio MCP registration differs per harness, so the
skill must stay canary-gated and never assume presence. **Con — surface
area**: two more pinned components in the SDK to maintain and re-pin.

**Not in scope.** This spec does **not** add an MCP to Frama-C/WP or Creusot.
Those are batch, memory-heavy, parallel (`-wp-par`), and already well served
by committed `verify.sh` CLI lines that are reproducible, auditable and
harness-neutral. If they ever get an MCP it should be a **read-only query
surface** over the WP property database / why3 session — alongside the batch
run, never replacing it — and is a separate spec.

## 10. Open points

- **O-1.** Does a suitable upstream `rocq-mcp` exposing this tool surface
  exist, or do we vendor a pinned ~300-line adapter over `pytanque`? (§3)
- **O-2.** Pin a coq-lsp / `pet-server` build compatible with the SDK's
  **Rocq 9.2**; coq-lsp's released line tops out at 9.1/master as of
  2026-11-24. Resolve before adding the part. (§4)
- **O-3.** Watchdog policy for a named long-lived server (§7.2): add a
  memory-capped server class to `bin/mem-watchdog`, or keep `pet-server`
  strictly self-limited and invisible to it?
- **O-4.** Per-harness registration lines (OpenCode, Copilot) — collect the
  exact commands, or document only Claude Code and leave the rest to the
  canary fallback.
- **O-5.** Worktree/subagent isolation: one `pet-server` per subagent (RAM
  cost) vs. a shared read-only server — mirror the Lean subagent guidance in
  `rocq/references/subagent-workflows.md`.

## 11. Relationship to existing files

- `sdks/rocq/` — SDK gains the coq-lsp part, the venv install, the profile
  export, and the T-mcp tests (§4, §8).
- `templates/common/skills/rocq/SKILL.md` and `references/rocq-mcp-tools-api.md`
  — already written to this tool surface; this spec makes them real. The
  capability table gains an MCP row with the canary and `scripts_only`
  fallback (§5, §6).
- `bin/mem-watchdog` / `bin/heavy` (shipped by the time-loop R6 guard) —
  gain the long-lived-server policy of §7.
- `spec/workshop-autowp-c-base-spec.md` — the `rocq` SDK row there is the
  thing this spec extends; keep them consistent.
