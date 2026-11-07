# Copilot-focused feedback on `spec/choose-harness.md`

Reviewed on 2026-11-07 against `spec/choose-harness.md` (the revision that
applies `choose-harness-feedback.md`), `tests/lib/harness.sh`,
`templates/c/skills/time-loop/SKILL.md` (§ "The heartbeat on each harness"),
`templates/c/commands/time-loop.md`, and the host's GitHub Copilot CLI
**1.0.107** (`copilot --help`, `copilot help {environment,commands,billing,
limits,providers}`, `copilot skill --help`, `copilot plugin --help`).
The earlier review covered the OpenCode path and the credential modes; this one
looks at what the Copilot sections (§1 column, §4, §5, §6, §9) say, against what
the CLI shows today. Statements marked **checked** were read in the CLI's own
help; the rest are my inference.

## Summary verdict

The structure is sound: one table, one "primitives" paragraph per skill, a
recommended Route A, a sketched Route B. The Copilot column is now mostly
accurate but **stale in four places** that change decisions, and **Route A is
recommended on weaker grounds than the text admits**. Route B is closer to
viable than the "sketch" status says, and the CLI offers two things the spec
does not consider (BYOK, `--max-ai-credits`).

## Findings that change a decision

### C1. §6 premium-request arithmetic is on the wrong billing model

