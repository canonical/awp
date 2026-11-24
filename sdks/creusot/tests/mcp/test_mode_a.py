#!/usr/bin/env python3
"""Mode A tests for creusot-mcp, harness-free (python3 -m unittest).

Run from the repo root:
    python3 -m unittest discover -s sdks/creusot/tests/mcp -p 'test_*.py'
or:
    python3 sdks/creusot/tests/mcp/test_mode_a.py

Fixtures under fixtures/ are MINIMAL REAL why3find proof.json trees copied out
of a 2026-11 httparse campaign overlay (a passing split_vc tree, a leaf-only
module, a module with a why3session.xml, and a trimmed module carrying a real
`null` failed leaf). No Creusot toolchain is required or invoked.
"""

import json
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
MCP_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "mcp"))
FIX = os.path.join(HERE, "fixtures")
sys.path.insert(0, MCP_DIR)

from creusot_mcp import core, server  # noqa: E402

NO_PROVE = lambda verif_dir: False  # noqa: E731  (no active why3find prove)


class ModeAStatus(unittest.TestCase):
    def test_status_counts_rev1(self):
        s = core.creusot_status(os.path.join(FIX, "overlay_rev1"),
                                prove_active=NO_PROVE)
        self.assertEqual(s["modules"], 3)
        self.assertEqual(s["goals"], 9)
        self.assertEqual(s["unproved"], 0)
        self.assertEqual(s["discharged"], s["leaves"])
        self.assertFalse(s["in_flight"])

    def test_status_counts_rev2_has_unproved(self):
        s = core.creusot_status(os.path.join(FIX, "overlay_rev2"),
                                prove_active=NO_PROVE)
        self.assertEqual(s["modules"], 4)
        self.assertEqual(s["unproved"], 2)  # regressed offsetnz leaf + parse_chunk_size null

    def test_status_reproducible_by_reference_script(self):
        # T-A4: equals a plain re-read of the same files.
        overlay = os.path.join(FIX, "overlay_rev2")
        verif = os.path.join(overlay, "verif")
        ref_unproved = 0
        for root, _dirs, files in os.walk(verif):
            if "proof.json" in files:
                with open(os.path.join(root, "proof.json")) as fh:
                    data = json.load(fh)
                ref_unproved += json.dumps(data).count("null")
        s = core.creusot_status(overlay, prove_active=NO_PROVE)
        self.assertEqual(s["unproved"], ref_unproved)


class ModeARemaining(unittest.TestCase):
    def test_remaining_lists_exactly_the_null_leaves(self):
        r = core.creusot_remaining(os.path.join(FIX, "overlay_rev2"),
                                   prove_active=NO_PROVE)
        self.assertEqual(r["count"], 2)
        goals = sorted(x["goal"] for x in r["remaining"])
        self.assertEqual(goals, ["vc_offsetnz", "vc_parse_chunk_size"])

    def test_remaining_filter_by_function(self):
        r = core.creusot_remaining(os.path.join(FIX, "overlay_rev2"),
                                   function="parse_chunk_size",
                                   prove_active=NO_PROVE)
        self.assertEqual(r["count"], 1)
        self.assertEqual(r["remaining"][0]["position"], "0.2.0.0.0")
        self.assertEqual(r["remaining"][0]["depth"], 5)

    def test_remaining_filter_by_unit(self):
        r = core.creusot_remaining(os.path.join(FIX, "overlay_rev2"),
                                   unit="demo_rlib", prove_active=NO_PROVE)
        self.assertEqual(r["count"], 2)
        r2 = core.creusot_remaining(os.path.join(FIX, "overlay_rev2"),
                                    unit="sess_rlib", prove_active=NO_PROVE)
        self.assertEqual(r2["count"], 0)


class ModeATree(unittest.TestCase):
    def test_tree_reconstructs_nesting(self):
        t = core.vc_tree(os.path.join(FIX, "overlay_rev1"),
                         "sess_rlib/parse_reason")
        root = t["tree"]["vc_parse_reason"]
        self.assertEqual(root["tactic"], "compute_specified")
        self.assertEqual(root["status"], "proved")
        self.assertEqual(root["children"][0]["tactic"], "split_vc")

    def test_tree_merges_session_expl(self):
        # T-A2: expl/proved come from the why3session.xml where present.
        t = core.vc_tree(os.path.join(FIX, "overlay_rev1"),
                         "sess_rlib/parse_reason")
        self.assertTrue(t["has_session"])
        leaf03 = t["tree"]["vc_parse_reason"]["children"][0]["children"][3]
        self.assertEqual(leaf03["expl"], "loop invariant #3")

    def test_tree_marks_null_leaf_unproved(self):
        t = core.vc_tree(os.path.join(FIX, "overlay_rev2"),
                         "demo_rlib/parse_chunk_size")
        self.assertEqual(t["tree"]["vc_parse_chunk_size"]["status"], "unproved")
        self.assertFalse(t["has_session"])


