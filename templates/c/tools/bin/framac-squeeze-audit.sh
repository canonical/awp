#!/bin/sh
# framac-squeeze-audit.sh — check a filled squeeze table for disjointness compliance.
# (WS2 of fc-sl-loops-improve-plan.md; SL paper compliance C1 + C3.)
#
# Usage: ./framac-squeeze-audit.sh CAMPAIGN-squeeze-table.md
# Exit 0 if compliant, 1 on any violation.
#
# Checks:
#   C1  pairwise-distinct (U,L) pairs — two actors with identical (U,L) are one actor.
#   C3  every JUDGE role (property-author, verifier, completeness oracle, monitor) lists the
#       implementation / annotation / diff / scaffolding as Denied (absent from its context).
#   provider recorded (no unfilled <placeholder>).
#   the canonical judge roles are present.
set -eu
PY="${ROCQ_PYTHON_BIN:-python3}"
[ -n "${1:-}" ] || { echo "usage: $0 CAMPAIGN-squeeze-table.md" >&2; exit 2; }
"$PY" - "$1" <<'PYAUD'
import re, sys
rows = []
for ln in open(sys.argv[1]):
    if not ln.lstrip().startswith("|"): continue
    cells = [c.strip() for c in ln.strip().strip("|").split("|")]
    if len(cells) < 5: continue
    a = cells[0]
    if a.lower() == "actor" or set(a) <= set("-: "): continue   # header / separator
    rows.append(cells[:5])  # Actor, U, L, Denied, Provider

viol = []
if not rows:
    viol.append("no actor rows found (is the table filled?)")

# C1: distinct (U,L)
seen = {}
for a, U, L, D, P in rows:
    key = (U.lower(), L.lower())
    if key in seen:
        viol.append(f"C1: '{a}' shares an (U,L) pair with '{seen[key]}' — they are one actor, not two")
    else:
        seen[key] = a

# C3: judges must deny the implementation
JUDGES = ("property", "verifier", "completeness", "monitor")
DENY_TOKENS = re.compile(r'implementation|\bbody\b|\bcode\b|annotation|\bdiff\b|scaffolding|rationale|notes', re.I)
for a, U, L, D, P in rows:
    if any(j in a.lower() for j in JUDGES):
        if not DENY_TOKENS.search(D):
            viol.append(f"C3: judge '{a}' does not deny the implementation/annotation (Denied = '{D}')")

# provider recorded
for a, U, L, D, P in rows:
    if not P or P.startswith("<") or P.lower() in ("", "tbd", "?"):
        viol.append("provider not recorded for '" + a + "'")

# canonical judge roles present
present = " ".join(a.lower() for a,_,_,_,_ in rows)
for need in ("coordinator", "property", "annotat", "verifier", "completeness", "monitor"):
    if need not in present:
        viol.append(f"canonical role missing: no actor matching '{need}'")

if viol:
    print(f"SQUEEZE-AUDIT FAIL ({len(rows)} actor rows):")
    for v in viol: print("  - " + v)
    sys.exit(1)
print(f"SQUEEZE-AUDIT OK ({len(rows)} actors; C1 distinct; C3 judges code-blind; providers recorded)")
PYAUD
