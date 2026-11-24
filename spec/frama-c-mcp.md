# Frama-C usage via MCP — specification

This document specifies how to expose **Frama-C/WP** to the agent harness as
an **MCP server**, and — as importantly — what that server must **not** do.
It is the deliberate counterpart to `spec/rocq-mcp.md`: Rocq and Lean are
interactive provers where an MCP *drives proving*; **Frama-C is a batch,
memory-heavy, parallel verifier**, so its MCP is a **read-only query surface
over the property/goal database**, running **alongside** the committed
`verify.sh` WP runs, never replacing them. `spec/creusot-mcp.md` is the third
sibling (batch SMT with an optional interactive layer); the three share one
stance: read-only by default, interactivity only where the prover offers it,
the batch run always banks the verdict.

## 0. Thesis and scope

The `frama-c-monitoring` loop already treats WP output as a **property
database**: the report's claims are the upper bound `U`, and its **banking
method** is a per-goal diff of `-wp-report-json` records — one record per
goal, `(file, function, property, line, passed, verdict, provers)`, keyed by
`(file, function, property, line)` because WP goal *names* are model-prefixed
(`typed_…`/`bytes_…`) and renumber between runs (`frama-c-internals` §6,
`frama-c-monitoring` §4b). The loop still spends real effort reconstructing
"which obligations remain and why" from console output (the 900-line
`frama-c-monitoring/references/wp-gotchas.md` is the evidence). An MCP server
pays for itself **only** as a structured read over that database — so the
agent queries state instead of scraping logs, and spends fewer tokens doing
it.

What this spec explicitly rules **out**:

- **No "prove this goal" tool.** Discharging obligations stays the batch
  `frama-c … -wp … -wp-par 2` run launched from the committed `verify.sh`
  under `bin/heavy`. That model is reproducible, auditable, harness-neutral
  and already integrated with the R6 resource guard; an MCP must not fork it.
- **No mutation of the overlay.** The MCP does not write ACSL, edit
  `verify.sh`, touch `framac/.verdicts.tsv`, or bank verdicts. It reads.

So the server is an **accelerator for navigation and triage**, not a new way
to run WP. If that line blurs, the spec has failed.

## 1. Background facts the design relies on

Frama-C **Server plugin** (`frama-c.com/fc-plugins/server.html` and the
`frama-c-server.core` `Server.Request` API for 32.1, read 2026-11-24):

- The Server plugin turns Frama-C into a request server for IDE/scripting
  integration; **Ivette** (the Frama-C GUI) is built on it, so it is
  exercised, not experimental.
- **Transports:** three built-in protocols — **Unix sockets**
  (`-server-socket`), **ZeroMQ sockets**, and **static JSON script files**
  (batch request/response, no live process). Other plugins may define new
  protocols. No stdio transport is documented; the adapter therefore speaks
  the Unix-socket protocol in Mode B.
- **Requests** are OCaml routines registered by plugins, classified **GET /
  SET / EXEC**, with enforced naming: GET names contain `get` or `print`, SET
  names `set`, EXEC names `exec` or `compute` (case-insensitive); kernel
  requests are namespaced `Kernel.*` and plugin requests `<Plugin>.*`. The
  server can **generate HTML documentation of the registered requests with
  their JSON input/output formats** — the practical way to enumerate them.
- **Caveat (load-bearing for this spec):** which kernel/WP requests exist
  (AST locations, property status, WP goals) and the JSON they return are
  **version-specific and not pinned in public docs**. Ivette's WP integration
  implies WP-side requests exist; their names and schema must be enumerated
  against the SDK's **Frama-C 32.1** at implementation time (open point
  **O-1**). The published surface confirms the architecture, not the schema;
  nothing below names a specific request as confirmed.

Second data source, already in the repo and **cheaper**:

- **`-wp-report-json <file>`** writes the per-goal table after a run: one
  record per goal with `file`, `function`, `property`, `line`, `passed`,
  `verdict`, `provers` (per-prover sub-records; `"verdict":"valid"` and a
  `"Coq:8.20.1"` success entry are the shapes the `frama-c` skill relies on).
  It is a **static artifact**, needs no live server, and the monitoring loop's
  banking method already diffs it. A read over this file covers most triage
  queries with zero added process. The exact `verdict` vocabulary beyond
  `valid` is fixed from a 32.1 fixture, not assumed.

Build/packaging facts (grounded in the repo):

