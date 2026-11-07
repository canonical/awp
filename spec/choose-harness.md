# choose-harness — selecting and switching the agent harness

This document specifies:

- the **harness abstraction**: the fixed set of capabilities a harness must
  provide for a generated project and for the container tests (§1) — the
  table a new harness fills;
- how to **switch a generated project or a test run to OpenCode** (§2, §3) —
  implemented since auto-wp 0.4.0, with the fixes §3.2 still requires;
- how to switch to **GitHub Copilot**, by two routes: **Route A** — Copilot as
  a model *provider* inside the OpenCode harness (§4, proposed) — and
  **Route B** — the Copilot CLI as a third harness *binary* (§5, a sketch);
- the account, plan and terms constraints of each route (§6);
- why a **running campaign is never switched**, and how to stop one (§7);
- the files each route touches and its acceptance tests (§8);
- what is still open (§9).

Status: Claude Code and OpenCode are implemented (`auto-wp.py` 0.5.0);
GitHub Copilot is not. Facts that the repository cannot show are marked
**unverified**, or cite the page or command they come from; the Copilot CLI
facts come from its documentation and from `copilot --help` of GitHub Copilot
CLI 1.0.105, read on 2026-11-07. "OpenCode V2" is the OpenCode release
observed when the OpenCode path was written (`opencode --version`), whose
TUI talks to a background service.

Review: [`choose-harness-feedback.md`](choose-harness-feedback.md)
(2026-11-07); this revision applies it. Finding numbers (B1, M2, m4 …) refer
to that review.

## 1. The harness abstraction

A harness is a terminal agent that can (a) discover the project's skills and
commands, (b) run a multi-hour campaign unattended in a container, and (c) be
driven by the test harness (`tests/lib/harness.sh`: launched in `tmux`, a
command typed into its input box, its transcript checked). Everything
harness-specific in this repository is one row of this table:

