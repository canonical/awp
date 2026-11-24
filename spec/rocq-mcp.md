# A Rocq MCP server on coq-lsp — specification

This document specifies how to give the `rocq` skill a real **interactive
proof-state server**, exposed to the agent harness as an **MCP server** and
backed by **coq-lsp**'s Petanque protocol. It mirrors the Lean arrangement
that already ships (`lean` SDK → `lean-lsp-mcp` → `lake serve`), adapted to
Rocq's session-based proof model.

It is one of three prover-MCP specs written together. The shared stance:
**read-only surface by default; interactivity only where the prover actually
offers it; the batch run always banks the verdict; any long-lived heavy
server is reconciled with the R6 resource guard.** Rocq is the one prover of
the three that *is* interactive, so this is the spec where the MCP drives
proving; `spec/frama-c-mcp.md` (batch, read-only) and `spec/creusot-mcp.md`
(batch with an optional guarded interactive layer) are the siblings.

## 0. Why this spec exists

The `rocq` skill is **already written MCP-first**: its `SKILL.md` says it
"prioritizes MCP-based interactive proving", and
`references/rocq-mcp-tools-api.md` documents a full tool surface
(`rocq_start`, `rocq_check`, `rocq_step_multi`, `rocq_compile`,
`rocq_query`, `rocq_toc`, `rocq_notations`, `rocq_verify`). But **no server
is provisioned**: the `rocq` SDK (`sdks/rocq/`) ships only the Rocq opam
switch and `coqc` on `PATH` (`sdks/rocq/tests/README.md`: "no Rocq MCP
server and nothing sets `$ROCQ_SCRIPTS`"), so every MCP-first path in the
skill currently falls through to the `scripts_only` fallback — which, today,
is `coqc` alone. `spec/workshop-autowp-c-base-spec.md` §4 left the server
"to be identified (open point 5)". This spec closes that gap: it names the
backend, the adapter, how the SDK installs it, how the harness registers it,
and how it coexists with the R6 resource guard.

It is also the first deliberate answer to the "should we add an MCP server
for the provers?" question: **yes, a proving MCP for the interactive,
LSP-shaped provers (Lean, done; Rocq, here); read-only (or read-only plus a
guarded scratch layer) for the batch provers**, where the committed-CLI model
keeps banking the verdict. See §9 and the sibling specs.

## 1. Background facts the design relies on

coq-lsp / rocq-lsp (read 2026-11-24; repository
`github.com/rocq-community/rocq-lsp`, formerly `ejgallego/coq-lsp`; the opam
package is still named **`coq-lsp`**, latest release **`0.2.5+9.1`**):

- coq-lsp is a language server for the Rocq Prover. Beyond editor LSP it
  bundles **Petanque**, a machine-to-machine **JSON-RPC** protocol that
  exposes proof state ("designed for low-latency interaction with Rocq",
  for AI and software-engineering applications). Two front-ends ship in the
  tree: **`pet-server`**, a keep-alive **TCP** server (default
  `127.0.0.1:8765`, `--address`/`--port`), and **`pet`**, a JSON-RPC shell on
  stdin/stdout. Both hold session state in one long-lived process.
- **Petanque calls** (from `petanque/agent.mli` and `CHANGES.md`; the Python
  client **pytanque**, `github.com/LLM4Coq/pytanque`, wraps the same set):
  - `setWorkspace(root)` → point the server at a project (coq-lsp loads the
    `_CoqProject`/dune workspace from there);
  - `start(file, theorem, pre_commands?, opts?)` → a `state` handle for a
    proof session; fails if the theorem parsed but did not execute;
  - `run(state, tactic, opts?)` → a `Run_result {st, proof_finished, hash?,
    feedback: (level, message) list}`. States are **values**: running from
    `st` yields a new state and leaves `st` intact, so branching is
    non-destructive by construction. `opts = {memo, hash}` (both default on)
    control memoisation and state hashing;
  - `goals(state)` → the open goals; `premises(state)` → accessible
    constants/inductives, fully qualified;
  - `state/eq(st1, st2, kind)`, `state/hash(state)` → state identity, for
    de-duplicating branches and caching;
  - `toc(file)` → an LSP-style document outline (0.2.0);
  - `list_notations_in_statement(state, statement)` → how the notations in
    a statement resolve (0.2.5);
  - `ast(state, text)`, `ast_at_pos(file, pos)`, `get_state_at_pos(file,
    pos)`, `get_root_state(file)`, `run_at_pos`, `proof_info[_at_pos]` →
    position-based entry points (0.2.3–0.2.5). **LSP positions are
    0-based** (stated in `agent.mli` for `get_state_at_pos`). `agent.mli`
    marks none of these as development-only; `get_state_at_pos` falls back
    to the previous node's state when there is no node at the point.
- **Version support.** The 0.2.5 release line ships one build per Rocq
  version: `0.2.5+8.20`, `0.2.5+9.0`, `0.2.5+9.1`; the opam `0.2.5+9.1`
  package constrains `rocq-core >= 9.1 & < 9.2`. The `main` README states
  support for **Rocq 9.2**, 9.1, 9.0, Coq 8.20 and `master`, and
  recommends 9.2 or `master` — but **no `+9.2` release exists** as of the
  reading date (§4, O-2). It supports OCaml 4.14 (the SDK switch's
  compiler), 5.3 and 5.4. The README lists an **MCP protocol as
  "upcoming"** — i.e. not relied on here; we build the adapter ourselves
  (§3).
- **The Petanque server is stateful and long-lived**: it holds session
  states in memory and is slow to warm (document elaboration, imports). This
  is the property that makes it worth an MCP wrapper — and the property the
  R6 guard must account for (§7).
- **pytanque** has no documented PyPI release (its README installs from
  git) and exposes three transports: `SOCKET` (to `pet-server`), `STDIO`
  (spawning `pet`), and an HTTP mode via a separate `rocq-ml-server`. Only
  the first two matter here.

The Lean precedent this spec copies (grounded in the repo):

- `sdks/lean/hooks/setup-base` installs `lean-lsp-mcp` **pinned**, in a
  **venv at a fixed path** (`/opt/lean/venv`, a real directory — the Lean SDK
  has no `/opt/lean → $SDK` link), re-created only on a version mismatch;
  `python3-venv` is apt-installed for it. `check-health` probes
  `lean-lsp-mcp --help`.
- The server is **registered with the harness**, user-scoped, as a stdio
  MCP: `claude mcp add --transport stdio --scope user lean-lsp -- …`
  (`templates/common/skills/lean/references/subagent-workflows.md`:
  "user-scoped servers have been more reliable"; `sdks/lean/README.md`
  documents the shorter `claude mcp add lean-lsp -- lean-lsp-mcp`).
- The server is tested harness-free: `sdks/lean/tests/lib/mcp_probe.py`
  drives it over stdio with raw MCP JSON-RPC (initialize, `tools/list`,
  `tools/call`) from a spread task.
- The skill degrades cleanly when the MCP is absent (`scripts_only` mode).

## 2. Architecture

```
agent harness (claude | opencode | copilot)
        │  MCP (stdio, JSON)
        ▼
  rocq-mcp  ──────────────┐   thin adapter: MCP tools  →  Petanque JSON-RPC
        │                 │   (one per harness session; spawned by the harness)
        │  JSON-RPC over   │
        │  loopback TCP    │
        │  (or stdio pet)  │
        ▼                 │
   pet-server  ───────────┘   coq-lsp Petanque: holds session state
        │
        ▼
   coqc / Rocq 9.2        the rocq SDK's read-only opam switch (/opt/rocq)
```

Two processes are introduced into the workshop: the **`rocq-mcp` adapter**
(stdio MCP ⇄ Petanque client) and the **`pet-server`** it drives. Both are
spawned by the harness's MCP launch (stdio), not by `workshop launch`, so
they live for the duration of an agent session, not the container. The
adapter takes its workspace from its launch `cwd` (and from the per-call
`workspace` parameter the skill API already gives every tool), so one
user-scoped registration serves every project (§5).

**Adapter, not a fork.** `rocq-mcp` is a small program that maps the tool
names the skill already documents onto Petanque calls. It is **not** a
reimplementation of Rocq, and it adds no proving logic. The mapping (tool
signatures as in `rocq-mcp-tools-api.md`):

| Skill MCP tool | Petanque backing | Notes |
|---|---|---|
| `rocq_start(file, theorem)` | `setWorkspace` once, then `start(file, theorem)` | returns `state_id` = adapter handle for the Petanque state |
| `rocq_start(file, line, character)` | `get_state_at_pos(file, (line, character))` | 0-based, as the skill API says; "jump to error position" after `rocq_compile` |
| `rocq_start(preamble)` | scratch document holding the preamble; state at its end via `get_state_at_pos` | import context only |
| `rocq_check(body, from_state?, timeout?)` | `run(state, body)` | `from_state` ⇒ run from a prior handle (backtrack); on `proof_finished`, `proof_tactics` is the adapter's recorded tactic lineage; on error, the last valid handle |
| `rocq_step_multi(tactics[], from_state?)` | N× `run` from one state | non-destructive because states are values; children de-duplicated by `state/hash`, then discarded; cap 20 |
| `rocq_query(command, preamble?)` | `run` of `Search`/`Check`/`Print`/`About`/`Print Assumptions` on a scratch state | answer read from `Run_result.feedback`; read-only vernac only |
| `rocq_compile(source, timeout?)` | **`coqc`** on a scratch copy, under `bin/heavy` (§7.3) | file-level gate, no session; `error_positions` normalised to 0-based for `rocq_start` |
| `rocq_toc(file)` | `toc(file)` | outline, no session |
| `rocq_notations(statement, preamble?)` | `list_notations_in_statement` | disambiguation (0.2.5+) |
| `rocq_verify(proof, problem_name, problem_statement)` | fresh scratch dir: `coqc` both files under `bin/heavy`, compare statements, `Print Assumptions` | sandboxed; never trusts session state (§6) |

**State identity.** The adapter keeps a handle→Petanque-state map for the
session and the tactic lineage of each handle (for `proof_tactics`), nothing
more. `state/hash` / `state/eq` are used to collapse branches that reach the
same state and to cache; non-destructiveness itself comes from Petanque's
value semantics.

## 3. The `rocq-mcp` adapter

- **Language/transport.** Python, stdio MCP (matches `lean-lsp-mcp` and the
  harness registration already used). It depends on **`pytanque`** and an
  MCP server lib (`mcp`/`fastmcp`).
- **Backend transport.** Default: the adapter spawns one `pet-server` on a
  **free loopback port it picks** (never the fixed 8765 — concurrent
  subagents would collide, O-5) and connects with pytanque `SOCKET` mode.
  Alternative: pytanque `STDIO` mode over a child `pet`, which needs no port
  at all. Decide at implementation (O-1); the R6 rules of §7 are the same
  either way.
- **Pinning.** Pin `rocq-mcp`, `pytanque` (**by git commit** — no PyPI
  release is documented), and the `mcp` lib to exact versions, installed in
  a venv at a fixed path **outside the SDK tree** (§4), re-created only on
  version mismatch — the exact shape of `sdks/lean/hooks/setup-base`.
- **Server lifecycle.** The adapter spawns one `pet-server` as a child on
  first tool call and reuses it for the session; it exits when the adapter
  exits. The child runs in **its own process group** so it can be reaped
  cleanly and killed independently of the adapter (§7).
- **Rocq discovery.** The adapter inherits `/etc/profile.d/rocq.sh` (`coqc`,
  `ROCQ_PYTHON_BIN`), calls `setWorkspace` on the project root so coq-lsp
  reads the project's `_CoqProject`/dune workspace, and locates `bin/heavy`
  in the workspace for the batch gates (§7.3).

**Build vs. vendor.** No upstream `rocq-mcp` exposing this tool surface is
known. The expected shape is a ~300-line adapter over pytanque shipped in
the SDK itself: `sdks/rocq/files/rocq-mcp/` is dumped into `$SDK` by the
`config` part, and `setup-base` pip-installs it from there into the venv.
Treat "does a suitable upstream appear, and `pet-server` vs `pet`" as
**open point O-1**.

## 4. Provisioning in the `rocq` SDK

Extend `sdks/rocq/hooks/setup-base` (today it only links `/opt/rocq`, apt-
installs run-time libs, and installs `rocq.profile`). Add, in the
`lean-lsp-mcp` style:

```sh
# coq-lsp / Petanque: the pet-server (and pet) binaries.  Built into the
# opam switch at pack time (opam pin of coq-lsp to a commit compatible with
# the switch's Rocq, see O-2), exposed on PATH by /opt/rocq/env.sh.
# rocq-mcp + pytanque: pinned, in a venv at a fixed path OUTSIDE /opt/rocq
# (/opt/rocq is a link to the read-only, root-owned $SDK; a venv there is
# refused or lost on refresh).
apt-get install python3-venv          # (python3, ripgrep, make, gcc already present)
ROCQ_MCP_VERSION=<pin>                # the vendored adapter's version
PYTANQUE_COMMIT=<sha>
VENV=/opt/rocq-mcp/venv
if ! "$VENV/bin/pip" show rocq-mcp 2>/dev/null | grep -qx "Version: $ROCQ_MCP_VERSION"; then
    rm -rf "$VENV"; mkdir -p /opt/rocq-mcp
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet \
        "pytanque @ git+https://github.com/LLM4Coq/pytanque@$PYTANQUE_COMMIT" \
        "$SDK/rocq-mcp"
fi
```

- **`pet-server` belongs in the SDK's opam switch**, built from the pinned
  coq-lsp at pack time in the `rocq` part's `override-build` (not apt / not
  a user opam install — the switch is read-only; `env.read-only-switch` in
  `sdks/rocq/tests/check.sh` already asserts this). `/opt/rocq/env.sh`
  already prepends the switch's `bin` to `PATH`, so `pet-server` and `pet`
  appear with no further wiring.
