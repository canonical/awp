"""Mode A + Mode-B-blocked tests for framac-mcp. Standard library only.

Run from the repo:
    python3 -I -m unittest discover -s sdks/frama-c-sdk/tests/mcp -p 'test_*.py'
or:
    cd sdks/frama-c-sdk/tests/mcp && python3 -I -m unittest -v

No Frama-C is spawned: every assertion reads the SYNTHETIC fixtures in
fixtures/ (see fixtures/README.md). Mirrors spec section 10 tests
T-A1 (status), T-A2 (diff + renumbering), T-A3 (reproducibility),
T-B4 (GET only) and the Mode-B-unavailable path.
"""

import json
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
MCP = os.path.normpath(os.path.join(HERE, os.pardir, os.pardir, "mcp"))
sys.path.insert(0, MCP)

from framac_mcp import report as R          # noqa: E402
from framac_mcp.server import Server        # noqa: E402

RUN1 = os.path.join(FIX, "report_run1.json")
RUN2 = os.path.join(FIX, "report_run2.json")


class ModeAStatus(unittest.TestCase):
    """T-A1: exact passed / per-verdict counts and open list."""

    def setUp(self):
        self.r1 = R.Report.load(RUN1)

    def test_status_counts(self):
        s = R.wp_status(self.r1)
        self.assertEqual(s["total"], 4)
        self.assertEqual(s["passed"], 2)
        self.assertEqual(s["open"], 2)
        self.assertEqual(s["verdicts"],
                         {"valid": 2, "timeout": 1, "unknown": 1})
        self.assertEqual(s["run"], RUN1)   # section 8: names the run read

    def test_remaining_exact(self):
        rem = R.wp_remaining(self.r1)
        self.assertEqual(rem["open"], 2)
        keys = sorted((g["function"], g["property"]) for g in rem["goals"])
        self.assertEqual(keys, [("bar", "ensures"), ("baz", "loop invariant inv")])

    def test_remaining_filter_function(self):
        rem = R.wp_remaining(self.r1, function="bar")
        self.assertEqual(rem["open"], 1)
        self.assertEqual(rem["goals"][0]["property"], "ensures")

    def test_remaining_filter_prover(self):
        rem = R.wp_remaining(self.r1, prover="Z3")
        self.assertEqual([g["function"] for g in rem["goals"]], ["baz"])


class ModeAGoalProvenance(unittest.TestCase):

    def test_goal_by_key_ignores_name(self):
        r2 = R.Report.load(RUN2)
        # key present in run2 under a renumbered bytes_* name
        g = R.wp_goal(r2, ("behaviors.c", "bar", "ensures", 30))
        self.assertTrue(g["found"])
        self.assertEqual(g["verdict"], "valid")
        self.assertEqual(g["goal"], "bytes_g2")

    def test_goal_missing_key(self):
        r1 = R.Report.load(RUN1)
        g = R.wp_goal(r1, ("nope.c", "x", "y", 1))
        self.assertFalse(g["found"])

    def test_provenance_closer_model_timeout(self):
        r1 = R.Report.load(RUN1)
        p = R.wp_provenance(r1, ("behaviors.c", "foo", "ensures", 12))
        self.assertTrue(p["found"])
        self.assertEqual(p["closed_by"]["name"], "Alt-Ergo")
        self.assertEqual(p["model"], "Typed")          # from wp:model meta
        self.assertEqual(p["wp_timeout"], 10)           # from wp:timeout meta
        self.assertEqual(p["timeout_source"], "report-meta")

    def test_provenance_timeout_unknown_without_meta(self):
        # Bare-array run2 has no run metadata -> timeout honestly unknown (O-7).
        r2 = R.Report.load(RUN2)
        p = R.wp_provenance(r2, ("behaviors.c", "bar", "ensures", 30))
        self.assertEqual(p["closed_by"]["name"], "Coq:8.20.1")
        self.assertEqual(p["model"], "bytes")           # from bytes_* name prefix
        self.assertIsNone(p["wp_timeout"])
        self.assertIn("O-7", p["timeout_source"])

    def test_locate(self):
        r1 = R.Report.load(RUN1)
        loc = R.wp_locate(r1, "ensures")
        pairs = sorted((h["function"], h["line"]) for h in loc["locations"])
        self.assertEqual(pairs, [("bar", 30), ("foo", 12)])


class ModeADiff(unittest.TestCase):
    """T-A2: diff keyed by the stable tuple, across a WP renumbering."""

    def test_diff_renumbered(self):
        r1, r2 = R.Report.load(RUN1), R.Report.load(RUN2)
        d = R.wp_diff(r1, r2)
        self.assertEqual([e["key"] for e in d["newly_closed"]],
                         [["behaviors.c", "bar", "ensures", 30]])
        self.assertEqual([e["key"] for e in d["regressed"]],
                         [["behaviors.c", "foo", "ensures", 12]])
        # No goals were added or removed: all four keys are common to both runs,
        # proving the bytes_* renumbering produced no spurious change.
        self.assertEqual(d["added"], [])
        self.assertEqual(d["removed"], [])

    def test_diff_detects_added_removed(self):
        # A synthetic one-off: run2 restricted to 3 keys -> one removed.
        r1 = R.Report.load(RUN1)
        trimmed = R.Report([r for r in R.Report.load(RUN2).records
                            if r["function"] != "baz"], "trimmed")
        d = R.wp_diff(r1, trimmed)
        self.assertEqual([e["key"] for e in d["removed"]],
                         [["loops.c", "baz", "loop invariant inv", 45]])


