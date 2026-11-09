# Second review of `spec/choose-harness.md`

Reviewed on 2026-11-07 against the revision that applies
`choose-harness-feedback.md` and `choose-harness-copilot-feedback.md`
(commit 7456bbc), `auto-wp.py` 0.5.0, `tests/lib/{harness,secret,workshop}.sh`,
`tests/{c,rust}/provision.sh`, `tests/test_harness.py`, `spec/{tests,auto-wp}.md`,
`templates/{c,rust}/README.md`, `templates/c/skills/time-loop/SKILL.md`,
`templates/c/commands/time-loop.md`, the host's GitHub Copilot CLI 1.0.107
(`copilot --help`, `copilot help {environment,commands,billing,limits,providers}`,
`copilot skill list` in a throwaway generated project, `copilot login --help`),
and the pages cited inline. `opencode` is not installed on this host, so
OpenCode facts come from its documentation only. Findings the two earlier
reviews made and the revision applied correctly are not repeated. Facts I
could not check are marked **unverified**.

## Summary verdict

The revision applied the two reviews faithfully, and §1–§3 now read as a
specification. Three things still stop an implementer:

1. **The generated skills do not load in the Copilot CLI.** Run in a project
   that `auto-wp.py --c` just generated, `copilot skill list` rejects 15 of the
   skills, `time-loop`, `rmf-sl`, `fips-sl`, `frama-c-launch`,
   `frama-c-monitoring`, `sl-builder` and `sl-auditor` among them, because their
   `description` exceeds the 1024-character limit of the Agent Skills
   specification; two more fail YAML parsing. The Rust `creusot-monitoring`
   skill fails for the same reason. The wiring cell "the generated links
   already work" is therefore true for the directory and false for the content,
   and Route B and B′ cannot be spiked before the templates change. Neither
   earlier review caught this; it is checkable on the host without a login.
2. **The revision introduced a contradiction between §1 and §3.** §1 now says
   "a harness without [a sub-agent primitive that returns a delivered report]
   is not supported for `/time-loop`" while OpenCode's sub-agent and
   background-task cells are **unverified**; so the "implemented" OpenCode
   harness is, by §1's own rule, unsupported for the one campaign the tests
   run.
