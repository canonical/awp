"""Tool dispatch.

Validates a tool call's arguments (pure, parse.py) and checks the required
backend class is reachable.  When it is not — the state on this host, and
whenever coq-lsp/pet-server is down — it returns a *structured* MCP tool error
("backend unavailable", with the blocking open points named) rather than
crashing or fabricating a prover result.

The live branch (a reachable backend) is intentionally a thin stub: wiring it
to pytanque is blocked on O-1/O-2 and untestable here, so it fails closed with
a clear "not implemented in Mode A" error instead of pretending to prove.
"""
from . import tools
from .parse import ValidationError, start_mode, step_multi_tactics


def _error_result(text, structured):
    return {
        "isError": True,
        "content": [{"type": "text", "text": text}],
        "structuredContent": structured,
    }


def backend_unavailable_result(name, backend_class, detail):
    """The structured error for a tool whose backend is not reachable."""
    if backend_class == tools.PETANQUE:
        blocked = ["O-1", "O-2"]
        why = ("no coq-lsp/pet-server reachable for Rocq 9.2 — a +9.2 coq-lsp "
               "build is unresolved (O-2) and the adapter/transport is O-1")
    else:  # coqc
        blocked = ["toolchain"]
        why = "coqc not found on PATH (no Rocq toolchain on this host)"
    if detail:
        why = "%s [%s]" % (why, detail)
    return _error_result(
        "rocq-mcp: backend unavailable for %s: %s" % (name, why),
        {
            "error": "backend_unavailable",
            "tool": name,
            "backend": backend_class,
            "blocked": blocked,
            "detail": why,
        },
    )


def _validation_result(name, exc):
    return _error_result(
        "rocq-mcp: invalid arguments for %s: %s" % (name, exc),
        {"error": "invalid_arguments", "tool": name, "detail": str(exc)},
    )


# Per-tool argument validators (pure).  Absence means "no extra validation".
_VALIDATORS = {
    "rocq_start": lambda a: start_mode(a),
    "rocq_step_multi": lambda a: step_multi_tactics(a),
}


def validate(name, args):
    """Run the tool's argument validator plus the schema's `required` list.
    Raises ValidationError on a bad call; returns None otherwise."""
    spec = tools.BY_NAME.get(name)
    if spec is None:
        raise ValidationError("unknown tool %r" % (name,))
    for req in spec["inputSchema"]["required"]:
        if args.get(req) in (None, ""):
            raise ValidationError("%s requires `%s`" % (name, req))
    validator = _VALIDATORS.get(name)
    if validator is not None:
        validator(args)


def dispatch(name, args, backend):
    """Handle one `tools/call`.  Returns an MCP tool-result dict (never raises
    for an expected condition)."""
    args = args or {}
    spec = tools.BY_NAME.get(name)
    if spec is None:
        return _error_result(
            "rocq-mcp: unknown tool %r" % (name,),
            {"error": "unknown_tool", "tool": name},
        )

    try:
        validate(name, args)
    except ValidationError as exc:
        return _validation_result(name, exc)

    backend_class = spec["backend"]
    if backend is None or not backend.has(backend_class):
        detail = getattr(backend, "detail", "") if backend is not None else "no backend"
        return backend_unavailable_result(name, backend_class, detail)

    # Reachable-backend branch: not implemented in Mode A.  Fail closed — never
    # fabricate a result (spec §6: the batch gate banks the verdict, not us).
    return _error_result(
        "rocq-mcp: %s reached a live backend but the Mode A adapter does not "
        "drive it yet (blocked: O-1 live Petanque wiring)" % (name,),
        {"error": "not_implemented_mode_a", "tool": name, "backend": backend_class,
         "blocked": ["O-1"]},
    )
