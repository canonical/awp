"""stdio MCP server skeleton for framac-mcp (spec frama-c-mcp.md section 4).

Speaks raw JSON-RPC 2.0 over stdio (standard library only, ``-I``-safe), in
the harness-free style of ``sdks/lean/tests/lib/mcp_probe.py``. Mode A tools
are backed by the static ``-wp-report-json`` artifact via ``report.py`` and
spawn no Frama-C. Mode B tools (``wp_query``, ``wp_property``) return a clear
structured error -- live Frama-C Server is unavailable here and its request
names / JSON schema are open point O-1; this adapter never fabricates them.

Report resolution for Mode A tools:
  * a tool may pass an explicit ``run`` / ``report`` path;
  * otherwise the newest ``*.json`` in ``FRAMAC_MCP_REPORTS`` (env) is used.
"""

import json
import os
import sys

try:
    from . import report as R
    from . import __version__
except ImportError:  # run as a loose script (tests add the dir to sys.path)
    import report as R  # type: ignore
    __version__ = "0.0.0+local"

PROTOCOL_VERSION = "2025-06-18"

# Live Frama-C Server (Mode B) is blocked here: no frama-c on host and the
# request-name / JSON schema is open point O-1. A Mode-B refusal is NOT a
# canary failure (spec section 6) -- the skill continues on artifacts.
MODE_B_BLOCKED = {
    "mode": "B",
    "available": False,
    "reason": ("live Frama-C Server unavailable "
               "(blocked: O-1 request/JSON schema not pinned; no frama-c on this host). "
               "Mode A only."),
}

# GET/SET/EXEC naming rule from the Server plugin (spec section 1/3): wp_query
# accepts GET-classed requests only. The adapter refuses SET/EXEC by a string
# check before any server is contacted (spec section 3, test T-B4).
def _is_get_request(name):
    low = str(name).lower()
    if "set" in low or "exec" in low or "compute" in low:
        return False
    return "get" in low or "print" in low