| Capability | Claude Code | OpenCode | Copilot CLI (Route B, proposed) |
|---|---|---|---|
| install, README route | `curl -fsSL https://claude.ai/install.sh \| bash` | `curl -fsSL https://opencode.ai/install \| bash` | `npm install -g @github/copilot` (Node ≥ 22), or `curl -fsSL https://gh.io/copilot-install \| bash` (GitHub's install page) |
| install, test route | the host's binary pushed by `provision.sh`, version-checked, `DISABLE_AUTOUPDATER=1` (`tests.md` §3.3) | the host's binary pushed by `provision.sh` (`C-prov.4-opencode`, `R-prov.3-opencode`) | the same push; `COPILOT_AUTO_UPDATE=false` |
| wiring the project | `.claude/{skills,commands}` → `config/` | `.opencode/{skills,commands}` → `config/`; V2 also reads `.claude/skills` and `.agents/skills`. Commands are read from `.opencode/commands/` only, so that link is load-bearing. The commands' `argument-hint` frontmatter is Claude Code's; OpenCode documents `description`, `agent`, `model`, `subagent` (unknown keys ignored: **unverified**) | skills from `.github/skills/`, `.agents/skills/` or `.claude/skills/` (the generated links already work); custom agents from `.github/agents/*.agent.md`; **no project slash commands** |
| campaign entry point | the slash command `/time-loop <dir> N` | the slash command `/time-loop <dir> N` | none yet: a prompt ("Load the `time-loop` skill and run it for `<dir>` with N hours") or a generated `.github/agents/time-loop.agent.md` (§9, point 1) |
| credential mode (`HARNESS_CREDENTIAL`, §1.1) | `file` | `file` (API key); `persisted` under Route A | `file` |
| credential | a long-lived OAuth token (`claude setup-token`) streamed to `/run/autowp/token`, exported as `CLAUDE_CODE_OAUTH_TOKEN`, deleted after read | `file`: a provider **API key** in `AUTOWP_TOKEN_FILE`, exported under `AUTOWP_OPENCODE_KEY_ENV` (default `ANTHROPIC_API_KEY`). `persisted`: Route A's device-flow connection, stored in the container (§4) | a fine-grained PAT with the "Copilot Requests" permission, exported as `COPILOT_GITHUB_TOKEN` (precedence over `GH_TOKEN`, `GITHUB_TOKEN`); the stream-and-delete route applies unchanged |
| permission posture | `--dangerously-skip-permissions` + `skipDangerousModePermissionPrompt` in `~/.claude/settings.json` | none needed: the V2 base policy allows every action; the harness writes a global `opencode.json` pinning it with `"action": "*"` (the wildcard and the `.env` reads claim are **unverified**: the config page documents named actions) and a `cli.json` without the release popup (**unverified**, undocumented) | `--allow-all-tools` (required for non-interactive mode), or `--allow-all`/`--yolo`, or `COPILOT_ALLOW_ALL=true` |
| trust / onboarding dialogs | `~/.claude.json` onboarding + folder trust, written by `harness_trust` for the exact project path | none; the global config is written instead | a folder-trust prompt: `--trust-folder` for one session, or `COPILOT_ALLOW_ALL=true`; where interactive trust is persisted is **unverified** |
| input-box prompt (the tmux regex) | `❯` followed by a space or, since 2.1.3xx, a no-break space — `$'... '` in `HARNESS_PROMPT_RE` | `Ask anything…` (the placeholder) / `shift+tab agents` (the status line; **unverified**) | **unverified** (spike) |
| transcript (what `harness_confirm` greps) | `~/.claude/projects/*/*.jsonl` | `~/.local/share/opencode/opencode.db*` (`grep -a`; the glob covers a WAL file, §3.2) — the same database holds any stored credential | state under `~/.copilot` (`COPILOT_HOME`), logs in `~/.copilot/logs/`; the session file format is **unverified** |
| headless mode | `claude -p` and `--bare`, never used for campaigns (`tests.md` §3.3, §3.5: one turn, no wake-ups) | `opencode run` (the `-c`, `--auto`, `-m` flags are **unverified**: the CLI page documents none); `opencode mini` is a minimal interactive mode | `copilot -p "<prompt>" --allow-all-tools [-s] [--output-format json]`; `--continue`, `-r/--resume [id]`, `--session-id`; `--autopilot` with `--max-autopilot-continues` |
| time-loop heartbeat | in-session: `ScheduleWakeup` (armed as the cycle's last action) + `CronCreate`/`CronList` idle watchdog | an external watchdog: a detached loop re-invoking `opencode run --standalone` when `time-loop.state` goes quiet (`time-loop/SKILL.md`, "The heartbeat on each harness"; §3.2) | none visible in `--help`: the external watchdog with `copilot -p … --allow-all-tools --continue` |
| sub-agent spawn (the delegation barrier) | `Agent`/`Task`: the verifier of each cycle runs in a spawned sub-agent (`time-loop/SKILL.md` §4 step 2) | subagents via `@agent` mentions and commands with `subagent: true` (opencode.ai/docs/commands); whether the coordinator gets the delivered report back as Claude Code's does is **unverified** | custom agents; `--fleet` parallel sub-agent orchestration; the in-session spawn API is **unverified** |
| background task + stop | background sub-agents whose completion notification re-invokes the session; `TaskStop` on a verifier past its time box | **unverified**; fallback: one verifier at a time, run in the foreground of the cycle | **unverified** |
| test switch | `HARNESS=claude` (the default) | `HARNESS=opencode` | `HARNESS=copilot`: **rejected** until Route B lands (§1.2) |

**The rule the table enforces.** The skills and commands live once in
`config/` and every harness reads the same files through links. They are
harness-neutral **except one paragraph per skill that maps the primitives**:
in `time-loop/SKILL.md` that is "The heartbeat on each harness", which this
revision extends to **"Primitives on each harness"**: heartbeat, sub-agent
spawn, background task and stop, and entry point, one bullet per harness.
The rest of the skill keeps Claude Code's names (`ScheduleWakeup`,
`CronCreate`, `TaskStop`, `/loop`) as the reference vocabulary that this
paragraph translates. Adding a harness means filling one row of this table,
that paragraph, and the files of §8.

Where a harness has no sub-agent primitive that returns a delivered report,
the paragraph says so and the skill must allow an explicit fallback. Whether
the delegation barrier is a requirement of the method or a Claude Code
convenience is open (§9, point 2). Until that is decided, a harness without
it is not supported for `/time-loop`.

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
  `/run/autowp/token` and exports nothing. `harness_start` runs plain
  `opencode --standalone`. K2 has no pattern to grep and is replaced by the
  check of §4.4.

### 1.2 Unknown harness values

Every `case $HARNESS` in `harness.sh`, `secret.sh` and `workshop.sh` today
falls through to `*)`, which is Claude Code. `HARNESS=copilot` would
therefore run Claude Code with the Claude credential and report green. The
scripts must instead reject any value other than `claude` and `opencode`
(`die "HARNESS=<v>: unknown harness"`), and `copilot` stays rejected until
Route B lands. A unit test in `tests/test_harness.py` pins this (§8.2, test 4).

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
   subscription login**: Anthropic's terms reserve the subscription for its
   own clients (§6). Other choices: OpenRouter (an API key), or GitHub
   Copilot (§4).
4. The key or connection you enter is **stored in the container**, in
   OpenCode's data directory (`~/.local/share/opencode/opencode.db`;
   `auth.json` before V2). The tests' stream-and-delete discipline does not
   apply to this route. Deleting the container (`workshop remove`,
   `lxc delete`) deletes the credential with it.
