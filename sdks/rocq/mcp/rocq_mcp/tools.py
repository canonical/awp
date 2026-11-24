"""The MCP tool registry.

One entry per tool the `rocq` skill documents (references/rocq-mcp-tools-api.md
and spec/rocq-mcp.md §3).  Each carries the JSON-schema the harness needs for
`tools/list`, and the *backend class* it requires:

  - "petanque": needs a live coq-lsp/pet-server session (rocq_start, rocq_check,
    rocq_step_multi, rocq_query, rocq_toc, rocq_notations);
  - "coqc": needs a batch `coqc` under bin/heavy, no session (rocq_compile,
    rocq_verify).

`tools/list` is fully functional offline — it is the part of Mode A that works
with no prover at all.  Actually *running* a tool needs the matching backend,
which is why dispatch (dispatch.py) gates on these classes.
"""

PETANQUE = "petanque"
COQC = "coqc"

# A compact property schema helper.
_STR = {"type": "string"}
_INT = {"type": "integer"}


def _tool(name, description, backend, properties, required):
    return {
        "name": name,
        "description": description,
        "backend": backend,
        "inputSchema": {
            "type": "object",
            "properties": properties,
            "required": required,
        },
    }


TOOLS = [
    _tool(
        "rocq_start",
        "Start an interactive proof session (by theorem, by 0-based position, "
        "or from a preamble) and return a state handle plus the open goals.",
        PETANQUE,
        {
            "file": {**_STR, "description": "Path to the .v file, relative to the workspace."},
            "theorem": {**_STR, "description": "Theorem to prove (highest precedence)."},
            "line": {**_INT, "description": "0-based line (position mode)."},
            "character": {**_INT, "description": "0-based column (position mode)."},
            "preamble": {**_STR, "description": "Import context only (lowest precedence)."},
            "workspace": _STR,
        },
        [],
    ),
    _tool(
        "rocq_check",
        "Run tactics from the current (or a prior) state and return the updated "
        "goals; on proof_finished returns the recorded tactic lineage.",
        PETANQUE,
        {
            "body": {**_STR, "description": "Tactics to execute."},
            "from_state": {**_INT, "description": "Run from this handle (backtrack)."},
            "timeout": _INT,
            "workspace": _STR,
        },
        ["body"],
    ),
    _tool(
        "rocq_step_multi",
        "Try up to 20 candidate tactics from one state without advancing it "
        "(non-destructive); children deduplicated by state hash.",
        PETANQUE,
        {
            "tactics": {"type": "array", "items": _STR, "maxItems": 20},
            "from_state": _INT,
        },
        ["tactics"],
    ),
    _tool(
        "rocq_query",
        "Read-only vernac (Search/Check/Print/About/Print Assumptions) on a "
        "scratch state; answer read from the run feedback.",
        PETANQUE,
        {
            "command": {**_STR, "description": "The query vernac."},
            "preamble": _STR,
            "workspace": _STR,
        },
        ["command"],
    ),
    _tool(
        "rocq_toc",
        "Document outline (toc) of a .v file.  No session.",
        PETANQUE,
        {"file": _STR, "workspace": _STR},
        ["file"],
    ),
    _tool(
        "rocq_notations",
        "List the notations in a statement and how they resolve.",
        PETANQUE,
        {"statement": _STR, "preamble": _STR, "workspace": _STR},
        ["statement"],
    ),
    _tool(
        "rocq_compile",
        "Batch-compile a complete .v file with coqc under bin/heavy; returns "
        "0-based error_positions for rocq_start.",
        COQC,
        {
            "source": {**_STR, "description": "Complete .v file content."},
            "timeout": _INT,
            "include_warnings": {"type": "boolean"},
            "workspace": _STR,
        },
        ["source"],
    ),
    _tool(
        "rocq_verify",
        "Sandboxed verification: coqc in a fresh scratch dir on proof + "
        "problem_statement, statement comparison and Print Assumptions audit; "
        "never consults session state.",
        COQC,
        {
            "proof": _STR,
            "problem_name": _STR,
            "problem_statement": _STR,
            "timeout": _INT,
            "include_warnings": {"type": "boolean"},
            "workspace": _STR,
        },
        ["proof", "problem_name", "problem_statement"],
    ),
]

BY_NAME = {t["name"]: t for t in TOOLS}


def tool_names():
    return sorted(BY_NAME)


def backend_of(name):
    """The backend class a tool needs, or None if the tool is unknown."""
    t = BY_NAME.get(name)
    return t["backend"] if t else None


def list_payload():
    """The `tools/list` result payload (schema only, no internal `backend` key)."""
    return {
        "tools": [
            {"name": t["name"], "description": t["description"], "inputSchema": t["inputSchema"]}
            for t in TOOLS
        ]
    }