3. **The abstraction covers only the C `time-loop`.** The Rust template has no
   `time-loop` skill and no commands at all; the Rust level-3 tests type a
   free-text prompt that embeds `ScheduleWakeup` (Claude Code's name) as the
   heartbeat. Under OpenCode a Rust campaign has no heartbeat, and the entry
   point row, §2 step 6 and §7 step 2 do not describe Rust projects.

Below those, the Copilot column misses two data paths the CLI opens by
default (the built-in GitHub MCP server and account session sync), the
acceptance tests 2, 7, 10 and 11 have no oracle an implementer can code, and
the "not yet implemented" list in the header is shorter than the set of
things the document describes in the present tense.

Fix B1 in the templates first (it is a level-1 test), then M1–M3 in the text;
the rest is wording and bookkeeping.

## Blocking

### B1. The generated skills are rejected by the Copilot CLI; the §1 wiring cell and §5 step 1 rest on an untested assumption (§1 table "wiring the project", line 48; §5 lines 291–292; §9 point 1)

**What is wrong.** The Copilot cell says "skills from `.github/skills/`,
`.agents/skills/` or `.claude/skills/` (the generated links already work)".
The directories are found, but the files are refused:

```
$ cd <generated project>   # python3 auto-wp.py --c probe, in a scratch dir
$ COPILOT_HOME=<scratch>/copilot-home COPILOT_AUTO_UPDATE=false copilot skill list
Project skills:
  directory-structure - …
  ebios-risk-manager - …
  frama-c-internals - …
  framac-sl - …
  lean - …   rocq - …   stride - …   workshop - …
  ebios - Run the EBIOS-SL (code-blind) -> frama-c-launch/monitoring verification campaign on a directory
  rmf - Run the RMF-SL (code-blind) -> frama-c-launch/monitoring verification campaign on a directory
  time-loop - Run the time-loop META squeeze — drive /rmf XXX XXX-analysis to maximize …
✖ The following skills failed to load:
  • .agents/skills/ebios-sl/SKILL.md: Skill description must be at most 1024 characters
  • .agents/skills/fips-sl/SKILL.md: Skill description must be at most 1024 characters
  • .agents/skills/frama-c-api/SKILL.md: …   • .agents/skills/frama-c-launch/SKILL.md: …
  • .agents/skills/frama-c-monitoring/SKILL.md: …   • .agents/skills/frama-c/SKILL.md: …
  • .agents/skills/linux-api/SKILL.md: …   • .agents/skills/ocaml/SKILL.md: …
  • .agents/skills/polish-skill/SKILL.md: failed to parse YAML frontmatter: mapping values are not allowed in this context at line 2 column 567
  • .agents/skills/rmf-sl/SKILL.md: …   • .agents/skills/sl-auditor/SKILL.md: …
  • .agents/skills/sl-builder/SKILL.md: …
  • .agents/skills/sl-internal/SKILL.md: failed to parse YAML frontmatter: mapping values are not allowed in this context at line 2 column 1541
  • .agents/skills/sl-monitoring-sl/SKILL.md: …
  • .agents/skills/time-loop/SKILL.md: Skill description must be at most 1024 characters
```

Measured description lengths (characters, `templates/*/skills/*/SKILL.md`):
`time-loop` 2983, `rmf-sl` 2026, `fips-sl` 1977, `sl-auditor` 1912,
`frama-c-launch` 1880, `sl-internal` 1693, `frama-c-monitoring` 1680,
`linux-api` 1667, `frama-c-api` 1645, `creusot-monitoring` 1520, `ocaml` 1489,
`ebios-sl` 1432, `frama-c` 1251, `sl-builder` 1070, `sl-monitoring-sl` 1046,
`workshop` 1030. The limit is the Agent Skills specification's
("`description` … Max 1024 characters", https://agentskills.io/specification),
which the Copilot CLI enforces and Claude Code does not. Whether OpenCode
enforces it is **unverified** — and the spec admits OpenCode has never driven
a campaign (§3.2), so it may be hiding the same failure.

Two consequences the spec does not know about:

- Three entries named `ebios`, `rmf` and `time-loop` **do** load — they are
  `.claude/commands/*.md`, which the Copilot CLI reads as skills named after
  the file (verified: removing the `.claude/commands` link from a copy of the
  project makes the three entries disappear; `.agents/commands` is not read).
  So on Copilot, "load the `time-loop` skill" resolves to the 109-line command
  text, which says "Invoke the `time-loop` skill", while the 1061-line method
  is absent. The agent would run the campaign without the method. This also
  half-answers §9 point 1: the command *is* addressable by name, as a skill.
- The two YAML failures are unquoted colons in a one-line `description`
  (`polish-skill`, `sl-internal`); Claude Code's parser tolerates them,
  Copilot's does not.

**Fix.**
1. Add to §8.1 a row `templates/*/skills/*/SKILL.md` — "descriptions
   ≤ 1024 characters, frontmatter valid YAML" — and to §8.2 a level-1 test
   (`tests/test_templates.py`): every `SKILL.md` frontmatter parses with a
   strict YAML parser, `name` matches the directory, `description` is
   1–1024 characters. Put it first: it is the only test in §8.2 that runs
   without a container, and it gates every Copilot item.
2. Rewrite the wiring cell: "skills are read from `.agents/skills` (first) or
   `.claude/skills`; `.claude/commands/*.md` are loaded as skills named after
   the file (verified with `copilot skill list`); SKILL.md files must meet the
   Agent Skills limits, which the templates do not yet (§8.2 test 0)."
3. Make §5's spike step 1 start with `copilot skill list` in the generated
   project — it needs no login — and only then the `-i` prompt.
4. Add to test 1 (OpenCode smoke): the transcript shows the `time-loop`
   *skill* loaded, not only the command, or state how OpenCode reports a
   rejected skill.

## Major

### M1. §1's new support rule makes OpenCode unsupported for `/time-loop`, contradicting §3 "implemented" and test 1 (§1 lines 74–78; table lines 58–59; §3 title; §8.2 test 1)

**What is wrong.** Lines 74–78: "Where a harness has no sub-agent primitive
that returns a delivered report … Until that is decided, a harness without it
is not supported for `/time-loop`." The OpenCode cells say "whether the
coordinator gets the delivered report back … is **unverified**" and
"**unverified**; fallback: one verifier at a time". By the rule, OpenCode is
not supported for `/time-loop`; §3 calls it implemented and test 1 runs a
`/time-loop` smoke test on it.

The OpenCode agents page settles part of this
(https://opencode.ai/docs/agents/): a subagent "runs only in a child session
through the `subagent` tool", subagents "run with fresh context in foreground
or background child sessions", and modes are `primary`/`subagent`/`all`. The
commands page (https://opencode.ai/docs/commands/) says `subagent: true`
"runs in a background child session" and `subtask` is a "deprecated alias
for `subagent`". So OpenCode has a spawn primitive and background child
sessions; whether the parent receives the result and whether a child can be
stopped are still not stated on those pages (**unverified**). The spec's
"`@agent` mentions" is not on the agents page either (**unverified**).

**Fix.** Either (a) weaken the rule to "a harness without it runs the
verifier inline in the coordinator's session, which the skill must permit
explicitly (§9 point 2)", and say OpenCode runs in that mode until the spike
verifies the `subagent` tool; or (b) keep the rule and downgrade OpenCode to
"implemented for the test switch, unsupported for `/time-loop` until test 1
passes". Update the two OpenCode cells with the documented facts above.

### M2. The abstraction and the Rust template disagree: no `time-loop`, no commands, a prompt entry point, and a Claude-only heartbeat in the prompt (§1 rows "campaign entry point", "time-loop heartbeat"; §2 step 6; §7 step 2; §8.1 SKILL.md row)

**What is wrong.** `templates/rust/skills/` has no `time-loop`;
`templates/rust/commands/` and `templates/common/commands/` are empty; the
Rust README says "The skills are wired" (no commands). The Rust level-3
scripts do not type a slash command: `tests/rust/smoke-test.sh:32` types
`"onboard the crate mycrate with creusot-launch, then analyze it with
creusot-monitoring"`, and `tests/rust/sudo-rs-test.sh:155-159` appends
"before ending every turn, if `$(date +%s)` is below `$DEADLINE`, call
`ScheduleWakeup` with `delaySeconds` 300 …" — the heartbeat is a Claude Code
tool name in the test's own prompt. Under `HARNESS=opencode` that sentence is
meaningless and no watchdog exists; `harness_confirm` greps
`creusot-monitoring`/`creusot-launch` (`sudo-rs-test.sh:173`,
`smoke-test.sh:56`), not `time-loop`.

So: the "campaign entry point" row ("the slash command `/time-loop <dir> N`")
is false for Rust projects on every harness; the heartbeat row describes only
the C skill; §2 step 6 ("The commands are the same: `/time-loop`, `/rmf` or
`/fips`, `/ebios`") does not hold for a Rust project; §7 step 2 ("re-invoke
`/time-loop <dir> N`") has no Rust form; and the Copilot entry-point debate
(§5, §9 point 1) ignores that a prompt entry point is already what the Rust
tests do — which is a strong argument for the `-i` prompt route.

**Fix.** Add a short §1.3 "Two campaign shapes": C — `/time-loop` command +
skill with its own heartbeat paragraph; Rust — a prompt that names the skills,
with the heartbeat sentence supplied by the prompt. State that under
OpenCode a Rust campaign currently has **no heartbeat** (a required fix, or
an accepted limitation: say which), and that the Copilot entry point will be
the Rust shape for both languages if `-i` wins. Give the entry-point and
heartbeat rows two values each (C / Rust). Fix §2 step 6 and §7 step 2.

### M3. K2 under `persisted` is specified two incompatible ways, and the oracle it needs is not provisioned (§1.1 lines 89–94; §4.4 lines 262–277; §8.2 test 5)

**What is wrong.** §1.1: "K2 has no pattern to grep and is replaced by the
check of §4.4." §4.4: "the access token read from OpenCode's store at the end
of the run (by the test, never printed) does not occur in those three
places" — that *is* a pattern grep, with the pattern taken from the store.
Beyond the contradiction, the implementer has no way to do it: the store is a
SQLite database of **unverified** schema; `sqlite3` is not in either
`provision.sh` apt list (`tests/c/provision.sh:64-69`,
`tests/rust/provision.sh:56-58`); the database path "follows the release
channel and `OPENCODE_DB`" and is printed by `opencode debug paths`
(https://opencode.ai/docs/cli/), so the hard-coded
`~/.local/share/opencode/opencode.db` of `harness.sh:167,399` may be wrong
for a non-default channel. Also, `secret_k2` greps `~` (`secret.sh:108`), so
"the scan excludes OpenCode's data directory" needs an explicit
`--exclude-dir`, and the exclusion must also cover `opencode.db-wal` and the
`state`/`cache` paths `debug paths` lists.

**Fix.** Pick one: (a) `persisted` ⇒ K2 is `skip`ped with the note "the
credential rests in the harness store by design (§4.4)" and §4.4 shrinks to
the policy text; or (b) specify the oracle: `sqlite3` added to both
provision scripts, the query (or "settled by the spike, §4.5"), the path from
`opencode debug paths`, and the exclusion list. Make §1.1 and §4.4 say the
same thing and point test 5 at it.

### M4. Two Copilot data paths are open by default and the spec's data-handling list and test 10 miss them; `--secret-env-vars` is overstated (§1 "credential" cell line 51; §6 "Data handling" lines 377–383; §8.2 test 10)

**What is wrong.**
- `copilot --help`: `--disable-builtin-mcps` — "Disable all built-in MCP
  servers (currently: github-mcp-server, githubiq)". The GitHub MCP server is
  on by default and uses the signed-in credential; with `--allow-all-tools`
  the agent can call it. It is a write path to GitHub (issues, PRs, gists via
  the API) that `/delegate`, `/share`, `--share-gist`, `/remote` do not
  cover.
- `--sync-session[=on|off]` — "read-only account history sync for this run
  only (omitted: use configured/default behavior)". Whether session content
  is synced to the account by default is **unverified**; the launcher should
  pass `--sync-session=off` rather than rely on the default.
- The `--secret-env-vars` help text continues: "a value that reaches a tool
  result another way still goes to the model and is saved in the session
  history". The §1 cell and §5 say it "removes the variable … so the agent's
  shell and MCP servers do not inherit it" and call this "stronger than
  Claude's token": true for the environment, but the token can still land in
  `~/.copilot` session history, which is exactly what K2 greps. Say so.
- Test 10 ("no secret gist, no `/delegate` PR and no remote session was
  created") has no oracle: a PAT with only the "Copilot Requests" permission
  cannot list gists or PRs, and the test has no other token. The cheaper
  guarantee is structural: that PAT cannot *create* them either
  (**unverified** that `/delegate` and `--share-gist` fail cleanly without
  `gist`/`contents`/`pull_requests` permissions).

**Fix.** Launcher flags for every Copilot run: `--disable-builtin-mcps
--sync-session=off --no-ask-user --secret-env-vars COPILOT_GITHUB_TOKEN
--max-ai-credits N --usage-output-file F`. Test 10 becomes: the launcher
passes those flags (unit test), the PAT is fine-grained with "Copilot
Requests" only (documented in `tests.md` §7.1, not testable), and the
transcript contains none of `/delegate`, `/share`, `/remote`, `--share-gist`.
Reword the `--secret-env-vars` sentence with the help text's caveat.

### M5. `harness_stop` and test 2 cannot be implemented as written (§3.2 point 2 lines 176–185; §8.2 test 2; §1 heartbeat cell line 57)

**What is wrong.**
- `pkill -f time-loop-watchdog` matches the watchdog only because the string
  `.time-loop-watchdog.stop` happens to be inside the `bash -c` argument
  (`SKILL.md:976`). Run through `autowp_exec_user` the command arrives as
  `sh -c '… pkill -f time-loop-watchdog'`, whose own command line matches:
  `pkill` excludes itself, not its parent, so the wrapper dies and the exit
  status is noise.
- Killing the loop does not kill an in-flight `opencode run` child, whose
  cycle can last longer than test 2's 10 minutes; test 2 would fail on a
  correct implementation.
- The cell states "re-invoking `opencode run --standalone`" as a fact. The
  CLI page shows `--standalone` only on bare `opencode`
  (https://opencode.ai/docs/cli/: "`opencode --standalone` … runs with a
  private server"); for `run` it is **unverified**, as §3.2 point 1 half
  admits ("the alternative is `opencode service set disabled true`", which
  the same page documents: "disables automatic use of the shared service and
  stops the running one").

**Fix.** The skill arms the watchdog with a name and a pidfile
(`exec -a time-loop-watchdog bash -c …`, `echo $! > .time-loop-watchdog.pid`,
both gitignored); `harness_stop` touches the stop file, kills the pid from the
pidfile and then any `opencode run` child of it, and waits up to 60 s. Test 2
checks "no process named `time-loop-watchdog` and no `opencode run` 60 s
after `harness_stop`". Mark `opencode run --standalone` **unverified** and
make `service set disabled true` the default fix, since it is documented.

### M6. The Copilot watchdog is specified by flags, not by a design, and test 11 has no oracle (§1 heartbeat cell line 57; §5 step 3; §8.2 test 11)

**What is wrong.**
- `--session-id <id>` "Resume an existing session or task by ID, or set the
  UUID for a new session". The cell wants "a stable id" across wakes. If the
  campaign's interactive `-i` session is still open in tmux (hung, which is
  the case the watchdog exists for), a second `copilot -p --session-id <same>`
  attaches to the same session; what happens is **unverified**. The OpenCode
  design avoids this by starting a *new* session per wake (`SKILL.md:985`).
- `copilot help limits`: "Usage accumulates across the entire session … In
  non-interactive prompt runs, usage accumulates across the whole run." With
  a stable id the cap spans wakes; with a fresh session it is per wake. The
  spec sets `--max-ai-credits` "for every Copilot run" without saying which
  scope it means or what `N` is.
- "The watchdog tells exit causes apart: a reached credit limit or an expired
  PAT stops it, a network error retries" — by what? The help documents no
  exit codes for `-p`; `--output-format json` gives JSONL events and
  `--usage-output-file` a JSON summary, both **unverified** as to content.
  Test 11 cannot be coded until one of these is chosen.

**Fix.** Decide: one session per wake (`-n time-loop-wake-<epoch>`), the
interactive session only for the first cycle; `--max-ai-credits` per wake
with a per-campaign total enforced by the watchdog summing
`--usage-output-file`. For the exit-cause oracle, name the candidate
(`--output-format json` final event, or the usage file) as spike step 3's
deliverable, and phrase test 11 as "the watchdog stops after the limit event
recorded in `<file>`".

### M7. §6 and test 7 still carry a legacy-billing concept, and the Free-plan statement conflicts with OpenCode's page (§6 "Copilot via OpenCode" lines 358–362, "Cost" lines 363–376; §8.2 test 7)

**What is wrong.**
- Test 7: "completes without a fallback to an included model". "Included
  models" belong to the legacy premium-request scheme. Under AI credits the
  docs describe exhaustion as: upgrade, "keep working by setting a budget for
  additional usage", or wait for the reset; additional usage "may be capped"
  (https://docs.github.com/en/copilot/concepts/billing/usage-based-billing-for-individuals).
  No model fallback is described. So the criterion tests nothing on the
  current scheme.
- The same page gives figures §6 lacks: Pro $10 — 1,500 credits (1,000 base +
  500 flex); Pro+ $39 — 7,000; Max $100 — 20,000; "1 AI credit = $0.01 USD";
  consumption per input/output/cached token at per-model prices; the Copilot
  CLI is billed in AI credits from version 1.0.48. §6 should quote these in
  place of "record which scheme the test account is on".
- §6: "Copilot Free is not supported" (from the 2026-01-16 changelog, which
  lists "Pro, Pro+, Business, or Enterprise" and does not mention Free —
  verified). But the OpenCode providers page says the account "needs Copilot
  Chat access" and, if GitHub reports no entitlement, to "sign up for Copilot
  Free or have the organization assign a seat, then connect again"
  (https://opencode.ai/docs/providers/). The two sources disagree; the spec
  should say so rather than pick one.

**Fix.** Test 7 → "the run ends on deadline or terminus, not on a credit
limit (M6's oracle), and the credits used are recorded; cost ≤ the budget
stated in `tests.md`". Replace the Cost bullet's first half with the figures
above and keep the legacy footnote. Rewrite the Free sentence as "the
changelog names paid plans only; OpenCode's page suggests Free may connect;
**unverified** which is current".

### M8. The "specified, not yet implemented" list is incomplete, and §8.1 files OpenCode's own fixes under "Route A" (header lines 31–34; §1 lines 63–72; §8.1 lines 413–427)

**What is wrong.**
- Header: only `HARNESS_CREDENTIAL`, the unknown-harness check and the
  Copilot rows are declared unimplemented. Also unimplemented, but written
  in the present tense: the skill paragraph "Primitives on each harness"
  (§1 line 67 "which this revision extends to" — `SKILL.md` still has only
  "The heartbeat on each harness", line 964, and no sub-agent or entry-point
  bullet); the `.gitignore` entry (`templates/{c,rust}/tools/.gitignore` have
  no `.time-loop-watchdog.stop`); the README wording (`templates/*/README.md`
  still say `auth.json`, lines 263/271, and do not say "API key, not a
  subscription login"); `tests.md` §3.5 "120 s" and §7.1 `auth.json`.
- §8.1 has two columns, Route A and Route B, but the first column holds the
  §3.2 OpenCode fixes (watchdog `--standalone`, `harness_stop`, `.gitignore`,
  timeout message, `tests.md` §3.5) and the §1 generic items (tests 4 and 6,
  the `test_harness.py` row). An implementer doing Route B only, as §5
  recommends, would read the OpenCode fixes as optional. They are not: they
  fix the harness that is "implemented".
- The `.gitignore` row names `auto-wp.py`; the file is copied from
  `templates/{c,rust}/tools/.gitignore` (`auto-wp.md` §4.2: "a `.gitignore`,
  written for auto-wp"; output line "copied foobar/.gitignore"), and its
  content is pinned in `tests/test_templates.py`/`test_auto_wp.py`.

**Fix.** Header: "not yet implemented: everything in §1.1, §1.2, §3.2, the
skill paragraph of §1, and the Copilot column". §8.1: three columns —
"OpenCode now (§3.2, §1)", "Route A", "Route B/B′" — and move the
`.gitignore` item to the two template files. Change line 67 to "must be
extended to".

## Minor

- **m1 (§4.2 line 232).** `COPILOT_CONNECT=1` appears nowhere else: not in
  the §1 table, §1.1, §8.1 or §8.2. What `HARNESS_CREDENTIAL=persisted`
  without it means is undefined. Fold it into `persisted` or define it. Also
  say the pre-step is idempotent (acceptance `restart`/resume call
  `harness_start` again on the same container, `acceptance.sh:142-146,
  246, 274, 284`) and that the pre-step's TUI must use the same server mode
  as the campaign (`--standalone` vs the shared service) so both read the
  same store — **unverified** that they do.
- **m2 (§1 "install, test route", line 47).** "The same push" holds for the
  standalone binary only: the host's `~/.local/bin/copilot` is a 205 MB
  dynamically linked x86-64 ELF (`file`), so `lxc file push` works as for
  Claude Code; an `npm install -g @github/copilot` host has a Node package
  instead, which cannot be pushed. Say "the standalone binary from
  `gh.io/copilot-install`; the npm install is not supported by the test
  route". For the README route, Ubuntu 24.04 has no Node ≥ 22, so the
  container quick start should name the script, not npm.
- **m3 (§1 "campaign entry point", line 49; §1 definition (c), line 40).**
  "so the test types nothing" contradicts "(c) … a command typed into its
  input box". `harness_write_launcher` takes no command
  (`harness.sh:37-73`); `harness_start` types `$cmd` after the prompt
  appears (`harness.sh:157-159`). Specify that under `copilot` the launcher
  receives `$cmd` as the `-i` argument and step 3 is skipped, and that
  `harness_confirm` greps the skill name in the `-i` session's transcript
  (location **unverified**, §9 point 7).
- **m4 (§5 "Route B′", lines 327–335).** `copilot help providers`: "A model
  is required for BYOK. Set `COPILOT_MODEL`, `COPILOT_PROVIDER_MODEL_ID`, or
  `--model`." The paragraph does not mention it. Also list
  `--secret-env-vars COPILOT_PROVIDER_API_KEY` for this route, and note
  `COPILOT_PROVIDER_API_KEY_COMMAND` ("a shell command that prints a fresh
  API key for each provider request") as the way to keep the key out of the
  environment entirely.
- **m5 (§8.1 `secret.sh` row).** The default `AUTOWP_TOKEN_FILE` for
  `copilot` is not named (e.g. `~/.config/auto-wp/copilot-pat`); `secret.sh`
  needs it (`secret.sh:19-22`) and the credential hint text too
  (`secret.sh:30-34`). `copilot login --help` confirms the token types:
  "fine-grained personal access tokens (v2 PATs) with the 'Copilot Requests'
  permission … Classic personal access tokens (ghp_) are not supported" —
  worth one sentence in §5.
- **m6 (§2 step 3 vs §6).** §2 states "Anthropic's terms reserve the
  subscription for its own clients" as fact; §6 says the claim is from
  secondary sources and **unverified**. Add "(§6, unverified)" to §2.
- **m7 (§1 "transcript" OpenCode cell; §3.2 point 3).** Use `opencode debug
  paths` (documented) to locate the database instead of the hard-coded path,
  and say the K3 allowlist (`harness.sh:319`) must follow the same paths.
- **m8 (§1 "sub-agent spawn" Copilot cell).** `copilot help commands` also
  lists `/subagents` ("Configure default and per-agent subagent models") and
  `/autopilot … with an optional AI-credit limit (--max-ai-credits)`; the
  first is a hint that sub-agents are first-class, the second that the cap
  can be scoped to an autopilot objective. Add both to the spike list.
- **m9 (§8.2 test 10, last clause).** "`.github/hooks` is absent from the
  project" belongs with the trust row (test 9 or a level-1 template test),
  not with data handling.
- **m10 (§6 "Data handling").** Add `--disable-builtin-mcps` and
  `--sync-session=off` here as well as in the launcher (M4), so the policy
  and the mechanism are in one place.

## Editorial

- **e1 (§1 table).** The Copilot column's cells run to 60–90 words; the
  table is unreadable as plain text and duplicates §5. Keep each cell to a
  phrase and a section reference; move the verified flags into §5 as a
  "Launcher flags" list (which M4/M6 need anyway).
- **e2 (§3.3 vs §9 point 5; §3.2 point 3 vs §9 point 3).** Each pair says
  the same thing twice. Keep the §3 text and make the §9 entry one line.
- **e3 (header line 22).** "(the cells were first written against 1.0.105)"
  is history, not specification; drop it.
- **e4 (§4.5 and §5 "Which route first").** §4.5 says Route A "stays
  proposed until one spike has run"; §5 says "Run Route B's spike first" and
  §9 point 10 says Route B's spike "decides whether Route A stays the
  fallback or is dropped". Three places state the ordering; one decision
  sentence in §5 and references elsewhere.
- **e5 (§8.2).** Tests are numbered 1–11 and cited by number from §1, §3, §6;
  B1 adds a level-1 test. Number it 0 to keep the citations stable, or
  renumber everywhere.

## Open questions for the author

1. **Skill descriptions.** Will the templates be brought under the Agent
   Skills limits (1024-character description, strict YAML) for every skill,
   or will a Copilot-specific shortened copy be generated? The first keeps
   "the skills live once in `config/`" true; the second breaks it.
2. **Rust under OpenCode.** Is a Rust campaign without a heartbeat an
   accepted limitation of the "implemented" status, or a required fix like
   §3.2? If a fix: an external watchdog armed by the test prompt, or by
   `harness_start`?
3. **Support rule.** Does the author want rule (a) — inline verifier
   permitted, OpenCode supported now — or rule (b) — OpenCode unsupported for
   `/time-loop` until the `subagent` tool is verified (M1)?
4. **K2 under `persisted`.** Skip with a note, or read the token out of
   `opencode.db`? The second needs `sqlite3` in the base and a schema
   (M3).
5. **Copilot watchdog sessions.** One session resumed across wakes, or one
   per wake? This fixes the meaning of `--max-ai-credits` and the shape of
   test 11 (M6).
6. **Budget.** What is the AI-credit budget of one 96-hour run the tests
   should assume, now that the figures are known (Pro 1,500; Pro+ 7,000; Max
   20,000; 1 credit = $0.01)? Which plan does the test account have?
7. **Built-in GitHub MCP.** Disable it for every Copilot campaign (M4), or is
   there a use for it (e.g. filing the Frama-C bug reports of the terminus)?
8. **`.claude/commands` as Copilot skills.** Since the CLI loads them by
   name, is `/time-loop <dir> N` typed into the Copilot TUI worth one
   spike step before committing to the `-i` prompt?