5. Never copy the host's OpenCode data directory into the container (the same
   rule as `~/.claude/.credentials.json`).
6. The commands are the same: `/time-loop <dir> N`, `/rmf` or `/fips`,
   `/ebios` — OpenCode lists them from `.opencode/commands/` (type `/`).

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

The OpenCode path has never driven a real campaign. Besides the first-contact
adjustments that are overridable by environment without code changes
(`HARNESS_PROMPT_RE`, `HARNESS_START_TIMEOUT`, `HARNESS_SESSION`), four
defects are known from reading the code:

1. **The watchdog's credential (M1).** The watchdog in `time-loop/SKILL.md`
   runs plain `opencode run`, which goes through the shared background
   service rather than the private server the launcher gave the key to. If
   that service lacks the key (likely, since the providers page gives
   `ANTHROPIC_API_KEY=… opencode --standalone` as the way to use an
   environment key), every wake after the first fails to authenticate and the
   campaign stalls silently. Fix: the skill's watchdog runs
   `opencode run --standalone`, and the watchdog shell inherits the launcher's
   environment. The alternative is for `harness_trust` and `provision.sh` to
   run `opencode service set disabled true` (private servers by default) and
   record it in the permission row of §1.
2. **Nothing stops the watchdog (M2).** It is `setsid nohup … &`, so
   `harness_stop` (which kills only the tmux session), the acceptance
   `restart` and resume scenarios, and a user `STOP` all leave it firing; the
   next `harness_start` then competes with it, and `wait_loop_stopped` never
   sees the run go idle. Fix: under `HARNESS=opencode`, `harness_stop`
   creates `.time-loop-watchdog.stop` in the project root and runs
   `pkill -f time-loop-watchdog`, and `wait_loop_stopped` reports whether a
   watchdog is alive. The generated `.gitignore` gains
   `.time-loop-watchdog.stop`, which the per-cycle checkpoint would otherwise
   commit.
3. **The transcript may be a WAL file (M3).** If OpenCode's SQLite database
   runs in WAL mode (**unverified**), recent writes land in
   `opencode.db-wal`, so the main file's mtime and content lag, K4 can time
   out, and idle is measured wrong. Fix: glob `opencode.db*` in
   `harness_confirm` and `wait_loop_stopped`, and prefer an official export
   or the server API if one exists (**unverified**). The grep patterns
   `<command-name>` and `"skill":` are Claude Code's JSONL shapes; under
   OpenCode only `/time-loop ` can match, and only if the prompt is stored
   verbatim (**unverified**).
4. **The start timeout's message.** `HARNESS_START_TIMEOUT` defaults to
   300 s, but the failure message says "after 120 s" (`harness.sh:152`), and
   `tests.md` §3.5 says 120 s. The three must agree (300 s).

Tests 1–3 of §8.2 turn these into checks.

### 3.3 Ownership of the watchdog