- **`rocq.profile`** gains the venv bin on `PATH` and a marker the skill can
  probe, e.g. `export ROCQ_MCP_BIN=/opt/rocq-mcp/venv/bin/rocq-mcp`.
- **`check-health`** adds `rocq-mcp --help` and `pet-server --help` to its
  probe, as the Lean hook does for `lean-lsp-mcp`.
- **Version compatibility is the sharp edge.** The `rocq` SDK ships **Rocq
  9.2.0** (`sdkcraft.yaml`); the released coq-lsp line tops out at
  `0.2.5+9.1`, whose opam constraint **excludes 9.2** (`rocq-core < 9.2`).
  The `main` README claims 9.2 support, so the pin is either a **`main`
  commit** (an `opam pin` to a git URL) or a `+9.2` release once one exists.
  Whatever is pinned must be built against the SDK's exact Rocq, or the two
  disagree at the AST level. This is **open point O-2** and must be resolved
  before the part is added, not after; T-mcp-3 guards it afterwards.

## 5. Harness registration

Register `rocq-mcp` the way the Lean skill registers its server — **stdio,
user-scoped** — so it is available to the main thread and to subagents:

```sh
claude mcp add --transport stdio --scope user rocq -- /opt/rocq-mcp/venv/bin/rocq-mcp
```

