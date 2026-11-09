# Copilot prerequisite evidence and pending runtime spike

Date: 2026-11-09. **This is not a completed P1 spike or a P2 route decision.**
The user chose "Keep Copilot gated; finish the local implementation".
No authenticated model session, paid wake loop or campaign was started.

## P0: observed

On the host, with GitHub Copilot CLI 1.0.107:

```sh
python3 auto-wp.py --c --harness none <temporary-c-project>
python3 auto-wp.py --rust --harness none <temporary-rust-project>
# In each project, with a fresh temporary COPILOT_HOME:
COPILOT_AUTO_UPDATE=false copilot skill list --json
```

Both discovery commands exited 0 with empty stderr. C listed 25 enabled
project entries: all 23 manifest skills plus the non-colliding `rmf` and
`ebios` commands. Rust listed all 18 installed skills (`creusot-launch` is
still absent). In both projects `time-loop` resolved to
`.agents/skills/time-loop`, not `.claude/commands/time-loop.md`.

The host's standalone Copilot binary was also pushed to `/usr/local/bin`
in a fresh Ubuntu 24.04 amd64 LXD container. `copilot --version` reported
1.0.107 and `copilot skill list --json` exited 0 in a generated C project,
without a token or a model request. The container was deleted afterwards.
This does not establish arm64 support or authenticated startup.

## P1 cells

| Cell | Result |
|---|---|
| a: TUI/prompt entry point and transcript proof of loading | Not determined: no model session authorized. Discovery alone does not prove execution. |
| b: verifier report read-back and stop | Not determined: requires a live agent session. |
| c: 30-minute loop, limits/auth/network exit causes | Not determined: no paid run or credit budget authorized. |
| d: input marker and transcript format/location | Not determined: no interactive campaign session. |
| e: persistent trust and suppression of dialogs | Not determined: skill listing is not interactive startup. |
| f: hooks, MCP and sync behavior | Templates ship no `.github/hooks`; live flag behavior not determined. |
| g: standalone binary | Runs and discovers C skills on Ubuntu 24.04 amd64; arm64 not tested. |
| h: available models and credits | Not determined: no authenticated request. |

P2 remains blocked. `--harness copilot`, `HARNESS=copilot` and persisted
credential mode remain rejected; no route is silently substituted.

## OpenCode prerequisite checks

The C and Rust level-2 install suites passed under `HARNESS=opencode`.
Host tests exercise selection, manifest mismatch, YAML limits, custom
database paths/WAL, separate configuration files, inherited watchdog
credentials, duplicate-start prevention, stale pidfiles and process-tree
shutdown without sending requests to a model.

An installer check found that `https://opencode.ai/install` installed
1.19.5, which rejected `opencode service set disabled true`. The generated
installer and README now use `https://opencode.ai/v2/install`. A repeat in
a fresh container installed OpenCode 2.2.6 and Claude Code 2.1.319 as root
under `/opt/autowp/`, then successfully ran both as `ubuntu` through
`/usr/local/bin`. The service-disable command succeeded with V2. This was
not a full Workshop/toolchain launch or an OpenCode campaign.
