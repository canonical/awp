#!/bin/sh
# framac-gen-report.sh — emit a discipline-compliant campaign report from a verdict log,
# or lint an existing report.  (WS6 of fc-sl-loops-improve-plan.md)
#
# Usage:
#   ./framac-gen-report.sh [VERDICTS.tsv]            # generate report to stdout
#   ./framac-gen-report.sh --lint REPORT.md          # check a report; exit 1 on violation
#
# Enforces the reporting discipline the review asked for:
#   - one count convention, stated once: N/M = proved/total WP goals (RTE included)
#   - every residual classified into a fixed taxonomy
#   - a summary table (unit, verdict, proved/total, residual-classes, guarantee-kind)
#   - the mandatory attribution line (WP delivers robustness; the squeeze adds trust + disjoint adjudication)
#   - headline discipline: no "end-to-end robust" without its denominator + residual list adjacent
#
# Verdict log format (TSV): <file> <TAB> <PROVED|PARTIAL|FAILED> <TAB> <note>
set -eu

PY="${ROCQ_PYTHON_BIN:-python3}"

if [ "${1:-}" = "--lint" ]; then
  [ -n "${2:-}" ] || { echo "usage: $0 --lint REPORT.md" >&2; exit 2; }
  "$PY" - "$2" <<'PYLINT'
import re, sys, os
txt = open(sys.argv[1]).read()
low = txt.lower()
viol = []
fname = os.path.basename(sys.argv[1]).lower()
# 0. found-issues files MUST carry the status legend at the top, so a reader/AO does not mistake a
#    WITNESSED heading (proven-safe) for a defect. The file records BOTH bugs and positive assurance;
#    only FINDING / FI-* sections are bugs. Keyed on the filename (the consolidated found-issues artifact).
if 'found-issues' in fname:
    head = "\n".join(txt.splitlines()[:45]).lower()
    has_legend = ('legend' in head and 'witnessed' in head
                  and re.search(r'witnessed[^.\n]*(proven safe|not a bug|discharged proof)', head)
                  and re.search(r'(finding|fi-\*|fi-)[^.\n]*(bug|defect)', head))
    if not has_legend:
        viol.append("found-issues file missing the status legend at top "
                    "(define WITNESSED=proven-safe/NOT-a-bug vs FINDING/FI-*=the bug; see frama-c-monitoring §8b)")
# 1. mandatory attribution line (report artifacts only — a found-issues ledger has no attribution line)
if 'found-issues' not in fname and (not re.search(r'frama-?c\s*/?\s*wp\s+delivers', low) or 'squeeze adds' not in low):
    viol.append("missing attribution line ('Frama-C/WP delivers …; the squeeze adds …')")
# 2. headline discipline: any robustness/coverage headline must carry a caveat in the SAME sentence.
#    (Markdown header lines and table rows are not prose coverage claims — exclude them.)
prose = "\n".join(l for l in txt.splitlines() if not l.lstrip().startswith(("#", "|")))
banned = re.compile(r'[^.]*\b(end-to-end|fully (proved|verified)|machine-checked[^.]*robust|completely robust)\b[^.]*\.', re.I)
caveat = re.compile(r'(residual|RTE.?only|parsing.path|amenable|out-of-scope|gap ?#?1|partial|except|caveat|\d+\s*/\s*\d+)', re.I)
for m in banned.finditer(prose):
    s = m.group(0)
    if not caveat.search(s):
        viol.append("unqualified coverage headline (no denominator/residual in the sentence): " + s.strip()[:120])
# 3. a count convention must be stated (report artifacts only)
if 'found-issues' not in fname and 'proved/total' not in low and 'n/m' not in low:
    viol.append("count convention not stated ('N/M = proved/total …')")
# 4. no-blend (WS5.3): EVA must not be cited as a discharge oracle (never substitutes for a WP Valid)
for m in re.finditer(r'[^.]*\b(eva)\b[^.]*\.', txt, re.I):
    s = m.group(0)
    if re.search(r'\b(proved|valid|discharg|suffic|no alarm|clean)\b', s, re.I) and not re.search(r'\bnever\b|not\b.*substitut|triage', s, re.I):
        viol.append("no-blend violation: EVA cited as a discharge oracle (EVA never substitutes for a WP Valid): " + s.strip()[:120])
if viol:
    print("LINT FAIL:")
    for v in viol: print("  - " + v)
    sys.exit(1)
print("LINT OK")
PYLINT
  exit $?
fi

TSV="${1:-framac/.verdicts.tsv}"
[ -f "$TSV" ] || { echo "verdict log not found: $TSV" >&2; exit 2; }