No `--workspace` is baked in: a user-scoped registration outlives any one
project, so the adapter resolves the workspace from its launch `cwd` and the
tools' `workspace` parameter (§2).

- **Where it is run.** Registration is a per-environment step, like the Lean
  one: documented in the generated project's `README.md` step 2 and/or wired
  by the harness install snippet. It is **not** `auto-wp.py`'s job to edit a
  harness MCP config — generated projects stay stand-alone and the three
  harnesses differ. `auto-wp.py` only ships the skill (which already
  references the tools) and the SDK (which ships the binaries). The base
  spec's idea of doing it from the SDK's `setup-project` hook when `claude`
  is present is an option under O-4.
- **Harness portability.** `claude mcp add` is Claude Code syntax. For
  OpenCode and Copilot the equivalent config differs; the spec requires the
  skill to **detect availability by canary** and fall back, exactly as the
  Lean skill's capability table does — never to assume the server is
  present. Harness-specific registration lines live in the skill's
  references, not in `auto-wp.py`.

## 6. Degraded mode and the banking rule

The skill already defines `scripts_only`. This spec only pins the contract:

- **Canary on entry.** Before relying on MCP, the skill runs one cheap tool
  call. The canary must be **`rocq_query("Check nat.")`** (as the
  capability table says), not `rocq_compile` (as
  `references/subagent-workflows.md` says): `rocq_compile` runs `coqc`
  under `bin/heavy` and may block on the slot pool during a campaign — a
  canary that waits is a broken canary. Align the two references.
