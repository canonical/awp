"""Mode A core: parse why3find proof.json trees and answer read-only queries.

Everything here is a plain reader of committed files (spec creusot-mcp.md §2,
§8): no prover and no Why3 process is ever spawned, so every result is
reproducible by a human re-reading the same artifacts at the same commit.

Artifact shape (spec §1), learned from real fixtures:
  proof.json = {"profile": [...],
                "proofs": {"Coma": {"vc_<name>": GOAL, ...}}}
  GOAL is a leaf   {"prover": "alt-ergo", "time": 0.013}
         a node    {"tactic": "split_vc"|"compute_specified", "children": [...]}
         or a FAILED leaf: null.
  children are POSITIONAL (no goal explanation, no source span).
A why3session.xml, where present, carries the richer expl/proved per node.
"""

import glob
import json
import os
import re
import subprocess
import xml.etree.ElementTree as ET


# --------------------------------------------------------------------------
# Low-level artifact model
# --------------------------------------------------------------------------

class CreusotError(Exception):
    """A query that cannot be answered honestly from the committed files."""


def _module_id(verif_dir, proof_json_path):
    """Relative module id, e.g. 'hp_swar_32_rlib/impl_Bytes/advance'."""
    rel = os.path.relpath(os.path.dirname(proof_json_path), verif_dir)
    return rel.replace(os.sep, "/")


def _unit_of(module_id):
    """The <crate>_rlib directory a module lives in."""
    return module_id.split("/", 1)[0]


def _function_of(goal_name):
    """'vc_parse_chunk_size' -> 'parse_chunk_size' (best effort)."""
    name = goal_name
    if name.startswith("vc_"):
        name = name[3:]
    # strip a trailing why3find positional suffix if any leaked into the key
    return name.split("'", 1)[0]


def find_verif_dir(overlay):
    """Locate the verif/ tree under an overlay root."""
    cand = os.path.join(overlay, "verif")
    if os.path.isdir(cand):
        return cand
    # the overlay root may itself be a verif/ tree
    if os.path.basename(os.path.normpath(overlay)) == "verif":
        return overlay
    raise CreusotError("no verif/ tree under %r" % overlay)


def list_proof_jsons(verif_dir):
    return sorted(glob.glob(os.path.join(verif_dir, "**", "proof.json"),
                            recursive=True))


