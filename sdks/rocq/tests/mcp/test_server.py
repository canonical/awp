"""Mode A: the stdio MCP server loop (in-process and as an -I-safe subprocess).

The subprocess test drives the adapter with raw newline-delimited JSON-RPC, the
same transport sdks/lean/tests/lib/mcp_probe.py uses — harness-free."""
import io
import json
import os
import subprocess
import sys
import unittest

import _support  # noqa: F401
from rocq_mcp import server
from rocq_mcp.backend import probe_backend

NULL = probe_backend({"PATH": ""})
ADAPTER_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "mcp")


def drive(requests, backend=NULL):
    """Feed newline-delimited JSON-RPC through serve(), return parsed responses."""
    stdin = io.StringIO("".join(json.dumps(r) + "\n" for r in requests))
    stdout = io.StringIO()
    server.serve(stdin, stdout, backend)
    return [json.loads(line) for line in stdout.getvalue().splitlines() if line.strip()]


class InProcess(unittest.TestCase):
    def test_initialize(self):
        out = drive([{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}])
        self.assertEqual(out[0]["result"]["serverInfo"]["name"], "rocq-mcp")

    def test_initialized_notification_silent(self):
        out = drive([{"jsonrpc": "2.0", "method": "notifications/initialized"}])
        self.assertEqual(out, [])

    def test_tools_list_has_all_eight(self):
        out = drive([{"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}])
        names = sorted(t["name"] for t in out[0]["result"]["tools"])
        self.assertEqual(names, [
            "rocq_check", "rocq_compile", "rocq_notations", "rocq_query",
            "rocq_start", "rocq_step_multi", "rocq_toc", "rocq_verify"])
        for t in out[0]["result"]["tools"]:
            self.assertIn("inputSchema", t)

    def test_tools_call_backend_unavailable(self):
        out = drive([{"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                      "params": {"name": "rocq_query", "arguments": {"command": "Check nat."}}}])
        result = out[0]["result"]
        self.assertTrue(result["isError"])
        self.assertEqual(result["structuredContent"]["error"], "backend_unavailable")

    def test_unknown_method(self):
        out = drive([{"jsonrpc": "2.0", "id": 4, "method": "no/such", "params": {}}])
        self.assertEqual(out[0]["error"]["code"], -32601)

    def test_garbage_line_ignored(self):
        stdin = io.StringIO("not json\n" + json.dumps(
            {"jsonrpc": "2.0", "id": 9, "method": "tools/list"}) + "\n")
        stdout = io.StringIO()
        server.serve(stdin, stdout, NULL)
        out = [json.loads(x) for x in stdout.getvalue().splitlines() if x.strip()]
        self.assertEqual(len(out), 1)


class Subprocess(unittest.TestCase):
    """End-to-end over a real isolated (-I) process, the way the installed
    console script launches it.  -I ignores PYTHONPATH/cwd, so the path is
    injected explicitly — which is exactly what proves the adapter is -I-safe:
    an isolated interpreter, no implicit cwd import, runs it cleanly."""

    BOOT = ("import sys; sys.path.insert(0, %r); "
            "from rocq_mcp.server import main; sys.exit(main(sys.argv[1:]))" % ADAPTER_DIR)

    def _run(self, lines, args=()):
        return subprocess.run(
            [sys.executable, "-I", "-c", self.BOOT, *args],
            input="".join(json.dumps(x) + "\n" for x in lines),
            capture_output=True, text=True, timeout=60)

    def test_help(self):
        proc = self._run([], args=["--help"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("rocq_query", proc.stdout)

    def test_handshake(self):
        proc = self._run([
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
             "params": {"name": "rocq_start",
                        "arguments": {"file": "F.v", "theorem": "t"}}},
        ])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        msgs = {json.loads(l)["id"]: json.loads(l)
                for l in proc.stdout.splitlines() if l.strip()}
        self.assertEqual(msgs[1]["result"]["serverInfo"]["name"], "rocq-mcp")
        self.assertEqual(len(msgs[2]["result"]["tools"]), 8)
        self.assertTrue(msgs[3]["result"]["isError"])
        self.assertEqual(msgs[3]["result"]["structuredContent"]["blocked"], ["O-1", "O-2"])


if __name__ == "__main__":
    unittest.main()
