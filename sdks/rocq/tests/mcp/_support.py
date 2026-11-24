"""Shared test support: put the vendored adapter package on sys.path and load
the SYNTHETIC fixtures.  Standard library only (python3 -m unittest, -I-safe)."""
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
# .../sdks/rocq/tests/mcp -> .../sdks/rocq -> .../sdks/rocq/mcp
_ADAPTER = os.path.join(os.path.dirname(os.path.dirname(_HERE)), "mcp")
if _ADAPTER not in sys.path:
    sys.path.insert(0, _ADAPTER)

FIXTURES = os.path.join(_HERE, "fixtures")


def fixture(name):
    with open(os.path.join(FIXTURES, name), encoding="utf-8") as fh:
        return json.load(fh)