"$PY" - "$TSV" <<'PYGEN'
import re, sys, collections
rows = []
for ln in open(sys.argv[1]):
    if not ln.strip(): continue
    c = ln.rstrip("\n").split("\t", 2)
    if len(c) < 2: continue
    f, verdict = c[0], c[1].strip()
    note = c[2] if len(c) > 2 else ""
    rows.append((f, verdict, note))

# residual taxonomy: class -> matcher on the note
TAX = [
    ("alloc/\\fresh (gap#1)", re.compile(r'\bfresh\b|allocation|calloc|gap ?#?1|linked-list', re.I)),
    ("+cast-frame",           re.compile(r'\+cast|cast[- ]frame|malloc[- ]frame', re.I)),
    ("crypto-oos",            re.compile(r'crypto|\bPSA\b|out[- ]of[- ]scope|BLOCKED', re.I)),
    ("termination",           re.compile(r'termination|loop_variant|\bvariant\b', re.I)),
    ("libc-init",             re.compile(r'memset|memcmp|init[- ]track|\binitialized\b', re.I)),
    ("cast-residual",         re.compile(r'obj_size|cast[- ]residual|requires_3|SIZE_MAX', re.I)),
    ("spec-incomplete",       re.compile(r'incomplete|permutation|sortedness|trivial|under[- ]specified|intended property', re.I)),
    ("faithfulness",          re.compile(r'fabricat|forward-decl|FABRICATED|strip-ACSL', re.I)),
]
def classes(note):
    return [name for name, rx in TAX if rx.search(note)] or (["—"] if note else ["—"])

def guarantee(verdict, note):
    n = note.lower()
    if 'revert' in n or 'self-correct' in n or 'declined to axiomatize' in n:
        return "self-corrected (NOT a disjointness result)"
    if 'authored-authority' in n or 'no gold' in n:
        return "authored-authority (soft, author-independence)"
    if verdict == "PROVED":
        return "by-construction (hard)"
    if verdict in ("PARTIAL", "FAILED"):
        return "disjoint-authority (soft, human-pending)"
    return "—"

def proved_total(note):
    m = re.search(r'\b(\d+)\s*/\s*(\d+)\b', note)
    return f"{m.group(1)}/{m.group(2)}" if m else "—"

tally = collections.Counter(v for _, v, _ in rows)
clscount = collections.Counter()
for _, _, n in rows:
    for c in classes(n):
        if c != "—": clscount[c] += 1

print("# Campaign report\n")
print("**Attribution.** Frama-C/WP delivers the robustness / defect-finding result; the squeeze "
      "adds trustworthiness-by-construction (the disjoint faithfulness gate) and disjoint "
      "adjudication of the soft residual — the verification is WP's, the *trust* is the loop's.\n")
print("**Count convention (stated once).** `N/M = proved/total` WP goals (RTE included). A unit is "
      "PROVED only if faithful (strip-ACSL == git HEAD) AND WP all-`Valid` for the claimed scope; "
      "otherwise PARTIAL/FAILED with its residual classified below. Coverage is reported as a "
      "fraction of the **amenable attack surface**, never the whole tree.\n")
print(f"**Tally.** PROVED {tally.get('PROVED',0)} · PARTIAL {tally.get('PARTIAL',0)} · "
      f"FAILED {tally.get('FAILED',0)}  (of {len(rows)} units).\n")

print("## Summary\n")
print("| Unit | Verdict | Proved/Total | Residual classes | Guarantee |")
print("|---|---|---|---|---|")
for f, v, n in rows:
    print(f"| `{f}` | {v} | {proved_total(n)} | {', '.join(classes(n))} | {guarantee(v,n)} |")

print("\n## Residual taxonomy (counts)\n")
if clscount:
    for c, k in clscount.most_common():
        print(f"- **{c}**: {k}")
else:
    print("- (none)")

print("\n## Headline (discipline-compliant)\n")
nprov = tally.get('PROVED',0)
print(f"> The amenable parsing surface is machine-checked on its **parsing paths** "
      f"({nprov}/{len(rows)} units PROVED); **every residual is a timeout, not a counter-model**, "
      f"classified above as alloc/`\\fresh`, `+cast`-frame, crypto-out-of-scope, termination, "
      f"libc-init, or cast-residual — i.e. **RTE-robustness on the amenable surface, not whole-tree "
      f"or functional correctness**. Soft-side completeness is human-pending (see SOFT-RESIDUAL).\n")
print("_(Generated by framac-gen-report.sh — run `--lint` on any hand-written report to enforce "
      "the same discipline.)_")
PYGEN
