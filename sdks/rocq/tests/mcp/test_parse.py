"""Mode A: pure Petanque-response parsing and state bookkeeping."""
import unittest

import _support  # noqa: F401  (sys.path side effect)
from rocq_mcp import parse


class RunResult(unittest.TestCase):
    def test_finished(self):
        r = parse.parse_run_result(_support.fixture("run_result_finished.json"))
        self.assertTrue(r["proof_finished"])
        self.assertFalse(r["error"])
        self.assertEqual(r["petanque_state"], 42)
        self.assertEqual(r["hash"], 999001)
        self.assertIn("No more goals.", r["messages"])

    def test_open(self):
        r = parse.parse_run_result(_support.fixture("run_result_open.json"))
        self.assertFalse(r["proof_finished"])
        self.assertFalse(r["error"])
        self.assertEqual(r["petanque_state"], 7)

    def test_error(self):
        r = parse.parse_run_result(_support.fixture("run_result_error.json"))
        self.assertTrue(r["error"])
        self.assertFalse(r["proof_finished"])
        self.assertTrue(any("Unable to unify" in m for m in r["messages"]))

    def test_rejects_non_object(self):
        with self.assertRaises(parse.ValidationError):
            parse.parse_run_result([1, 2, 3])


class Goals(unittest.TestCase):
    def test_two_goals(self):
        g = parse.parse_goals(_support.fixture("goals_two.json"))
        self.assertEqual(len(g), 2)
        self.assertEqual(g[0]["conclusion"], "n + 0 = n")
        self.assertEqual(g[0]["hypotheses"][0]["names"], "n")
        self.assertEqual(g[0]["hypotheses"][0]["type"], "nat")
        self.assertEqual(g[1]["hypotheses"], [])

    def test_empty_after_finished(self):
        self.assertEqual(parse.parse_goals({"goals": []}), [])


class TocPremises(unittest.TestCase):
    def test_toc_flattens(self):
        entries = parse.parse_toc(_support.fixture("toc.json"))
        names = [e["name"] for e in entries]
        self.assertEqual(names, ["Sort", "insert", "isort_sorted"])
        self.assertEqual(entries[2]["kind"], "theorem")

    def test_premises(self):
        prems = parse.parse_premises(_support.fixture("premises.json"))
        self.assertIn("Stdlib.Arith.PeanoNat.Nat.add_comm", prems)


class StartMode(unittest.TestCase):
    def test_theorem_wins(self):
        mode, norm = parse.start_mode(
            {"file": "F.v", "theorem": "add_comm", "line": 3, "character": 0, "preamble": "x"})
        self.assertEqual(mode, "theorem")
        self.assertEqual(norm["theorem"], "add_comm")

    def test_position(self):
        mode, norm = parse.start_mode({"file": "F.v", "line": 10, "character": 2})
        self.assertEqual(mode, "position")
        self.assertEqual((norm["line"], norm["character"]), (10, 2))

    def test_preamble(self):
        mode, norm = parse.start_mode({"preamble": "Require Import Arith."})
        self.assertEqual(mode, "preamble")

    def test_negative_position_rejected(self):
        with self.assertRaises(parse.ValidationError):
            parse.start_mode({"file": "F.v", "line": -1, "character": 0})

    def test_empty_rejected(self):
        with self.assertRaises(parse.ValidationError):
            parse.start_mode({})


class StepMulti(unittest.TestCase):
    def test_ok(self):
        self.assertEqual(parse.step_multi_tactics({"tactics": ["auto.", "lia."]}),
                         ["auto.", "lia."])

    def test_cap_20(self):
        with self.assertRaises(parse.ValidationError):
            parse.step_multi_tactics({"tactics": ["t."] * 21})

    def test_empty_rejected(self):
        with self.assertRaises(parse.ValidationError):
            parse.step_multi_tactics({"tactics": []})


class Store(unittest.TestCase):
    def test_handles_and_lineage(self):
        s = parse.StateStore()
        root = s.add(petanque_state=100, state_hash="h0")
        child = s.extend(root, petanque_state=101, tactic="intros n.", state_hash="h1")
        self.assertEqual(s.lineage(child), ["intros n."])
        self.assertEqual(s.petanque_state(child), 101)

    def test_hash_dedup(self):
        # Two branches reaching the same state/hash collapse to one handle.
        s = parse.StateStore()
        root = s.add(petanque_state=100, state_hash="h0")
        a = s.extend(root, 200, "auto.", state_hash="hX")
        b = s.extend(root, 200, "trivial.", state_hash="hX")
        self.assertEqual(a, b)
        self.assertEqual(len(s), 2)  # root + one deduped child

    def test_unknown_handle(self):
        s = parse.StateStore()
        with self.assertRaises(parse.ValidationError):
            s.petanque_state(99)


if __name__ == "__main__":
    unittest.main()
