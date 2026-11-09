# choose-harness — selecting and switching the agent harness

This document specifies:

- the **harness abstraction**: the fixed set of capabilities a harness must
  provide for a generated project and for the container tests (§1) — the
  table a new harness fills;
- how to **switch a generated project or a test run to OpenCode** (§2, §3) —
  implemented since auto-wp 0.4.0, with the fixes §3.2 still requires;
- how to switch to **GitHub Copilot**, by two routes: **Route A** — Copilot as
  a model *provider* inside the OpenCode harness (§4, proposed) — and
  **Route B** — the Copilot CLI as a third harness *binary*, with its BYOK
  variant **B′** (§5, a sketch);
- the account, plan and terms constraints of each route (§6);
- why a **running campaign is never switched**, and how to stop one (§7);
- how a harness is **selected**: `auto-wp.py --harness` at generation,
  `HARNESS` in the tests, and `--harness none` for a harness installed by
  hand (§1.5);
- the files each route touches and its acceptance tests (§8);
- what is still open (§9);
- the **implementation path for GitHub Copilot**: phases, decision table,
  steps, verification and the definition of "implemented" (§10).

**Status.** Claude Code and OpenCode are implemented (`auto-wp.py` 0.6.0);
GitHub Copilot is not. **Specified, not yet implemented**: the `--harness` option (§1.5,
`auto-wp.md` §1.1, for 0.7.0); everything in
§1.1, §1.2, §1.3 (the Rust test's entry point) and §3.2; the skill paragraph
"Primitives on each harness" (§1); the template limits of §1.4; the README
and `tests.md` wording of §8.1; and the whole Copilot column. Until then
`tests/lib/*.sh` behave as §1.2 and §3.2 describe. The path from here to a
working Copilot harness is §10.

Facts the repository cannot show are marked **unverified**, or cite the page
or command they come from. The Copilot CLI facts come from its documentation
and from GitHub Copilot CLI 1.0.107 (`copilot --help`, `copilot help
<topic>`, `copilot skill list`), read on 2026-11-07. "OpenCode V2" is the
OpenCode release observed when the OpenCode path was written
(`opencode --version`), whose TUI talks to a background service.

Reviews applied: [`choose-harness-feedback.md`](choose-harness-feedback.md)
(findings B1, M1 … m13),
[`choose-harness-copilot-feedback.md`](choose-harness-copilot-feedback.md)
(C1–C14) and [`choose-harness-feedback-2.md`](choose-harness-feedback-2.md)
(the second review), all 2026-11-07.

## 1. The harness abstraction

A harness is a terminal agent that can (a) discover the project's skills and
commands, (b) run a multi-hour campaign unattended in a container, and (c) be
driven by the test harness (`tests/lib/harness.sh`: launched in `tmux`, the
campaign request given to it — typed into its input box, or passed at launch
where the harness allows it (Copilot's `-i`) — and its transcript checked).
Everything harness-specific in this repository is one row of this table. Cells
are short; the details are in the section each one cites.

| Capability | Claude Code | OpenCode | Copilot CLI (Route B, proposed) |
|---|---|---|---|
| install, README route | `curl -fsSL https://claude.ai/install.sh \| bash` | `curl -fsSL https://opencode.ai/install \| bash` | `curl -fsSL https://gh.io/copilot-install \| bash` (npm needs Node ≥ 22, which Ubuntu 24.04 lacks) |
| install, test route | the host binary pushed by `provision.sh`, version-checked, `DISABLE_AUTOUPDATER=1` (`tests.md` §3.3) | the host binary pushed (`C-prov.4-opencode`, `R-prov.3-opencode`) | the host's **standalone** binary pushed (an npm install cannot be pushed); `COPILOT_AUTO_UPDATE=false` |
| wiring the project | `.claude/{skills,commands}` → `config/` | `.opencode/{skills,commands}` → `config/`; also reads `.claude/skills`, `.agents/skills`. Commands only from `.opencode/commands/` | skills from `.agents/skills` or `.claude/skills`, **subject to the limits of §1.4**; `.claude/commands/*.md` load as skills named after the file (§1.4); agents from `.github/agents/` |
| campaign entry point | §1.3 | §1.3 | §1.3, §5.1 |
| credential mode (§1.1) | `file` | `file`; `persisted` under Route A | `file` |
| credential | OAuth token (`claude setup-token`) → `/run/autowp/token` → `CLAUDE_CODE_OAUTH_TOKEN`, deleted after read | a provider **API key** → `AUTOWP_OPENCODE_KEY_ENV` (default `ANTHROPIC_API_KEY`); Route A: device flow (§4) | a fine-grained PAT ("Copilot Requests") → `COPILOT_GITHUB_TOKEN` (§5.2); B′: an API key → `COPILOT_PROVIDER_API_KEY` (§5.4) |
| permission posture | `--dangerously-skip-permissions` + `skipDangerousModePermissionPrompt` | global `opencode.json` with the documented rule-array form (`"action": "*"` first); the default base policy also allows actions with no config — a bare `opencode run` wrote a file with no prompt and no `--auto` (verified 2026-11-09, 2.2.5) | `--allow-all-tools` (§5.2) |
| trust / onboarding | `~/.claude.json` onboarding + folder trust (`harness_trust`) | none; the global config | `COPILOT_ALLOW_ALL=true`, which also loads the project's hooks: a generated project ships no `.github/hooks` (§5.2) |
| input-box prompt (tmux regex) | `❯` + space or no-break space (`$'… '`) | `Ask anything…` / `shift+tab agents` (verified 2026-11-09: capture-pane in tmux, the regex matches) | **unverified** (spike); needed only for the idle check |
| transcript | `~/.claude/projects/*/*.jsonl` | the database `opencode debug paths` reports (default `~/.local/share/opencode/opencode.db*`), which also holds stored credentials (§3.2); session text greps out of it with `grep -a` (verified 2026-11-09) | `~/.copilot` (`COPILOT_HOME`); format **unverified**; in `-p` runs `--output-format json` |
| headless mode | `claude -p`, `--bare`: never for campaigns (`tests.md` §3.3, §3.5) | `opencode run` (verified 2026-11-09: `opencode run -m provider/model 'prompt'` ran and answered; `-c`, `--auto`, `--agent`, `--session`, `--format` in the help); `opencode mini` | `copilot -p … --allow-all-tools --no-ask-user` (§5.2) |
| time-loop heartbeat | `ScheduleWakeup` (armed last) + `CronCreate`/`CronList` watchdog | external watchdog re-invoking `opencode run` (`time-loop/SKILL.md`; §3.2) | external watchdog, one `copilot -p` session per wake (§5.3) |
| sub-agent spawn | `Agent`/`Task` (`time-loop/SKILL.md` §4 step 2) | the `subagent` tool; agents of mode `subagent`; commands with `subagent: true` run in a background child session (opencode.ai/docs/agents, /commands). The parent receiving the report: **unverified** | custom agents, `/fleet`, `/subagents`; report read-back **unverified** (spike) |
| background task + stop | background sub-agents re-invoke the session on completion; `TaskStop` | background child sessions; a stop primitive **unverified** | `/tasks` (**unverified** as stop) |
| spend limit | none | none known | `--max-ai-credits`, `--usage-output-file` (§5.3, §6) |
| test switch | `HARNESS=claude` (default) | `HARNESS=opencode` | `HARNESS=copilot`: **rejected** until Route B lands (§1.2) |

**The rule the table enforces.** The skills and commands live once in
`config/` and every harness reads the same files through links. They are
harness-neutral **except one paragraph per skill that maps the primitives**.
In `time-loop/SKILL.md` that paragraph is today "The heartbeat on each
harness"; it **must be extended** to "Primitives on each harness": heartbeat,
sub-agent spawn, background task and stop, and entry point, one bullet per
harness. The rest of the skill keeps Claude Code's names (`ScheduleWakeup`,
`CronCreate`, `TaskStop`, `/loop`) as the reference vocabulary that this
paragraph translates. Adding a harness means filling one row of this table,
that paragraph, and the files of §8.

**The delegation barrier (decision).** The skill requires the verifier of
each cycle to run in a spawned sub-agent. Where a harness has no verified
primitive that spawns a sub-agent and returns its delivered report, the
"Primitives" paragraph says so and the **verifier runs inline in the
coordinator's session**; the skill must permit that explicitly for that
harness, as a known weakening of the barrier. OpenCode runs in this inline
mode until test 1 of §8.2 shows its `subagent` tool returns the report.
Whether the barrier is a requirement of the method (so inline mode is only a
stopgap) stays open (§9, point 2).

### 1.1 Credential modes

`HARNESS_CREDENTIAL=file|persisted`, default `file`, read by `secret.sh` and
`harness.sh`:

- **`file`** (today's only mode): `secret_check_file`, `secret_check_expiry`
  and `secret_push` run as now. The launcher requires `/run/autowp/token`,
  exports it under the harness's variable, and deletes it. K2 greps `~`,
  `/tmp` and `$CAMPAIGN_DIR` for the file's content (`secret_k2`).
- **`persisted`** (Route A): the credential lives in the harness's own store
  in the container. `secret_check_file`, `secret_check_expiry` and
  `secret_push` print a note and do nothing. The launcher does not require
  `/run/autowp/token` and exports nothing. `harness_start` runs the connect
  pre-step of §4.2, then the campaign as §3. **K2 is skipped** with the note
  "the credential rests in the harness store by design (choose-harness §4.4)".

### 1.2 Unknown harness values

Every `case $HARNESS` in `harness.sh`, `secret.sh` and `workshop.sh` today
falls through to `*)`, which is Claude Code. `HARNESS=copilot` would
therefore run Claude Code with the Claude credential and report green. The
scripts must instead reject any value other than `claude` and `opencode`
(`die "HARNESS=<v>: unknown harness"`), including `none` (§1.5), and
`copilot` stays rejected until Route B lands. Test 4 of §8.2 pins this.

### 1.3 One campaign shape, two test entry points

Since `auto-wp.py` 0.6.0 (`46fd7e3`, 2026-11-08) both templates start a
campaign the same way: the slash command `/time-loop <dir> N`, which loads
the language's `time-loop` skill. The Rust skill
(`templates/rust/skills/time-loop/SKILL.md`, a Creusot port of the C one)
carries the same "heartbeat on each harness" section as the C skill: on
Claude Code `ScheduleWakeup` armed last plus a `CronCreate` watchdog; on
OpenCode the external `opencode run` watchdog, keyed on
`<dir>-creusot/time-loop.state` instead of `<dir>-analysis-acsl/`. A Rust
*project* therefore has a heartbeat under both harnesses.

The container *tests* still differ, because `tests/rust/sudo-rs-test.sh` was
written before the Rust command existed:

| | C (`tests/c/gzip-test.sh`) | Rust (`tests/rust/sudo-rs-test.sh`) |
|---|---|---|
| what the test types | `/time-loop gzip-1.9 <hours>` | a long prompt naming `creusot-monitoring` and `rmf-sl` |
| heartbeat | in the skill ("The heartbeat on each harness") | in the prompt: a deadline and "call `ScheduleWakeup` … before ending every turn" |
| what `harness_confirm` greps | `/time-loop`, the skill load | `creusot-monitoring`, `creusot-launch` |

Consequences:

- Under **OpenCode**, the Rust *test* has **no heartbeat**: its prompt's
  `ScheduleWakeup` sentence names a tool OpenCode does not have, and no
  watchdog is armed. This is a **required fix**: the Rust test types
  `/time-loop sudo-rs <hours>` like the C test, so the skill arms the
  heartbeat under either harness, and `harness_confirm` greps `/time-loop`.
  The prompt's extra guidance (the code-blind study first, build in a copy,
  the ordered list for a quiet cycle, the 45-minute box) is already in the
  Rust skill. The change waits for the running 96-hour sudo-rs campaign to
  end (the script is edited only by atomic rename while it runs). Who arms
  the watchdog in the tests, the skill or `harness_start`, still follows
  §3.3.
- A **prompt entry point** (text typed or passed at launch that loads the
  `time-loop` skill) remains what §5.1 chooses for Copilot, for both
  languages.

### 1.4 Template limits (the Agent Skills specification)

The Copilot CLI enforces the Agent Skills specification
(https://agentskills.io/specification): a `SKILL.md` frontmatter must be
valid YAML and its `description` at most 1,024 characters. Claude Code does
not enforce it; **neither does OpenCode** (verified 2026-11-09, 2.2.5: a
SKILL.md with a 1,435-character `description` loads through the
`.opencode/skills` link). In a freshly
generated C project, `copilot skill list` (no login needed) **rejects 15
skills**, `time-loop`, `rmf-sl`, `fips-sl`, `frama-c-launch`,
`frama-c-monitoring`, `sl-builder` and `sl-auditor` among them, for their
description length, and two (`polish-skill`, `sl-internal`) for YAML errors
(unquoted colons in a one-line description). The Rust `creusot-monitoring`
fails too. Measured lengths go up to 2,983 characters (the C `time-loop`);
the Rust `time-loop`, written to the limit, has 882.

The CLI also loads `.claude/commands/*.md` as skills named after the file.
With the real `time-loop` skill rejected, "load the `time-loop` skill"
resolves to the 109-line command text, and the agent would run the campaign
without the method.

**Decision:** the templates are brought under the limits for every skill:
descriptions shortened to ≤ 1,024 characters (the rest moves into the
skill body), and the frontmatter made strict YAML. A Copilot-only shortened
copy is rejected, because it would break "the skills live once in
`config/`". Test 0 of §8.2 pins the limits. Every Copilot item depends on it.

### 1.5 Selecting a harness: `--harness` and `HARNESS`

Two selectors, one vocabulary (`claude`, `opencode`, `copilot`, plus `none`
for the first):

| | Where | Values | Role |
|---|---|---|---|
| `auto-wp.py --harness <v>` | project generation (`auto-wp.md` §1.1, specified for 0.7.0) | `claude` (default), `opencode`, `copilot`, `none` | which harness the README documents and the Workshop definition installs; recorded as `harness` in `config/auto-wp.json` |
| `HARNESS=<v>` | the test scripts (`tests/lib/*.sh`) | `claude` (default), `opencode`, `copilot` | which harness the test drives |

Rules:

- **`none` is generation-only.** A generated project with `--harness none`
  has no harness; the user installs one by hand in the workshop
  (`auto-wp.md` §1.1.1). `HARNESS=none` is rejected by the test scripts
  (§1.2): a test needs a harness to drive.
- **The tests pass the flag through.** Every test that generates a project
  runs `auto-wp.py --harness "$HARNESS"`, so the README and `setup-base`
  under test are the ones for the harness being driven, and C2.2 checks that
  README against the harness bullet (test 8). `ws_install_harness` is
  skipped when the generated `setup-base` already installed that harness
  (§1.1 of `auto-wp.md`, item 3).
- **A mismatch is an error.** A test that finds `harness` in the manifest
  different from `$HARNESS` fails with a message naming both, instead of
  driving the wrong harness.
- **`copilot` is refused by both selectors** until implemented (§1.2,
  `auto-wp.md` §1): a usage error (exit 2) for the flag, `die` for the
  variable. §10.4 lists the step that lifts it.
- **Wiring is independent of the choice** (the five links of `auto-wp.md`
  §3.3 are always written), so switching harness later, or running two, needs
  no regeneration; §7 still forbids switching a *running* campaign.
- **Credentials are not a generation matter.** `--harness` never reads or
  writes a credential; the credential modes of §1.1 belong to the tests.

## 2. Switching a generated project to OpenCode (implemented)

The project needs nothing: both wirings exist since 0.4.0. In the container
(workshop quick-start step 2, or the LXD fallback):

1. Install the harness — replace the Claude Code install line with
   `curl -fsSL https://opencode.ai/install | bash` (or install both; they do
   not conflict).
2. Start it in the `tmux` session: `opencode` instead of
   `claude --dangerously-skip-permissions`. OpenCode needs no permission
   flag: by default its agents act without asking (to be asked, add
   `permissions` rules to `opencode.json`).
3. On the first start, run `/connect` to add the provider and `/models` to
   pick the model. For Anthropic this is an **API key, not a Claude
   subscription login**: Anthropic's terms are reported to reserve the
   subscription for its own clients (§6, **unverified**). Other choices:
   OpenRouter (an API key), or GitHub Copilot (§4).
4. The key or connection you enter is **stored in the container**, in
   OpenCode's database (`opencode debug paths`; `auth.json` before V2). The
   tests' stream-and-delete discipline does not apply to this route.
   Deleting the container (`workshop remove`, `lxc delete`) deletes the
   credential with it.
5. Never copy the host's OpenCode data directory into the container (the same
   rule as `~/.claude/.credentials.json`).
6. The campaign starts as in §1.3: in a C project with `/time-loop <dir> N`,
   `/rmf`, `/fips` or `/ebios` (OpenCode lists them from
   `.opencode/commands/`; type `/`); in a Rust project with
   `/time-loop <crate> N`. In both, the skill arms the OpenCode watchdog.

## 3. Running the container tests with OpenCode (implemented)

### 3.1 What `HARNESS=opencode` changes

On any level-2/3/4 script, `HARNESS=opencode` switches every
`case $HARNESS` in `harness.sh`, `secret.sh` and `workshop.sh` and leaves the
checks unchanged:

- **Credential** (`file` mode). `secret.sh` defaults `AUTOWP_TOKEN_FILE` to
  `~/.config/auto-wp/opencode-provider-key`, the provider API key. The
  launcher (`harness_write_launcher`) reads it from `/run/autowp/token` and
  exports it under `AUTOWP_OPENCODE_KEY_ENV` (default `ANTHROPIC_API_KEY`;
  set the variable to match another provider's catalog entry, e.g.
  `OPENROUTER_API_KEY`).
- **Launch.** The launcher runs `opencode --standalone`, so that a private
  server inherits the exported environment. `harness_trust` writes the
  global config instead of the Claude dialogs.
- **Prompt, transcript, idle.** The OpenCode prompt regex, the `opencode.db`
  transcript for `harness_confirm` (K4), the same file for
  `wait_loop_stopped`'s idle measure, and the K3 allowlist entries for
  OpenCode's data directories.
- **Provisioning.** `provision.sh` pushes both binaries into the base
  container and writes the OpenCode global config (`C-prov.4-opencode` in C,
  `R-prov.3-opencode` in Rust; skipped with a note when the OpenCode binary
  is not on the host PATH).

### 3.2 Required fixes before a real OpenCode campaign

The OpenCode path has never driven a real campaign. The OpenCode mechanics
the harness relies on are verified, though (2026-11-09, OpenCode 2.2.5,
host install): skills and commands are discovered through the `.opencode`
links, the default base policy let a bare `opencode run` write a file with
no prompt and no `--auto`, the TUI prompt markers match `HARNESS_PROMPT_RE`,
session text greps out of `opencode.db` with `grep -a`, headless
`opencode run -m provider/model 'prompt'` runs and answers, and no
Agent-Skills description-length limit is enforced (§1.4). What remains
unverified is the harness plumbing around those mechanics. Besides the
first-contact adjustments that are overridable by environment without code
changes (`HARNESS_PROMPT_RE`, `HARNESS_START_TIMEOUT`, `HARNESS_SESSION`),
these defects are known from reading the code. They fix the harness that is
already implemented, so they come before either Copilot route.

1. **The watchdog's credential.** The watchdog in `time-loop/SKILL.md` runs
   plain `opencode run`, which goes through the shared background service,
   not the private server the launcher gave the key to. If that service
   lacks the key (likely: the providers page gives
   `ANTHROPIC_API_KEY=… opencode --standalone` as the way to use an
   environment key), every wake after the first fails to authenticate and
   the campaign stalls silently. **Fix:** `harness_trust` and `provision.sh`
   run `opencode service set disabled true`, which the CLI page documents as
   disabling the shared service so CLI commands use private servers; the
   watchdog shell inherits the launcher's environment. `opencode run
   --standalone` would be shorter, but the docs show `--standalone` on bare
   `opencode` only (**unverified** for `run`).
2. **Nothing stops the watchdog.** It is `setsid nohup … &`, so
   `harness_stop` (which kills only the tmux session), the acceptance
   `restart` and resume scenarios, and a user `STOP` all leave it firing; the
   next `harness_start` then competes with it, and `wait_loop_stopped` never
   sees the run go idle. `pkill -f time-loop-watchdog` is not a fix: run
   through `autowp_exec_user` its own `sh -c` wrapper matches the pattern,
   and it leaves a running `opencode run` child alive. **Fix:**
   - the skill arms the watchdog under a fixed name with a pidfile
     (`exec -a time-loop-watchdog bash -c …`, `echo $! >
     .time-loop-watchdog.pid`);
   - under `HARNESS=opencode`, `harness_stop` creates
     `.time-loop-watchdog.stop`, kills the pid from the pidfile, then any
     `opencode run` child of it, and waits up to 60 s;
   - `wait_loop_stopped` reports whether a watchdog is alive;
   - the generated `.gitignore` (`templates/{c,rust}/tools/.gitignore`)
     gains `.time-loop-watchdog.stop` and `.time-loop-watchdog.pid`, which the
     per-cycle checkpoint would otherwise commit.
3. **The transcript may be a WAL file, at a path that depends on the
   channel.** If OpenCode's SQLite database runs in WAL mode
   (**unverified**), recent writes land in `opencode.db-wal`, so the main
   file's mtime and content lag, K4 can time out, and idle is measured
   wrong. The database path also "follows the release channel and
   `OPENCODE_DB`" (opencode.ai/docs/cli), so the hard-coded
   `~/.local/share/opencode/opencode.db` may be wrong. **Fix:** take the
   path from `opencode debug paths`, glob `<db>*` in `harness_confirm` and
   `wait_loop_stopped`, and make the K3 allowlist follow the same paths. The
   grep patterns `<command-name>` and `"skill":` are Claude Code's JSONL
   shapes; under OpenCode only `/time-loop ` can match, and only if the
   prompt is stored verbatim (**unverified**, §9 point 3).
4. **The start timeout's message.** `HARNESS_START_TIMEOUT` defaults to
   300 s, but the failure message says "after 120 s" (`harness.sh:152`), and
   `tests.md` §3.5 says 120 s. The three must agree (300 s).
5. **The Rust test's entry point** (§1.3): type `/time-loop`, not a prompt.

Tests 1–3 of §8.2 turn points 1–4 into checks.

### 3.3 Ownership of the watchdog

Two placements meet §3.2 points 1–2: the skill arms the watchdog (today), or
the test harness owns it under `HARNESS=opencode` (`harness_start` arms it,
`harness_stop` kills it), which makes the fixes test-side, keeps the skill
shorter and would also serve a prompt entry point that loads no skill. A user running
OpenCode without the tests still needs the skill's version, so the skill keeps
it either way. Which one the tests use is open (§9, point 4).

## 4. GitHub Copilot, Route A — as an OpenCode provider (proposed)

OpenCode ships a GitHub Copilot provider: connect with the device OAuth flow
(choose **GitHub Copilot** in `/connect`, complete the flow in a browser on
the host, pick the model in `/models`). No API key is involved, so Route A
runs in credential mode `persisted` (§1.1). The account needs Copilot Chat
access; which plans qualify is in §6. Route A needs the §3.2 fixes first.

### 4.1 In a generated project

Follow §2, and in `/connect` choose GitHub Copilot instead of an API-key
provider. The connection is stored in the container's OpenCode database
(§2, step 4); nothing is copied from the host.

### 4.2 In the container tests: authorize each test container

**Decision: the authorization is done per test container, never in the
base.** Storing it in the base snapshot would copy a live credential into
every container ever made from it, kept ones (`KEEP=1`) included. That is
exactly the option `tests.md` §7.2 rejects for `lxc config set …
environment.*`.

Under `HARNESS=opencode HARNESS_CREDENTIAL=persisted`, `harness_start` runs
a pre-step, check `C-copilot.connect`, in the test container before the
campaign starts:

1. if the connection already exists (post-condition 5 holds), pass and skip
   to step 6: acceptance `restart` and the resume scenarios call
   `harness_start` again on the same container, so the pre-step is
   idempotent;
2. start `opencode` in a dedicated tmux session in the container
   (`lxc exec` without a TTY cannot drive the TUI), in the same server mode
   as the campaign (§3.2 point 1), so both read the same store;
3. send the `/connect` keystrokes and select GitHub Copilot; capture the pane
   and parse the device code and the verification URL; print both on the
   test's stdout for the human on the host;
4. wait for completion, up to `COPILOT_CONNECT_TIMEOUT` (default 600 s),
   polling the pane;
5. post-condition: the connection exists. `opencode auth list` is the
   candidate oracle; that it lists OAuth accounts is **unverified**, and the
   spike of §4.5 settles it. On failure: `fail C-copilot.connect` and stop;
6. kill that tmux session, then start the campaign session as §3.

The container is deleted at the end as today, which deletes the credential.
With `KEEP=1` the credential stays on disk in the kept container. The test
prints a warning saying so, and the user revokes the authorization at GitHub
(Settings → Applications → Authorized OAuth Apps) when they remove the
container.

### 4.3 The campaign command

`HARNESS=opencode` as in §3, with the model pinned to a Copilot model:
`/models` in the TUI, or `model:` in the global config. Headless
re-invocations by the watchdog use the global config's model; the
`opencode run -m <provider/model>` form and the provider id
`github-copilot/<model>` are **unverified** (user reports only).

### 4.4 The K2 delta

Under `file` mode, the credential is streamed into `/run/autowp/token` and
deleted after reading; it never rests in the container. Under Route A the
connection **must** rest in the container, in OpenCode's database, which is
**also the transcript** the tests grep. **Decision: K2 is skipped under
`persisted`** (§1.1). Checking that the token is absent from the project
tree, `~/remote.git` and `/tmp` would need the token read out of the
database: `sqlite3` in the base (in neither `provision.sh` today), a schema
nobody has checked, and a `--exclude-dir` list covering the database, its WAL
file and the `state`/`cache` paths of `opencode debug paths`. That oracle may
be added after the spike (§4.5).

`tests.md` §7.3 gains a row: the agent can read its own connection, as it
could always read its own OAuth token, and the connection must be revoked
after a kept run.

### 4.5 Status

Route A stays **proposed** until one spike has run §4.2 end to end, settled
the `auth list` oracle and the `-m` flag, and run test 1 of §8.2 with a
Copilot model. The order between Route A and Route B is decided in §5.5.

## 5. GitHub Copilot, Route B — the Copilot CLI as a third harness (sketch)

Route B makes `HARNESS=copilot` a first-class column of §1. It depends on the
template limits of §1.4. The work starts with a **spike** — a
level-2-shaped exercise in a throwaway container, in this order:

1. `copilot skill list` in a freshly generated project (no login needed):
   every skill loads (test 0);
2. authorize with `COPILOT_GITHUB_TOKEN`; start a session with
   `-i "<prompt that loads the time-loop skill>"`; also type
   `/time-loop <dir> N` into the TUI, since the CLI loads `.claude/commands`
   as skills by name (§1.4), and record which form invokes the method;
3. the delegation barrier: can a coordinator spawn a verifier (`.github/agents`,
   `/fleet`, `/subagents`) and read back its delivered report, and does
   `/tasks` stop one;
4. a 30-minute watchdog loop as in §5.3, with `--max-ai-credits` and
   `--usage-output-file`; deliverable: the exit-cause oracle (the final event
   of `--output-format json`, or the usage file) and its observed values for a
   reached limit;
5. only then the interactive items: the input-box marker, the session file,
   where folder trust is persisted.

Then come the file changes of §8.1.

### 5.1 Entry point

The CLI has no project-defined slash commands in `copilot help commands`,
but loads `.claude/commands/*.md` as skills named after the file (§1.4).
**First choice:** a prompt entry point (§1.3), passed at launch with
`-i "<prompt>"` (an interactive session that executes it at start). Under
`copilot` the launcher receives `harness_start`'s `$cmd` as the `-i`
argument and the typing step is skipped; `harness_confirm` greps the skill
name in that session's transcript (location **unverified**, §9 point 6).
**Fallback:** a generated `.github/agents/time-loop.agent.md`, which adds a
`.github/` layer to every generated project. Spike step 2 decides.

### 5.2 Launcher flags

Every Copilot run (interactive or `-p`) passes:

| Flag / variable | Why |
|---|---|
| `COPILOT_GITHUB_TOKEN` (from `/run/autowp/token`, then deleted) | the credential; precedence over stored credentials, `GH_TOKEN`, `GITHUB_TOKEN`. Fine-grained PATs (v2) with "Copilot Requests" only; classic `ghp_` tokens are not supported (`copilot login --help`) |
| `--secret-env-vars COPILOT_GITHUB_TOKEN` | the agent's shell and MCP servers do not inherit the variable. Per its help text, a value that reaches a tool result another way still goes to the model and into the session history under `~/.copilot`, which K2 greps |
| `--allow-all-tools` | required for non-interactive mode |
| `COPILOT_ALLOW_ALL=true` (exactly `true`) | trusts the directory in a tmux session (`--trust-folder` covers one prompt-mode session only); it also loads the project's hooks, so a generated project ships no `.github/hooks` (test 0) |
| `--no-ask-user` | a headless turn cannot block on a question form |
| `--disable-builtin-mcps` | turns off the built-in `github-mcp-server`, a write path to GitHub with the signed-in credential |
| `--sync-session=off` | no account session sync; the default behaviour is **unverified** |
| `--max-ai-credits <n>`, `--usage-output-file <f>` | the spend cap and its record (§5.3) |
| `COPILOT_AUTO_UPDATE=false`, `COPILOT_MULTIPLEXER=tmux` | pinned binary; no misdetection of the nested tmux |

`--autopilot` is not used: `--max-autopilot-continues` defaults to 5, so it
stops after five continuations, not at the deadline.

### 5.3 The watchdog

**Decision: one session per wake.** The interactive `-i` session drives the
first cycle; each later wake is a new `copilot -p "<resume prompt>"
-n time-loop-wake-<epoch>` with the flags of §5.2. A stable `--session-id`
is not used: if the interactive session is still open in tmux (hung, the
case the watchdog exists for), attaching a second run to it has unverified
behaviour, and `--continue` can pick another project's session when
`COPILOT_HOME` is shared. This is the same design as OpenCode's watchdog.

`--max-ai-credits` is therefore a **per-wake** cap (`copilot help limits`:
usage accumulates across the whole run). The **per-campaign** budget is
enforced by the watchdog, which sums the `--usage-output-file` of each wake
and stops when the total reaches `COPILOT_CAMPAIGN_CREDITS`. The watchdog
stops on a reached limit or an expired PAT and retries on a network error;
the oracle that tells these apart is spike step 4's deliverable, and test 11
uses it.

### 5.4 Route B′ — BYOK

The CLI can use a custom provider instead of Copilot's routing:
`COPILOT_PROVIDER_BASE_URL`, `COPILOT_PROVIDER_TYPE` (`openai`, `azure`,
`anthropic`), `COPILOT_PROVIDER_API_KEY`, and a model, which BYOK requires
(`COPILOT_MODEL`, `COPILOT_PROVIDER_MODEL_ID` or `--model`; `copilot help
providers`). GitHub authentication is then not required. It is Route B with
an API key in `AUTOWP_TOKEN_FILE`, exported as `COPILOT_PROVIDER_API_KEY`
and listed in `--secret-env-vars`. `COPILOT_PROVIDER_API_KEY_COMMAND` (a
command printing a fresh key per request) can keep the key out of the
environment altogether. B′ needs no Copilot plan, is outside the plan limits
of §6, and avoids subscription OAuth in a third-party client: it is the path
when no paid Copilot seat is available.

### 5.5 Which route first

Route A reuses the OpenCode path (heartbeat, transcript, permissions) but
needs the `persisted` credential mode, the connect pre-step and the §3.2
fixes, and it leaves a live OAuth token in the container for the agent to
read, with an unknown 96-hour refresh behaviour (§9, point 5). Route B needs
no new credential machinery and keeps stream-and-delete and K2 intact, at
the price of the open questions of §9, points 1, 6 and 7.

**Decision: run Route B's spike first** (phase P1 of §10). If it answers the entry-point and
sub-agent questions, Route B (or B′) is the recommended route for GitHub
Copilot and Route A is dropped; if the CLI cannot carry a long headless
loop, Route A is the fallback. Until the spike has run, neither is
recommended. §4.5 and §9 refer here instead of restating it.

## 6. Accounts, plans and terms

- **Claude.** The Claude subscription token (`claude setup-token`) is for
  Claude Code only. Anthropic's terms are reported to forbid using
  subscription OAuth in third-party harnesses, and in 2026 the access was
  reported blocked server-side and OpenCode's Anthropic OAuth login removed;
  this comes from secondary sources only and is **unverified** against the
  primary terms. Under OpenCode, Anthropic means an API key billed to the
  API account (`tests.md` §7.2).
- **Copilot plans.** The GitHub changelog of 2026-01-16 names the paid plans
  (Pro, Pro+, Business, Enterprise) for Copilot in OpenCode and does not
  mention Free; OpenCode's providers page says an account without
  entitlement can "sign up for Copilot Free" and connect again. The two
  sources disagree; which is current is **unverified**. Business and
  Enterprise administrators can disable the Copilot CLI by policy. The tests
  assume a paid plan whose policy allows the client used.
- **Cost.** The Copilot CLI is billed in **AI credits** since version 1.0.48:
  token-based, at per-model prices for input, output and cached tokens,
  shown in `/model`, in the footer (`Session: N AIC used`) and in `/usage`
  (`copilot help billing`). For individuals: Pro ($10) 1,500 credits a
  month, Pro+ ($39) 7,000, Max ($100) 20,000; 1 credit = $0.01; when they run
  out, the user upgrades, sets a budget for additional usage, or waits for
  the reset (docs.github.com, "Usage-based billing for individuals"). The
  cost of a campaign therefore depends on tokens, the model and sub-agent
  work, not on the number of wakes. Route B runs record it with
  `--usage-output-file` (§5.3); for Route A it comes from the account's
  billing page. The tests' budget per 96-hour run is open (§9, point 8).
  Legacy scheme, for annual Pro/Pro+ plans still on it: one premium request
  per prompt times the model's rate, 300 a month on Pro and 1,500 on Pro+;
  a 96-hour campaign with a wake at least every 20 minutes sends at least
  288 prompts, which exhausts a Pro allowance in one run.
- **Data handling.** A campaign sends third-party source code (GRUB, gzip,
  sudo-rs, Mbed TLS) to the provider. Retention rules differ between
  individual and Business/Enterprise plans, and between providers; the
  user's provider policy applies. The Copilot CLI has further paths to
  GitHub, none of which a campaign uses: `/delegate` (the cloud agent opens
  a PR), `/share`, `--share-gist`, `/remote`, the built-in GitHub MCP server
  and account session sync. The launcher closes the last two
  (`--disable-builtin-mcps`, `--sync-session=off`, §5.2), and the PAT's
  single "Copilot Requests" permission is meant to block the others
  (**unverified** that they fail cleanly without it). Test 10 checks this.

## 7. A running campaign is never switched

The campaign state (`time-loop.state`: start, deadline, cycles, wakes) and
the checkpoint commits are harness-neutral, but everything else about a live
run is not: the heartbeat primitives (Claude Code's `ScheduleWakeup` and
cron; the external watchdogs), the transcript the checks grep, and the
session's context. Switching harness mid-campaign is therefore not
supported.

To change harness:

1. **Stop the campaign.**
   - Under Claude Code: a `STOP` in the session, or let the deadline pass,
     after which the loop pauses with an interim report.
   - Under OpenCode (and Copilot): create `.time-loop-watchdog.stop` in the
     project root, kill the pid in `.time-loop-watchdog.pid` (§3.2 point 2),
     then stop the session. A `STOP` in the TUI stops the current turn only.
2. **Start the new harness** in the same project and restart the campaign
   with its entry point (§1.3): `/time-loop <dir> N`, in C and in Rust,
   which reuses the stored start and deadline, ignores `N` and resumes from
   the last checkpoint. (A campaign started from a prompt, like the running
   sudo-rs test, is resumed with the same prompt and the same deadline.)
3. **A fresh budget** needs `--fresh` (both languages). Under an external watchdog it
   also needs a re-armed watchdog, because the watchdog's loop embeds the
   deadline and `N` literally.

## 8. Files and acceptance tests

### 8.1 Files each piece of work touches

"OpenCode now" fixes the implemented harness (§1.2, §1.4, §3.2) and is
needed whichever Copilot route follows.

| File | OpenCode now | Route A | Route B / B′ |
|---|---|---|---|
| `templates/*/skills/*/SKILL.md` | descriptions ≤ 1,024 characters, strict YAML (§1.4) | — | — |
| `templates/c/skills/time-loop/SKILL.md` | "Primitives on each harness", the inline-verifier mode (§1); watchdog name and pidfile (§3.2) | — | a Copilot bullet |
| `templates/{c,rust}/tools/.gitignore` | `.time-loop-watchdog.stop`, `.time-loop-watchdog.pid` | — | — |
| `auto-wp.py`, `templates/common/harness/{claude,opencode,copilot}.sh`, `templates/{c,rust}/README.md` (harness blocks), `tests/test_auto_wp.py` | `--harness` for `claude`, `opencode`, `none` (§1.5, `auto-wp.md` §1.1) | — | `copilot` accepted (lifting the refusal) |
| `templates/{c,rust}/README.md` | §2 steps 3, 4, 6 (API key; credential in the container) | — | the third choice in "The agent harness" |
| `tests/*/*.sh` (every script that generates a project) | `auto-wp.py --harness "$HARNESS"`; the manifest-mismatch check (§1.5) | — | — |
| `tests/lib/harness.sh` | unknown values (§1.2); `harness_stop`, `wait_loop_stopped`, DB path and glob, timeout message (§3.2) | credential mode; connect pre-step (§4.2) | the `copilot` case: launcher with `-i` and §5.2 flags, trust, prompt regex, transcript, K3 entries |
| `tests/lib/secret.sh` | unknown values (§1.2) | `persisted` mode; K2 skipped (§4.4) | default `AUTOWP_TOKEN_FILE` `~/.config/auto-wp/copilot-pat` and its hint |
| `tests/lib/workshop.sh` | unknown values (§1.2) | — | `ws_install_copilot`, the `ws_install_harness` switch |
| `tests/c/provision.sh`, `tests/rust/provision.sh` | `opencode service set disabled true` (§3.2) | — | push of the standalone binary, version check |
| `tests/rust/*-test.sh` | type `/time-loop sudo-rs <hours>` instead of the prompt, so the skill arms the heartbeat under either harness (§1.3) | — | — |
| `tests/test_templates.py` | test 0 | — | — |
| `tests/test_harness.py` | tests 4, 6 | — | test 9; the Copilot prompt regex |
| `tests/test_auto_wp.py` | the `.gitignore` entries, where pinned | — | where the harness name is pinned |
| `tests/README.md`, `README.md` | — | — | the harness list |
| `spec/tests.md` | §3.5 timeout (120 → 300 s) and the watchdog cross-reference; §7.1 OpenCode database (not `auth.json`) | §7.3 the Route A row | §3.3, §3.5, §7.1 (the PAT) |
| `spec/auto-wp.md` | the `.gitignore` entries | — | §3.3, §3.4 (wiring) |
| `spec/choose-harness.md` | the status line | §4.5 | the §1 column from proposed to verified |

### 8.2 Acceptance tests

| # | Test | Closes |
|---|---|---|
| 0 | `test_templates.py` (level 1, no container): every `SKILL.md` frontmatter parses with a strict YAML parser, `name` matches the directory, `description` is 1–1,024 characters; no template ships `.github/hooks` | §1.4, §5.2 |
| 1 | `HARNESS=opencode` smoke test passes K4 (C3.1) within 5 min, the transcript shows the `time-loop` skill loaded (not only the command), and C3.5 strict holds: at least two `wake=` lines in the state file | §3.2 points 1, 3; the delegation-barrier decision of §1 |
| 2 | Under `HARNESS=opencode`, 60 s after `harness_stop` there is no process named `time-loop-watchdog` and no `opencode run` | §3.2 point 2 |
| 3 | `HARNESS_START_TIMEOUT` default, its message and `tests.md` §3.5 agree | §3.2 point 4 |
| 4 | `test_harness.py`: an unknown `HARNESS` (including `copilot` before Route B) makes `harness.sh` and `secret.sh` exit non-zero | §1.2 |
| 5 | Route A: `C-copilot.connect` passes, twice in a row on the same container (idempotence), and K2 reports `skip` with the §1.1 note | §4.2, §4.4 |
| 6 | `test_harness.py`: `HARNESS_PROMPT_RE` matches the recorded input box of each implemented harness and rejects ordinary output | §1 prompt row |
| 7 | A Copilot run (Route A, B or B′) ends on the deadline or the terminus, not on a credit limit (the §5.3 oracle), and records the AI credits used (`--usage-output-file`, or the billing page for Route A) | §6 |
| 8 | C2.2 covers each harness bullet of the generated README | §8.1 READMEs |
| 9 | `test_harness.py`, once Route B has a spike result: `HARNESS=copilot` is accepted and the launcher passes the token and every flag of §5.2; the pair of test 4 | §1.2, §5.2 |
| 10 | After a Copilot run: the transcript contains none of `/delegate`, `/share`, `/remote`, `--share-gist`; the launcher's flags are those of §5.2 (via test 9); the PAT's permissions are documented in `tests.md` §7.1 (not testable) | §6 |
| 11 | The Copilot watchdog stops after the limit event recorded by the §5.3 oracle and after an expired PAT, and retries after a network error | §5.3 |

## 9. Open points

1. **Copilot entry point** (§5.1): `-i` prompt, `/time-loop` typed (the
   command loaded as a skill), or `.github/agents`? Spike step 2.
2. **The delegation barrier** (§1): a requirement of the method, so the
   inline mode is a stopgap, or a Claude Code convenience? And which OpenCode
   and Copilot primitive returns a sub-agent's delivered report?
3. **OpenCode transcript oracle** (§3.2 point 3): WAL mode, verbatim prompt,
   an export or server API.
4. **Watchdog ownership in the tests** (§3.3).
5. **Copilot session lifetime (Route A)**: whether OpenCode's refresh keeps
   the Copilot session working unattended for 96 hours ("saves tokens and
   refreshes them when supported"); whether the GitHub OAuth token expires is
   **unverified**.
6. **Copilot CLI open cells** (Route B): the tmux input-box marker, the
   session file format and location, where folder trust is persisted, arm64
   builds.
7. **The Copilot exit-cause oracle** (§5.3), spike step 4.
8. **Budget.** The AI-credit budget of one 96-hour run the tests assume
   (`COPILOT_CAMPAIGN_CREDITS`), the plan of the test account, and whether the
   Copilot-provided or BYOK models (§5.4) are good enough for a 96-hour WP/Coq
   campaign. The ranking and the cross-provider judge (`sl-auditor`) exist;
   cost and quality are unmeasured.
9. **The built-in GitHub MCP server** (§5.2): disabled for every campaign;
   is there a later use for it, such as filing the terminus's Frama-C bug
   reports?
10. **`opencode mini` vs the full TUI** as the tmux target.

## 10. GitHub Copilot implementation path

§1–§9 specify the pieces. This section orders them: what is done first, what
decides the route, what each phase delivers, and when Copilot counts as
implemented. Each phase has an exit that can be checked; a phase starts only
when the previous exit holds.

### 10.1 Phases

| Phase | Work | Delivers | Exit |
|---|---|---|---|
| **P0 — prerequisites** | Templates under the Agent Skills limits (§1.4); the unknown-harness rejection (§1.2) in `harness.sh`, `secret.sh`, `workshop.sh`. Neither needs Copilot access. | The templates the Copilot CLI can load; `HARNESS=copilot` failing loudly instead of running Claude Code. | Tests 0 and 4 pass. `copilot skill list` in a freshly generated C and Rust project reports no rejected skill. |
| **P1 — spike** | The five steps of §5, in a throwaway container, by hand, with a PAT (or a BYOK key for B′). | A dated report, `spec/choose-harness-copilot-spike.md`, with one answer per open cell (below), the commands that produced it and the raw values (exit causes, usage file, transcript location). Observed facts only. | Every cell of §10.2 has an answer or an explicit "could not be determined, because …". |
| **P2 — decision gate** | Apply the table of §10.3 to the spike report. | A recorded decision: route (B, B′ or A), entry point, barrier mode. The unchosen routes are marked dropped in §4/§5 and §9. | The decision is in the spec and §5.5 and §9 are updated to say so. |
| **P3 — implementation** | The steps of §10.4 for the chosen route, in that order. | The `copilot` case in the test scripts, the template wording, the watchdog. | Tests 6, 9, 10, 11 pass at level 1 (no container, no token). |
| **P4 — verification** | Level 2 (a generated project in a container: `copilot skill list`, README quick start), then the level 3 smoke test, then one short campaign, then the real campaign (§10.5). | Evidence per level; the Copilot column of §1 with its **unverified** marks replaced by observed values. | §10.6 holds. |
| **P5 — status** | Flip the status line, the §1 column header, §4.5 / §5 titles, and §8.1's "proposed to verified" row; update `README.md`, `tests/README.md`, `spec/tests.md`. | The documents say what the code does. | A reader can tell, from the status line alone, which harnesses work. |

P0 is also the work "OpenCode now" needs (§8.1), so it is not Copilot-only.
Route A additionally needs the §3.2 fixes before its own phase P3; Route B
and B′ do not.

### 10.2 What the spike must answer

The answers feed §10.3. None is assumed.

| # | Cell | Spike step | Used by |
|---|---|---|---|
| a | Does `/time-loop <dir> N` typed into the TUI invoke the skill, and does `-i "<prompt>"` load it? Which transcript line shows the load? | 2 | entry point (§5.1), `harness_confirm` |
| b | Can a coordinator spawn a verifier and read back its delivered report (`.github/agents`, `/fleet`, `/subagents`)? Does `/tasks` stop one? | 3 | barrier mode (§1) |
| c | Does a 30-minute loop of `copilot -p` wakes carry state through `time-loop.state`, and what distinguishes a reached `--max-ai-credits`, an expired PAT and a network error (exit status, final JSON event, usage file)? | 4 | watchdog (§5.3), test 11 |
| d | The input-box marker, usable as `HARNESS_PROMPT_RE`; the session file location and format. | 5 | tests 6, 9; K4; idle check |
| e | Where folder trust is persisted, and whether `COPILOT_ALLOW_ALL=true` alone suppresses every dialog in tmux. | 5 | `harness_trust` |
| f | Is a project-level `.github/hooks` loaded under `COPILOT_ALLOW_ALL=true`, and does `--disable-builtin-mcps` / `--sync-session=off` behave as §5.2 says? | 2 | §5.2 flags |
| g | Does the standalone binary run in the container under the pinned version, and on arm64? | 1 | provisioning |
| h | Which models are available to the test account, and the AI credits of the 30-minute loop. | 4 | `COPILOT_CAMPAIGN_CREDITS` (§9 point 8) |

### 10.3 Decision table

| Spike outcome | Decision |
|---|---|
| (a) `-i` loads the skill **and** (c) a stop cause is distinguishable **and** (d) a transcript can be found | **Route B**, entry point `-i`, as §5. |
| (a) `-i` fails but typed `/time-loop` works | Route B, entry point typed (the launcher starts the TUI, `harness_start` types as for the other harnesses). |
| (a) neither works | Route B with the `.github/agents/time-loop.agent.md` fallback (§5.1), which adds a `.github/` layer to generated projects; record the cost in `auto-wp.md` §3.3. |
| (b) a verifier's report comes back | Barrier mode "spawned", as for Claude Code. |
| (b) no read-back | Barrier mode "inline" for Copilot (§1), written into the "Primitives on each harness" paragraph. Not a blocker for B. |
| (c) no usable stop-cause oracle | The watchdog stops on **any** non-zero exit after the first retry and reports "unknown cause"; test 11 is weakened to match, and the weakening is written in §5.3. Not a blocker. |
| the account has no paid Copilot plan or its policy forbids the CLI | **Route B′** (BYOK, §5.4) for the tests; Copilot proper stays unverified. |
| the CLI cannot carry a long headless loop: wakes lose state, or `-p` sessions cannot resume the campaign | **Route A**: the §3.2 fixes first, then the credential mode and connect pre-step of §4. Route B is marked dropped. |

Anything not covered is a new open point in §9, not a guess.

### 10.4 Route B implementation steps (P3)

In this order; each step is a commit with its tests.

1. **`tests/lib/harness.sh`: the `copilot` case.**
   - `HARNESS_PROMPT_RE` from spike (d).
   - `harness_write_launcher`: reads `/run/autowp/token`, exports it as
     `COPILOT_GITHUB_TOKEN`, deletes the file, then execs `copilot` with the
     flags of §5.2 and, when the entry point is `-i`, the request as its
     argument (`autowp-launch "$@"`; `harness_start` passes `$cmd`). The
     launcher exits 1 without the token, as the other launchers do.
   - `harness_trust`: the persistence found in spike (e), or nothing when
     `COPILOT_ALLOW_ALL=true` is enough.
   - `harness_confirm` and `wait_loop_stopped`: the transcript location and
     patterns from spike (a) and (d); K3 allowlist entries for `~/.copilot`.
   - `harness_stop`: kills the tmux session and the §5.3 watchdog (as the
     OpenCode path does, §3.2 point 2).
2. **`tests/lib/secret.sh`**: the default `AUTOWP_TOKEN_FILE`
   `~/.config/auto-wp/copilot-pat`, its hint (fine-grained PAT with "Copilot
   Requests"; classic tokens are refused by the CLI), and the expiry check
   (the `.created` metadata, as for Claude).
3. **`tests/lib/workshop.sh`**: `ws_install_copilot`, and the
   `ws_install_harness` case.
4. **Provisioning** (`tests/{c,rust}/provision.sh`): push the host's
   standalone `copilot` binary, check host and container versions are equal
   (`R-prov.3-copilot`, `C-prov.4-copilot`), set `COPILOT_AUTO_UPDATE=false`
   in the profile; skipped with a note when `copilot` is not on the host
   PATH, as for OpenCode.
5. **The watchdog** (§5.3): written once, in the skill's "Primitives on each
   harness" paragraph, as a Copilot bullet (one `copilot -p` per wake, the
   flags of §5.2, the credit sum, the stop causes found in (c)), and its
   barrier mode from (b). The paragraph's other bullets are not changed.
6. **Templates**: the third choice in "The agent harness" of the C and Rust
   READMEs (install line, PAT, `COPILOT_ALLOW_ALL`, the `copilot` start
   command), and nothing else: no `.github/` layer unless §10.3 chose the
   agent-file fallback.
7. **Tests**: `test_harness.py` (tests 6, 9), the Copilot cases of tests 10
   and 11 as level-1 checks against the launcher text and the watchdog
   script; `tests/README.md` lists `HARNESS=copilot`.

**Route B′** is step 2 with `COPILOT_PROVIDER_API_KEY` in place of the PAT
and the `COPILOT_PROVIDER_*` variables in the launcher; every other step is
the same.

**Route A** (only if §10.3 selects it): the §3.2 fixes; `HARNESS_CREDENTIAL`
in `secret.sh` and `harness.sh` (§1.1); the connect pre-step
`C-copilot.connect` (§4.2); the K2 skip (§4.4); `spec/tests.md` §7.3.

### 10.5 Verification ladder (P4)

Cheapest first; a failure stops the ladder and is fixed at its level.

| Level | What | Needs |
|---|---|---|
| 1 | tests 0, 4, 6, 9, 10, 11 (§8.2), host only | nothing |
| 2 | `install-test.sh` for C and Rust with `copilot skill list` showing every skill; README step C2.2 for the Copilot choice | a container, no token |
| 3 | `HARNESS=copilot` smoke test (`tests/c/smoke-test.sh`, `tests/rust/smoke-test.sh`): K4, the skill loaded, at least two `wake=` lines (C3.5 strict) | the token or BYOK key; a small credit budget |
| 3 | one short `/time-loop` run (the gzip or sudo-rs test with a 2-hour budget): the run ends on the deadline, not on a credit limit (test 7), and no forbidden command appears (test 10) | the token; credits for 2 hours |
| 4 | the real run (96 hours) | the token valid beyond the budget plus 30 minutes; the budget of §9 point 8 |

### 10.6 Definition of "implemented"

GitHub Copilot is implemented when all of the following hold, and each is
observable:

1. `HARNESS=copilot` is accepted by the scripts, and any other unknown value
   is rejected (tests 4 and 9).
2. The §10.5 level 1 and 2 tests pass, and the level 3 smoke test passes once
   with `HARNESS=copilot`.
3. One `/time-loop` run under Copilot has ended on its deadline or terminus
   and its entry in `spec/tests.md` or the test's spec records the harness,
   the version, the credits used and the result, including failures.
4. The Copilot column of §1 has no **unverified** cell that a test depended
   on; the cells that remain unverified are listed in §9.
5. The spike report exists and the decision of §10.3 is in the spec.

Until then the status line stays "Specified, not yet implemented", and the
Copilot column keeps its "proposed" header.

### 10.7 What the user has to provide

- A GitHub account with a paid Copilot plan that allows the CLI (§6), or a
  provider API key for B′.
- A fine-grained PAT with the "Copilot Requests" permission, written to
  `AUTOWP_TOKEN_FILE` with its `.created` metadata, expiring after the
  longest run planned.
- A decision on `COPILOT_CAMPAIGN_CREDITS` for the real run (§9 point 8).
- Acceptance that campaign source code goes to the provider (§6).