**Checked.** `copilot help billing` says usage is measured in **AI credits**,
with premium requests only "on the legacy billing platform"; the footer shows
`Session: N AIC used`, `/usage` shows per-session credits, and `/model` shows
per-token prices. §6 builds its conclusion ("exhausts a Pro allowance in one
run; needs Pro+") on 300/1,500 premium requests and a per-prompt count, and
calls the current scheme "unverified".

**Fix.** Rewrite the bullet: a campaign's cost is token-based, not
per-prompt, so "wakes × prompts" is not the estimator. Record the scheme the
test account is on, and have test 7 record `AIC used` (Route B:
`--usage-output-file`, **checked**; Route A: whatever OpenCode exposes, or the
account's billing page) rather than a premium-request count. Keep the legacy
calculation as a footnote.

### C2. A budget guard exists and the spec does not use it (Route B)

**Checked.** `--max-ai-credits <n>` (minimum 30, soft cap, subagents share
it, blocks the next model call when exceeded) and `--usage-output-file`.
For a 96-hour unattended run on a metered account this is the missing safety
rail, and it has no OpenCode equivalent in the spec.

**Fix.** Add a row "spend limit" to the §1 table (Claude Code: none;
OpenCode: none known; Copilot: `--max-ai-credits`) and require the test
harness to set it for Copilot runs. Note the interaction with the watchdog:
once the cap is hit every re-invocation fails the same way, so the watchdog
must treat "limit reached" as a stop, not a retry (see C6).

### C3. Route B's blocking unknown (slash commands) is half-answered, and the answer is better than "none"

**Checked.** `copilot help commands` lists no project-defined commands; skills
are found in `.github/skills/`, `.agents/skills/`, `.claude/skills/` (the
generated project already links the last two), and **plugins** can bundle
"skills, agents, hooks, MCP servers, and LSP servers" (`--plugin-dir`,
`copilot plugin install`). `/skills` is an interactive command.
**Unverified**: whether a skill can be invoked as `/<skill-name>`; whether a
plugin can add a slash command.

The spec offers two entry points (a prompt, or a generated
`.github/agents/time-loop.agent.md`) and asks `auto-wp.py` to add a
`.github/` layer. A third is cheaper and keeps projects harness-neutral:
**the test types a prompt**, `-i "<prompt>"` (**checked**: "start interactive
mode and automatically execute this prompt") removes even the tmux typing
step. Put this first in §9 point 1; keep the agent file as the fallback, and
make the spike's first question "does `/time-loop` or `/skills` invoke the
skill by name?". Also make `harness_confirm` for Copilot match the skill
load, not `<command-name>`.

### C4. The "delegation barrier" has a Copilot candidate that the spec treats as unknown

**Checked.** The CLI has `/tasks` ("subagents and shell commands"), `/fleet`,
`--fleet`, `--agent <agent>`, and `/delegate` (hands the session to the cloud
agent, which opens a PR — *not* a sub-agent in the sense of the barrier, and a
data-handling issue, see C7). The table's "background task + stop" cell says
**unverified** for Copilot; `/tasks` is the likely stop mechanism for a verifier
past its time box. This is still a spike item, but name `/tasks` and
`.github/agents` as the primitives to try, so the spike has a target rather
than "find out".

### C5. Route A is recommended, but its credential risk is understated

§5 says Route A is recommended because it "reuses the OpenCode path". Two
costs weigh against it and should be in that paragraph:

- It is the only route with **no unattended-credential story** for 96 hours
  (§9 point 4) and it must leave a live OAuth token in the container
  (§4.4), which the agent can read.
- Route B's `file` mode needs **no new credential machinery**: a PAT in
  `AUTOWP_TOKEN_FILE`, exported as `COPILOT_GITHUB_TOKEN` (**checked**, takes
  precedence over stored credentials), keeps K2 and the stream-and-delete
  discipline intact, and the PAT has a real expiry that
  `secret_check_expiry` already handles.

My recommendation is the reverse of §5's: **do Route B's spike first**. If
the entry point and sub-agent questions resolve favourably, Route B is less
code (no connect pre-step, no `persisted` K2, no OpenCode watchdog fixes as
prerequisites) and has the better security posture. Route A remains the
fallback if Copilot's headless mode cannot carry a long loop. At minimum,
state the trade-off both ways instead of "recommended".

## Smaller corrections

- **C6. Heartbeat for Route B.** The table's "none visible in `--help`:
  external watchdog with `copilot -p … --continue`" is right, but note two
  checked flags that change the watchdog: `--session-id <id>` (a stable
  session across wakes, better than `--continue`, which resumes "the most
  recent" and can pick the wrong one if two projects share `COPILOT_HOME`)
  and `--max-autopilot-continues` (default **5**, so `--autopilot` alone
  stops after five continuations, not at the deadline). The watchdog must
  also distinguish exit causes (credit limit, expired PAT, network) and stop
  on the first two. `--no-ask-user` (**checked**) should be set so a headless
  turn cannot block on a question form.
- **C7. Data handling (§6).** Add that `/delegate`, `/share`, `--share-gist`,
  and `/remote` send the session or its content to GitHub; the campaign
  prompts must never invoke them, and the tests should assert no gist was
  created. `--secret-env-vars` (**checked**) removes named variables from
  shell and MCP environments; if the PAT is exported as
  `COPILOT_GITHUB_TOKEN`, list it there so the agent's shell cannot read it
  (this is a stronger K2 than Claude's, whose token the agent can read).
  The spec's "the CLI redacts the values in its output" is weaker than this
  and should be replaced by the option.
- **C8. Trust cell.** `--trust-folder` is **one prompt-mode session only (no
  saved trust)**, so it fits `-p` but not an interactive tmux session;
  `COPILOT_ALLOW_ALL=true` ("exactly `true`") also trusts the directory and
  **loads its hooks, which can run shell commands**. State both: the tests
  want the second for tmux, and the generated project must not ship
  `.github/hooks` that a "trusted" run would execute.
- **C9. BYOK is a third Copilot-CLI credential route.** **Checked**:
  `COPILOT_PROVIDER_BASE_URL/TYPE/API_KEY` (types `openai`, `azure`,
  `anthropic`), with `COPILOT_OFFLINE` available. This sidesteps the plan,
  premium-request and Copilot-policy constraints of §6 and the OAuth-in-a-
  third-party-client problem of the Claude bullet (it is an API key). Add it
  as Route B′, or at least list it in §9; it also gives the tests a
  deterministic, billable path when no paid Copilot seat is available.
- **C10. Install row.** Version pinning is documented (`COPILOT_AUTO_UPDATE=
  false`, `--no-auto-update`; **checked**), and auto-update is off by default
  in CI environments; say that the test route sets it explicitly rather than
  relying on CI detection. The host's version is now 1.0.107; the header says
  1.0.105 — update, or say "1.0.105 and later" after the spike.
- **C11. Prompt regex row.** Still "**unverified** (spike)". Since the
  tests can start with `-i`, `HARNESS_PROMPT_RE` is only needed for the
  *idle* check; consider using `COPILOT_MULTIPLEXER=tmux` (**checked**) to avoid
  the CLI guessing wrong inside the harness's nested tmux.
- **C12. Transcript row.** `--share <path>` (non-interactive) writes a
  Markdown transcript and `--output-format json` gives JSONL
  (**checked**), so under `-p` the transcript oracle exists and the
  `harness_confirm` greps can run on a file the test chose, not on
  `~/.copilot` internals. For interactive tmux runs it is still open.
- **C13. §1.2 test 4** names `copilot` as "rejected until Route B lands". Once
  Route B has a spike result, a *positive* test is needed (the harness
  accepts `copilot` and writes the right launcher); add it to §8.2 so the
  rejection test and the acceptance test are a pair.
- **C14. Review-reference line.** The header says "this revision applies" the
  earlier review; `tests/lib/harness.sh` still has the 120 s message at
  line 152 and no `HARNESS_CREDENTIAL`. That is expected for a spec, but say
  "specified, not yet implemented" next to §1.1/§1.2 so readers do not assume
  the scripts already behave that way.

## Suggested order of work

1. Spike Route B (entry by `-i`, skill load check, `/tasks` and
   `.github/agents` for the delegation barrier, a 30-minute `-p` loop with
   `--session-id`, `--max-ai-credits`, `--usage-output-file`).
2. Rewrite §6 for AI credits (C1) and add the spend-limit row (C2).
3. Decide Route A vs B from the spike (C5), then trim the other to a
   paragraph.
4. Add BYOK to §9 (C9) and the security items of C7/C8 to §6 and §8.2.