Two placements meet §3.2 points 1–2: the skill arms the watchdog (today), or
the test harness owns it under `HARNESS=opencode` (`harness_start` arms it,
`harness_stop` kills it), which makes the fixes test-side and keeps the skill
shorter. A user running OpenCode without the tests still needs the skill's
version, so the skill keeps it either way. Which one the tests use is open
(§9, point 5).

## 4. GitHub Copilot, Route A — as an OpenCode provider (proposed)

OpenCode ships a GitHub Copilot provider: connect with the device OAuth flow
(choose **GitHub Copilot** in `/connect`, complete the flow in a browser on
the host, pick the model in `/models`). No API key is involved, so Route A
runs in credential mode `persisted` (§1.1). The account must have Copilot
Chat access on a paid plan (§6).

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

Under `HARNESS=opencode HARNESS_CREDENTIAL=persisted
COPILOT_CONNECT=1`, `harness_start` gains a pre-step, check
`C-copilot.connect`, run in the test container before the campaign starts:

1. start `opencode` in a dedicated tmux session in the container
   (`lxc exec` without a TTY cannot drive the TUI);
2. send the `/connect` keystrokes and select GitHub Copilot;
3. capture the pane and parse the device code and the verification URL;
   print both on the test's stdout for the human on the host;
4. wait for completion, up to `COPILOT_CONNECT_TIMEOUT` (default 600 s),
   polling the pane;
5. post-condition: the connection exists. `opencode auth list` is the
   candidate oracle; that it lists OAuth accounts is **unverified**, and the
   spike of §4.5 settles it. On failure: `fail C-copilot.connect` and stop.
6. kill that tmux session, then start the campaign session as §3.

The container is deleted at the end as today, which deletes the
credential. With `KEEP=1` the credential stays on disk in the kept
container. The test prints a warning saying so, and the user revokes the
authorization at GitHub (Settings → Applications → Authorized OAuth Apps)
when they remove the container.

### 4.3 The campaign command

`HARNESS=opencode` as in §3, with the model pinned to a Copilot model:
`/models` in the TUI, or `model:` in the global config. Headless
re-invocations by the watchdog use the global config's model; the
`opencode run -m <provider/model>` form and the provider id
`github-copilot/<model>` are **unverified** (user reports only).

### 4.4 The K2 delta

Under `file` mode, Claude's or the API key's credential is streamed into
`/run/autowp/token` and deleted after reading; it never rests in the
container. Under Route A the connection **must** rest in the container, in
OpenCode's database, which is **also the transcript** the tests grep.

The invariant that survives: the credential is not in the project tree
(`<project>/`, the checkpoints, the crosswalk), in `~/remote.git`, or in
`/tmp`. Under `persisted` mode K2 has no pattern to grep, so it becomes:
the access token read from OpenCode's store at the end of the run (by the
test, never printed) does not occur in those three places. The scan
excludes OpenCode's data directory, which is where it is supposed to be.
`tests.md` §7.3 gains a row: the agent can read its own connection, as it
could always read its own OAuth token, and the connection must be revoked
after a kept run.

### 4.5 Status

Route A stays **proposed** until one spike has run §4.2 end to end, settled
the `auth list` oracle and the `-m` flag, and run test 1 of §8.2 with a
Copilot model.

## 5. GitHub Copilot, Route B — the Copilot CLI as a third harness (sketch)

Route B makes `HARNESS=copilot` a first-class row of §1. The verified cells
are in the table. The work starts with a **spike** — a level-2-shaped
exercise in a throwaway container: install, authorize with
`COPILOT_GITHUB_TOKEN`, drive one prompt through tmux, find the input-box
marker, locate the session file — then the file changes of §8.1.

Route B also needs two decisions that Route A does not:

- **The entry point** (§9, point 1). The Copilot CLI has no project slash
  commands, so typing `/time-loop …` is probably rejected as unknown
  (**unverified**) and `harness_confirm`'s patterns would not match. Either
  the test types a prompt that loads the skill, or `auto-wp.py` generates a
  `.github/agents/time-loop.agent.md`; the second adds a `.github/` layer to
  every generated project.
