#!/bin/sh
# framac-soft-residual.sh — emit SOFT-RESIDUAL.md: the bounded soft-side delta a human terminus
# adjudicates to move a campaign from MACHINE-DONE to DONE.  (WS3 of fc-sl-loops-improve-plan.md;
# paper §mechanics: nesting terminates in a human who adjudicates only the soft residual, the
# delta between what the upper bound claims and what the lower bound established — NOT a re-verify
# of the hard side, which WP already settled.)
#
# Usage: ./framac-soft-residual.sh [VERDICTS.tsv]   # default framac/.verdicts.tsv -> stdout
set -eu
PY="${ROCQ_PYTHON_BIN:-python3}"
TSV="${1:-framac/.verdicts.tsv}"
[ -f "$TSV" ] || { echo "verdict log not found: $TSV" >&2; exit 2; }
"$PY" - "$TSV" <<'PYSR'
import re, sys
rows = []
for ln in open(sys.argv[1]):
    if not ln.strip(): continue
    c = ln.rstrip("\n").split("\t", 2)
    if len(c) < 2: continue
    rows.append((c[0], c[1].strip(), c[2] if len(c) > 2 else ""))

# Soft residual = a gap between intended property and what WP established that a HUMAN must judge.
# Only PARTIAL/FAILED units can carry one (a PROVED unit passed its gates incl. Gate C').
# (Tooling gaps and out-of-scope crypto are NOT human decisions — they are filed/recorded.)
SOFT = re.compile(r'incomplete|unspecified|permutation|sortedness|trivial|under[- ]specified|'
                  r'intended (property|Y)|authored-authority|maximal|needs.*ensures|copy-correctness', re.I)
TOOLING = re.compile(r'\bfresh\b|gap ?#?1|\+cast|cast[- ]residual|obj_size|termination|loop_variant|'
                     r'memset|memcmp|init-track|crypto|\bPSA\b|out[- ]of[- ]scope|BLOCKED|model limit', re.I)
AMEND = re.compile(r'gate[- ]?a|amend|sharpen|rubber', re.I)
CARVE = re.compile(r'carve[- ]?out', re.I)
SELFCORR = re.compile(r'\brevert|self[- ]correct|declined to axiomatize', re.I)

soft_units, tooling_units, amendments, carveouts, selfcorr = [], [], [], [], []
for f, v, n in rows:
    if v in ("PARTIAL", "FAILED"):                 # only non-PROVED units can carry a soft residual
        if SOFT.search(n):       soft_units.append((f, v, n))
        elif TOOLING.search(n):  tooling_units.append((f, v, n))
        else:                    soft_units.append((f, v, n))   # unclassified PARTIAL -> a human look
    if AMEND.search(n):    amendments.append((f, n))
    if CARVE.search(n):    carveouts.append((f, n))
    if SELFCORR.search(n): selfcorr.append((f, n))

def short(n, k=200): return (n[:k] + "…") if len(n) > k else n

print("# SOFT-RESIDUAL — human terminus adjudication packet\n")
print("**What this is.** The recursion of monitors only relocates the un-squeezed editorial "
      "judgment upward; only a person outside the construction closes it (paper §mechanics). This "
      "packet is the **bounded** thing that person adjudicates: the delta between what the upper "
      "bound *claims* and what the executable lower bound *established*. The reviewer does **not** "
      "re-verify the hard side — WP already settled it — and holds the requirement/gold + the gate "
      "record without having produced the work.\n")
print(f"**Status: MACHINE-DONE.** Promote to **DONE** only after external sign-off below. "
      f"({len(rows)} units; {len(soft_units)} carry a soft residual needing a human decision.)\n")

print("## Soft residuals — REQUIRE a human decision\n")
if soft_units:
    print("| Unit | Verdict | The soft delta (is the proved theorem the intended property?) |")
    print("|---|---|---|")
    for f, v, n in soft_units:
        print(f"| `{f}` | {v} | {short(n)} |")
else:
    print("_(none — this campaign produced no soft residue; e.g. a pure RTE-robustness run. Say so "
          "explicitly: this exercises the HARD side only — the editorial half is not engaged.)_")

print("\n## Recorded, NOT human decisions (filed tooling gaps / out-of-scope)\n")
if tooling_units:
    for f, v, n in tooling_units:
        print(f"- `{f}` ({v}) — tooling/out-of-scope: {short(n,140)}")
else:
    print("- (none)")

print("\n## Gate-A amendments (editorial deltas to confirm)\n")
print("\n".join(f"- `{f}` — {short(n,140)}" for f, n in amendments) or "- (none recorded — if Gate A only rubber-stamped, that is itself a finding)")

print("\n## Gate-S carve-outs (learned-skill narrowings to confirm)\n")
print("\n".join(f"- `{f}` — {short(n,140)}" for f, n in carveouts) or "- (none)")

print("\n## Self-corrections — NOT disjointness results (do not count as caught-by-the-gate)\n")
print("\n".join(f"- `{f}` — {short(n,140)}" for f, n in selfcorr) or "- (none)")

print("\n## Sign-off (the mandatory human terminus)\n")
print("- [ ] An **external reviewer** (outside the loop; ideally a different provider family) has "
      "adjudicated every soft residual above against the requirement/gold.")
print("- [ ] Each Gate-A amendment and Gate-S carve-out confirmed (or reopened as a `gap-N`).")
print("- [ ] On sign-off, the campaign is **DONE**; until then it is **MACHINE-DONE** only.")
PYSR
