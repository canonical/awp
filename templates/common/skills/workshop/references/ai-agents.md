# Workshop and AI agents

## Documentation for agents

- <https://ubuntu.com/workshop/docs/llms.txt>: index of every page with a
  one-line summary.
- <https://ubuntu.com/workshop/docs/llms-full.txt>: every page concatenated
  as Markdown.
- Append `.md` to any docs page URL to get Markdown, e.g.
  `https://ubuntu.com/workshop/docs/reference/ai-agents.md`.
- Context7 indexes the docs at <https://context7.com/canonical/workshop> and
  serves them through its MCP server.

When this skill and the live docs disagree, the live docs win. Workshop and
SDKcraft change quickly.

## Upstream agent skills

<https://github.com/canonical/use-workshop-skill> provides three skills:

| Skill | Use when | Start with |
|-------|----------|------------|
| `use-workshop` | A definition exists and the agent should operate it | Mention Workshop in a prompt |
| `onboard-workshop` | A repository has no definition yet | `/onboard-workshop onboard <REPO-PATH>`, or `/onboard-workshop analyze` to stop at the verdict |
| `design-sdk` | You publish software as an SDK | `/design-sdk new <SOFTWARE>`; `/design-sdk` alone lists the other paths (`iterate`, `test`, `onboard`, `publish`) |

To install them in Claude Code:
`/plugin marketplace add canonical/use-workshop-skill`, then
`/plugin install use-workshop@canonical`. Without plugins, copy the skill
directories from the repository's `.github/skills/` into `.claude/skills/`.
Always copy `use-workshop/` as well, because the other two read its
references. In OpenCode, copying them into `.claude/skills/` also works —
it reads that directory for compatibility (or `.opencode/skills/`, which
this project links to the same `config/skills/`).

Behaviours worth copying from those skills:

- After every mutating command, verify with `workshop changes`,
  `workshop tasks` and `workshop info`.
- Before writing any file, `onboard-workshop` gives a feasibility verdict and
  proposes a definition whose **actions wrap the repository's existing entry
  points** (make targets, scripts, CI commands). Once approved, it writes
  `.workshop/<NAME>.yaml` plus any in-project SDKs, launches the workshop and
  runs every action inside it. It leaves the repository's own build files
  untouched.
- `design-sdk` first agrees on a design: the software, how upstream ships it,
  what must persist, network services and hardware, bases and architectures.
  Then it writes `sdkcraft.yaml`, the hooks and the spread tests, and
  iterates with `sdkcraft try` and `workshop refresh` until the SDK is
  healthy. It writes the README last. On request it adds version branches,
  CI, `renovate.json` and publishing.
- Parallel environments: one git worktree per task, each with its own
  workshop. Run git on the host.

## Agent SDKs

Coding agents are published as SDKs:

```bash
sdk find agent                   # e.g. claude-code, codex, copilot
sdk info claude-code             # check before use
```

Check the `publisher` field (`✓` verified, `✪` starred; `**` and `*` without
a UTF-8 terminal), the `license` (often the vendor's terms), the `website`
(where to review the SDK's hooks, plugs and README), and the `CHANNELS` table
(`--arch all` shows every architecture).

## Running commands as an agent

- Use `workshop exec [WS] -- CMD` for one-off commands, `workshop run [WS] --
  ACTION` for named actions, and `-I` to force non-interactive mode in
  scripts. Always use `--`, because without it the first word is taken as the
  workshop name.
- Pass `--timeout` (e.g. `--timeout 10m`) for long commands, and `-w` to
  choose the working directory.
- `--no-wait` on launch, refresh, restore, connect and similar commands
  returns a change ID; follow it with `workshop tasks <ID>`.
- Prefer actions in the definition to long ad-hoc `exec` lines, so humans and
  agents run the same commands.

## Security boundaries

A workshop limits an agent but does not replace its approval prompts:

- The **project directory is mounted read-write**, including `.git`. Hooks or
  `.git/config` written there run on the host the next time you use git. For
  unattended agents, use a separate clone and review the result.
- Subdirectories and worktrees do not narrow the mount.
- Everything runs as `workshop`, which has passwordless `sudo`, and SDK hooks
  run as root. An agent can read other SDKs' files and stored credentials.
- **Outbound network is unfiltered.**
- Connected interfaces extend its reach: `ssh-agent` (your SSH identities),
  `secret` (keyring items), writable host mounts (never mount an agent's own
  config directory from your home), `desktop`, tunnels to host services,
  `camera` and `custom-device`. Disconnect them before an autonomous run.
- The experimental VM runtime changes the kernel only. The project mount and
  the network stay open.
