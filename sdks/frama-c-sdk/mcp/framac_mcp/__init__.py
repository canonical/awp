"""framac-mcp: read-only MCP query surface over the WP property database.

See spec/frama-c-mcp.md. Mode A (default) reads static -wp-report-json
artifacts and spawns no Frama-C; Mode B (live Frama-C Server) is blocked on
this host (open point O-1, no frama-c present).
"""

__version__ = "0.1.0"
