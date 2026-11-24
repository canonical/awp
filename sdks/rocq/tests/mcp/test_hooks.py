"""Provisioning: the edited hooks parse (bash -n) and carry the venv pin and
the profile marker the spec mandates (spec/rocq-mcp.md §4)."""
import os
import subprocess
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
SDK = os.path.dirname(os.path.dirname(_HERE))  # .../sdks/rocq


def read(rel):
    with open(os.path.join(SDK, rel), encoding="utf-8") as fh:
        return fh.read()


class BashSyntax(unittest.TestCase):
    def test_setup_base_parses(self):
        r = subprocess.run(["bash", "-n", os.path.join(SDK, "hooks/setup-base")],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_check_health_parses(self):
        r = subprocess.run(["bash", "-n", os.path.join(SDK, "hooks/check-health")],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)


class VenvPin(unittest.TestCase):
    def test_setup_base_pins_venv_outside_switch(self):
        s = read("hooks/setup-base")
        self.assertIn("/opt/rocq-mcp/venv", s)
        self.assertIn("ROCQ_MCP_VERSION", s)
        self.assertIn("python3 -m venv", s)
        self.assertIn('"$VENV/bin/pip" install --quiet "$SDK/rocq-mcp"', s)
        # The venv must NOT be under the read-only /opt/rocq switch link.
        self.assertNotIn("/opt/rocq/venv", s)
        self.assertIn("python3-venv", s)

    def test_profile_exports_marker(self):
        p = read("files/rocq.profile")
        self.assertIn("ROCQ_MCP_BIN=/opt/rocq-mcp/venv/bin/rocq-mcp", p)
        self.assertIn("/opt/rocq-mcp/venv/bin", p)


if __name__ == "__main__":
    unittest.main()
