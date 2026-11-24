"""creusot-mcp: a read-only MCP surface over why3find proof artifacts.

Mode A (default) reads the committed proof.json / why3session.xml / verdicts.tsv
artifacts of a Creusot overlay. Mode B (interactive prover layer) is blocked on
this host: no why3find toolchain is present (spec creusot-mcp.md O-1).
"""

__version__ = "0.1.0"

# The SDK pin this adapter was validated against (spec creusot-mcp.md §1, O-1).
PINNED_SDK_COMMIT = "f15b985"
PINNED_WHY3_VERSION = "1.8.2+git"
PINNED_WHY3FIND_VERSION = "1.3.0+dev"