def load_proof_json(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return json.load(fh)


def iter_leaves(node):
    """Yield (leaf_or_None) for every leaf in a goal subtree, in order."""
    if node is None:
        yield None
        return
    if "children" in node:
        for child in node["children"]:
            for leaf in iter_leaves(child):
                yield leaf
    else:
        yield node


def goal_proved(node):
    """True iff every leaf in the subtree discharged (no null leaf)."""
    return all(leaf is not None for leaf in iter_leaves(node))


def node_tactics(node):
    """Set of tactic names used anywhere in a subtree."""
    out = set()
    if isinstance(node, dict):
        if "tactic" in node:
            out.add(node["tactic"])
        for child in node.get("children", []):
            out |= node_tactics(child)
    return out


def node_depth(node):
    """Transformation depth of a goal subtree (leaf = 0)."""
    if not isinstance(node, dict) or "children" not in node:
        return 0
    return 1 + max((node_depth(c) for c in node["children"]), default=0)


def _goals_of(proof):
    """Top-level {goal_name: node} under proofs.Coma (and any theory)."""
    out = {}
    for theory in proof.get("proofs", {}).values():
        out.update(theory)
    return out


# --------------------------------------------------------------------------
# Provenance and the in-flight guard (spec §3, §8)
# --------------------------------------------------------------------------

def git_commit(path):
    try:
        out = subprocess.run(
            ["git", "-C", path, "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=10)
        if out.returncode == 0:
            return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def provenance(overlay, path):
    try:
        mtime = os.path.getmtime(path)
    except OSError:
        mtime = None
    return {
        "commit": git_commit(overlay),
        "path": os.path.relpath(path, overlay) if path else None,
        "mtime": mtime,
    }


_SUMMARY_RE = re.compile(
    r"Proved \(\d+ files?\)|unproved file|Error:|'why3find prove' failed")


def _default_prove_active(verif_dir):
    """True iff a `why3find prove` is running on this verif/ tree."""
    try:
        out = subprocess.run(["pgrep", "-af", "why3find prove"],
                             capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return False
    if out.returncode != 0:
        return False
    target = os.path.abspath(verif_dir)
    for line in out.stdout.splitlines():
        # match a prove whose command line names this tree (best effort)
        if target in line or os.path.basename(target) in line:
            return True
    return False


def in_flight(overlay, run_log="run.log", prove_active=None):
    """Return (bool, reason) per the oracle-integrity rule (spec §8).

    in_flight is true when a `why3find prove` is active on the tree, or when a
    run log is present but lacks a final summary (a partial proof.json is not a
    verdict). A missing run log is NOT a trigger: committed artifacts with no
    active run are reproducible and summarizable.
    """
    try:
        verif_dir = find_verif_dir(overlay)
    except CreusotError:
        verif_dir = overlay
    checker = prove_active if prove_active is not None else _default_prove_active
    if checker(verif_dir):
        return True, "a why3find prove is active on %s" % verif_dir
    log_path = run_log if os.path.isabs(run_log) else os.path.join(overlay, run_log)
    if os.path.exists(log_path):
        with open(log_path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        if not _SUMMARY_RE.search(text):
            return True, "run log %s has no final summary" % os.path.basename(log_path)
    return False, None


def _guard(overlay, run_log, prove_active):
    flag, reason = in_flight(overlay, run_log=run_log, prove_active=prove_active)
    if flag:
        raise CreusotError(
            "in_flight: refusing to summarize a verif/ tree while %s "
            "(oracle-integrity rule, spec creusot-mcp.md §8)" % reason)


# --------------------------------------------------------------------------
# why3session.xml (richer read where present)
# --------------------------------------------------------------------------

def load_session(proof_json_path):
    """Return {goal_name: {'expl':..., 'proved':bool}} from a sibling
    why3session.xml, or {} when none is present."""
    session = os.path.join(os.path.dirname(proof_json_path), "why3session.xml")
    if not os.path.exists(session):
        return {}
    out = {}
    try:
        root = ET.parse(session).getroot()
    except ET.ParseError:
        return {}
    for goal in root.iter("goal"):
        name = goal.get("name")
        if name is None:
            continue
        out[name] = {
            "expl": goal.get("expl"),
            "proved": goal.get("proved") == "true",
        }
    return out


# --------------------------------------------------------------------------
# Mode A tools
# --------------------------------------------------------------------------

def _scan(overlay):
    verif_dir = find_verif_dir(overlay)
    for path in list_proof_jsons(verif_dir):
        proof = load_proof_json(path)
        yield verif_dir, path, proof


def creusot_status(overlay, run_log="run.log", prove_active=None):
    _guard(overlay, run_log, prove_active)
    verif_dir = find_verif_dir(overlay)
    modules = goals = leaves = discharged = unproved = 0
    for path in list_proof_jsons(verif_dir):
        proof = load_proof_json(path)
        modules += 1
        for node in _goals_of(proof).values():
            goals += 1
            for leaf in iter_leaves(node):
                leaves += 1
                if leaf is None:
                    unproved += 1
                else:
                    discharged += 1
    return {
        "modules": modules,
        "goals": goals,
        "leaves": leaves,
        "discharged": discharged,
        "unproved": unproved,
        "in_flight": False,
        "provenance": provenance(overlay, verif_dir),
    }


def creusot_remaining(overlay, unit=None, module=None, function=None,
                      tactic=None, depth=None, run_log="run.log",
                      prove_active=None):
    """List unproved (null) leaves, with their positional path and filters."""
    _guard(overlay, run_log, prove_active)
    verif_dir = find_verif_dir(overlay)
    out = []
    for path in list_proof_jsons(verif_dir):
        proof = load_proof_json(path)
        mid = _module_id(verif_dir, path)
        if module is not None and mid != module:
            continue
        if unit is not None and _unit_of(mid) != unit:
            continue
        for gname, node in _goals_of(proof).items():
            if function is not None and _function_of(gname) != function:
                continue
            if tactic is not None and tactic not in node_tactics(node):
                continue
            if depth is not None and node_depth(node) != depth:
                continue
            for pos in _unproved_positions(node):
                out.append({
                    "module": mid,
                    "unit": _unit_of(mid),
                    "function": _function_of(gname),
                    "goal": gname,
                    "position": pos,          # e.g. "0.141.0.0.0" or "" for a top leaf
                    "tactics": sorted(node_tactics(node)),
                    "depth": node_depth(node),
                })
    return {"remaining": out, "count": len(out),
            "provenance": provenance(overlay, verif_dir)}


def _unproved_positions(node, prefix=""):
    """Positional paths (dotted child indices) of every null leaf."""
    if node is None:
        return [prefix.lstrip(".")]
    if "children" not in node:
        return []
    out = []
    for i, child in enumerate(node["children"]):
        out += _unproved_positions(child, "%s.%d" % (prefix, i))
    return out


def _walk_position(node, parts):
    """Descend positional child indices; returns the subtree or raises."""
    cur = node
    for p in parts:
        if cur is None or "children" not in cur:
            raise CreusotError("position %r overruns the tree" % ".".join(parts))
        try:
            cur = cur["children"][int(p)]
        except (ValueError, IndexError):
            raise CreusotError("bad position component %r" % p)
    return cur


def _parse_id(goal_id):
    """'Coma.vc_foo.0.3' -> ('vc_foo', ['0','3'])."""
    body = goal_id
    if body.startswith("Coma."):
        body = body[len("Coma."):]
    m = re.match(r"(vc_[^.]+(?:'[0-9]+)?)((?:\.[0-9]+)*)$", body)
    if not m:
        raise CreusotError("unrecognized goal id %r" % goal_id)
    pos = [p for p in m.group(2).split(".") if p]
    return m.group(1), pos


def _find_goal(overlay, goal_name):
    verif_dir = find_verif_dir(overlay)
    for path in list_proof_jsons(verif_dir):
        proof = load_proof_json(path)
        goals = _goals_of(proof)
        if goal_name in goals:
            return verif_dir, path, proof, goals[goal_name]
    raise CreusotError("goal %r not found in any module" % goal_name)


def vc_goal(overlay, goal_id):
    """One goal: tactic path, prover, time, status; expl from a session."""
    gname, pos = _parse_id(goal_id)
    verif_dir, path, proof, top = _find_goal(overlay, gname)
    node = _walk_position(top, pos)
    mid = _module_id(verif_dir, path)
    session = load_session(path)
    full_name = gname if not pos else "%s.%s" % (gname, ".".join(pos))
    expl = None
    proved_session = None
    if full_name in session:
        expl = session[full_name]["expl"]
        proved_session = session[full_name]["proved"]
    result = {
        "id": "Coma.%s" % full_name,
        "module": mid,
        "function": _function_of(gname),
        "tactics": sorted(node_tactics(node)),
        "depth": node_depth(node),
        "proved": goal_proved(node),
        "expl": expl,
        "provenance": provenance(overlay, path),
    }
    if proved_session is not None:
        result["session_proved"] = proved_session
    if node is None:
        result["status"] = "unproved"
    elif "children" in node:
        result["status"] = "proved" if goal_proved(node) else "unproved"
        result["subgoals"] = len(node["children"])
    else:
        result["status"] = "proved"
        result["prover"] = node.get("prover")
        result["time"] = node.get("time")
    return result


def vc_tree(overlay, module):
    """Reconstruct the transformation tree with per-node status, merging the
    session's expl/proved where a why3session.xml is present."""
    verif_dir = find_verif_dir(overlay)
    target = None
    for path in list_proof_jsons(verif_dir):
        if _module_id(verif_dir, path) == module:
            target = path
            break
    if target is None:
        raise CreusotError("module %r not found" % module)
    proof = load_proof_json(target)
    session = load_session(target)

    def build(node, name):
        info = session.get(name, {})
        if node is None:
            return {"status": "unproved", "expl": info.get("expl")}
        if "children" in node:
            kids = []
            for i, child in enumerate(node["children"]):
                kids.append(build(child, "%s.%d" % (name, i)))
            return {
                "tactic": node["tactic"],
                "status": "proved" if goal_proved(node) else "unproved",
                "expl": info.get("expl"),
                "children": kids,
            }
        return {
            "status": "proved",
            "prover": node.get("prover"),
            "time": node.get("time"),
            "expl": info.get("expl"),
        }

    tree = {name: build(node, name) for name, node in _goals_of(proof).items()}
    return {
        "module": module,
        "has_session": bool(session),
        "tree": tree,
        "provenance": provenance(overlay, target),
    }


def _load_verdicts(overlay):
    """Parse XXX-creusot/verdicts.tsv if present -> list of dict rows."""
    path = os.path.join(overlay, "verdicts.tsv")
    if not os.path.exists(path):
        return [], None
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    if not lines:
        return [], path
    header = lines[0].split("\t")
    for line in lines[1:]:
        if not line.strip():
            continue
        cells = line.split("\t")
        rows.append(dict(zip(header, cells)))
    return rows, path


def vc_provenance(overlay, goal_id):
    """Prover+time that closed a goal, and the verdicts.tsv row that banked it."""
    gname, pos = _parse_id(goal_id)
    verif_dir, path, proof, top = _find_goal(overlay, gname)
    node = _walk_position(top, pos)
    leaves = [leaf for leaf in iter_leaves(node) if leaf is not None]
    provers = sorted({leaf.get("prover") for leaf in leaves})
    total_time = round(sum(leaf.get("time", 0.0) for leaf in leaves), 6)
    func = _function_of(gname)
    rows, vpath = _load_verdicts(overlay)
    ledger = [r for r in rows
              if func in (r.get("function", "")) or r.get("function", "") in func]
    return {
        "id": goal_id,
        "function": func,
        "proved": goal_proved(node),
        "provers": provers,
        "total_time": total_time,
        "leaves": len(list(iter_leaves(node))),
        "ledger_rows": ledger,
        "commit": git_commit(overlay),
        "provenance": provenance(overlay, path),
    }


def vc_locate(overlay, goal_id):
    """PARTIAL in Mode A (spec §3, O): proof.json children are positional and
    carry no source span. Where a why3session.xml exists we can name the leaf's
    `expl`; a full (file, line, clause) needs the Why3 task (Mode B)."""
    gname, pos = _parse_id(goal_id)
    verif_dir, path, proof, top = _find_goal(overlay, gname)
    session = load_session(path)
    full_name = gname if not pos else "%s.%s" % (gname, ".".join(pos))
    expl = session.get(full_name, {}).get("expl")
    return {
        "id": goal_id,
        "partial": True,
        "reason": ("Mode A over proof.json is positional: no source span. "
                   "expl is available only from a why3session.xml; a full "
                   "(file, line, clause) requires the Why3 task (Mode B, "
                   "blocked here)."),
        "expl": expl,
        "module": _module_id(verif_dir, path),
        "provenance": provenance(overlay, path),
    }


# --------------------------------------------------------------------------
# creusot_diff over two COMMITTED revisions (spec §3, §8)
# --------------------------------------------------------------------------

def _status_map(overlay):
    """{'<module>::<goal>': proved_bool} across the whole overlay."""
    verif_dir = find_verif_dir(overlay)
    out = {}
    for path in list_proof_jsons(verif_dir):
        proof = load_proof_json(path)
        mid = _module_id(verif_dir, path)
        for gname, node in _goals_of(proof).items():
            out["%s::%s" % (mid, gname)] = goal_proved(node)
    return out


def creusot_diff(overlay_rev1, overlay_rev2):
    """Goals that changed status between two committed revisions.

    regressed  : proved in rev1, unproved in rev2 (standing proof regressed)
    newly_open : absent in rev1, present & unproved in rev2
    closed     : unproved or absent in rev1, proved in rev2
    removed/added: informational.
    """
    a = _status_map(overlay_rev1)
    b = _status_map(overlay_rev2)
    regressed, newly_open, closed, removed, added = [], [], [], [], []
    for key in sorted(set(a) | set(b)):
        in_a, in_b = key in a, key in b
        if in_a and in_b:
            if a[key] and not b[key]:
                regressed.append(key)
            elif not a[key] and b[key]:
                closed.append(key)
        elif in_b and not in_a:
            added.append(key)
            if not b[key]:
                newly_open.append(key)
        elif in_a and not in_b:
            removed.append(key)
    return {
        "regressed": regressed,
        "newly_open": newly_open,
        "closed": closed,
        "added": added,
        "removed": removed,
        "rev1": {"commit": git_commit(overlay_rev1)},
        "rev2": {"commit": git_commit(overlay_rev2)},
    }
