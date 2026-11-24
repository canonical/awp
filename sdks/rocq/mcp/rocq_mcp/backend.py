"""Backend detection and the pet-server launch plan.

Mode A ships no live backend wiring that runs on this host (no coqc, no
pet-server, no pytanque — all absent; the live path is blocked on O-1/O-2).
What *is* here and testable:

  - `probe_backend(env)`: decide, from the environment, which backend classes
    are reachable.  With nothing installed it reports both unreachable, and
    dispatch then returns the structured "backend unavailable" error.
  - `pet_launch_plan(env)`: the *marks* the adapter must give a pet-server
    child so the R6 mem-watchdog treats it as the long-lived-server class
    (spec §7.2): its own process group, `oom_score_adj=1000`, and a `ulimit
    -v` from ROCQ_PET_MEM_KB (default HEAVY_MEM_KB).  Pure data — the actual
    spawn is blocked, but the plan is unit-tested so the marks can't silently
    drift.
"""
import os
import shutil


class Backend:
    """What the adapter can reach.  `petanque` = a live coq-lsp/pet-server
    session; `coqc` = a batch compiler for rocq_compile/rocq_verify."""

    def __init__(self, petanque=False, coqc=False, detail=""):
        self.petanque = petanque
        self.coqc = coqc
        self.detail = detail

    def has(self, backend_class):
        return getattr(self, backend_class, False)


def _pytanque_importable():
    import importlib.util  # stdlib
    return importlib.util.find_spec("pytanque") is not None


def probe_backend(env=None):
    """Detect reachable backends without side effects on the prover.

    pet-server/pet presence is a necessary condition for the Petanque class and
    `coqc` for the batch class; pytanque is required to drive Petanque.  On a
    host with no Rocq toolchain every check fails and dispatch degrades to the
    structured-error path (which is exactly the Mode A contract here)."""
    env = os.environ if env is None else env
    path = env.get("PATH", "")
    which = lambda b: shutil.which(b, path=path) is not None  # noqa: E731

    has_server = which("pet-server") or which("pet")
    petanque = bool(has_server and _pytanque_importable())
    coqc = which("coqc")

    bits = []
    if not has_server:
        bits.append("no pet-server/pet on PATH (O-1/O-2)")
    elif not _pytanque_importable():
        bits.append("pytanque not importable")
    if not coqc:
        bits.append("no coqc on PATH")
    detail = "; ".join(bits) if bits else "backends reachable"
    return Backend(petanque=petanque, coqc=bool(coqc), detail=detail)


# Default memory cap for pet-server; mirrors HEAVY_MEM_KB (1.5 GiB) when unset.
DEFAULT_HEAVY_MEM_KB = 1572864


def pet_launch_plan(env=None):
    """The marks for a pet-server child (spec §7.2).  Returns a dict; it does
    not spawn anything."""
    env = os.environ if env is None else env
    heavy = env.get("HEAVY_MEM_KB")
    mem_kb = env.get("ROCQ_PET_MEM_KB") or heavy or str(DEFAULT_HEAVY_MEM_KB)
    try:
        mem_kb = int(mem_kb)
    except (TypeError, ValueError):
        mem_kb = DEFAULT_HEAVY_MEM_KB
    return {
        # Own process group so the watchdog can group+kill it and the adapter
        # can reap it independently (setsid / os.setsid at spawn).
        "own_process_group": True,
        # The watchdog keys solely on this value — this mark alone enrolls the
        # server in the long-lived-server class, no watchdog code change.
        "oom_score_adj": 1000,
        # ulimit -v (address space), in KiB.
        "ulimit_v_kb": mem_kb,
    }
