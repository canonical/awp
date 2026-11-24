"""Mode A: backend detection and the pet-server launch marks (spec §7.2)."""
import unittest

import _support  # noqa: F401
from rocq_mcp import backend


class Probe(unittest.TestCase):
    def test_empty_path_reports_nothing(self):
        b = backend.probe_backend({"PATH": ""})
        self.assertFalse(b.petanque)
        self.assertFalse(b.coqc)
        self.assertIn("pet-server", b.detail)

    def test_has_helper(self):
        b = backend.Backend(petanque=False, coqc=True)
        self.assertTrue(b.has("coqc"))
        self.assertFalse(b.has("petanque"))


class LaunchPlan(unittest.TestCase):
    def test_marks_default(self):
        plan = backend.pet_launch_plan({})
        self.assertEqual(plan["oom_score_adj"], 1000)   # watchdog keys on this
        self.assertTrue(plan["own_process_group"])       # setsid group
        self.assertEqual(plan["ulimit_v_kb"], backend.DEFAULT_HEAVY_MEM_KB)

    def test_rocq_pet_mem_kb_override(self):
        plan = backend.pet_launch_plan({"ROCQ_PET_MEM_KB": "3145728"})
        self.assertEqual(plan["ulimit_v_kb"], 3145728)

    def test_falls_back_to_heavy_mem_kb(self):
        plan = backend.pet_launch_plan({"HEAVY_MEM_KB": "2000000"})
        self.assertEqual(plan["ulimit_v_kb"], 2000000)

    def test_bad_value_falls_back(self):
        plan = backend.pet_launch_plan({"ROCQ_PET_MEM_KB": "not-a-number"})
        self.assertEqual(plan["ulimit_v_kb"], backend.DEFAULT_HEAVY_MEM_KB)


if __name__ == "__main__":
    unittest.main()
