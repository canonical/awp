"""Minimal stdio MCP server for creusot-mcp (standard library only, -I-safe).

Mode A tools answer from the committed proof.json / why3session.xml /
verdicts.tsv artifacts. Mode B tools (vc_split / vc_try / why3_task) return a
clear "prover unavailable" error: this adapter binds to the SDK pin
(creusot-mcp.md O-1) and spawns a prover only through bin/heavy, neither of
which is available on a host without the why3find toolchain. It NEVER fakes a
discharge.
"""

import json
import os
import shutil
import sys

from . import (PINNED_SDK_COMMIT, PINNED_WHY3_VERSION, PINNED_WHY3FIND_VERSION,
               __version__, core)

PROTOCOL_VERSION = "2025-06-18"


def _overlay():
    return os.environ.get("CREUSOT_OVERLAY", os.getcwd())


# --------------------------------------------------------------------------
# Tool definitions
# --------------------------------------------------------------------------

MODE_A_TOOLS = {
    "creusot_status": {
        "description": "Totals over the overlay's proof.json artifacts: "
                       "modules, goals, leaves, discharged/unproved; in_flight.",
        "schema": {"type": "object", "properties": {
            "unit": {"type": "string"}}},
    },
    "creusot_remaining": {
        "description": "Unproved (null) leaves, filterable by unit / module / "
                       "function / tactic / depth.",
        "schema": {"type": "object", "properties": {
            "unit": {"type": "string"}, "module": {"type": "string"},
            "function": {"type": "string"}, "tactic": {"type": "string"},
            "depth": {"type": "integer"}}},
    },
    "vc_goal": {
        "description": "One goal by id (Coma.vc_<fn>[.i.j]): tactic path, "
                       "prover, time, status; expl when a session exists.",
        "schema": {"type": "object", "required": ["id"], "properties": {
            "id": {"type": "string"}}},
    },
    "vc_tree": {
        "description": "The compute_specified/split_vc tree of a module with "
                       "per-node status; expl per node where a session exists.",
        "schema": {"type": "object", "required": ["module"], "properties": {
            "module": {"type": "string"}}},
    },
    "vc_provenance": {
        "description": "Prover and time that closed a goal, plus the "
                       "verdicts.tsv rows and commit that banked it.",
        "schema": {"type": "object", "required": ["id"], "properties": {
            "id": {"type": "string"}}},
    },
    "vc_locate": {
        "description": "Source location of a goal. PARTIAL in Mode A: "
                       "proof.json is positional; only expl (from a session) "
                       "is available, a full (file,line,clause) needs Mode B.",
        "schema": {"type": "object", "required": ["id"], "properties": {
            "id": {"type": "string"}}},
    },
    "creusot_diff": {
        "description": "Goals that changed status between two committed "
                       "revision overlays (newly-open / closed / regressed).",
        "schema": {"type": "object", "required": ["rev1", "rev2"], "properties": {
            "rev1": {"type": "string"}, "rev2": {"type": "string"}}},
    },
}

MODE_B_TOOLS = {
    "vc_split": "apply one Why3 transformation to a goal in a scratch copy",
    "vc_try": "run one prover on one (sub)goal under bin/heavy",
    "why3_task": "read a subgoal's task text and source positions",
}

MODE_B_BLOCKED = (
    "prover unavailable (blocked: O-1 version lockstep, no why3find here). "
    "Mode B (%s) needs the pinned why3find/Why3 toolchain (SDK commit %s, "
    "Why3 %s, why3find %s) run through bin/heavy; neither is present. "
    "This adapter never fakes a discharge -- use Mode A over the committed "
    "proof.json, or run cargo creusot in a real workshop."
)


def _toolchain_present():
    return shutil.which("why3find") is not None and shutil.which("why3") is not None


# --------------------------------------------------------------------------
# Dispatch
# --------------------------------------------------------------------------

def call_tool(name, args):
    """Return (structured_result_dict, is_error)."""
    overlay = _overlay()
    try:
        if name == "creusot_status":
            return core.creusot_status(overlay), False
        if name == "creusot_remaining":
            return core.creusot_remaining(
                overlay, unit=args.get("unit"), module=args.get("module"),
                function=args.get("function"), tactic=args.get("tactic"),
                depth=args.get("depth")), False
        if name == "vc_goal":
            return core.vc_goal(overlay, args["id"]), False
        if name == "vc_tree":
            return core.vc_tree(overlay, args["module"]), False
        if name == "vc_provenance":
            return core.vc_provenance(overlay, args["id"]), False
        if name == "vc_locate":
            return core.vc_locate(overlay, args["id"]), False
        if name == "creusot_diff":
            return core.creusot_diff(args["rev1"], args["rev2"]), False
        if name in MODE_B_TOOLS:
            if not _toolchain_present():
                return {"error": MODE_B_BLOCKED % (
                    name, PINNED_SDK_COMMIT, PINNED_WHY3_VERSION,
                    PINNED_WHY3FIND_VERSION), "mode": "B", "banked": False}, True
            # Even when a toolchain is found, this build never banks and would
            # need the full bin/heavy guard (spec §7); not implemented here.
            return {"error": "Mode B interactive layer is not enabled in this "
                             "build (spec creusot-mcp.md O-2/O-7).",
                    "mode": "B", "banked": False}, True
        return {"error": "unknown tool %r" % name}, True
    except core.CreusotError as exc:
        return {"error": str(exc)}, True
    except (KeyError, FileNotFoundError) as exc:
        return {"error": "%s: %s" % (type(exc).__name__, exc)}, True


def _tools_list():
    tools = []
    for name, spec in MODE_A_TOOLS.items():
        tools.append({"name": name, "description": spec["description"],
                      "inputSchema": spec["schema"]})
    for name, desc in MODE_B_TOOLS.items():
        tools.append({
            "name": name,
            "description": "[Mode B, guarded] %s. Returns an error unless the "
                           "pinned toolchain is present; never banks a verdict."
                           % desc,
            "inputSchema": {"type": "object"}})
    return tools


# --------------------------------------------------------------------------
# JSON-RPC over stdio
# --------------------------------------------------------------------------

def handle(msg):
    """Return a JSON-RPC response dict, or None for a notification."""
    method = msg.get("method")
    mid = msg.get("id")
    if method == "initialize":
        return _ok(mid, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "creusot-mcp", "version": __version__},
        })
    if method == "notifications/initialized":
        return None
    if method == "tools/list":
        return _ok(mid, {"tools": _tools_list()})
    if method == "tools/call":
        params = msg.get("params", {})
        result, is_error = call_tool(params.get("name"),
                                     params.get("arguments") or {})
        text = json.dumps(result, indent=2, sort_keys=True)
        return _ok(mid, {
            "content": [{"type": "text", "text": text}],
            "structuredContent": result,
            "isError": is_error,
        })
    if mid is None:
        return None
    return {"jsonrpc": "2.0", "id": mid,
            "error": {"code": -32601, "message": "method not found: %s" % method}}


def _ok(mid, result):
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def main(argv=None):
    stdin = sys.stdin
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        resp = handle(msg)
        if resp is not None:
            sys.stdout.write(json.dumps(resp) + "\n")
            sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