class Server:
    """Dispatches MCP tool calls. Holds only Mode A config; no live process."""

    def __init__(self, reports_dir=None, verdicts_tsv=None):
        self.reports_dir = reports_dir or os.environ.get("FRAMAC_MCP_REPORTS")
        self.verdicts_tsv = verdicts_tsv or os.environ.get("FRAMAC_MCP_VERDICTS")

    # -- report resolution ---------------------------------------------------
    def _resolve(self, run):
        if run:
            return run
        if self.reports_dir:
            latest = R.latest_report(self.reports_dir)
            if latest:
                return latest
        raise R.ReportError(
            "no report given and none found (set FRAMAC_MCP_REPORTS or pass 'run')")

    def _load(self, run):
        return R.Report.load(self._resolve(run))

    # -- tool catalogue ------------------------------------------------------
    TOOLS = [
        {"name": "wp_status", "mode": "A",
         "description": "WP run summary: total / passed / per-verdict counts and the report read.",
         "inputSchema": {"type": "object", "properties": {
             "target": {"type": "string"}, "run": {"type": "string"}}}},
        {"name": "wp_remaining", "mode": "A",
         "description": "Open obligations, filterable by file/function/property/prover/verdict.",
         "inputSchema": {"type": "object", "properties": {
             "run": {"type": "string"}, "file": {"type": "string"},
             "function": {"type": "string"}, "property": {"type": "string"},
             "prover": {"type": "string"}, "verdict": {"type": "string"}}}},
        {"name": "wp_goal", "mode": "A",
         "description": "One goal by (file, function, property, line) key.",
         "inputSchema": {"type": "object", "properties": {
             "run": {"type": "string"}, "key": {"type": "array"}}}},
        {"name": "wp_provenance", "mode": "A",
         "description": "Which prover closed a goal, in which run/model, and that run's -wp-timeout.",
         "inputSchema": {"type": "object", "properties": {
             "run": {"type": "string"}, "key": {"type": "array"}}}},
        {"name": "wp_locate", "mode": "A",
         "description": "Source (file,line) for a property / function contract.",
         "inputSchema": {"type": "object", "properties": {
             "run": {"type": "string"}, "property": {"type": "string"}}}},
        {"name": "wp_diff", "mode": "A",
         "description": "Goals that changed status between two runs, keyed by the stable tuple.",
         "inputSchema": {"type": "object", "properties": {
             "run1": {"type": "string"}, "run2": {"type": "string"}}}},
        {"name": "wp_query", "mode": "B",
         "description": "(Mode B, blocked) a kernel/WP GET request against a loaded project.",
         "inputSchema": {"type": "object", "properties": {
             "request": {"type": "string"}, "args": {"type": "object"}}}},
        {"name": "wp_property", "mode": "B",
         "description": "(Mode B, blocked) live property status for a goal not in the last report.",
         "inputSchema": {"type": "object", "properties": {"key": {"type": "array"}}}},
    ]

    # -- dispatch ------------------------------------------------------------
    def call_tool(self, name, args):
        """Return a plain dict result for a tool call, or raise ValueError."""
        args = args or {}
        if name == "wp_status":
            return R.wp_status(self._load(args.get("run")))
        if name == "wp_remaining":
            rep = self._load(args.get("run"))
            return R.wp_remaining(
                rep, file=args.get("file"), function=args.get("function"),
                property=args.get("property"), prover=args.get("prover"),
                verdict=args.get("verdict"))
        if name == "wp_goal":
            return R.wp_goal(self._load(args.get("run")), args.get("key") or [])
        if name == "wp_provenance":
            return R.wp_provenance(self._load(args.get("run")), args.get("key") or [],
                                   verdicts_tsv=self.verdicts_tsv)
        if name == "wp_locate":
            return R.wp_locate(self._load(args.get("run")), args.get("property"))
        if name == "wp_diff":
            r1 = self._load(args.get("run1"))
            r2 = self._load(args.get("run2"))
            return R.wp_diff(r1, r2)
        if name == "wp_query":
            # GET-only guard runs before any (absent) server contact (T-B4).
            if not _is_get_request(args.get("request", "")):
                return {"error": "refused: only GET-classed requests are allowed "
                                  "(SET/EXEC/compute names rejected)",
                        **MODE_B_BLOCKED}
            return dict(MODE_B_BLOCKED, request=args.get("request"))
        if name == "wp_property":
            return dict(MODE_B_BLOCKED)
        raise ValueError("unknown tool: %s" % name)

    # -- MCP protocol --------------------------------------------------------
    def handle(self, msg):
        """Handle one JSON-RPC request object; return a response dict or None."""
        method = msg.get("method")
        mid = msg.get("id")
        if method == "initialize":
            return self._ok(mid, {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "framac-mcp", "version": __version__},
            })
        if method == "notifications/initialized":
            return None
        if method == "tools/list":
            tools = [{"name": t["name"], "description": t["description"],
                      "inputSchema": t["inputSchema"]} for t in self.TOOLS]
            return self._ok(mid, {"tools": tools})
        if method == "tools/call":
            params = msg.get("params") or {}
            name = params.get("name")
            try:
                result = self.call_tool(name, params.get("arguments"))
            except (R.ReportError, ValueError) as exc:
                return self._ok(mid, {
                    "content": [{"type": "text", "text": str(exc)}],
                    "isError": True})
            return self._ok(mid, {
                "content": [{"type": "text", "text": json.dumps(result)}],
                "structuredContent": result})
        if mid is not None:
            return self._err(mid, -32601, "method not found: %s" % method)
        return None

    @staticmethod
    def _ok(mid, result):
        return {"jsonrpc": "2.0", "id": mid, "result": result}

    @staticmethod
    def _err(mid, code, message):
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": message}}


def serve(stdin=None, stdout=None, server=None):
    """Line-delimited JSON-RPC loop over stdio."""
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    server = server or Server()
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        resp = server.handle(msg)
        if resp is not None:
            stdout.write(json.dumps(resp) + "\n")
            stdout.flush()


def main():
    serve()
    return 0


if __name__ == "__main__":
    sys.exit(main())