- **The sub-agent primitive** (§9, point 2). The `--fleet` mode and custom
  agents may meet the delegation barrier; the spike checks whether a
  coordinator can spawn a verifier and read back its delivered report.

The credential needs nothing new: a PAT in `AUTOWP_TOKEN_FILE`
(`file` mode), exported as `COPILOT_GITHUB_TOKEN`, with the `.created`
metadata and `secret_check_expiry` as for Claude. A PAT has a chosen
expiry, so the expiry check applies as is. The CLI redacts
`GITHUB_TOKEN`/`COPILOT_GITHUB_TOKEN` values in its output.

**Route A is the recommended route for GitHub Copilot**: it reuses the
OpenCode path (heartbeat, transcript, permissions) and needs only the
credential mode and the connect step. Route B stays a sketch until the spike
answers §9.

## 6. Accounts, plans and terms

- **Claude.** The Claude subscription token (`claude setup-token`) is for
  Claude Code only. Anthropic's terms forbid using subscription OAuth in
  third-party harnesses, and in 2026 the access was blocked server-side and
  OpenCode removed its Anthropic OAuth login; this comes from secondary
  sources only and is **unverified** against the primary terms. Under
  OpenCode, Anthropic means an API key billed to the API account
  (`tests.md` §7.2).
- **Copilot via OpenCode (Route A)** is officially supported for paid
  Copilot plans: Pro, Pro+, Business, Enterprise (GitHub changelog,
  2026-01-16). Copilot Free is not supported. Business and Enterprise
  administrators can disable the Copilot CLI by policy. The tests assume a
  paid plan whose policy allows the client used.
- **Premium requests.** Copilot counts one premium request per prompt,
  multiplied by the model's rate. On the legacy billing scheme a Pro plan
  has 300 a month and Pro+ 1,500; the current scheme for other plans is
  **unverified**. A 96-hour campaign with a wake at least every 20 minutes
  sends at least 288 prompts before counting sub-agent prompts, which
  exhausts a Pro allowance in one run. A Copilot campaign therefore needs
  Pro+ or above, or paid overage; test 7 of §8.2 checks the run did not fall
  back to an included model.
- **Data handling.** A campaign sends third-party source code (GRUB, gzip,
  sudo-rs, Mbed TLS) to the provider. Retention rules differ between
  individual and Business/Enterprise plans, and between providers; the
  user's provider policy applies.

## 7. A running campaign is never switched

