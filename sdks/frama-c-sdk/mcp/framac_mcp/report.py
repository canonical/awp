"""Mode A core: read-only queries over a WP ``-wp-report-json`` table.

Pure, side-effect-free functions over parsed report records. No Frama-C
process is ever spawned here -- this module only *reads* the static artifact
the batch ``verify.sh`` run already banks (spec frama-c-mcp.md Mode A, section 2).

Record shape (spec section 0, ``frama-c-internals`` section 6): one record per
goal with ``file``, ``function``, ``property``, ``line``, ``passed``,
``verdict`` and ``provers``. The *goal key* is the 4-tuple
``(file, function, property, line)`` -- never the WP goal name, which is
model-prefixed (``typed_...`` / ``bytes_...``) and renumbers between runs.

Standard library only, ``-I``-safe.
"""

import json
import os

# Fields that make up the stable goal key (spec section 1/3).
KEY_FIELDS = ("file", "function", "property", "line")


class ReportError(Exception):
    """A report file is missing or not in the expected shape."""


def goal_key(record):
    """The stable (file, function, property, line) key of a goal record."""
    return tuple(record.get(f) for f in KEY_FIELDS)


def _normalize(raw, source):
    """Return (records, meta) from a parsed report document.

    Accepts either a bare JSON array of goal records, or an object that wraps
    the array under ``goals`` / ``wp:goals`` with optional run metadata
    (``wp:timeout`` / ``wp:model``). The exact top-level envelope WP emits is
    pinned from a 32.1 fixture; both forms are tolerated so a future envelope
    change does not silently misread records.
    """
    meta = {}
    if isinstance(raw, list):
        records = raw
    elif isinstance(raw, dict):
        records = None
        for key in ("goals", "wp:goals", "records"):
            if isinstance(raw.get(key), list):
                records = raw[key]
                break
        if records is None:
            raise ReportError("%s: object has no goals/wp:goals array" % source)
        for mk, out in (("wp:timeout", "timeout"), ("wp:model", "model")):
            if mk in raw:
                meta[out] = raw[mk]
    else:
        raise ReportError("%s: top level is neither array nor object" % source)
    for rec in records:
        if not isinstance(rec, dict):
            raise ReportError("%s: a record is not an object" % source)
    return records, meta


class Report:
    """A loaded ``-wp-report-json`` table plus the path it was read from."""

    def __init__(self, records, source, meta=None):
        self.records = records
        self.source = source            # report file path (spec section 8: name the run)
        self.meta = meta or {}

    @classmethod
    def load(cls, path):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                raw = json.load(fh)
        except FileNotFoundError:
            raise ReportError("report not found: %s" % path)
        except (OSError, ValueError) as exc:
            raise ReportError("cannot read report %s: %s" % (path, exc))
        records, meta = _normalize(raw, path)
        return cls(records, path, meta)

    def by_key(self):
        return {goal_key(r): r for r in self.records}


def is_open(record):
    """A goal is open (an obligation that still stands) when it is not passed.

    ``passed`` is the primary signal (spec/internals section 6). When absent,
    fall back to the verdict vocabulary: only ``valid`` closes a goal.
    """
    if "passed" in record and record["passed"] is not None:
        return not bool(record["passed"])
    return str(record.get("verdict", "")).lower() != "valid"


def _model_of(record):
    """Best-effort model (Typed vs bytes) from the goal-name prefix.

    The report does not carry the run's model as a dedicated field in the
    shape this spec pins; the goal name is model-prefixed (section 1), so the
    prefix is the only in-artifact signal. Returns None when unknown.
    """
    name = str(record.get("goal", record.get("name", "")))
    low = name.lower()
    if low.startswith("typed"):
        return "Typed"
    if low.startswith("bytes"):
        return "bytes"
    return None


# --- the section 3 tool surface, Mode A -------------------------------------

def wp_status(report):
    """Summary: total, passed, per-verdict counts, and which run it was read from."""
    verdicts = {}
    passed = 0
    for rec in report.records:
        v = str(rec.get("verdict", "unknown"))
        verdicts[v] = verdicts.get(v, 0) + 1
        if not is_open(rec):
            passed += 1
    total = len(report.records)
    return {
        "run": report.source,
        "total": total,
        "passed": passed,
        "open": total - passed,
        "verdicts": verdicts,
    }


def wp_remaining(report, file=None, function=None, property=None,
                 prover=None, verdict=None):
    """Open obligations, filterable by file/function/property/prover/verdict."""
    out = []
    for rec in report.records:
        if not is_open(rec):
            continue
        if file is not None and rec.get("file") != file:
            continue
        if function is not None and rec.get("function") != function:
            continue
        if property is not None and rec.get("property") != property:
            continue
        if verdict is not None and str(rec.get("verdict")) != verdict:
            continue
        if prover is not None and prover not in _prover_names(rec):
            continue
        out.append(_goal_view(rec))
    return {"run": report.source, "open": len(out), "goals": out}


