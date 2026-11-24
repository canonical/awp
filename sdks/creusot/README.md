# creusot SDK

The Creusot toolchain the auto-wp Rust skills expect: `cargo-creusot` and
`creusot-rustc` built at commit `f15b985`, the Rust `nightly-2026-08-03` they
need, Creusot's Why3 and `why3find` switch, Alt-Ergo, Z3, CVC4 and CVC5, and
the Creusot sources that `creusot-std` is patched to, in a read-only opam
switch.

> Alt-Ergo 2.6.4 is bundled under the OCamlPro Non-Commercial Purpose License
> (research use only); see `share/licenses/alt-ergo/` in the SDK.

## Query proof results with creusot-mcp

`creusot-mcp` is a read-only MCP query surface over the committed `why3find`
proof artifacts (`spec/creusot-mcp.md`). The SDK's `setup-base` hook installs
it into a pinned venv, and `/etc/profile.d/creusot.sh` puts it on `PATH` and
exports `CREUSOT_MCP_BIN=/opt/creusot-mcp/venv/bin/creusot-mcp`.

To register it with Claude Code inside the workshop:

```bash
workshop shell
claude mcp add --transport stdio --scope user creusot -- "$CREUSOT_MCP_BIN"
```

The `creusot`, `creusot-sl` and `creusot-monitoring` skills then run their
MCP-first workflow and degrade to the scripted path when the server's
`creusot_status` canary is unavailable.

**The MCP never banks a verdict and never edits source.** `cargo creusot` /
`verify.sh` remain the sole authority; the server only reads and summarizes the
artifacts they produce.

**Current state (Mode A).** The venv installs the standard-library Mode A
reader over the committed `proof.json` / `why3session.xml` / `verdicts.tsv`
(leaf `{prover, time}`, node `{tactic, children}`, a `null` leaf = failed):
`creusot_status`, `creusot_remaining`, `vc_goal`, `vc_tree`, `vc_provenance`,
`vc_locate`, `creusot_diff`. No prover and no Why3 process is ever spawned, and
every result carries `provenance` and respects the in-flight guard (the
summarizing tools refuse while a `why3find prove` run is active). The
interactive Why3 (Mode B) path is advisory only and returns a structured error
pending the version-lockstep open point (O-1). See
[`mcp/MANIFEST.md`](mcp/MANIFEST.md) for the implemented-vs-blocked breakdown.
