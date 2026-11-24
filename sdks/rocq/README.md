# rocq SDK

Rocq 9.2.0 with its standard library and the `coq` compatibility binaries
(`coqc`, `coqtop`, `coqdep`), built from opam once at SDK build time into a
read-only switch. This is the environment the auto-wp `rocq` skill expects.
It is independent of the Coq 8.20.1 that `frama-c-sdk` ships for Frama-C's WP.

Rocq, `coqc`, `coqtop` and `coqdep` reach `PATH` from the SDK's read-only opam
switch via `/etc/profile.d/rocq.sh`. Users do not `opam install` into it.

## Inspect proofs with rocq-mcp

`rocq-mcp` is the vendored stdio MCP adapter for coq-lsp/Petanque
(`spec/rocq-mcp.md`). The SDK's `setup-base` hook installs it into a pinned
venv **outside** the read-only switch, and `/etc/profile.d/rocq.sh` puts it on
`PATH` and exports `ROCQ_MCP_BIN=/opt/rocq-mcp/venv/bin/rocq-mcp`.

To register it with Claude Code inside the workshop:

```bash
workshop shell
claude mcp add --transport stdio --scope user rocq -- "$ROCQ_MCP_BIN"
```

The `rocq` skill then runs its MCP-first workflow (`rocq_start`, `rocq_check`,
`rocq_step_multi`, `rocq_query`, …). The skill's capability table probes
`$ROCQ_MCP_BIN` and a canary `rocq_query("Check nat.")`; if either fails it
falls back to its `scripts_only` mode (`$ROCQ_SCRIPTS` + `coqc`), so proving
still works without the server, just more slowly.

**Current state (Mode A).** The venv installs only the standard-library Mode A
adapter: it serves the MCP handshake and the full tool list, and answers each
call with a structured "backend unavailable" error rather than fabricating
goals. The live Petanque backend (`pytanque` + `pet-server`/`pet`) is blocked
on pinning a `pytanque` commit built against Rocq 9.2 (open point O-2); until
then `PYTANQUE_COMMIT` in `setup-base` is left empty. See
[`mcp/MANIFEST.md`](mcp/MANIFEST.md) for the implemented-vs-blocked breakdown.