- `sdks/frama-c-sdk/sdkcraft.yaml` builds Frama-C 32.1 from the patched tree
  as an opam pin (all plugins) into the read-only `framac-coq8` switch under
  `/opt/frama-c-sdk` (`FRAMA_C_SDK_SWITCH`); the `frama-c-launch` skill's
  source-build path (Phase order, step 3) installs **`frama-c-server`** (and
  `qed`) by name. So the Server plugin is present; only the adapter is new.
  Its presence in the shipped switch is **probed, not assumed** — `frama-c
  -plugins` in `check-health` (§5).
- `/opt/frama-c-sdk/bin` exposes only wrapper binaries; `setup-base`
  installs `python3` but not `python3-venv` (the Lean SDK installs both).

## 2. Architecture — two modes, prefer the cheap one

```
agent harness ──MCP/stdio──▶ framac-mcp
                                 │
          ┌──────────────────────┴───────────────────────┐
   Mode A (default)                          Mode B (optional, heavy)
   read static artifacts:                    live Frama-C Server plugin:
   <target>-acsl/ per-run                    frama-c -server-socket … holding
   -wp-report-json files,                    a loaded project/AST in memory
   framac/.verdicts.tsv, VERDICTS.md,        (kernel/WP GET requests: property
   <prefix>-found-issues.md                  status, goal text, AST locations)
   → no Frama-C process
```

- **Mode A (default, stateless).** `framac-mcp` answers queries by reading the
  overlay's committed artifacts: the per-run `-wp-report-json` tables, the
  verdict log, and the monitoring report. **No Frama-C process is spawned.**
  This is the baseline because it is cheap, reproducible (anyone can re-read
  the same files), and carries **zero** R6 risk.
- **Prerequisite for Mode A (P-A).** The report must exist as a *committed,
  per-run* artifact. Today `-wp-report-json` is run ad hoc for banking diffs;
  the `verify.sh` skeleton's frama-c line does not pass it. The launch skill's
  `verify.sh` / `verify-bytes.sh` gain `-wp-report-json <overlay>/reports/
  <unit>.<model>.json` (naming: **O-7**), so every batch run leaves the table
  Mode A reads. A one-flag change, no added cost.
- **Mode B (optional, guarded).** For queries Mode A cannot answer from
  artifacts — live AST locations, the goal text, property status for a goal
  not in the last report — `framac-mcp` drives a **live Frama-C Server** over
  `-server-socket`. A loaded Frama-C project is **as memory-heavy as a WP
  run**, so Mode B is gated by §7 and off by default. The spec's
  recommendation: **ship Mode A first; make Mode B an explicit, capped
  opt-in.**

## 3. Tool surface (read-only)

