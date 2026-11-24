"""The stdio MCP server loop.

Standard-library only, line-delimited JSON-RPC — the mirror image of the
client in sdks/lean/tests/lib/mcp_probe.py, so the same harness-free probe can
drive it.  It handles `initialize`, `notifications/initialized`, `tools/list`
and `tools/call`; `tools/call` goes through dispatch (dispatch.py), which with
no reachable backend returns the structured "backend unavailable" error.

Run as `rocq-mcp` (console script) or `python3 -m rocq_mcp`.
"""
import json
import sys

from . import tools, __version__
from .backend import probe_backend
from .dispatch import dispatch

PROTOCOL_VERSION = "2025-06-18"
SERVER_INFO = {"name": "rocq-mcp", "version": __version__}


def handle(message, backend):
    """Map one JSON-RPC request to a response dict, or None for a notification."""
    method = message.get("method")
    mid = message.get("id")
    params = message.get("params") or {}

    if method == "initialize":
        return _ok(mid, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": SERVER_INFO,
        })
    if method == "notifications/initialized":
        return None
    if method == "tools/list":
        return _ok(mid, tools.list_payload())
    if method == "tools/call":
        result = dispatch(params.get("name"), params.get("arguments"), backend)
        return _ok(mid, result)
    if mid is None:
        return None  # unknown notification
    return {"jsonrpc": "2.0", "id": mid,
            "error": {"code": -32601, "message": "method not found: %s" % method}}


def _ok(mid, result):
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def serve(stdin, stdout, backend):
    """Read newline-delimited JSON-RPC from `stdin`, write responses to
    `stdout`.  Returns when stdin is exhausted."""
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        response = handle(message, backend)
        if response is not None:
            stdout.write(json.dumps(response) + "\n")
            stdout.flush()


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(
            "rocq-mcp %s: stdio MCP adapter for coq-lsp/Petanque (Mode A).\n"
            "Tools: %s\n" % (__version__, " ".join(tools.tool_names()))
        )
        return 0
    if "--version" in argv:
        sys.stdout.write("rocq-mcp %s\n" % __version__)
        return 0
    backend = probe_backend()
    serve(sys.stdin, sys.stdout, backend)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
