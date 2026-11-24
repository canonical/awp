"""Mode A: dispatch gating and the structured backend-unavailable path."""
import unittest

import _support  # noqa: F401
from rocq_mcp import tools
from rocq_mcp.backend import Backend, probe_backend
from rocq_mcp.dispatch import dispatch


# On this host probe_backend finds nothing; use it directly as the null case.
NULL = probe_backend({"PATH": ""})


class BackendUnavailable(unittest.TestCase):
    def test_this_host_has_no_backend(self):
        self.assertFalse(NULL.petanque)
        self.assertFalse(NULL.coqc)

    def test_petanque_tool_blocked_on_O1_O2(self):
        r = dispatch("rocq_start", {"file": "F.v", "theorem": "t"}, NULL)
        self.assertTrue(r["isError"])
        sc = r["structuredContent"]
        self.assertEqual(sc["error"], "backend_unavailable")
        self.assertEqual(sc["backend"], "petanque")
        self.assertEqual(sc["blocked"], ["O-1", "O-2"])
        self.assertIn("coq-lsp", r["content"][0]["text"])

    def test_query_canary_blocked_not_crashed(self):
        # The skill's canary: rocq_query("Check nat.") must return a clean,
        # structured error here, never an exception or a fake answer.
        r = dispatch("rocq_query", {"command": "Check nat."}, NULL)
        self.assertTrue(r["isError"])
        self.assertEqual(r["structuredContent"]["backend"], "petanque")

    def test_coqc_tool_names_toolchain(self):
        r = dispatch("rocq_compile", {"source": "Theorem t: True. Proof. exact I. Qed."}, NULL)
        self.assertTrue(r["isError"])
        sc = r["structuredContent"]
        self.assertEqual(sc["backend"], "coqc")
        self.assertEqual(sc["blocked"], ["toolchain"])

    def test_every_tool_degrades_cleanly(self):
        samples = {
            "rocq_start": {"file": "F.v", "theorem": "t"},
            "rocq_check": {"body": "reflexivity."},
            "rocq_step_multi": {"tactics": ["auto."]},
            "rocq_query": {"command": "Check nat."},
            "rocq_toc": {"file": "F.v"},
            "rocq_notations": {"statement": "n + 0 = n"},
            "rocq_compile": {"source": "(* x *)"},
            "rocq_verify": {"proof": "p", "problem_name": "t", "problem_statement": "s"},
        }
        self.assertEqual(set(samples), set(tools.tool_names()))
        for name, args in samples.items():
            r = dispatch(name, args, NULL)
            self.assertTrue(r["isError"], name)
            self.assertEqual(r["structuredContent"]["error"], "backend_unavailable", name)


class Validation(unittest.TestCase):
    def test_missing_required(self):
        r = dispatch("rocq_check", {}, NULL)
        self.assertEqual(r["structuredContent"]["error"], "invalid_arguments")

    def test_step_multi_cap(self):
        r = dispatch("rocq_step_multi", {"tactics": ["t."] * 21}, NULL)
        self.assertEqual(r["structuredContent"]["error"], "invalid_arguments")

    def test_unknown_tool(self):
        r = dispatch("rocq_nonsense", {}, NULL)
        self.assertEqual(r["structuredContent"]["error"], "unknown_tool")


class ReachableBackendFailsClosed(unittest.TestCase):
    def test_mode_a_does_not_fabricate(self):
        # Even if a backend reports reachable, Mode A refuses to pretend it
        # proved anything; it fails closed on O-1.
        fake = Backend(petanque=True, coqc=True, detail="test")
        r = dispatch("rocq_check", {"body": "reflexivity."}, fake)
        self.assertTrue(r["isError"])
        self.assertEqual(r["structuredContent"]["error"], "not_implemented_mode_a")


if __name__ == "__main__":
    unittest.main()