- **Fallback floor.** On canary failure the skill drops to `coqc` and the
  scripted primitives — the current behaviour. Note the floor is lower than
  the skill assumes: nothing in the SDK sets `$ROCQ_SCRIPTS` today, so
  `scripts_only` is in practice `coqc` alone. Out of scope here, but the
  degraded path must stay functional with `coqc` only.
- **Banking rule (the shared stance, Rocq instance).** The session is for
  *finding* the proof; the verdict is banked by the batch gates the skill's
  Quality Gate already names — `coqc`/project build with zero `Admitted`,
  `Print Assumptions` showing only standard axioms, `rocqchk` where the
  tests use it — never by a session state. `rocq_check`'s
  `proof_finished=True` is a hint to write the proof into the file, not a
  result.
- **`rocq_verify` sandbox.** The sandboxed-verification tool runs `coqc` in
  a **fresh scratch directory** on the submitted `proof` and
  `problem_statement`, compares the theorem statements, and audits `Print
  Assumptions` — it never consults the Petanque session, so a poisoned
  session state cannot pass a proof. If this isolation cannot be
  guaranteed, `rocq_verify` must fail closed, not fall back to session
  state.

## 7. R6 resource-guard integration (mandatory)

This is the part that distinguishes a Rocq MCP from a batch `coqc` call, and
the part that, done wrong, re-introduces the 2026-11-15 OOM/fork-bomb class
of failure. `pet-server` is **long-lived and memory-hungry** (it holds
elaborated session states; large dependent contexts OOM, exactly as the Lean
LSP does — `lean/references/compilation-errors.md`, "OOM from Large
Dependent Type Signatures").

How the guard actually works (`templates/common/tools/bin/heavy`,
`bin/mem-watchdog`, shipped into every generated project's `bin/`):
`heavy` takes a slot (`HEAVY_SLOTS`, flock), sets `ulimit -v`
(`HEAVY_MEM_KB`, 1.5 GiB) and `oom_score_adj=1000`, runs the job in its own
process group via `setsid`, kills the group on exit, and refuses nesting
beyond `HEAVY_MAX_DEPTH`. `mem-watchdog` identifies heavy jobs **solely by
`oom_score_adj == 1000`**, groups them by pgid, and below 1 GiB
`MemAvailable` (or above 1500 tasks) kills the group with the most RSS (or
most processes), logging `KILLED heavy group pgid=… leader='…'`. It never
touches anything else.

Requirements:

1. **Known, bounded processes.** Exactly one `rocq-mcp` and one `pet-server`
   per agent session. The adapter must **not** spawn `pet-server` per tool
   call, and must reap its child's process group on exit (`setsid` + group
   kill), so no orphan `pet-server` survives a crashed adapter.
2. **Watchdog-known, as the long-lived-server class.** `pet-server` is not
   launched through `bin/heavy` (it is a persistent session server, not a
   batch job, and must not hold a slot for a whole session). Instead the
   adapter launches it with the same marks `heavy` would give a job: its
   **own process group**, `ulimit -v` (`ROCQ_PET_MEM_KB`, default
   `HEAVY_MEM_KB`; Rocq elaboration of large imports may need more — a
   tunable), and **`oom_score_adj=1000`**. Because the watchdog keys on that
   value, no watchdog code change is required: an over-budget `pet-server`
   is already a kill candidate by RSS, and the existing log line names its
   leader command. The adapter itself keeps a normal `oom_score_adj` and
   stays out of the server's group, so a kill takes the server, not the
   adapter (→ item 4). This mark alone **is** the "named long-lived-server
   class" the sibling specs refer to — it needs no watchdog code change.
   Whether the watchdog should go further and *prefer* a long-lived server as
   victim (kill-server-first) and tag such kills distinctly in the log is an
   optional refinement, left as O-3 (`frama-c-mcp.md` §7 is the sibling that
   most wants it).
3. **Batch gates stay under `bin/heavy`.** `rocq_compile` and `rocq_verify`
   run `coqc` through the workspace's `bin/heavy` like any verifier job
   (slot, cap, group, depth guard). The adapter must surface a slot wait as
   progress or honour the tools' `timeout`, never spin silently. Only the
   **session server** is the exception, and it is memory-capped instead
   (item 2). If the workspace has no `bin/heavy` (a project generated
   before R6), the adapter applies `ulimit -v` and `oom_score_adj=1000` to
   the `coqc` child itself.
4. **Restart, don't leak.** On a `pet-server` OOM or watchdog kill the
   adapter reports the tool error (session handles are invalid), and
   restarts a fresh server on the next call; it never silently re-attaches
   to a dead one.

## 8. Testing

Extend `sdks/rocq/tests/` (which already has `cases/`, `check.sh` and
`run.sh`, PASS/FAIL per check inside a throwaway workshop). Drive the MCP
the way `sdks/lean/tests/lib/mcp_probe.py` does — raw MCP JSON-RPC over
stdio, standard library only — so the tests need no harness:

- **T-mcp-1 (canary).** `rocq_query("Check nat.")` answers; `rocq_start` on
  a trivial theorem returns goals; `rocq_check("reflexivity.")` reports
  `proof_finished`; `goals` is then empty.
- **T-mcp-2 (backtrack).** `rocq_step_multi` over three candidate tactics
  from one state leaves the parent state unchanged (`state/hash` equal
  before/after) and the winner is then committed via `rocq_check(…,
  from_state=…)`.
- **T-mcp-3 (version match).** `pet-server` and the SDK's `coqc` agree:
  compile `cases/make/theories/Sort.v` both ways, assert identical
  success and identical `Print Assumptions` output (guards O-2).
- **T-mcp-4 (lifecycle).** Kill the adapter mid-session; assert no
  `pet-server` survives (§7.1). Assert the server's `oom_score_adj` is 1000
  and its pgid differs from the adapter's (§7.2).
- **T-mcp-5 (degraded).** With the venv removed, the skill's canary fails and
  `scripts_only` still proves a trivial file via `coqc`.
- **T-mcp-6 (sandbox).** `rocq_verify` rejects the existing
  `cases/negative/admitted.v`, `axiom.v` and `mutant_sort` shapes and a
  proof whose statement differs from `problem_statement`, after a session
  has been poisoned with a redefinition (§6).
- **T-mcp-7 (read-only switch).** `env.read-only-switch` still passes with
  the MCP installed: nothing was written under `/opt/rocq` (§4).
- **Template test.** `tests/test_templates.py` pins the SDK list
  (`WORKSHOP_SDKS`) and the R6 scripts but has **no** venv-pin assertion
  for Lean today. Add, for both SDKs, assertions that the profile exports
  the `*_MCP_BIN` marker and that `setup-base` pins the venv contents.

## 9. Pros and cons (recap, scoped)

**Pro — fits Rocq's shape.** Rocq is interactive: goal state after each
tactic is the unit of work, and `coqc` rebuild cycles (10–30 s) are the wrong
granularity. Petanque gives sub-second goal feedback and non-destructive
multi-tactic trials — the "30×" regime the Lean skill already banks on.
**Pro — structured state, fewer tokens.** The agent reads goals/premises as
data instead of scraping `coqc` stderr. **Pro — reuses a proven pattern.**
The Lean SDK is the template; this is the same wiring with a different
backend. **Pro — the skill-side surface maps almost one-to-one** onto
released Petanque calls (`toc`, `list_notations_in_statement`,
`get_state_at_pos`), so the adapter stays thin.

**Con — a long-lived process in a guard-sensitive environment** (§7); the
whole of §7 is the cost of admitting it. **Con — version lockstep** (O-2):
the coq-lsp build and the SDK's Rocq must be built together, and today that
means a `main` pin. **Con — harness portability**: stdio MCP registration
differs per harness, so the skill must stay canary-gated and never assume
presence. **Con — surface area**: two more pinned components in the SDK to
maintain and re-pin, one of them pinned by git commit.

**Scope of the stance.** This spec adds a *proving* MCP only to Rocq. For
Frama-C/WP and Creusot — batch, memory-heavy, parallel, already served by
committed `verify.sh`/`cargo creusot` lines that are reproducible, auditable
and harness-neutral — the sibling specs give a **read-only query surface**
over the property database / why3find session alongside the batch run, plus
(Creusot only) a guarded, non-banking scratch layer. In all three the batch
run banks the verdict (§6).

## 10. Open points

- **O-1.** Adapter sourcing and backend transport: vendor the ~300-line
  adapter in `sdks/rocq/files/rocq-mcp/` (default) unless a suitable
  upstream appears; `pet-server` on an adapter-chosen loopback port vs.
  `pet` over stdio. (§3)
- **O-2.** Pin a coq-lsp / `pet-server` build compatible with the SDK's
  **Rocq 9.2**; the released line tops out at `0.2.5+9.1` with
  `rocq-core < 9.2`, while `main` claims 9.2 support, as of 2026-11-24.
  Resolve (a `main` commit, or wait for a `+9.2` release) before adding the
  part. (§4)
- **O-3.** Watchdog policy for the long-lived-server class (§7.2): the
  `oom_score_adj=1000` mark already makes it a kill candidate with no code
  change. Two optional refinements the sibling specs lean on and that `frama-c-mcp.md`
  §7 in particular wants — should `mem-watchdog` **prefer a long-lived
  server as victim** (kill-server-first, since it is advisory and restartable
  whereas a batch job loses a unit's run), and **tag** such a kill distinctly
  in its log? Also: should `ROCQ_PET_MEM_KB` default above `HEAVY_MEM_KB`?
- **O-4.** Per-harness registration lines (OpenCode, Copilot) — collect the
  exact commands, or document only Claude Code and leave the rest to the
  canary fallback; and whether the SDK's `setup-project` hook should run the
  Claude Code registration when `claude` is present.
- **O-5.** Worktree/subagent isolation: one `pet-server` per subagent (RAM
  cost, one port each) vs. a shared read-only server — mirror the Lean
  subagent guidance in `rocq/references/subagent-workflows.md`.

## 11. Relationship to existing files

- `sdks/rocq/` — SDK gains the coq-lsp pin in the `rocq` part, the vendored
  adapter under `files/`, the venv install, the profile export, the
  `check-health` probe, and the T-mcp tests (§4, §8).
- `templates/common/skills/rocq/SKILL.md` and `references/rocq-mcp-tools-api.md`
  — already written to this tool surface; this spec makes them real. The
  capability table's MCP row keeps the `rocq_query("Check nat.")` canary
  and `scripts_only` fallback; `references/subagent-workflows.md` must stop
  naming `rocq_compile` as the canary (§5, §6).
- `templates/common/tools/bin/mem-watchdog` / `bin/heavy` (the R6 guard) —
  no change strictly required by §7; O-3 may add a log tag.
- `spec/workshop-autowp-c-base-spec.md` — the `rocq` SDK row there (and its
  open point 5, "Rocq MCP server … to be identified") is the thing this
  spec extends; keep them consistent.
- `spec/frama-c-mcp.md`, `spec/creusot-mcp.md` — the sibling specs; they
  reference §7.2 here for the long-lived-server class. Keep the shared
  stance consistent: **read-only surface by default; interactivity only
  where the prover actually offers it; the batch run always banks the
  verdict.**

---

Sources (external, read 2026-11-24): the rocq-lsp README
<https://github.com/rocq-community/rocq-lsp> (supported versions, Petanque,
"MCP protocol (upcoming)"); its Petanque README, `petanque/agent.mli` and
`CHANGES.md` in the same tree (call list, `Run_result`/`Run_opts`, 0-based
positions, `pet`/`pet-server` transports); the coq-lsp release list
<https://github.com/rocq-community/rocq-lsp/releases> and the opam page
<https://opam.ocaml.org/packages/coq-lsp/> (`0.2.5+9.1`, `rocq-core >= 9.1
& < 9.2`); and the pytanque README <https://github.com/LLM4Coq/pytanque>
(client modes, method list, git install).
