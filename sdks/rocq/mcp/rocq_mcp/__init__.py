"""rocq-mcp: a thin stdio-MCP adapter mapping the rocq skill's tool surface
onto coq-lsp / Petanque (see spec/rocq-mcp.md).

Mode A (this package) is the harness-facing, standard-library-only core:
protocol handling, the tool registry, pure Petanque-response parsers, the
adapter-side state bookkeeping, and the dispatch that returns a structured
"backend unavailable" error when no coq-lsp/pet-server (or coqc) is reachable
instead of crashing or fabricating a prover result.

The live Petanque backend (pytanque SOCKET/STDIO, pet-server lifecycle) is
blocked on O-1/O-2 and on the absence of any Rocq toolchain here; see
MANIFEST.md.  No proving logic lives in this adapter.
"""

__version__ = "0.1.0"
