# choose-harness — selecting and switching the agent harness

This document specifies:

- the **harness abstraction**: the fixed set of capabilities a harness must
  provide for a generated project and for the container tests (§1) — the
  table a new harness fills;
- how to **switch a generated project or a test run to OpenCode** (§2, §3) —
  implemented since auto-wp 0.4.0/0.5.0;
- how to switch to **GitHub Copilot**, by two routes: **Route A** — Copilot as
  a model *provider* inside the OpenCode harness (§4, specified, needs
  container-side authorization) — and **Route B** — the Copilot CLI as a
  third harness *binary* (§5, specified as a sketch: every uncertain fact is
  marked TO VERIFY and listed in §8);
- why a **running campaign is never switched** (§6);
- the tests and documents each route touches (§7).

Status: Claude Code and OpenCode are implemented (`auto-wp.py` 0.5.0);
GitHub Copilot is not. The open points are in §8.

## 1. The harness abstraction

A harness is a terminal agent that can (a) discover the project's skills and
commands, (b) run a multi-hour campaign unattended in a container, and (c) be
driven by the test harness (`tests/lib/harness.sh`: launched in `tmux`, a
command typed into its input box, its transcript checked). Everything
harness-specific in this repository is one row of this table:

| Capability | Claude Code | OpenCode | Copilot CLI (Route B, proposed) |
|---|---|---|---|
| install, in the container | `curl -fsSL https://claude.ai/install.sh \| bash` | `curl -fsSL https://opencode.ai/install \| bash` | TO VERIFY (a Node-based CLI; expected `npm i -g @github/copilot-cli`) |
| wiring the project | `.claude/{skills,commands}` → `config/` | `.opencode/{skills,commands}` → `config/` (V2 also reads `.claude/skills` and `.agents/skills` for compatibility) | TO VERIFY (custom agents are `.github/copilot/agents/*.agent.md`; whether it reads the links above is open point 1) |
| credential | a long-lived OAuth token (`claude setup-token`) streamed to `/run/autowp/token`, exported as `CLAUDE_CODE_OAUTH_TOKEN`, deleted after read | a provider API key in `AUTOWP_TOKEN_FILE`, exported under `AUTOWP_OPENCODE_KEY_ENV` (default `ANTHROPIC_API_KEY`) | Route A: OpenCode's device-OAuth connection persisted in the container (§4). Route B: TO VERIFY (§8 point 4) |
| permission posture | `--dangerously-skip-permissions` + `skipDangerousModePermissionPrompt` in `~/.claude/settings.json` | none needed: the V2 base policy allows every action; the harness writes a global `opencode.json` pinning it (`.env` reads included) and a `cli.json` without the release popup | TO VERIFY |
| trust / onboarding dialogs | `~/.claude.json` onboarding + folder trust, written by `harness_trust` for the exact project path | none; the global config is written instead | TO VERIFY |
| input-box prompt (the tmux regex) | `❯` followed by a space or, since 2.1.3xx, a no-break space — `$'...\u00a0'` in `HARNESS_PROMPT_RE` | `Ask anything…` (the placeholder) / `shift+tab agents` (the status line) | TO VERIFY |
| transcript (what `harness_confirm` greps) | `~/.claude/projects/*/*.jsonl` | `~/.local/share/opencode/opencode.db`, `grep -a` | TO VERIFY |
| headless mode | `claude -p` (never used for campaigns: it exits after one turn, so the wake-ups never fire) | `opencode run [-c] [--auto]` | TO VERIFY |
| time-loop heartbeat | in-session: `ScheduleWakeup` (armed as the cycle's last action) + `CronCreate`/`CronList` idle-watchdog | external watchdog: a detached loop re-invoking `opencode run` when `time-loop.state` goes quiet (`time-loop/SKILL.md`, "The heartbeat on each harness") | TO VERIFY (§8 point 5) |
| test switch | `HARNESS=claude` (the default) | `HARNESS=opencode` | `HARNESS=copilot` (proposed) |

The rule the table enforces: **adding a harness means filling one row and
touching the files of §7 — never the skills.** The skills and commands are
harness-neutral: `config/` holds them once and every harness reads the same
files through links.

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
3. On the first start, run `/connect` to add the provider (Anthropic,
   OpenRouter, GitHub Copilot — §4) and `/models` to pick the model. The
   connection persists in the container.
4. Never copy the host's `~/.local/share/opencode/auth.json` into the
   container (the same rule as `~/.claude/.credentials.json`).
5. The commands are the same: `/time-loop <dir> N`, `/rmf` or `/fips`,
   `/ebios` — OpenCode lists them from `.opencode/commands/` (type `/`).

## 3. Running the container tests with OpenCode (implemented)

`HARNESS=opencode` on any level-2/3/4 script changes four things and leaves
the checks unchanged:

- **Credential.** `secret.sh` defaults `AUTOWP_TOKEN_FILE` to
  `~/.config/auto-wp/opencode-provider-key` — the provider API key the
  launcher exports. The launcher (`harness_write_launcher`) reads it from
  `/run/autowp/token` and exports it under `AUTOWP_OPENCODE_KEY_ENV`
  (default `ANTHROPIC_API_KEY`; set the variable to match another provider's
  catalog entry, e.g. `OPENROUTER_API_KEY`).
- **Launch.** The launcher runs `opencode --standalone` (a private server
  inherits the exported environment). `harness_trust` writes the global
  config instead of the Claude dialogs.
- **Prompt and transcript.** The OpenCode prompt regex and the
  `opencode.db` transcript, as in §1.
- **Provisioning.** `provision.sh` pushes both binaries into the base
  container and writes the OpenCode global config (`C-prov.4-opencode`,
  skipped with a note when the OpenCode binary is not on the host PATH).

What is verified and what is not: the OpenCode path has never driven a real
campaign. The pieces expected to need first-contact adjustment, all
overridable by environment without code changes (`HARNESS_PROMPT_RE`,
`HARNESS_START_TIMEOUT`, `HARNESS_SESSION`), are the tmux prompt match, the
`harness_confirm` transcript grep against the session database, and the
wake-up cadence of the external watchdog.

## 4. GitHub Copilot, Route A — as an OpenCode provider (specified)

OpenCode ships a GitHub Copilot provider: connect with the device OAuth flow
(choose **GitHub Copilot** in `/connect`, complete the flow in a browser on
the host, pick the model in `/models`). No API key is involved, which changes
the credential handling:

1. **In a generated project**: follow §2, and in `/connect` choose GitHub
   Copilot instead of an API-key provider. The connection persists in the
   container; nothing is copied from the host.
2. **In the container tests**: the device flow needs one interactive step per
   container. `provision.sh` gains an optional, skipped-by-default step
   `C-prov.5-copilot` — it starts `opencode` in the base container, prints
   the device code and URL, and waits for the flow to complete on the host
   (set `COPILOT_CONNECT=1` to run it). The authorization persists in the
   base's snapshot, so every copied test container starts connected.
3. **The campaign command**: `HARNESS=opencode` as in §3, with the model
   pinned to a Copilot model — `/models` in the TUI, or `model:` in the
   global config, or `opencode run -m <provider/model>` for headless
   re-invocations. The exact provider id for the `-m` form is open point 3.
4. **The K2 delta, stated honestly**: Claude's credential is streamed into
   `/run/autowp/token` and deleted after read — it never rests in the
   container. A Copilot connection *must* persist (`auth.json` in the
   container's data directory). The invariant that survives: the credential
   never enters the **project** tree (`mbedtls-analyze/`, the checkpoints,
   the crosswalk) — K2's scan targets the project and `/tmp`, and continues
   to hold. The threat model note in `tests.md` §7 gains a row: the agent can
   read its own `auth.json`; it could always read its own OAuth token too.

## 5. GitHub Copilot, Route B — the Copilot CLI as a third harness (sketch)

Route B makes `HARNESS=copilot` a first-class row of §1. Every row cell is
marked TO VERIFY in §8; the work is a **spike first** (a level-2-shaped
exercise in a throwaway container: install, authorize, drive one command
through tmux, locate the transcript), then the same five file changes every
harness needed:

- `tests/lib/harness.sh`: the `copilot` case in the `HARNESS` switch
  (launcher, trust, prompt regex, transcript), the K3 allowlist entries.
- `tests/lib/secret.sh`: the default `AUTOWP_TOKEN_FILE` for the harness.
- `provision.sh` (C and Rust): the binary push and version check.
- The generated READMEs: the third bullet in "The agent harness".
- `spec/choose-harness.md`: the table row moves from TO VERIFY to verified.

Until the spike answers §8, Route B stays a sketch. **Route A is the
recommended route for GitHub Copilot**: it needs no new harness code, reuses
the (implemented) OpenCode path, and inherits its heartbeat, transcript and
permission handling — its only new cost is the one-time device flow per
container (§4).

## 6. A running campaign is never switched

The campaign state (`time-loop.state`: start, deadline, cycles, wakes) and
the checkpoint commits are harness-neutral, but everything else about a live
run is not: the in-session heartbeat primitives (Claude Code's
`ScheduleWakeup`/cron; OpenCode's external watchdog), the transcript the
checks grep, and the session's context. Switching harness mid-campaign is
therefore not supported. To change harness: stop the campaign (a `STOP` in
the session, or let the deadline pass — the loop pauses with an interim
report), then start the new harness in the same project and re-invoke
`/time-loop <dir> N`: the stored start and deadline are reused, the `N` is
ignored, and the work resumes from the last checkpoint. A fresh budget needs
`--fresh`.

## 7. Tests and documents each route touches

For Route B (and, if anything is missing, Route A):

- `tests/lib/harness.sh` — the `HARNESS` switch (launcher, trust, prompt
  regex, transcript), the K3 allowlist entries for the harness's data
  directories.
- `tests/lib/secret.sh` — the default `AUTOWP_TOKEN_FILE` and the credential
  hint for the harness.
- `tests/c/provision.sh`, `tests/rust/provision.sh` — the binary push,
  version check, and the global config the harness needs.
- `tests/lib/workshop.sh` — `ws_install_<harness>` and the
  `ws_install_harness` switch.
- The generated READMEs (`templates/{c,rust}/README.md`) — the third choice
  in "The agent harness".
- `spec/choose-harness.md` — the §1 row and the status line.
- `tests/test_auto_wp.py` / `tests/test_templates.py` — only where the
  harness name appears in pinned output or templates.

## 8. Open points

1. **Copilot CLI discovery.** Which directories does the Copilot CLI read for
   custom agents and instructions (`.github/copilot/agents/*.agent.md`?
   `AGENTS.md`?), and does it follow the `.claude/skills` / `.agents/skills`
   links? Decides whether Route B needs new wiring in `auto-wp.py`.
2. **Copilot CLI automation.** Does it have a one-shot/print mode, a
   tmux-drivable TUI with a stable input-box marker, and a session-continue
   flag (the analog of `opencode run -c`)?
3. **The OpenCode provider id for Copilot models** — the `<provider/model>`
   string for `opencode run -m` under Route A.
4. **Copilot credential lifetime.** How long the device-OAuth token lives,
   whether it refreshes unattended in a container for 96 hours, and what
   that does to the `secret_check_expiry` discipline (§7 of `tests.md`).
5. **The Copilot heartbeat primitive.** Whether anything in Route B can
   self-schedule; if not, the external-watchdog pattern is the default.
6. **Route A model quality.** Whether the Copilot-provided models are
   acceptable for a 96-hour WP/Coq campaign — the ranking and the
   cross-provider judge (`sl-auditor`) exist; the campaign cost/quality is
   unmeasured.
7. **Copilot CLI on arm64** — the Route B binary's platforms; Route A
   inherits OpenCode's arm64 story.