def _prover_names(record):
    names = []
    for p in record.get("provers", []) or []:
        if isinstance(p, dict):
            names.append(p.get("name") or p.get("prover"))
        else:
            names.append(p)
    return [n for n in names if n]


def _goal_view(record):
    return {
        "file": record.get("file"),
        "function": record.get("function"),
        "property": record.get("property"),
        "line": record.get("line"),
        "verdict": record.get("verdict"),
        "passed": record.get("passed"),
        "provers": record.get("provers", []),
        "goal": record.get("goal", record.get("name")),
    }


def wp_goal(report, key):
    """One goal by (file, function, property, line) key."""
    key = tuple(key)
    rec = report.by_key().get(key)
    if rec is None:
        return {"run": report.source, "found": False, "key": list(key)}
    view = _goal_view(rec)
    view["run"] = report.source
    view["found"] = True
    return view


def wp_locate(report, property):
    """Source (file, line) for a property / function contract (Mode A: from json)."""
    hits = []
    for rec in report.records:
        if rec.get("property") == property:
            hits.append({"file": rec.get("file"), "line": rec.get("line"),
                         "function": rec.get("function")})
    return {"run": report.source, "property": property, "locations": hits}


def wp_provenance(report, key, verdicts_tsv=None):
    """Which prover closed a goal, in which run/model, and that run's timeout.

    Model is derived from the goal-name prefix (Typed vs bytes). The run's
    ``-wp-timeout`` is taken from report metadata when present, else from the
    verdicts.tsv recovery path (open point O-7); when neither is available it
    is reported as None, never fabricated.
    """
    key = tuple(key)
    rec = report.by_key().get(key)
    if rec is None:
        return {"run": report.source, "found": False, "key": list(key)}
    closer = None
    for p in rec.get("provers", []) or []:
        if isinstance(p, dict) and str(p.get("verdict", "")).lower() == "valid":
            closer = {"name": p.get("name") or p.get("prover"),
                      "time": p.get("time")}
            break
    timeout = report.meta.get("timeout")
    if timeout is None and verdicts_tsv:
        timeout = _timeout_from_tsv(verdicts_tsv, key)
    return {
        "run": report.source,
        "found": True,
        "key": list(key),
        "closed_by": closer,
        "model": report.meta.get("model") or _model_of(rec),
        "wp_timeout": timeout,
        "timeout_source": "report-meta" if report.meta.get("timeout") is not None
        else ("verdicts.tsv" if timeout is not None else "unknown (O-7)"),
    }


def _timeout_from_tsv(path, key):
    """Best-effort -wp-timeout recovery from a verdicts.tsv (O-7, optional)."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                cols = line.rstrip("\n").split("\t")
                # Heuristic: a row mentioning the function and carrying a numeric
                # timeout column. Kept tolerant; O-7 fixes the real schema.
                if key[1] and key[1] in cols:
                    for c in cols:
                        if c.isdigit():
                            return int(c)
    except OSError:
        return None
    return None


def wp_diff(report1, report2):
    """Goals that changed status between two runs, keyed by (file,function,property,line).

    Keying by the stable tuple (not the goal name) means WP renumbering goals
    between runs produces no spurious change (spec T-A2, section 10).
    """
    a = report1.by_key()
    b = report2.by_key()
    newly_closed, regressed, added, removed = [], [], [], []
    for key in sorted(set(a) | set(b), key=lambda k: tuple("" if x is None else str(x) for x in k)):
        ra, rb = a.get(key), b.get(key)
        entry = {"key": list(key)}
        if ra is not None and rb is not None:
            oa, ob = is_open(ra), is_open(rb)
            if oa and not ob:
                newly_closed.append(entry)
            elif not oa and ob:
                regressed.append(entry)
        elif rb is not None:          # only in run2
            e = dict(entry, open=is_open(rb))
            added.append(e)
        else:                          # only in run1
            e = dict(entry, open=is_open(ra))
            removed.append(e)
    return {
        "run1": report1.source,
        "run2": report2.source,
        "newly_closed": newly_closed,
        "regressed": regressed,
        "added": added,
        "removed": removed,
    }


def latest_report(reports_dir):
    """Most recently modified *.json in a reports dir, or None."""
    try:
        names = [n for n in os.listdir(reports_dir) if n.endswith(".json")]
    except OSError:
        return None
    if not names:
        return None
    paths = [os.path.join(reports_dir, n) for n in names]
    return max(paths, key=lambda p: os.path.getmtime(p))
