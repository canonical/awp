# Creusot usage via MCP — specification

This document specifies how to expose **Creusot** (Rust + Pearlite →
Coma → Why3/why3find → SMT) to the agent harness as an **MCP server**. It is
the third of the prover-MCP specs and sits **between** its siblings:

- `spec/rocq-mcp.md` / Lean — fully interactive provers; the MCP *drives
  proving* (per-tactic goal loop).
- `spec/frama-c-mcp.md` — a batch verifier; the MCP is a **read-only query
  surface** over the property database, never drives proving.
- **Creusot (here)** — batch SMT auto-discharge (`cargo creusot`), **but**
  with a real interactive proof layer underneath (Why3 transformations +
  per-goal provers). So Creusot gets **both**: a read-only default over the
  why3find proof artifacts, **and** an *optional, guarded* interactive layer
  for the hard VCs — while the authority that **banks verdicts stays the
  batch run**.

## 0. Thesis and scope

Creusot's proof model in this repo (grounded in the skills):

- `cargo creusot [PATTERN]` is the batch oracle. Creusot → Coma → **why3find**
  generates verification conditions and discharges them with SMT backends.
  A **verdict = the per-obligation discharge status from why3find**, plus a
  determinism re-run (`creusot-sl` §4 "Gate B — machine": *all VCs
  discharged*, no escape hatch on the target, **standing proof count holds**
  — previously discharged VCs stay discharged). The artifacts of record are
  the overlay's `verif/<crate>_rlib/<fn>/proof.json` files, and the campaign
  ledger `XXX-creusot/verdicts.tsv` is the time-loop's single source of truth
  (`time-loop` §5).
- The **proof plane** (Why3 discharge) and the **test plane** (`cargo test`)
  never substitute for one another (`creusot-sl` Gate C). The MCP lives
  wholly in the **proof plane**, and mostly on its **read** side.

What the MCP is for: the `creusot-sl` and `creusot-monitoring` loops spend
effort reading why3find output to answer "which obligations are open, under
which transformation, which prover closed the rest, and did any standing proof
regress?" Today that is done with ad-hoc scripts over `proof.json` and the
`cargo creusot` summary lines (a campaign's `tools/proofjson-check.py`,
`gen-report.py`). A structured read over the same artifacts turns that
scraping into typed queries and saves tokens.

What this spec rules **out**:

- **No tool banks a verdict.** `DONE`/Gate-B still comes from a committed
  `cargo creusot` batch run over the real crate — never from an MCP query or
  an interactive scratch session.
- **No tool edits Rust or Pearlite**, adds `#[trusted]`/`assume!`, or weakens
  a contract; no tool writes `verif/`, `verdicts.tsv`, `why3find.json` or any
  ledger. The interactive layer (Mode B) *discovers* a transformation or
  annotation that works; the human/loop then writes it into committed proof
  scaffolding and re-proves it with the batch. The MCP cannot close a goal of
  record.

## 1. Background facts the design relies on

**The installed SDK** (`sdks/creusot/`, read 2026-11-24): `cargo-creusot
0.15.0-dev` at commit `f15b985` (`CREUSOT_SDK_COMMIT`), Why3 `1.8.2+git`,
why3find `v1.3.0+dev`, provers Alt-Ergo 2.6.4, Z3, CVC5 and (x86_64 only)
CVC4. Everything is read-only under `/opt/creusot` (`CREUSOT_DATA_HOME=
/opt/creusot/data`, `CREUSOT_SDK_SRC`), the SDK tests assert `sdk-untouched`,
and rustup/cargo live in `$HOME`. `$CREUSOT_DATA_HOME/bin` (why3, why3find,
the provers) is **deliberately not on `PATH`** — `cargo-creusot` adds it for
its children, and it would clash with the frama-c-sdk wrappers
(`creusot.profile`). The switch is built **without `why3-ide`** (no GTK), so
there is **no Why3 IDE in a workshop**.

