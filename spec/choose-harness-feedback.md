# Feedback on `spec/choose-harness.md`

Reviewed against `auto-wp.py` 0.5.0, `tests/lib/{harness,secret,workshop,lxc}.sh`,
`tests/{c,rust}/provision.sh`, the level-3/4 scripts, `spec/{auto-wp,tests}.md`,
the README templates and `templates/c/skills/time-loop/SKILL.md` +
`templates/c/commands/time-loop.md`, on 2026-11-07. Facts about OpenCode and
the Copilot CLI that the repository cannot show are marked **unverified**
or cite the page they come from; the Copilot CLI flags come from
`copilot --help` of the host's install (GitHub Copilot CLI 1.0.105).

## Summary verdict

§2 and §3 (OpenCode, implemented) describe the code accurately in almost
every sentence; the §1 table is a good shape. The document is not ready as a
specification for the two Copilot routes:

- **Route A cannot be run by the test harness as written.** Every level-3/4
  script needs a credential *file* (`secret_check_file`, `secret_push`,
  `secret_check_expiry`, the launcher's `/run/autowp/token` check, K2's
  pattern) and Route A has none. The spec says "`HARNESS=opencode` as in §3"
  and leaves the gap unstated.
- **Route A's credential handling contradicts `tests.md` §7.2** (a credential
  baked into the base snapshot is exactly the option that section rejects)
  and misstates what K2 scans.
- **The harness abstraction is incomplete for the long-running loop.** The
  time-loop skill makes three Claude-Code-only mechanisms mandatory —
  the self-rescheduling heartbeat, a *spawned sub-agent per cycle* (with
  `TaskStop`), and slash commands — and only the first has an OpenCode
  equivalent written down. The table has no row for sub-agents or background
  tasks, and the "never the skills" rule (§1) is already violated by the
  skill text (`ScheduleWakeup` ×18, `CronCreate`/`CronList` ×10,
  `TaskStop`, `/loop`).
- Several Copilot CLI cells marked TO VERIFY are now verifiable and two are
  wrong (package name, agents directory); the account/terms constraints
  (paid plans only, premium-request budget, Anthropic's ban on subscription
  OAuth in third-party clients) are absent.
- No acceptance criteria or numbered tests exist for either route.

Fix the blocking items, then turn §4 into a procedure the scripts can
execute; §5 can stay a sketch once its cells are corrected.

## Blocking

### B1. Route A has no credential file, so the implemented test path cannot start (§4.2–4.3, lines 104–113)

**What is wrong.** §4.3 says "`HARNESS=opencode` as in §3". §3's path
requires a file: `secret_check_file` refuses to run without
`AUTOWP_TOKEN_FILE` (`tests/lib/secret.sh:26-47`); every level-3/4 script
calls `secret_push` before `harness_start` (`tests/c/gzip-test.sh:172`,
`tests/c/mbed-tls-test.sh:321`, `tests/c/acceptance.sh:70,246,274`,
`tests/rust/sudo-rs-test.sh:168`); the OpenCode launcher exits 1 when
`/run/autowp/token` is missing (`tests/lib/harness.sh:47-50`); `secret_k2`
builds its grep pattern from the same file (`secret.sh:106`); and
`secret_check_expiry` needs the `.created` metadata (`secret.sh:53-58`,
called at `gzip-test.sh:131`, `mbed-tls-test.sh:260`, `acceptance.sh:82`).
Under Route A the credential is a device-flow connection persisted in the
container: there is nothing to stream, nothing to delete, nothing to grep for.

**Fix.** Specify a credential *mode* per harness, e.g. `HARNESS_CREDENTIAL=
file|persisted` (default `file`), and state for `persisted`: `secret_check_file`,
`secret_check_expiry` and `secret_push` are no-ops that print a note; the
launcher does not require `/run/autowp/token` and exports nothing; K2 is
`skip`ped with a note (no pattern) or uses a different oracle (see B2);
`harness_start` runs plain `opencode --standalone`. Add this as a row of the
§1 table ("credential mode") and as the first item of §7's `secret.sh` bullet.