All tools are GET-shaped. Names are indicative; align them to the existing
skills' vocabulary. A **goal key** is the tuple `(file, function, property,
line)` of `frama-c-internals` §6 — never the WP goal name, which is
model-prefixed and renumbers across runs.

| Tool | Returns | Mode | Backing |
|---|---|---|---|
| `wp_status(target?, run?)` | summary: total / passed / per-`verdict` counts, and which run (report file) it was read from | A | `-wp-report-json` |
| `wp_remaining(filter)` | open obligations, filterable by `file`/`function`/`property`/`prover`/`verdict` | A | report json |
| `wp_goal(key)` | one goal: `property`, `(file,line)`, `provers` with time, `verdict`; (Mode B) the goal text | A/B | json; server for text |
| `wp_provenance(key)` | which prover closed it, in which run/model (`Typed` vs `bytes`), and the `-wp-timeout` that run used | A | report path + `verdicts.tsv` |
| `wp_locate(property)` | source `(file,line)` for a property / function contract | A/B | json `line`; server AST |
| `wp_diff(run1, run2)` | goals that changed status between two runs (newly open / newly closed / regressed), keyed as above | A | two report jsons |
| `wp_query(request, args)` | a kernel/WP **GET** request against the loaded project (AST, property status) | **B** | Server request (O-1) |
| `wp_property(key)` | live property status + dependencies for a goal not in the last report | **B** | Server request (O-1) |

**Explicitly absent:** any tool that runs WP, schedules units, writes ACSL,
or mutates the overlay. Those remain `verify.sh` / the monitoring loop.
`wp_query` is restricted to GET-classed requests; the adapter refuses SET and
EXEC names (the Server's own naming rule makes this a string check).

**Positions.** The Server's location encoding is part of O-1. Whatever it is,
the adapter normalizes to the 1-based `file:line` the skills, humans and the
report json's `line` already use.

## 4. `framac-mcp` adapter

- **Transport/language.** stdio MCP (matches `lean-lsp-mcp` and the harness
  registration already in use). Mode A is a pure file reader; Mode B speaks
  the Server JSON protocol over `-server-socket`.
- **Pinning.** Pin `framac-mcp` and its MCP lib to exact versions in a venv
  at a fixed path, re-created only on mismatch — the shape of
  `sdks/lean/hooks/setup-base`. The venv must not live inside the read-only
  switch (O-3).
- **Schema binding.** The Server request names/JSON the adapter consumes are
  **bound to Frama-C 32.1**; the adapter pins a schema module enumerated
  against the SDK (O-1), checks `frama-c -version` of the binary it launches,
  and refuses (clear error, not a guess) on any other version.
- **Project/flags discovery.** Mode B must load a unit with the **same**
  preprocessing and plugin context the batch run uses, or the AST it serves
  disagrees with the one `verify.sh` proved. The adapter derives its load
  command from the overlay's `verify.sh` frama-c line **minus `-wp`** —
  `{file, flags}` from `compile_commands.json` via `bin/framac-queue.sh`, the
  `-kernel-warn-key …` settings, any `-load-module` (macsl). It does not
  invent flags.

## 5. Provisioning in the `frama-c-sdk`

Extend the SDK (which already ships the Server plugin):

- `setup-base`: apt-install `python3-venv`; add the `framac-mcp` venv install,
  pinned, in the `lean-lsp-mcp` style (`pip show … | grep -qx "Version: …"`
  guard, re-created only on mismatch).
- `frama-c-sdk.profile`: export a probe marker, e.g.
  `export FRAMAC_MCP_BIN=…/venv/bin/framac-mcp`, for the skills' capability
  table.
- `check-health`: add `frama-c -plugins | grep -qi server` next to the
  existing `-wp-detect` checks, so a switch rebuilt without the Server plugin
  is reported, not discovered by Mode B.
- **Do not write into the read-only switch.** The venv and any socket/scratch
  live outside `/opt/frama-c-sdk`'s tree (O-3).

`auto-wp.py` changes: **none to the generator's logic** beyond the SDK
shipping the binary. The skills already describe the property database; the
MCP is a new *capability row*, canary-gated (§6), not a new install step in
`auto-wp.py`. Generated projects stay stand-alone.

## 6. Harness registration and degraded mode

- **Registration.** stdio, **user-scoped**, as for Lean:
  `claude mcp add --transport stdio --scope user framac -- …/framac-mcp`.
  Documented in the generated project README step 2 / harness snippet, not
  wired by `auto-wp.py`. OpenCode/Copilot equivalents differ (O-4).
- **Canary + fallback.** The `frama-c-monitoring` / `framac-sl` skills must
  **detect the MCP by a cheap canary** (`wp_status` on the last report) and,
  on failure, fall back to the **existing** console/`-wp-report-json` parsing
  they do today. The MCP is never assumed present. A Mode-B refusal (§7) is
  **not** a canary failure: the tool answers with "Mode A only" and the skill
  continues on artifacts.

## 7. R6 resource-guard integration (mandatory for Mode B)

Mode A is a stateless file reader: it spawns no Frama-C, holds no AST, and is
effectively free — normal process hygiene suffices. **Mode B is the dangerous
one**, and the reason this section exists.

What the guard actually is (`templates/common/tools/bin/heavy`,
`bin/mem-watchdog`): `bin/heavy` takes one of `HEAVY_SLOTS` (default 4)
`flock` slots in `$HEAVY_LOCKDIR` (`/tmp/heavy-slots/slot.N`), applies
`ulimit -v $HEAVY_MEM_KB` (1.5 GiB), sets `oom_score_adj=1000`, runs the job
in its own `setsid` process group and kills the group on exit. `mem-watchdog`
selects victims **solely by `oom_score_adj=1000`**: when `MemAvailable` drops
under 1 GiB it kills the largest-RSS such group, logging the leader command.
A live Frama-C Server holding a loaded project is **as memory-heavy as a WP
run**, and campaigns already run units in parallel under this guard; a
careless long-lived server contends for exactly that RAM — the 2026-11-15
OOM class.

Requirements (same spirit as `rocq-mcp.md` §7, stricter on contention):

1. **One server, bounded, idle-reaped.** At most one Mode-B Frama-C server
   per agent session, spawned on first Mode-B call. The adapter owns its
   process group (`setsid` + group kill) and reaps it on exit; no orphan
   survives a crashed adapter. The server **exits after an idle timeout**
   (minutes, not the session): an advisory server must not sit on a loaded
   AST between queries.
2. **Memory cap + watchdog-known.** The server runs with `ulimit -v
   $HEAVY_MEM_KB` (the batch's own cap; a larger cap is an explicit,
   documented decision) and `oom_score_adj=1000`. This is the baseline
   **named long-lived-server class** `rocq-mcp.md` §7.2 defines (shared with
   `pet-server`): the mark alone makes the server a kill candidate under the
   watchdog's **existing** selector, with **no watchdog code change**.
   Because Mode B's sharper risk is contending with the batch, it is the
   sibling that most wants the optional refinement `rocq-mcp.md` §7.2 leaves
   open as **O-3** — when both a batch group and a long-lived server are
   candidates, **kill the server first** (advisory and restartable, whereas
   the batch job would lose a unit's run) and tag the class in the log. Until
   that lands, the baseline selector kills by RSS and may take a batch group
   first, so the yield rule (§7.3), not the watchdog, is what actually
   protects the batch.
3. **Yield to the batch.** A sweep is "active" when **any** `bin/heavy` slot
   is held — probe with a non-blocking `flock` on `$HEAVY_LOCKDIR/slot.*`.
   The pool is machine-wide and carries no target identity; RAM is
   machine-wide too, so the rule is machine-wide: the adapter **refuses to
   start** a server while a slot is held, and **shuts a running server down**
   when a slot becomes held (checked before each Mode-B call), answering
   "Mode A only" (§6). The server is deliberately **not** run *through*
   `bin/heavy`: that would pin a slot for the session and starve the batch of
   25% of its parallelism while the server idles. It is also never nested
   inside a heavy job (no `HEAVY_DEPTH` inheritance).
4. **Restart, don't leak.** On server OOM, watchdog kill or idle exit the
   adapter reports the tool error (or restarts transparently on the next
   call) and never re-attaches to a dead socket; the stale socket file is
   removed.

## 8. Reproducibility contract

Because this project values campaigns being reconstructable from artifacts:

- **Mode A answers must be reproducible from committed files.** Any
  `wp_status`/`wp_remaining`/`wp_diff`/`wp_provenance` result must be
  derivable by a human re-reading the same `-wp-report-json` /
  `verdicts.tsv` — the MCP is a faster path to the same data, never a source
  of truth of its own. Every answer names the run (report file) it was read
  from, so staleness relative to the overlay is visible, not hidden.
- **Mode A is never newer than the last batch.** Reports are produced only by
  batch runs (P-A); the MCP cannot observe a goal's status change that no
  `verify.sh` run has produced.
- **Mode B is advisory.** Live-server answers (AST locs, goal text, on-demand
  status) are navigation aids; anything the loop **banks** must still come
  from a committed batch run's report, not from a server query. The MCP
  cannot close a goal.

## 9. Pros and cons (scoped)

**Pro — structured property DB, fewer tokens.** The monitoring loop reads
goals/remaining/provenance as data instead of regex-ing WP stderr; `wp_diff`
makes cross-run regression triage a single call. **Pro — cheap default.**
Mode A adds a capability with **no** new process and no R6 exposure. **Pro —
reuses what ships**: the Server plugin is built, and the report json is the
loop's existing banking artifact.

**Con — schema version lockstep (O-1).** The Server request/JSON surface is
bound to Frama-C 32.1 and undocumented publicly; the adapter must pin a schema
enumerated against the SDK and fail loudly on mismatch. **Con — Mode B RAM
contention** (§7): a live server fights the parallel batch for memory; the
whole of §7 is the price. **Con — harness portability**: stdio registration
differs per harness, so the skills stay canary-gated. **Con — surface area**:
one more pinned component in the SDK.

**Why not more than read-only.** Making the MCP *drive* WP would trade away
reproducibility, auditability and R6 compatibility for an interactivity
Frama-C's batch model does not actually offer — WP does not expose a
sub-second per-tactic goal loop the way Rocq/Lean do, and the Server plugin's
EXEC requests are not that loop either. The gain is in **reading** the
property database, and that is where this spec stops.

## 10. Testing

Extend `sdks/frama-c-sdk/tests/run.sh` (whose `behavior-goals` case already
emits a `-wp-report-json`; its `behaviors.c` report is the fixture) and
`tests/test_templates.py`:

- **T-A1 (status).** On the fixture report, `wp_status` returns the exact
  passed / per-verdict counts; `wp_remaining` lists exactly the open goals.
- **T-A2 (diff).** `wp_diff` over two reports differing in one goal reports
  precisely that goal, keyed by `(file,function,property,line)`, including a
  case where WP renumbered the goals (guards the key rule).
- **T-A3 (reproducibility).** `wp_remaining` output equals a reference derived
  by a plain `jq` script over the same json (guards §8).
- **T-B0 (plugin present).** `frama-c -plugins` lists the Server plugin in the
  shipped switch (guards §1, `check-health`).
- **T-B1 (schema match).** Mode B refuses, with a clear error, a server whose
  version differs from the pinned 32.1 binding (guards O-1).
- **T-B2 (yield).** With one `bin/heavy` slot held, Mode B refuses to start
  and answers "Mode A only"; taking a slot while a server is up shuts it down
  (guards §7.3).
- **T-B3 (lifecycle).** Kill the adapter mid-session; assert no Frama-C
  server survives. Leave a server idle past the timeout; assert it exited
  (§7.1).
- **T-B4 (GET only).** `wp_query` with a SET- or EXEC-named request is
  refused before reaching the server (§3).
- **T-degraded.** With the venv removed, the skill canary fails and the loop
  falls back to its current json/console parsing and still triages.
- **Template test.** Assert the SDK profile exports `FRAMAC_MCP_BIN`,
  `setup-base` pins `framac-mcp`, and the launch skill's `verify.sh` line
  carries `-wp-report-json` (P-A) — alongside the existing R6 guard token
  checks in `tests/test_templates.py`.

## 11. Open points

- **O-1.** Enumerate the exact kernel/WP request names and the WP-goal /
  property-status JSON schema against the SDK's **Frama-C 32.1** — via the
  Server plugin's generated request documentation and Ivette's client code —
  and pin a schema module. (Blocks Mode B.)
- **O-2.** Is Mode A alone enough for the monitoring loop's real queries? If
  `wp_status`/`wp_remaining`/`wp_diff`/`wp_provenance` over the reports
  cover the triage need, Mode B may be deferred indefinitely.
- **O-3.** Where do the venv, the server socket, and scratch live, given the
  read-only `/opt/frama-c-sdk` switch? (A writable sibling under the project
  or `$HOME`.)
- **O-4.** Per-harness registration lines (OpenCode, Copilot).
- **O-5.** Subagent/worktree model: the loop already runs parallel units in
  separate worktrees; one Mode-B server per subagent multiplies the RAM.
  Default to Mode A for fan-out; at most one Mode-B server per machine is
  the safe reading of §7.1.
- **O-6.** Does `framac-sl` (the per-unit squeeze loop) benefit, or only
  `frama-c-monitoring`? Scope the capability row to the loop that triages.
- **O-7.** Report artifact convention (P-A): path and naming of the per-run
  `-wp-report-json` under the overlay (`reports/<unit>.<model>.json` is the
  placeholder), and how `wp_provenance` recovers the run's `-wp-timeout` and
  model from it — fix together with the `frama-c-launch` skill.

## 12. Relationship to existing files

- `sdks/frama-c-sdk/` — gains `python3-venv`, the `framac-mcp` venv install,
  the profile export, the `check-health` Server-plugin probe, and the
  T-A/T-B tests (§5, §10). The Server plugin is already built.
- `templates/c/skills/frama-c-launch/SKILL.md` — its `verify.sh` /
  `verify-bytes.sh` lines gain `-wp-report-json` (P-A, O-7); its Phase-order
  step 3 already installs `frama-c-server`; note the MCP as a downstream
  consumer.
- `templates/c/skills/frama-c-monitoring/SKILL.md` (§4b banking) and
  `frama-c-internals` (§6, the report-json key) — gain an MCP capability row
  with the canary and the json/console fallback (§6). The loop keeps
  committing `verify.sh` and banking only from batch runs (§0, §8).
- `templates/common/tools/bin/mem-watchdog` / `bin/heavy` (the time-loop R6
  guard) — the baseline long-lived-server class shared with `rocq-mcp.md` §7
  (the `oom_score_adj=1000` mark) needs **no** watchdog change; the optional
  kill-server-first + class-tag refinement is `rocq-mcp.md` O-3, which Mode B
  wants (§7.2). `bin/heavy` is unchanged, its slot files are what §7.3 probes.
- `spec/rocq-mcp.md` — the interactive sibling; its §9 names this one as the
  batch-prover case. `spec/creusot-mcp.md` — the third sibling; it reuses
  this §7's yield-to-batch rule. Keep the shared stance consistent across the
  three.

---

Sources (external, read 2026-11-24): the Frama-C Server plugin page
<https://frama-c.com/fc-plugins/server.html> (three built-in protocols,
custom protocols, Ivette, generated request documentation) and the
`frama-c-server.core` `Server.Request` API for 32.1
<https://ocaml.org/p/frama-c/32.1/doc/frama-c-server.core/Server/Request/index.html>
(GET/SET/EXEC kinds, naming and namespacing rules). Request names and the WP
JSON schema were **not** found in either and remain O-1.