The campaign state (`time-loop.state`: start, deadline, cycles, wakes) and
the checkpoint commits are harness-neutral, but everything else about a live
run is not: the heartbeat primitives (Claude Code's `ScheduleWakeup` and
cron; OpenCode's external watchdog), the transcript the checks grep, and the
session's context. Switching harness mid-campaign is therefore not
supported.

To change harness:

1. **Stop the campaign.**
   - Under Claude Code: a `STOP` in the session, or let the deadline pass,
     after which the loop pauses with an interim report.
   - Under OpenCode: create `.time-loop-watchdog.stop` in the project root
     (or kill the watchdog), then stop the session. A `STOP` in the TUI
     stops the current turn only.
2. **Start the new harness** in the same project and re-invoke
   `/time-loop <dir> N`. The stored start and deadline are reused and `N` is
   ignored; the work resumes from the last checkpoint.
3. **A fresh budget** needs `--fresh`. Under OpenCode it also needs a
   re-armed watchdog, because the watchdog's loop embeds the deadline and
   `N` literally.

## 8. Files and acceptance tests

### 8.1 Files each route touches

| File | Route A | Route B |
|---|---|---|
| `tests/lib/harness.sh` | credential mode; the connect pre-step (§4.2); the watchdog fixes (§3.2) | the `copilot` case (launcher, trust, prompt regex, transcript), K3 allowlist entries |
| `tests/lib/secret.sh` | `persisted` mode; K2 under `persisted` (§4.4) | the default `AUTOWP_TOKEN_FILE` and credential hint |
| `tests/lib/workshop.sh` | — | `ws_install_copilot`, the `ws_install_harness` switch |
| `tests/c/provision.sh`, `tests/rust/provision.sh` | — | the binary push, version check, global config |
| `templates/c/skills/time-loop/SKILL.md` | the watchdog's `--standalone` (§3.2); "Primitives on each harness" (§1) | a Copilot bullet in that paragraph |
| `templates/{c,rust}/README.md` | §2 step 3–4 wording (API key, credential stored in the container); a `.gitignore` entry | the third choice in "The agent harness" |
| `auto-wp.py` | `.time-loop-watchdog.stop` in the generated `.gitignore` | possibly `.github/agents/time-loop.agent.md` (§9, point 1) |
| `tests/test_harness.py` | tests 4 and 6 of §8.2 | the Copilot prompt regex |
| `tests/test_auto_wp.py`, `tests/test_templates.py` | the `.gitignore` entry | where the harness name appears in pinned output or templates |
| `tests/README.md`, `README.md` | — | the harness list |
| `spec/tests.md` | §3.5 timeout (120 → 300 s) and the watchdog cross-reference; §7.1 OpenCode data directory; §7.3 the Route A row | §3.3, §3.5, §7.1 |
| `spec/auto-wp.md` | the `.gitignore` entry | §3.3, §3.4 (wiring) |
| `spec/choose-harness.md` | §1 row, status line | §1 column moves from proposed to verified |

### 8.2 Acceptance tests

| # | Test | Closes |
|---|---|---|
| 1 | `HARNESS=opencode` smoke test passes K4 (C3.1) within 5 min and C3.5 strict: at least two `wake=` lines in the state file | §3.2 points 1, 3; "never drove a real campaign" |
| 2 | Under `HARNESS=opencode`, no watchdog process and no `opencode run` within 10 min after `harness_stop` | §3.2 point 2 |
| 3 | `HARNESS_START_TIMEOUT` default, its message and `tests.md` §3.5 agree | §3.2 point 4 |
| 4 | `test_harness.py`: an unknown `HARNESS` (including `copilot` before Route B) makes `harness.sh` and `secret.sh` exit non-zero | §1.2 |
| 5 | Route A: `C-copilot.connect` passes, and K2 under `persisted` (§4.4) passes: the token is not in the project tree, `~/remote.git` or `/tmp` | §4.2, §4.4 |
| 6 | `test_harness.py`: `HARNESS_PROMPT_RE` matches the recorded input box of each implemented harness and rejects ordinary output | §1 prompt row |
| 7 | A Copilot run (Route A or B) completes without a fallback to an included model, and records its premium-request count | §6 |
| 8 | C2.2 covers each harness bullet of the generated README | §8.1 READMEs |

## 9. Open points

1. **Copilot entry point** (Route B): a prompt that loads the `time-loop`
   skill, or a generated `.github/agents/time-loop.agent.md`? Decides
   whether `auto-wp.py` gains a `.github/` layer and what `harness_confirm`
   greps.
2. **The delegation barrier.** Is the verifier-in-a-sub-agent rule (and
   `TaskStop` on a verifier past its time box) a requirement of the method or
   a Claude Code convenience? If it is a requirement: which OpenCode and
   Copilot primitive meets it, with the delivered report returned to the
   coordinator? If not: the skill must state the inline fallback explicitly.
3. **OpenCode transcript oracle.** Is `opencode.db` in WAL mode, is the
   prompt stored verbatim, and is there an official session export or
   server API to read instead?
4. **Copilot session lifetime (Route A).** Whether OpenCode's refresh of the
   Copilot session token keeps working unattended for 96 hours; the
   providers page says only that it "saves tokens and refreshes them when
   supported". Whether the GitHub OAuth token itself expires is
   **unverified**.
5. **Watchdog ownership in the tests** (§3.3): the skill, or `harness_start`
   and `harness_stop`?
6. **`opencode mini` vs the full TUI** as the tmux target: which gives the
   more stable prompt marker?
7. **Copilot CLI open cells** (Route B): the tmux input-box marker, the
   session file format, where folder trust is persisted, and arm64 builds.
8. **Route A model quality and cost.** Whether the Copilot-provided models
   are good enough for a 96-hour WP/Coq campaign, and the premium-request
   budget of one run (wakes × sub-agent prompts × model rate). The ranking
   and the cross-provider judge (`sl-auditor`) exist; the cost and quality
   are unmeasured.
