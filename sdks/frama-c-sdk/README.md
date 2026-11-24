# frama-c-sdk SDK

The Frama-C toolchain auto-wp's C campaigns run: Frama-C 32.1 (Germanium)
built from source with auto-wp's `frama-c-patches`, the `macsl` plugin, Why3
1.8 with its Coq 8.20.1 realizations, Alt-Ergo and Z3, in a read-only opam
switch. Build it with `make sdk-framac` from the auto-wp repository.

> Alt-Ergo 2.6.4 is bundled under the OCamlPro Non-Commercial Purpose License
> (research use only); see `share/licenses/alt-ergo/` in the SDK.

## Query WP results with framac-mcp

`framac-mcp` is a read-only MCP query surface over the Frama-C/WP property
database (`spec/frama-c-mcp.md`). The SDK's `setup-base` hook installs it into
a pinned venv, and `/etc/profile.d/frama-c-sdk.sh` puts it on `PATH` and
exports `FRAMAC_MCP_BIN=/opt/frama-c-mcp/venv/bin/framac-mcp`.

To register it with Claude Code inside the workshop:

```bash
workshop shell
claude mcp add --transport stdio --scope user frama-c -- "$FRAMAC_MCP_BIN"
```

To register it with OpenCode instead (the same user scope, written to
`~/.config/opencode/opencode.json`):

```bash
opencode mcp add frama-c --global -- "$FRAMAC_MCP_BIN"
```

The server is stdio and reads its report directory from the environment, so
export `FRAMAC_MCP_REPORTS` the same way for both harnesses.

Point it at the directory holding WP's JSON reports with
`FRAMAC_MCP_REPORTS`; each tool resolves a report from an explicit `run`
argument or the newest `*.json` there. The `frama-c-monitoring` skill then runs
its MCP-first workflow and degrades to the scripted path when the server's
`wp_status` canary is unavailable.

**Current state (Mode A).** The venv installs the standard-library Mode A
reader over `-wp-report-json` (goals keyed by the `(file, function, property,
line)` tuple, not the renumbering WP goal name): `wp_status`, `wp_remaining`,
`wp_goal`, `wp_locate`, `wp_provenance`, `wp_diff`. The live Frama-C Server
tools (`wp_query`, `wp_property`) return a structured "live server unavailable"
error pending the Server-protocol request schema (open point O-1); the
`check-health` hook probes for the `server` plugin. See
[`mcp/MANIFEST.md`](mcp/MANIFEST.md) for the implemented-vs-blocked breakdown.