class Reproducibility(unittest.TestCase):
    """T-A3: wp_remaining equals a plain re-derivation over the same json."""

    def test_remaining_matches_manual_scan(self):
        rem = R.wp_remaining(R.Report.load(RUN1))
        with open(RUN1, encoding="utf-8") as fh:
            goals = json.load(fh)["goals"]
        manual = sorted((g["file"], g["function"], g["property"], g["line"])
                        for g in goals if not g["passed"])
        got = sorted((g["file"], g["function"], g["property"], g["line"])
                     for g in rem["goals"])
        self.assertEqual(got, manual)


class ModeBBlocked(unittest.TestCase):
    """Mode B must refuse clearly, never fabricate server data."""

    def setUp(self):
        self.srv = Server(reports_dir=FIX)

    def test_wp_property_blocked(self):
        res = self.srv.call_tool("wp_property", {"key": ["a.c", "f", "p", 1]})
        self.assertFalse(res["available"])
        self.assertIn("O-1", res["reason"])

    def test_wp_query_get_blocked_not_faked(self):
        res = self.srv.call_tool("wp_query", {"request": "Kernel.get_ast"})
        self.assertFalse(res["available"])
        self.assertIn("Mode A only", res["reason"])

    def test_wp_query_set_refused_before_server(self):   # T-B4
        res = self.srv.call_tool("wp_query", {"request": "Wp.setGoal"})
        self.assertIn("refused", res["error"])

    def test_wp_query_exec_refused(self):               # T-B4
        res = self.srv.call_tool("wp_query", {"request": "Wp.computeGoals"})
        self.assertIn("refused", res["error"])


class ServerDispatch(unittest.TestCase):
    """The MCP handle()/call_tool layer over the fixtures."""

    def setUp(self):
        self.srv = Server(reports_dir=FIX)

    def test_tools_list(self):
        resp = self.srv.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
        names = sorted(t["name"] for t in resp["result"]["tools"])
        self.assertEqual(names, ["wp_diff", "wp_goal", "wp_locate", "wp_property",
                                 "wp_provenance", "wp_query", "wp_remaining",
                                 "wp_status"])

    def test_tools_call_status_latest(self):
        # No 'run' arg -> newest *.json in reports_dir is used.
        resp = self.srv.handle({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                                "params": {"name": "wp_status", "arguments": {}}})
        self.assertFalse(resp["result"].get("isError"))
        self.assertEqual(resp["result"]["structuredContent"]["total"], 4)

    def test_tools_call_diff(self):
        resp = self.srv.handle({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                                "params": {"name": "wp_diff",
                                           "arguments": {"run1": RUN1, "run2": RUN2}}})
        sc = resp["result"]["structuredContent"]
        self.assertEqual(len(sc["newly_closed"]), 1)
        self.assertEqual(len(sc["regressed"]), 1)

    def test_missing_report_is_tool_error(self):
        srv = Server()   # no reports_dir, no run
        resp = srv.handle({"jsonrpc": "2.0", "id": 4, "method": "tools/call",
                           "params": {"name": "wp_status", "arguments": {}}})
        self.assertTrue(resp["result"]["isError"])

    def test_initialize(self):
        resp = self.srv.handle({"jsonrpc": "2.0", "id": 0, "method": "initialize",
                                "params": {}})
        self.assertEqual(resp["result"]["serverInfo"]["name"], "framac-mcp")


class StdioSmoke(unittest.TestCase):
    """End-to-end: drive the real stdio loop as a subprocess (-I-safe)."""

    def test_stdio_roundtrip(self):
        # Run under -I (isolated: no cwd, no PYTHONPATH) and resolve the package
        # by an explicit in-code path insert -- exactly how the venv console
        # script 'framac-mcp' resolves it in the SDK. Proves the loop is -I-safe.
        env = dict(os.environ, FRAMAC_MCP_REPORTS=FIX)
        boot = ("import sys; sys.path.insert(0, %r); "
                "from framac_mcp.server import main; sys.exit(main())" % MCP)
        reqs = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call",
             "params": {"name": "wp_status", "arguments": {"run": RUN1}}},
        ]
        stdin = "".join(json.dumps(r) + "\n" for r in reqs)
        proc = subprocess.run(
            [sys.executable, "-I", "-c", boot],
            input=stdin, capture_output=True, text=True, env=env, timeout=30)
        lines = [json.loads(ln) for ln in proc.stdout.splitlines() if ln.strip()]
        ids = {m.get("id"): m for m in lines}
        self.assertIn(1, ids)
        self.assertIn(2, ids)
        self.assertEqual(ids[2]["result"]["structuredContent"]["passed"], 2)


if __name__ == "__main__":
    unittest.main()