**CLI as installed** (from the SDK tests and a 2026-11 campaign's audit):
`cargo creusot [PATTERN]` runs `why3find prove -j N --summary
--no-autodetect-provers verif/<crate>_rlib`; `--dry-run-why3find` prints that
exact command; `--no-cache`, `-f`, `-r`/`--replay`, `-j N`,
`--why3find-arg=…`, `cargo creusot clean [--force]` exist. In this version
**`cargo creusot prove` is not a subcommand** (it is read as the pattern
`prove`); the upstream guide's `cargo creusot prove`, `-i`/`--ide-always` and
`--why3session` belong to a newer release line and are **not confirmed at
`f15b985`** (O-1). Do not design against them.

**Artifacts** (per module `verif/<crate>_rlib/<fn>.coma`, the `.coma` itself
gitignored and regenerated):

- `<fn>/proof.json` (committed) — why3find's proof certificate:
  `{"profile": [...], "proofs": {"Coma": {"vc_<name>": …}}}` where a goal is
  either a leaf `{"prover": "alt-ergo", "time": 0.013}` or a node
  `{"tactic": "compute_specified"|"split_vc", "children": [...]}`; a **failed
  leaf is `null`**. Children are **positional** — `proof.json` carries no
  goal explanation and no source span. The tactics and their depth come from
  `why3find.json` (`"tactics": ["compute_specified", "split_vc"]`,
  `"depth": 6`, `"provers"`, `fast`/`time` budgets, a `profile` calibration).
- `why3session.xml` (Why3 session v5, `shape_version="6"`) — a standard Why3
  session, seen next to `proof.json` for one module of ~320 in the campaign
  corpus (how it was produced is not recorded). It carries what `proof.json`
  lacks: `<transf name="split_vc">` nodes over goals named `vc_<fn>.0.3`
  with `expl="loop invariant #3"` and `proved="true|false"`. Where present it
  is a richer read; it cannot be assumed present.
- `cargo creusot` output: `Proved (N files) ✔` (N = `.coma` count),
  `Goal Coma.vc_<fn>: ✘`, `Error: K unproved file(s)`, `'why3find prove'
  failed`; under load, `can not calibrate prover <p>@` aborts the run.

**Oracle integrity** (the campaign's `oracle-integrity-01.md`): a verdict may
cite a `proof.json` **only from a run that finished with exit 0 and a printed
summary**; an interrupted run leaves partial files; never read `proof.json`
while a `why3find prove` is active on the same `verif/` tree.

**Why3 / why3find APIs.** why3find exposes an OCaml `Session` module
(`theories`/`split`/`goal_name` in the 1.2.0 docs) and Why3 a `Session_itp`
API (`get_transf_name`/`get_sub_tasks`) — i.e. the proof tree is
programmatically walkable. The docs read are for **other releases than the
installed `1.3.0+dev` / `1.8.2+git`**; names and signatures must be checked
against the SDK before any adapter links them (O-1). Why3's `why3 prove -a
<transformation> -P <prover>` is the discrete, session-free way to apply one
transformation and run one prover on a file.

The Lean/Frama-C precedents this spec reuses: pinned venv in the SDK
`setup-base` (`lean-lsp-mcp` style), stdio **user-scoped** harness
registration, **canary + fallback**, and the **R6 named-long-lived-server /
yield-to-batch** rules (`rocq-mcp.md` §7, `frama-c-mcp.md` §7).

## 2. Architecture — two modes

```
agent harness ──MCP/stdio──▶ creusot-mcp
                                 │
          ┌──────────────────────┴────────────────────────┐
   Mode A (default, read-only)              Mode B (optional, interactive, guarded)
   walk verif/**/proof.json (+ a             copy ONE .coma to scratch; apply a Why3
   why3session.xml where present),           transformation, run one prover on one
   verdicts.tsv, cargo creusot logs          subgoal, read the task text → provers
   → no prover, no Why3 process              under bin/heavy, -j 1, yields to batch
```

- **Mode A (default, stateless).** `creusot-mcp` answers from the overlay's
  committed artifacts: the `proof.json` trees, any `why3session.xml`, the
  `cargo creusot` run logs and `verdicts.tsv`. **No prover and no Why3
  process is spawned.** Cheap, reproducible, zero R6 risk. It covers the
  triage the loops actually do and replaces the per-campaign scripts.
- **Mode B (optional, interactive, guarded).** For a VC that does **not**
  auto-discharge (a `null` leaf), `creusot-mcp` copies the module's `.coma`
  into a **scratch** directory and lets the agent apply a transformation and
  try a prover per subgoal, or read the subgoal's task text — the one place
  Creusot's interactivity (unlike Frama-C) earns an interactive MCP, and the
  only interactive path in a workshop, since the SDK ships no Why3 IDE. It
  runs **provers through `bin/heavy`** and is off by default (§7). Its results
  are **advisory**: a transformation/annotation that works here must be
  written into committed scaffolding and re-proved by the batch to count.

## 3. Tool surface

**Mode A — read-only (GET-shaped).** Every answer carries its provenance
(`commit`, path, mtime) and an `in_flight` flag (§8).

| Tool | Returns | Backing |
|---|---|---|
| `creusot_status(unit?)` | totals: modules, goals, discharged / unproved leaves; `in_flight` | `proof.json` + last run log |
| `creusot_remaining(filter)` | unproved goals by `unit`/`module`/`function`/`tactic`/`depth` | `proof.json` |
| `vc_goal(id)` | one goal: `Coma.vc_<fn>[.i.j]`, tactic path, prover, time, status; `expl` when a session exists | `proof.json`; `why3session.xml` |
| `vc_tree(module)` | the `compute_specified`/`split_vc` tree with per-leaf status; `expl` per node when a session exists | `proof.json`; `why3session.xml` |
| `vc_provenance(id)` | prover and time that closed it; the `verdicts.tsv` row and commit that banked it | `proof.json` + ledger |
| `vc_locate(id)` | Rust/Pearlite source `(file, line, clause)` for a goal | **partial in Mode A**: `expl` from a session only; full location needs the task (Mode B) |
| `creusot_diff(rev1, rev2)` | goals that changed status between two **committed** revisions (newly open / closed / **regressed** standing proof) | two `proof.json` trees |

**Mode B — interactive, non-banking (EXEC-shaped, guarded).**

| Tool | Effect | Guard |
|---|---|---|
| `vc_split(id, transf?)` | apply one Why3 transformation (`split_vc`, `compute_specified`, or another by its Why3 name) to the goal in a **scratch** copy; return the subgoals | §7 |
| `vc_try(subgoal, prover, timeout)` | one prover on one (sub)goal, under `bin/heavy`, one process at a time | §7 |
| `why3_task(subgoal)` | the subgoal's task text and source positions, for reading | Why3 process, no prover; §7.1 |

**Explicitly absent:** any tool that runs `cargo creusot`/`why3find prove`,
edits Rust/Pearlite, adds `#[trusted]`/`assume!`, writes under the overlay
(`verif/`, `why3find.json`, `verdicts.tsv`, `time-loop.state`,
`trusted-base.md`), opens or saves a Why3 session on an overlay path, or
returns a bankable verdict. Mode B works on a scratch copy and reports what
*would* discharge.

## 4. `creusot-mcp` adapter

- **Transport/language.** stdio MCP. Mode A is a reader of `proof.json`,
  `why3session.xml`, run logs and `verdicts.tsv` (plain parsers; no OCaml
  needed). Mode B orchestrates discrete `why3`/`why3find` subcommands and
  prover calls; an OCaml tool linked against the pinned why3find `Session`
  API is an option only once O-1 is settled.
- **Pinning + SDK binding.** Pin `creusot-mcp` and its deps in a venv at a
  fixed path (the `lean-lsp-mcp` guard shape). The adapter records the
  `CREUSOT_SDK_COMMIT`, Why3 and why3find versions it was validated against
  and refuses with a clear error on any other (O-1).
- **Toolchain discovery.** The adapter inherits `/etc/profile.d/creusot.sh`
  and resolves `why3`, `why3find` and the provers **from
  `$CREUSOT_DATA_HOME/bin`**, never from `PATH` (which deliberately lacks
  them). It takes the exact why3find command line, load path and
  `why3find.json` from `cargo creusot --dry-run-why3find` for the unit, so a
  Mode-B task sees the same prelude/packages and prover configuration the
  batch used — it does not invent a proof environment.
- **Scratch isolation (Mode B).** The module's `.coma` and what why3find
  needs to load it are **copied** to a scratch dir outside the overlay (O-3);
  transformations, prover attempts and any session Why3 writes stay there.
  Nothing under the overlay's `verif/` is opened for writing, so a Mode-B
  experiment cannot forge a discharge of record (§8).

## 5. Provisioning in the `creusot` SDK

Extend `sdks/creusot/hooks/setup-base` (today: link `/opt/creusot`, apt libs,
install `creusot.profile`):

- Add the pinned `creusot-mcp` venv install, `lean-lsp-mcp`-style (`pip show …
  | grep -qx "Version: …"` guard, re-created only on mismatch). `python3`,
  `ripgrep`, `libgmp10`, `zlib1g` are already installed; add `python3-venv`
  as the lean hook does.
- Export a probe marker in `creusot.profile`, e.g.
  `export CREUSOT_MCP_BIN=…/venv/bin/creusot-mcp`.
- **Do not write into the read-only `/opt/creusot` tree** (the SDK test
  `sdk-untouched` would fail). The venv and Mode-B scratch live outside it
  (O-3).

`auto-wp.py` changes: **none to the generator's logic** — the SDK ships the
binary, the `creusot`/`creusot-sl`/`creusot-monitoring` skills gain a
canary-gated capability row (§6). Generated projects stay stand-alone.

## 6. Harness registration and degraded mode

- **Registration.** stdio, **user-scoped**:
  `claude mcp add --transport stdio --scope user creusot -- …/creusot-mcp`.
  Documented in the generated README step 2 / harness snippet, not wired by
  `auto-wp.py`. OpenCode/Copilot equivalents differ (O-4).
- **Canary + fallback.** The skills detect the MCP by a cheap canary
  (`creusot_status`) and, on failure, fall back to the **existing**
  `proof.json` / `cargo creusot` summary parsing (the `proofjson-check.py`
  shape: `.coma` ↔ `proof.json` coverage, `vc_<name>` presence, `null`
  leaves, the `Proved (N files) ✔` line). The MCP is never assumed present —
  same contract as Lean's capability table and the sibling specs.

## 7. R6 resource-guard integration (mandatory)

Mode A is a stateless reader of committed files — it spawns no prover, holds
no task, and is effectively free; normal process hygiene suffices. **Mode B is
the guarded one**, because it launches **SMT provers**, which is exactly the
memory/CPU load `bin/heavy` + `bin/mem-watchdog` were built for (`time-loop`
R6: every `creusot`/`why3`/prover call not through `bin/heavy` is a
loop-behaviour bug).

Requirements:

1. **Provers run under `bin/heavy`.** Every `vc_try` (and the Why3 process
   behind `vc_split`/`why3_task`) runs through `bin/heavy` — slot pool,
   `ulimit -v`, `oom_score_adj=1000`, process-group cleanup — like any
   discharge job. The adapter never spawns a raw prover. Mode B is
   **single-prover, single-goal** at a time (`-j 1`, one slot); it never runs
   `why3find prove` over a directory.
2. **Discrete calls, no persistent server.** Mode B issues one `why3`
   command per tool call and reads its result; nothing heavy outlives the
   call, so there is **no** long-lived server to manage (a simpler R6 story
   than Frama-C Mode B). If a persistent Why3 session process is ever
   introduced, it must join the **named long-lived-server class** of
   `rocq-mcp.md` §7.2 — memory-capped, watchdog-known, process-group-reaped
   — not an unbounded process.
3. **Yield to the batch.** Mode B must **not** run while a `cargo creusot` /
   `why3find prove` sweep is active on the same overlay: it doubles peak
   prover memory, and extra prover load makes why3find's calibration fail
   (`can not calibrate prover`), i.e. it can make the batch **abort**, not
   just slow down. The adapter checks `pgrep -af "why3find prove"` for the
   overlay's `verif/` tree and the monitoring loop's lock / `bin/heavy` slot
   pool, refuses, and directs the query to Mode A. Subagent fan-out uses Mode
   A only (O-5).
4. **Restart, don't leak.** On a prover OOM or a watchdog kill the adapter
   reports the tool error and cleans its scratch; no orphaned prover or Why3
   process survives (`bin/heavy` kills the group; the adapter kills its own
   children on exit). A `KILLED` line in `XXX-creusot/watchdog.log` naming a
   Mode-B group is still an incident for the coordinator to read, even though
   Mode B records no verdict.

## 8. Reproducibility and the banking rule

- **Mode A is reproducible from committed files.** Every
  `creusot_status`/`remaining`/`diff`/`tree` result must be derivable by a
  human re-reading the same `proof.json` / `why3session.xml` / `verdicts.tsv`
  at the same commit — the MCP is a faster path to the same data, not a
  source of truth. Mode A honours the oracle-integrity rule: it reports
  `in_flight: true` and refuses to summarize a `verif/` tree while a
  `why3find prove` is active on it or the last run log has no final
  summary, since a partial `proof.json` is not a verdict.
- **Mode B is advisory and non-banking.** A transformation or prover result
  from a scratch task is a *hint*. To count, the discovered annotation/
  scaffolding is written into committed Pearlite/`#[invariant]`/proof code and
  re-proved by `cargo creusot`; the verdict is banked from that batch run's
  `proof.json` and the ledger, per `creusot-sl` Gate B. No §3 tool can write
  under the overlay or run the batch, so the MCP **cannot** close a goal of
  record, and `creusot_diff`'s "regressed" flag is computed only between
  **committed** revisions.

## 9. Pros and cons (scoped)

**Pro — structured VC navigation, fewer tokens.** The loops read goals / the
`split_vc` tree / provenance / cross-run regressions as data instead of
re-writing `proof.json` scrapers per campaign. **Pro — cheap default.** Mode A
adds a capability with no new process and no R6 exposure. **Pro — genuine
interactivity where it helps.** Unlike Frama-C, Creusot has a real Why3
transformation layer and the SDK has no IDE; Mode B is the only way to *read
a failing subgoal's task* or try a split/prover the batch's strategy did not —
the middle ground between batch and the Rocq/Lean tactic loop. **Pro — reuses
shipped tools** (why3find, Why3, the provers are already in the SDK).

**Con — version lockstep (O-1).** The why3find/Why3 CLI and APIs move across
releases (the installed `cargo creusot` already lacks the guide's `prove`
subcommand); the adapter must bind to the SDK's pin and fail loudly on
mismatch. **Con — thin Mode-A locations.** `proof.json` is positional: without
a `why3session.xml`, Mode A cannot name a leaf's `expl` or source line; that
is what pushes `vc_locate` toward Mode B. **Con — Mode B prover load** (§7):
interactive discharge competes with the batch for exactly the RAM/CPU
`bin/heavy` rations and can break its calibration. **Con — banking
discipline** (§8): the interactive layer must stay advisory, or it erodes the
reproducible-from-batch guarantee `creusot-sl` depends on. **Con — harness
portability** and **surface area**, as in the sibling specs.

**Why not let the MCP bank verdicts.** The whole `creusot-sl`/`-monitoring`
design rests on verdicts coming from a deterministic `cargo creusot` over the
real crate, re-runnable by anyone from committed files. An MCP that closed
goals would trade that away for convenience. The gain is in **reading** the
artifacts and **experimenting** off to the side; banking stays with the batch.

## 10. Testing

Extend the `creusot` SDK tests and `tests/test_templates.py`. Fixtures are
`verif/` trees in the SDK-test layout (`<fn>.coma` + `<fn>/proof.json`, one
with a `why3session.xml`, one with `null` leaves):

- **T-A1 (status/remaining).** `creusot_status` returns exact module/goal/
  unproved counts; `creusot_remaining` lists exactly the `null` leaves.
- **T-A2 (tree).** `vc_tree` reproduces the `compute_specified`/`split_vc`
  nesting of `proof.json`, and the `expl`/`proved` per node where the
  fixture has a `why3session.xml`.
- **T-A3 (diff/regression).** `creusot_diff` over two revisions flags
  precisely the newly-open / closed / regressed goals.
- **T-A4 (reproducibility).** `creusot_remaining` equals a reference derived
  by a plain script over the same files (guards §8).
- **T-A5 (in-flight).** With a `why3find prove` process (or a run log without
  final summary) on the fixture, Mode A reports `in_flight` and refuses a
  summary (guards §8).
- **T-B1 (scratch isolation).** `vc_split`/`vc_try`/`why3_task` leave the
  overlay byte-identical — no new `why3session.xml`/`.bak`/`why3shapes.gz`
  under `verif/` (guards §8).
- **T-B2 (under heavy).** A `vc_try` prover appears in a `bin/heavy` process
  group, one at a time; killing the adapter leaves no prover or `why3`
  process (§7.1, §7.4).
- **T-B3 (yield).** Mode B refuses while a `why3find prove` is active on the
  overlay's `verif/` (§7.3).
- **T-B4 (version match).** The adapter refuses a why3find/Why3/
  `CREUSOT_SDK_COMMIT` that differs from its pinned binding (guards O-1).
- **T-degraded.** With the venv removed, the canary fails and the loop falls
  back to `proof.json`/`cargo creusot` parsing and still triages.
- **Template test.** Assert `creusot.profile` exports `CREUSOT_MCP_BIN` and
  `setup-base` pins `creusot-mcp`, mirroring the lean checks; `sdk-untouched`
  still passes.

## 11. Open points

- **O-1.** Bind to the SDK's pin (`f15b985`, Why3 `1.8.2+git`, why3find
  `1.3.0+dev`): confirm the `cargo creusot` flag set at that commit (no
  `prove` subcommand; `-i`/`--why3session` unverified), the exact `why3
  prove -a … -P …` invocation on a `.coma` with the Creusot package on the
  load path, and whether the why3find `Session`/Why3 `Session_itp` names in
  the docs read exist in the installed versions. (Blocks Mode B; Mode A over
  `proof.json` depends only on the JSON shape above.)
- **O-2.** Is Mode A alone enough? If
  `status`/`remaining`/`tree`/`diff`/`provenance` cover the loops' triage,
  Mode B may be deferred.
- **O-3.** Where do the venv and Mode-B scratch live, given the read-only
  `/opt/creusot`? (A writable sibling under the project or `$HOME`, never
  under the overlay's `verif/`.)
- **O-4.** Per-harness registration lines (OpenCode, Copilot).
- **O-5.** Subagent/worktree model: Mode A everywhere for fan-out; Mode B
  prover budget shared via the one `bin/heavy` slot pool.
- **O-6.** Which loop benefits — `creusot-sl` (per-unit), `creusot-monitoring`
  (cross-crate), or both — and how `creusot_diff`'s regression signal feeds
  Gate B's standing-proof-count check and the ledger.
- **O-7.** Is Mode B worth it? why3find already searches: it applies the
  `why3find.json` tactics (`compute_specified`, `split_vc`) to depth 6 and
  tries every configured prover within the time budget, so "find a split or
  prover that works" mostly re-runs what the batch did. What Mode B uniquely
  adds is **reading the failing subgoal's task text and positions** and
  trying a transformation or budget outside the batch's strategy. The
  Frama-C stance (read-only only) is therefore defensible; the counter-point
  is that the SDK ships no Why3 IDE, so without Mode B there is no way to
  look at a stuck VC in a workshop at all. Decide after Mode A has run on a
  campaign and the open-VC triage need is measured.

## 12. Relationship to existing files

- `sdks/creusot/` — gains the `creusot-mcp` venv install, the
  `CREUSOT_MCP_BIN` export, and the T-A/T-B tests (§5, §10); its
  `tests/README.md` and `in-workshop.sh` document the `verif/` layout and the
  `Proved (N files) ✔` / `Goal Coma.vc_<fn>: ✘` shapes Mode A parses.
  why3find/Why3/provers are already shipped.
- `templates/rust/skills/creusot/SKILL.md`,
  `creusot-sl/SKILL.md`, `creusot-monitoring/SKILL.md` — gain a canary-gated
  MCP capability row with the `proof.json`/`cargo creusot` fallback (§6).
  Gate B and `DONE` keep banking from committed batch runs (§0, §8).
- `templates/rust/skills/time-loop/SKILL.md` (R6, `verdicts.tsv`) and
  `bin/mem-watchdog` / `bin/heavy` — Mode-B prover calls run under
  `bin/heavy`; a persistent session, if ever added, joins the long-lived-
  server class shared with `rocq-mcp.md` §7 / `frama-c-mcp.md` §7 (§7).
- `spec/rocq-mcp.md`, `spec/frama-c-mcp.md` — the sibling specs. Keep the
  stance consistent: **read-only surface by default; interactivity only where
  the prover actually offers it; the batch run always banks the verdict.**

---

Sources (read 2026-11-24). In-repo: `sdks/creusot/` (`sdkcraft.yaml`,
`files/creusot.profile`, `hooks/*`, `tests/README.md`, `tests/in-workshop.sh`),
`templates/rust/skills/creusot/references/install.md`, `creusot-sl/SKILL.md`,
`time-loop/SKILL.md` (R6), and a 2026-11 httparse campaign overlay (untracked,
`serde_json-analyze/httparse-creusot/`: `verif/**/proof.json`, one
`why3session.xml`, `why3find.json`, `tools/proofjson-check.py`,
`../serde_json-creusot/oracle-integrity-01.md`). External, for releases
**other than the installed ones**: the Creusot CLI guide
<https://creusot-rs.github.io/creusot/guide/command_line_interface.html>; the
why3find `Session` API (1.2.0)
<https://ocaml.org/p/why3find/1.2.0/doc/why3find/Why3find/Session/index.html>;
a `why3session.xml` with a `split_vc` node
<https://sources.debian.org/src/why3/1.8.2-3/examples/binary_search/why3session.xml>;
and the Why3 session API (1.0.0)
<https://ocaml.org/p/why3/1.0.0/doc/Why3/Session_itp/index.html>.