### B2. Persisting the Copilot authorization in the base snapshot contradicts `tests.md` §7.2, and the K2 claim is false (§4.2 line 108–109, §4.4 lines 114–121)

**What is wrong.**
1. `tests.md` §7.2 rejects `lxc config set … environment.*` precisely because
   it is "copied into every snapshot and copy of the container"; §4.2 proposes
   to do the same with the Copilot OAuth token ("the authorization persists in
   the base's snapshot, so every copied test container starts connected").
   The spec calls this "the K2 delta, stated honestly" but does not say that
   the threat model of `tests.md` §7.3 ("revoke the token after a level 4
   run") now applies to a credential that lives in *every* container ever
   copied from the base, including kept ones (`KEEP=1`).
2. "K2's scan targets the project and `/tmp`" is wrong: `secret_k2` greps
   `~`, `/tmp` and `$CAMPAIGN_DIR` (`tests/lib/secret.sh:107-108`). Under
   Route A it would scan the credential's own store.
3. The store is not `auth.json`: OpenCode V2 keeps API keys and OAuth tokens
   in the SQLite database (`opencode.db`); a legacy `auth.json` is imported
   once (https://opencode.ai/docs/cli/providers/ — "Saved API keys and OAuth
   tokens are stored in the server's SQLite database … New and updated
   credentials are stored in SQLite rather than written back to that file").
   That database is also the *transcript* the tests grep (`harness.sh:167`):
   the credential and the transcript are one file.

**Fix.** Either (a) authorize per test container, not in the base (the
`C-prov.5` step becomes a `harness_start` pre-step under `persisted` mode,
and the container is deleted at the end as today), or (b) keep the base
authorization and say so plainly in a new row of `tests.md` §7.2/§7.3:
the token is in every copy, is readable by the agent, must be revoked at
GitHub (Settings → Applications → Authorized OAuth Apps) after each level-4
run, and `KEEP=1` keeps a live credential on disk. In both cases rewrite
§4.4: K2 scans `~` too; the invariant that survives is "not in the project
tree, `~/remote.git`, or `/tmp`", and the test must exclude the OpenCode
data directory from the grep *and say why*. Replace `auth.json` by
"the OpenCode data directory (`opencode.db`; `auth.json` before V2)"
here, in §2.4, in `tests.md` §7.1 and in `templates/{c,rust}/README.md`.

### B3. The abstraction has no row for sub-agents, background tasks or slash commands, and the skills are not harness-neutral (§1 table and lines 42–45)

**What is wrong.** The rule "adding a harness means filling one row … never
the skills" assumes the skills are harness-neutral. They are not:

- `SKILL.md` names `ScheduleWakeup` 18 times, `CronCreate` 4, `CronList` 6,
  `TaskStop` once (line 559), `/loop` 3 times; `commands/time-loop.md:86`
  names `ScheduleWakeup`; the lesson
  `skills/time-loop/getting-better/20260801-self-perpetuation-arm-the-heartbeat.md`
  is written entirely in Claude Code terms. Only one paragraph ("The heartbeat
  on each harness", `SKILL.md:964-989`) gives an OpenCode equivalent, and only
  for the heartbeat.
- The per-cycle verifier **must** run in a spawned sub-agent
  (`SKILL.md:533-559`: "done ONLY inside a spawned sub-agent … If you catch
  yourself about to run `frama-c` … STOP: that is the relapse"), a hung one is
  killed with `TaskStop` (559), and multi-cycle chaining relies on
  "background sub-agents whose completion notifications re-invoke you"
  (794-802, 916-918). None of this has an OpenCode or Copilot equivalent in
  the spec or the skill. OpenCode has subagents (`@agent` mentions, commands
  with `subagent: true` — https://opencode.ai/docs/commands/); whether it has
  a stop primitive and completion notifications is **unverified**. The
  Copilot CLI has custom agents and a `--fleet` "parallel subagent
  orchestration" mode (`copilot --help`); its in-session spawn/stop API is
  **unverified**.
- `/time-loop grub 72` is a slash command. OpenCode reads
  `.opencode/commands/*.md` (verified: https://opencode.ai/docs/commands/;
  `.claude/commands` is not read, so the `.opencode/commands` link is
  load-bearing). The Copilot CLI documents skills and agents under
  `/add-dir` but no project-defined slash commands
  (https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference);
  typing `/time-loop …` into it is therefore probably rejected as an unknown
  command (**unverified**), and `harness_confirm`'s patterns
  (`harness.sh:179`) would not match.

**Fix.** Add three rows to §1: *sub-agent spawn / delegation barrier*,
*background task + stop*, *how the campaign is invoked* (slash command,
prompt, or custom agent). For each harness say the primitive or, honestly,
"none — the cycle runs inline in the coordinator's session", and have the
skill's "heartbeat on each harness" paragraph grow into "primitives on each
harness" covering all three. Rewrite lines 42–45: the skills are neutral
*except* the one paragraph that maps the primitives, and adding a harness
means filling that paragraph too. For Copilot, decide now whether the entry
point is a prompt ("Load the `time-loop` skill and run `/time-loop grub 72`")
or a generated `.github/agents/time-loop.agent.md`; that decision changes
`auto-wp.py` (§8 point 1) and `harness_confirm`.

## Major

### M1. The OpenCode watchdog's `opencode run` does not inherit the credential path the launcher built (§1 line 39, §3 line 78; `SKILL.md:975-983`)

The launcher runs `opencode --standalone` so that a *private* server inherits
`ANTHROPIC_API_KEY` from the launcher's environment (`harness.sh:41-54`,
comment: "--standalone: a private server inherits this environment"). The
watchdog in `SKILL.md:981` runs plain `opencode run …`, which goes through the
shared background service ("owns sessions, configuration, integrations,
permissions, and tool execution for all local clients",
https://opencode.ai/docs/cli/). Whether that service, started by whichever
process first needed it, has the key in its environment is **unverified**;
the OpenCode providers page gives `ANTHROPIC_API_KEY=… opencode --standalone`
as the way to use an environment key, which suggests it does not. If so, every
wake after the first fails to authenticate and the campaign silently stalls —
the failure the heartbeat exists to prevent.

**Fix.** Pin `opencode run --standalone` in the skill's watchdog, or have
`harness_trust`/`provision.sh` run `opencode service set disabled true`
("makes private servers the default for CLI commands", same page) and record
it in the §1 permission/trust row. Add an acceptance criterion: on
`HARNESS=opencode`, the state file records at least two `wake=` lines
(C3.5 strict) — today the spec admits this has never run (lines 87–92).

### M2. Nothing stops the OpenCode watchdog: `harness_stop`, acceptance `restart`, resume scenarios and a user `STOP` all leave it running (§3, §6 lines 144–156)

`harness_stop` kills the tmux session only (`harness.sh:188-193`). The
watchdog is `setsid nohup … &` (`SKILL.md:975`), so it survives, keeps firing
`opencode run` every ~8 min whenever the state file is 10 min old, and
competes with the next `harness_start` in `acceptance.sh restart`
(`acceptance.sh:135-145`), the resume scenarios (`acceptance.sh:242-248,
274-286`) and the `--dir`/`--fresh` runs; `wait_loop_stopped` (`harness.sh:396-415`)
then never sees idle until the deadline. §6 says to stop a campaign with "a
`STOP` in the session"; under OpenCode that stops the TUI turn, not the
detached loop, unless the loop itself writes `.time-loop-watchdog.stop`.

**Fix.** In §6: "on OpenCode, stopping means creating
`.time-loop-watchdog.stop` in the project root (or killing the watchdog);
`--fresh` must re-arm it with the new deadline, because `DEADLINE_EPOCH` and
`N` are baked into the shell loop". In §3/§7: `harness_stop` under
`HARNESS=opencode` touches the stop file and `pkill -f time-loop-watchdog`;
`wait_loop_stopped` reports whether a watchdog is alive. Add a check: no
watchdog process after `harness_stop`. Also state that
`.time-loop-watchdog.stop` must be in the generated `.gitignore` (nothing in
`templates/` ignores it; it would otherwise be committed by the per-cycle
checkpoint).

### M3. The transcript and idle oracles assume `opencode.db` changes on every write (§1 line 37, §3 lines 81–82; `harness.sh:167,179,399`)

`harness_confirm` requires the database to be newer than
`~/.autowp-harness-start` and greps it with `grep -a`; `wait_loop_stopped`
stats it. If the database is in WAL mode (**unverified** for OpenCode; common
for SQLite servers), recent writes go to `opencode.db-wal` and the main
file's mtime and content lag until a checkpoint, so K4 can time out and idle
can be measured wrong. The grep patterns (`<command-name>`, `"skill":`,
`/time-loop `) are Claude Code's JSONL shapes; only the last can match
OpenCode's rows, and only if the prompt text is stored verbatim (**unverified**).

**Fix.** Glob `~/.local/share/opencode/opencode.db*` in both places; prefer an
official export if one exists (`opencode session …`/`export` — **unverified**)
or the server API (`opencode serve` is documented as having an API
reference). Make "K4 passes within 5 min on a real OpenCode run" a numbered
acceptance test rather than a remark.

### M4. `HARNESS=copilot` silently drives Claude Code today (§1 line 40)

Every `case $HARNESS` falls through to `*)` = Claude Code
(`harness.sh:30-33, 39-72, 81-114, 166-169, 398-401`; `secret.sh:19-22,
30-34`; `workshop.sh:158-161`). Setting the proposed value runs the wrong
harness with the Claude credential file and reports green.

**Fix.** Specify that unknown `HARNESS` values are rejected (`die`) in
`harness.sh` and `secret.sh`, and that `HARNESS=copilot` stays rejected until
Route B lands; add a unit test in `tests/test_harness.py`.

### M5. Copilot CLI cells marked TO VERIFY are verifiable now, and two are wrong (§1 lines 31–39, §5, §8 points 1, 2, 4, 5, 7)

From https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli,
https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-programmatic-reference
and `copilot --help` / `copilot skill --help` / `copilot help environment`
(host install, 1.0.105):

| Cell | Spec says | Verified |
|---|---|---|
| install | `npm i -g @github/copilot-cli` | `npm install -g @github/copilot` (Node ≥ 22), or `curl -fsSL https://gh.io/copilot-install | bash`, or `brew install --cask copilot-cli`; binaries on the `github/copilot-cli` releases page. Platforms listed as Windows/macOS/Linux; **arm64 unverified** (point 7 stays open). |
| wiring | `.github/copilot/agents/*.agent.md`; whether it reads the links is open | Agents: `.github/agents` (repo), `~/.copilot/agents` (user). Skills: "`.github/skills/`, `.agents/skills/`, or `.claude/skills/`" (project), "`~/.copilot/skills/` or `~/.agents/skills/`" (personal) — so the generated `.agents` and `.claude/skills` links already work for *skills*; *commands* are not read (see B3). Point 1 is half answered. |
| credential | TO VERIFY | `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN` (in that precedence) — a fine-grained PAT with the "Copilot Requests" permission; or `copilot login` / `/login` device flow stored under `~/.copilot` (`COPILOT_HOME`). The `/run/autowp/token` route therefore applies unchanged: export `COPILOT_GITHUB_TOKEN` in the launcher. Note the CLI redacts `GITHUB_TOKEN`/`COPILOT_GITHUB_TOKEN` values from output and has `--secret-env-vars`. Lifetime: a PAT has a chosen expiry — the `.created`/`expires=` discipline of `secret_check_expiry` applies as-is (point 4 for Route B). |
| permission posture | TO VERIFY | `--allow-all-tools` ("required for non-interactive mode"), `--allow-all`/`--yolo` (= tools + paths + urls), `COPILOT_ALLOW_ALL=true`. |
| trust/onboarding | TO VERIFY | A folder-trust prompt exists: `--trust-folder` (prompt mode, one session), `COPILOT_ALLOW_ALL=true` ("additionally trusts the working directory without prompting"). Where interactive trust is persisted is **unverified** — the analog of `harness_trust` needs the spike. Auto-update: `COPILOT_AUTO_UPDATE=false` (the `DISABLE_AUTOUPDATER=1` analog). |
| headless | TO VERIFY | `copilot -p "<prompt>" --allow-all-tools [-s] [--output-format json]`; `--continue` (most recent session), `-r/--resume [id]`, `--session-id`; `--autopilot`/`--mode autopilot` with `--max-autopilot-continues` (default 5). Point 2 is answered except the tmux prompt marker, which stays **unverified**. |
| transcript | TO VERIFY | State under `~/.copilot` (`COPILOT_HOME`), logs `~/.copilot/logs/` (`--log-dir`), `--share <path>` writes a markdown transcript after a non-interactive run. The exact session file format is **unverified**. |
| heartbeat | TO VERIFY | No in-session scheduler is visible in `--help`; the external-watchdog pattern (point 5) with `copilot -p … --allow-all-tools --continue` is the default, with the same M1/M2 caveats. |

**Fix.** Replace the two wrong cells, move the verified facts into the table
with their source, and shrink §8 to what is still open (prompt marker,
session file, arm64, trust persistence, in-session sub-agent API).

### M6. Account, plan and terms constraints are missing (§4, §5, §8 point 6)

- **Copilot via OpenCode** is officially supported for "paid GitHub Copilot
  subscriptions (Pro, Pro+, Business, or Enterprise)"
  (https://github.blog/changelog/2026-01-16-github-copilot-now-supports-opencode);
  Copilot Free is not named. The OpenCode page says the account needs
  "Copilot Chat access" (https://opencode.ai/docs/providers/). Business and
  Enterprise administrators can disable the Copilot CLI by policy
  (install page). Say which plan the tests assume.
- **Premium requests.** The Copilot CLI consumes "one premium request per
  prompt, multiplied by the model's rate"; a Pro plan has 300 per month,
  Pro+ 1,500, overage $0.04 per request when enabled
  (https://docs.github.com/en/copilot/concepts/billing/copilot-requests —
  that page now describes legacy billing for annual Pro/Pro+ plans; the
  current scheme for other plans is **unverified**). A 96-hour campaign with
  a wake every ≤ 20 min is ≥ 300 prompts before counting sub-agent prompts:
  it exhausts a Pro allowance in one run. The spec needs a budget estimate
  and an acceptance criterion ("the run completes without falling back to an
  included model"), or a statement that only Business/Enterprise or
  pay-per-request accounts are supported.
- **Anthropic.** Do not let the README's `/connect → Anthropic` be read as
  "log in with your Claude subscription": Anthropic's consumer terms forbid
  third-party harnesses on subscription OAuth, access was blocked
  server-side in 2026 and OpenCode removed its Anthropic OAuth login
  (secondary sources only, e.g.
  https://www.theregister.com/2026/02/20/anthropic_clarifies_ban_third_party_claude_access
  and https://falcao.org/posts/anthropic-claude-access-crackdown-ecosystem-fallout/;
  **unverified against the primary terms**). The spec's API-key path is the
  right one; make §2 step 3 and `templates/{c,rust}/README.md` say "an API
  key (not a Claude subscription login)", and keep `tests.md` §7.2's note
  that the key bills the API account.
- **Data handling.** The campaign sends third-party source (GRUB, Mbed TLS)
  to the provider; for Copilot the retention rules differ between Business/
  Enterprise and individual plans. One sentence pointing at the relevant
  policy is enough.

### M7. `C-prov.5-copilot` cannot be implemented as written (§4.2 lines 104–109)

The device flow runs in OpenCode's TUI; `provision.sh` drives the base with a
non-tty `lxc exec` (`tests/lib/lxc.sh:234-241`). "Starts `opencode` … prints
the device code and URL, and waits" needs: a tmux session in the base, the
`/connect` keystrokes, a capture-pane parse of the code and URL, a timeout,
and a post-condition that proves the connection exists (`opencode auth list`
— **unverified** that it lists OAuth accounts). Also: the model pin for
headless re-invocations uses `opencode run -m <provider/model>` — the `-m`
flag is **unverified** (the CLI page documents no `run` flags); the provider
id `github-copilot/<model>` is observed in user reports only
(**unverified**). Write the step as the sequence above, or move the whole
authorization into the spike of §5 and keep Route A "specified" only after
it has been done once.

### M8. No acceptance criteria or numbered tests for either route (§7)

§7 lists files, not checks. Propose at least: (1) `HARNESS=opencode`
smoke-test passes K4 (C3.1) and C3.5 strict (two wakes) — closes the
"never driven a real campaign" admission; (2) no watchdog process and no
`opencode run` after `harness_stop`; (3) K2 under Route A: credential not in
the project tree, `~/remote.git`, `/tmp`; (4) `HARNESS=copilot` is rejected
until Route B lands; (5) C2.2 extended to the README's third harness bullet;
(6) `test_harness.py`: `HARNESS_PROMPT_RE` for each harness, unknown value
rejected; (7) a budget check for Copilot (M6).

## Minor

- **m1 (§1 line 31).** The install row gives the user's `curl | bash` lines;
  the tests push the host's binary instead (`tests/c/provision.sh:121-139`,
  `tests.md` §3.3) and pin `DISABLE_AUTOUPDATER=1`. Say the row is the README
  route and name the test route.
- **m2 (§3 line 69).** "changes four things": `wait_loop_stopped`'s glob
  (`harness.sh:398-401`) and the K3 allowlist (`harness.sh:319`) also switch.
  Say "every `case $HARNESS` in `harness.sh` and `secret.sh`".
- **m3 (§3 line 84).** The Rust check is `R-prov.3-opencode`
  (`tests/rust/provision.sh:120`), not `C-prov.4-opencode`.
- **m4 (§1 line 34).** The global config uses `"action": "*"`; the docs show
  named actions (`shell`, `edit`, `read`, `skill`) and effects
  allow/ask/deny (https://opencode.ai/docs/config/) — the wildcard action and
  the ".env reads" claim are **unverified** (the config page does not mention
  `.env`). `cli.json` / `highlights` are not documented there either
  (**unverified**). Mark them or cite where they come from.
- **m5 (§1 line 36).** `shift+tab agents` as a status-line marker is
  **unverified**; say so, as the table does for Copilot.
- **m6 (§1 line 38).** `opencode run [-c] [--auto]`: neither flag is in the
  CLI page; **unverified**. `opencode mini` exists as a minimal interactive
  mode (same page) and may be the better tmux target than the full TUI.
- **m7 (§3 line 89).** `HARNESS_START_TIMEOUT` defaults to 300 s but the
  failure message says "after 120 s" (`harness.sh:152`) and `tests.md` §3.5
  says 120 s. Align the three.
- **m8 (§5 lines 128–136 vs §7).** "the same five file changes" vs seven
  items in §7 (`workshop.sh`, `test_*.py` added). Also missing from §7:
  `tests/README.md` (names both harnesses, lines 62–65, 86–94), `README.md`
  line 31, `tests.md` §3.3/§3.5/§7.1, and `spec/auto-wp.md` §3.3/§3.4.
- **m9 (§1 line 32).** `commands/time-loop.md` uses Claude Code's
  `argument-hint` frontmatter; OpenCode documents `description`, `agent`,
  `model`, `subagent`. Unknown keys are probably ignored (**unverified**);
  note it in the wiring row.
- **m10 (§6).** Under OpenCode the watchdog embeds `DEADLINE_EPOCH` and `N`
  literally; "a fresh budget needs `--fresh`" must add "and a re-armed
  watchdog" (see M2).
- **m11 (§2 step 3).** For the README route the API key pasted into
  `/connect` is stored in the container's database; say that the tests'
  stream-and-delete discipline does not apply to this route, so the user
  knows what `lxc delete` / `workshop remove` is removing.
- **m12 (§8 point 4).** Rephrase: what matters is whether OpenCode's refresh
  of the Copilot *session* token (the GitHub OAuth token itself has no fixed
  expiry — **unverified**) keeps working unattended for 96 h; the providers
  page only says it "saves tokens and refreshes them when supported".
- **m13 (§1 line 33, Claude row).** Fine as written; add that `claude -p`
  and `--bare` are excluded for the reasons in `tests.md` §3.3/§3.5 so the
  row is self-contained.

## Editorial

- **e1 (lines 13–14).** "every uncertain fact is marked TO VERIFY and listed
  in §8" — the permission, trust, prompt and transcript cells have no §8
  point. After M5 most become facts; list the rest.
- **e2 (line 32, 34).** "V2" is undefined; say "OpenCode's V2 TUI (the
  version observed, `opencode --version`)".
- **e3 (`tests.md` §3.5, cross-reference).** It cites "`time-loop/SKILL.md`
  §8" for the watchdog; the paragraph is "The heartbeat on each harness"
  under "Invocation / activation" (`SKILL.md:964`), which this spec cites
  correctly. Fix `tests.md`.
- **e4 (lines 8–9, 18).** "implemented since auto-wp 0.4.0/0.5.0": both the
  project wiring and the `HARNESS=opencode` test switch landed in 0.4.0
  (commit 967431a); say "0.4.0".
- **e5 (§4 title).** "(specified)" overstates it until B1, B2 and M7 are
  resolved; "(proposed)" matches the content.

## Open questions for the author

1. Route A credential: per-container authorization (deleted with the
   container) or base-image authorization (in every copy)? Who revokes it,
   when, and is `KEEP=1` acceptable with a live credential on disk?
2. Which Copilot plan do the tests assume, and what is the premium-request
   budget of one 96-hour campaign (wakes × sub-agent prompts × model
   multiplier)? Is falling back to an "included model" mid-campaign a test
   failure?
3. Sub-agents: is the delegation barrier (verifier in a spawned sub-agent,
   `TaskStop` on hang) a *requirement* of the method or a Claude Code
   convenience? If a requirement, which OpenCode/Copilot primitive meets it;
   if not, the skill must allow the inline fallback explicitly.
4. Copilot entry point: a prompt that loads the `time-loop` skill, or a
   generated `.github/agents/time-loop.agent.md`? The answer decides whether
   `auto-wp.py` gains a `.github/` layer and what `harness_confirm` greps.
5. Should the OpenCode watchdog be owned by the harness (`harness_start`
   arms it, `harness_stop` kills it) rather than by the skill? That would
   make M1/M2 test-side fixes and keep the skill text shorter.
6. Is `opencode mini` (minimal interactive mode) a better tmux target than
   the full TUI for prompt detection?
7. For OpenCode with an API key, is the Anthropic API account the intended
   payer (it is, per `tests.md` §7.2), and should the spec say the Claude
   subscription is Claude Code-only?
8. Does the spec want a "credential mode" column (file / persisted / none)
   rather than overloading `HARNESS`?