class ModeAGoalProvenanceLocate(unittest.TestCase):
    def test_vc_goal_leaf(self):
        g = core.vc_goal(os.path.join(FIX, "overlay_rev1"),
                         "Coma.vc_default_config_is_strict")
        self.assertEqual(g["status"], "proved")
        self.assertEqual(g["prover"], "alt-ergo")

    def test_vc_goal_positional_with_session_expl(self):
        g = core.vc_goal(os.path.join(FIX, "overlay_rev1"),
                         "Coma.vc_parse_reason.0.3")
        self.assertEqual(g["expl"], "loop invariant #3")
        self.assertTrue(g["session_proved"])

    def test_vc_provenance_reports_prover_and_ledger(self):
        p = core.vc_provenance(os.path.join(FIX, "overlay_rev1"),
                               "Coma.vc_offsetnz")
        self.assertIn("alt-ergo", p["provers"])
        self.assertEqual(len(p["ledger_rows"]), 1)
        self.assertEqual(p["ledger_rows"][0]["verdict"], "VERIFIED")

    def test_vc_locate_is_honestly_partial(self):
        loc = core.vc_locate(os.path.join(FIX, "overlay_rev1"),
                             "Coma.vc_parse_reason.0.3")
        self.assertTrue(loc["partial"])
        self.assertEqual(loc["expl"], "loop invariant #3")
        self.assertIn("positional", loc["reason"])


class ModeADiff(unittest.TestCase):
    def test_diff_flags_regression_and_new_open(self):
        d = core.creusot_diff(os.path.join(FIX, "overlay_rev1"),
                              os.path.join(FIX, "overlay_rev2"))
        self.assertEqual(d["regressed"], ["demo_rlib/offsetnz::vc_offsetnz"])
        self.assertEqual(d["newly_open"],
                         ["demo_rlib/parse_chunk_size::vc_parse_chunk_size"])
        self.assertEqual(d["closed"], [])


class InFlightGuard(unittest.TestCase):
    def test_run_log_without_summary_is_in_flight(self):
        flag, reason = core.in_flight(os.path.join(FIX, "overlay_inflight"),
                                      prove_active=NO_PROVE)
        self.assertTrue(flag)
        self.assertIn("no final summary", reason)

    def test_completed_run_log_is_not_in_flight(self):
        flag, _ = core.in_flight(os.path.join(FIX, "overlay_complete"),
                                 prove_active=NO_PROVE)
        self.assertFalse(flag)

    def test_active_prove_is_in_flight(self):
        flag, reason = core.in_flight(os.path.join(FIX, "overlay_rev1"),
                                      prove_active=lambda v: True)
        self.assertTrue(flag)
        self.assertIn("active", reason)

    def test_status_refuses_while_in_flight(self):
        with self.assertRaises(core.CreusotError) as cm:
            core.creusot_status(os.path.join(FIX, "overlay_inflight"),
                                prove_active=NO_PROVE)
        self.assertIn("in_flight", str(cm.exception))


class ModeBUnavailable(unittest.TestCase):
    """Mode B must refuse clearly and never fake a discharge (spec §8, O-1)."""

    def _call(self, tool):
        old = os.environ.get("CREUSOT_OVERLAY")
        os.environ["CREUSOT_OVERLAY"] = os.path.join(FIX, "overlay_rev1")
        try:
            return server.call_tool(tool, {"subgoal": "x", "prover": "z3",
                                           "timeout": 5, "id": "Coma.vc_x"})
        finally:
            if old is None:
                os.environ.pop("CREUSOT_OVERLAY", None)
            else:
                os.environ["CREUSOT_OVERLAY"] = old

    def test_vc_try_blocked_and_not_banked(self):
        result, is_error = self._call("vc_try")
        self.assertTrue(is_error)
        self.assertFalse(result["banked"])
        self.assertIn("prover unavailable", result["error"])
        self.assertIn("never fakes", result["error"].lower())

    def test_vc_split_and_why3_task_blocked(self):
        for tool in ("vc_split", "why3_task"):
            result, is_error = self._call(tool)
            self.assertTrue(is_error, tool)
            self.assertFalse(result.get("banked", False), tool)


class StdioServerSmoke(unittest.TestCase):
    """Drive the real stdio server end to end (mcp_probe.py style)."""

    def test_initialize_list_and_status(self):
        launch = ("import sys; sys.path.insert(0, %r); "
                  "from creusot_mcp.server import main; sys.exit(main())"
                  % MCP_DIR)
        reqs = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
             "params": {"name": "creusot_status", "arguments": {}}},
        ]
        env = dict(os.environ,
                   CREUSOT_OVERLAY=os.path.join(FIX, "overlay_rev1"))
        proc = subprocess.run(
            [sys.executable, "-c", launch],
            input="\n".join(json.dumps(r) for r in reqs),
            capture_output=True, text=True, timeout=60, env=env)
        responses = [json.loads(ln) for ln in proc.stdout.splitlines() if ln.strip()]
        by_id = {m.get("id"): m for m in responses}
        self.assertEqual(by_id[1]["result"]["serverInfo"]["name"], "creusot-mcp")
        names = {t["name"] for t in by_id[2]["result"]["tools"]}
        self.assertIn("creusot_status", names)
        self.assertIn("vc_try", names)
        sc = by_id[3]["result"]["structuredContent"]
        self.assertEqual(sc["modules"], 3)
        self.assertFalse(by_id[3]["result"]["isError"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
