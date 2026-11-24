"""Pure adapter logic: argument validation/normalisation, Petanque-response
parsing, and the adapter-side state bookkeeping.

Nothing here talks to a prover; every function is a total transformation over
JSON-shaped Python values.  This is the part of the adapter that the Mode A
unit tests exercise directly, with SYNTHETIC Petanque fixtures (there is no
real coq-lsp on this host to capture a real one — tests/mcp/fixtures/README).

Petanque shapes assumed (pytanque JSON, spec §1):
  - Run_result: {"st": int, "proof_finished": bool, "hash"?: int,
                 "feedback": [[level, message], ...]}
  - goals:      {"goals": [{"hyps": [...], "ty": "<concl>"}, ...]} or a bare list
  - feedback level 1 == Error (coq-lsp DocumentDiagnostic severity).
"""


class ValidationError(ValueError):
    """Raised for a malformed tool-call argument set (maps to an MCP tool error)."""


# --------------------------------------------------------------------------
# Argument validation / normalisation (precedence and caps the skill promises)
# --------------------------------------------------------------------------

def start_mode(args):
    """Resolve rocq_start's mode by the skill's precedence theorem > position >
    preamble.  Returns (mode, normalised_args).  0-based positions are passed
    through unchanged (the skill API and Petanque agree on 0-based)."""
    if args.get("theorem"):
        if not args.get("file"):
            raise ValidationError("rocq_start by theorem needs `file`")
        return "theorem", {"file": args["file"], "theorem": args["theorem"]}
    line, char = args.get("line"), args.get("character")
    if line is not None and char is not None:
        if not args.get("file"):
            raise ValidationError("rocq_start by position needs `file`")
        if line < 0 or char < 0:
            raise ValidationError("rocq_start positions are 0-based and non-negative")
        return "position", {"file": args["file"], "line": line, "character": char}
    if args.get("preamble"):
        return "preamble", {"preamble": args["preamble"]}
    raise ValidationError("rocq_start needs theorem, (line,character), or preamble")


MAX_TACTICS = 20


def step_multi_tactics(args):
    """Validate rocq_step_multi's tactic list (the spec caps it at 20)."""
    tactics = args.get("tactics")
    if not isinstance(tactics, list) or not tactics:
        raise ValidationError("rocq_step_multi needs a non-empty `tactics` list")
    if not all(isinstance(t, str) for t in tactics):
        raise ValidationError("rocq_step_multi tactics must be strings")
    if len(tactics) > MAX_TACTICS:
        raise ValidationError("rocq_step_multi caps at %d tactics (got %d)"
                              % (MAX_TACTICS, len(tactics)))
    return tactics


# --------------------------------------------------------------------------
# Petanque response parsing
# --------------------------------------------------------------------------

def parse_feedback(feedback):
    """Normalise Petanque feedback ([[level, message], ...] or [{...}]) to a
    list of {"level": int|None, "message": str}."""
    out = []
    for item in feedback or []:
        if isinstance(item, (list, tuple)) and len(item) >= 2:
            out.append({"level": item[0], "message": item[1]})
        elif isinstance(item, dict):
            out.append({"level": item.get("level"),
                        "message": item.get("message") or item.get("msg") or ""})
    return out


ERROR_LEVEL = 1


def has_error(feedback):
    """True if any normalised feedback entry is at the Error level."""
    return any(e.get("level") == ERROR_LEVEL for e in feedback)


def parse_run_result(obj):
    """Parse a Petanque Run_result.  Returns the adapter's normalised view;
    the caller assigns the handle (see StateStore) — `petanque_state` is the
    raw `st` value Petanque returned."""
    if not isinstance(obj, dict):
        raise ValidationError("Run_result is not an object")
    feedback = parse_feedback(obj.get("feedback"))
    return {
        "petanque_state": obj.get("st"),
        "proof_finished": bool(obj.get("proof_finished", False)),
        "hash": obj.get("hash"),
        "feedback": feedback,
        "messages": [e["message"] for e in feedback],
        "error": has_error(feedback),
    }


def _parse_hyp(h):
    if isinstance(h, dict):
        names = h.get("names") or h.get("name")
        if isinstance(names, list):
            names = ", ".join(names)
        return {"names": names, "type": h.get("ty") or h.get("type")}
    return {"names": None, "type": str(h)}


def parse_goals(obj):
    """Parse a Petanque `goals` result into [{"hypotheses": [...],
    "conclusion": str}, ...].  Accepts the {"goals": [...]} envelope or a bare
    list."""
    goals = obj.get("goals", []) if isinstance(obj, dict) else obj
    result = []
    for g in goals or []:
        result.append({
            "hypotheses": [_parse_hyp(h) for h in (g.get("hyps") or [])],
            "conclusion": g.get("ty") or g.get("pp") or g.get("conclusion"),
        })
    return result


def parse_toc(obj):
    """Flatten a Petanque `toc` outline to [{"name": str, "kind": str}, ...]."""
    entries = obj.get("toc", obj) if isinstance(obj, dict) else obj
    out = []

    def walk(node):
        if isinstance(node, dict):
            if "name" in node:
                out.append({"name": node.get("name"), "kind": node.get("kind")})
            for child in node.get("children") or []:
                walk(child)
        elif isinstance(node, (list, tuple)):
            for n in node:
                walk(n)

    walk(entries)
    return out


def parse_premises(obj):
    """Parse a Petanque `premises` result into a list of fully-qualified names."""
    prems = obj.get("premises", obj) if isinstance(obj, dict) else obj
    out = []
    for p in prems or []:
        if isinstance(p, dict):
            out.append(p.get("name") or p.get("fullname"))
        else:
            out.append(p)
    return out


# --------------------------------------------------------------------------
# Adapter-side state bookkeeping (handles, lineage, hash dedup)
# --------------------------------------------------------------------------

class StateStore:
    """Maps adapter handles (small ints the skill sees) to Petanque states and
    records each handle's tactic lineage (for proof_tactics).  Branches that
    reach the same state/hash collapse to one handle — the dedup the spec asks
    `rocq_step_multi` to do.  Non-destructiveness itself is Petanque's (states
    are values); this is only the bookkeeping on top."""

    def __init__(self):
        self._states = []       # handle -> petanque state
        self._lineage = {}      # handle -> [tactic, ...]
        self._by_hash = {}      # petanque hash -> handle

    def add(self, petanque_state, lineage=None, state_hash=None):
        if state_hash is not None and state_hash in self._by_hash:
            return self._by_hash[state_hash]
        handle = len(self._states)
        self._states.append(petanque_state)
        self._lineage[handle] = list(lineage or [])
        if state_hash is not None:
            self._by_hash[state_hash] = handle
        return handle

    def petanque_state(self, handle):
        if handle < 0 or handle >= len(self._states):
            raise ValidationError("unknown state handle %r" % (handle,))
        return self._states[handle]

    def lineage(self, handle):
        if handle not in self._lineage:
            raise ValidationError("unknown state handle %r" % (handle,))
        return list(self._lineage[handle])

    def extend(self, parent, petanque_state, tactic, state_hash=None):
        """Record a child of `parent` reached by `tactic`."""
        child_lineage = self.lineage(parent) + [tactic]
        return self.add(petanque_state, child_lineage, state_hash)

    def __len__(self):
        return len(self._states)
