# Preface

Operational lessons for running the LXD container tests
(`tests/c`, `tests/rust`) and following a long campaign, distilled from the
Mbed TLS fips campaign of 2026-11-06..09. Read with `tests/README.md` and
`spec/tests.md`.

IMPORTANT: Read the `.kb/agents.md` file.


# Laws

## §1 - Drive the container through stdin

Never pass nested `$variables` inside `bash -c '…'` over `lxc exec` — the
host-side expansion eats them silently and every fact comes back empty.
Write the inner script through stdin (`lxc exec … bash <<'EOF'`) or pipe it
with `printf … | lxc exec … bash`. Two agents lost an hour to this
(agent-check.sh read `verdicts.tsv` as "empty" for a day).

## §2 - Never pkill -f a self-matching pattern

`pkill -f "mbed-tls-test.sh"` matches the calling shell's own command line
and kills it (and with it, background drivers). Select the exact PID with
`pgrep` first, then `kill` it explicitly.

## §3 - The mbed-tls test keeps its artifacts by default

`KEEP=${KEEP:-1}` in `tests/c/mbed-tls-test.sh`: the container (or the
workshop and its project under `~/.awp/`) survives the run so the FIPS
documents can be read. `KEEP=0` restores delete-on-exit; `make clean-lxc`
sweeps leftover `autowp-*` containers.

## §4 - Interrupting the test driver does not stop the campaign

The campaign lives in the container's tmux session and continues after the
driver dies (KEEP keeps the container). Run the end-of-run checks against
the kept container with
`CHECK_ONLY=1 CT=<container> tests/c/mbed-tls-test.sh`.

## §5 - Budget generous timeouts for K2

K2 (the token-leak scan) greps the whole home and project tree, which grows
with every cycle (patches, scratch, `.git` objects). The scan outgrew 570 s
by day 3 — background the check-only run instead of bounding it.


# Concepts

## Harness selection and watchdog ownership

The test drivers pass `HARNESS` through to `auto-wp.py --harness`; launch
checks the generated manifest before consuming a credential. Copilot and
persisted credentials are deliberately gated on the live spike, not
aliases for Claude. `none` is generation-only.

Since 0.8.0, every automated generator call must supply `--c` or `--rust`,
`--harness` and the target directory. There is no implicit C or Claude.
Missing choices prompt only when both stdin and stderr are terminals;
`lxc exec` scripts and redirected commands fail immediately instead.
`ws_generate` forwards the language and harness explicitly.

The OpenCode heartbeat is skill-owned in manual sessions and tests alike.
Both languages use `bin/time-loop-watchdog.py`, with a locked pidfile and
process-start identity. Stop it with the helper's `stop` action before
closing tmux; deleting only the tmux session leaves detached wakes alive.
The shared OpenCode service must be disabled so wakes inherit the key.

Use `https://opencode.ai/v2/install` for the specified V2 harness.
The legacy `/install` endpoint installs V1, which cannot run the
`service set disabled true` pre-step. Root installers use an accessible
HOME under `/opt/autowp/` and link to `/usr/local/bin`, not into `/root`.

## Harness prompt regex (Claude Code)

Since Claude Code 2.1.3xx the input-box prompt char is followed by a
no-break space. Keep it as the ANSI-C escape
`$'(^|[│ ])(>|❯)( |\u00a0)|\\? for shortcuts'` — a literal NBSP pasted into
the file was silently lost through an edit once and M.1 failed for hours
(upstream commit d8ccdeb restored it the same escape way).

## OpenCode mechanics, verified 2026-11-09 (2.2.5)

Skills and commands are discovered through the `.opencode` links; the
default base policy let a bare `opencode run` write a file unprompted; the
TUI markers are `Ask anything…` / `shift+tab agents`; session text greps
out of `~/.local/share/opencode/opencode.db` with `grep -a`;
`opencode run -m provider/model 'prompt'` runs headless; no Agent-Skills
description-length limit is enforced (unlike Copilot CLI, which rejects
descriptions over 1,024 chars).

## Unattended-campaign monitoring stack

Three layers: the campaign's own heartbeat (wakes in `time-loop.state`),
a host-side 5-min watchdog answering permission prompts from the pane, and
a 30-min cron spawning an `opencode run` agent whose verdicts append to
`~/.local/share/auto-wp/agent-status.md`. Cron PATH needs `/usr/sbin`
(`lxc` lives there) and the agent model must be pinned to one with tool
support (`opencode run -m openrouter/z-ai/glm-5.3-flash`).

## Checkpoint labels lag the state log

The loop names each checkpoint after the cycle whose work it carries and
pushes it at the start of the next cycle, so state cycle N's work sits in
the commit labelled N-1. M.6 verifies pushes by hash: every
`checkpoint <hash> pushed` entry in `time-loop.state` must exist in
`~/remote.git`.
