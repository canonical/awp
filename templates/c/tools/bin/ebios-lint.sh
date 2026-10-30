#!/usr/bin/env bash
# ebios-lint.sh — structure + coverage + endogeneity linter for an EBIOS RM report.
#
# The mechanical lower bound (L) of the ebios-sl loop (config/skills/ebios-sl). It checks the
# STRUCTURE of a risk report, not its content realism — realism is the human terminus (a disjoint
# reviewer + the risk owner). Honest: checks whose required tags are absent report SKIP, never a
# silent PASS.
#
# Usage:   ./ebios-lint.sh REPORT.md
# Exit:    0 = all checks pass (WARN/SKIP allowed) · 1 = violations · 2 = usage/format error.
#
# FORMAT CONTRACT (authoritative): config/skills/ebios-sl/references/report-format.md — the PINNED
# tag convention. The report author writes to it and this linter parses it, so they cannot drift.
# In brief: workshop headings "Workshop N"/"WN"; one artifact per line/row with its tokens + parent
# IDs on that same line (locality rule); tags BA# SA# FE#(+G1-4) RO# TO# ROTO# SS# AP# OS#(+V1-4) R#.
# Checks:
#   C1  workshop sections present (and no gap in the middle)
#   C3  every FE carries a severity G1-4 ; C3b every OS carries a likelihood V1-4
#   C4  chaining: every SS -> an RO/TO ; C4b every OS -> an SS/AP
#   C5  coverage: every high-severity FE (G3/G4) is carried into a downstream scenario
#   C7  agile volume sanity (WARN): business assets 5-10 ; RO/TO 3-6
#   C8  endogeneity tripwire (FAIL): no code artifacts (.c/.h, #include, 0xHEX, ::, ->) in W1-W3
#   C9  STRIDE coverage ledger (SKIP-honest): SKIP when absent; else validate the §3.3 matrix
#       structure — each S/T/R/I/D/E cell holds one lifecycle token (UNMODELED|PROVED|TRUSTED-PENDING|
#       TRUSTED|N/A[(RR#)]) and every G3/G4 SA has a row. Single-file only; the cross-run ratchet
#       regression is frama-c-monitoring's CI gate (crosswalk-template §3.2), not here.
set -uo pipefail
PY="${ROCQ_PYTHON_BIN:-python3}"
[ "${1:-}" ] || { echo "usage: ebios-lint.sh REPORT.md" >&2; exit 2; }
[ -f "$1" ]  || { echo "ebios-lint: '$1' not found" >&2; exit 2; }

"$PY" - "$1" <<'PYLINT'
import re, sys
txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
lines = txt.splitlines()

def workshop_spans(t):
    hs = [(int(m.group(1) or m.group(2)), m.start())
          for m in re.finditer(r'(?im)^#{1,6}\s*(?:workshop\s*([1-5])|w([1-5]))\b', t)]
    hs.sort(key=lambda x: x[1])
    spans = {}
    for i, (n, s) in enumerate(hs):
        e = hs[i+1][1] if i+1 < len(hs) else len(t)
        spans.setdefault(n, []).append((s, e))
    return spans
spans = workshop_spans(txt)
def wtext(ns):
    return "\n".join(txt[s:e] for n in ns for (s, e) in spans.get(n, []))

def find_ids(tag):
    return sorted(set(re.findall(r'\b(' + tag + r'[0-9]+)\b', txt)))
ID = {t: find_ids(t) for t in ['BA','SA','FE','RO','TO','ROTO','SS','AP','OS','R']}
def lines_with(idstr):
    rx = re.compile(r'\b' + re.escape(idstr) + r'\b')
    return [ln for ln in lines if rx.search(ln)]

res = []
def add(level, code, msg): res.append((level, code, msg))

# C1 — workshops present
present = sorted(spans)
if not present:
    add('FAIL', 'C1', 'no Workshop sections found (need headings like "## Workshop 1")')
else:
    add('PASS', 'C1', 'workshops present: ' + ", ".join("W%d" % n for n in present))
    for n in range(min(present), max(present) + 1):
        if n not in spans:
            add('WARN', 'C1', 'gap: W%d missing inside the W%d-W%d range' % (n, min(present), max(present)))

# C3 — severity on every feared event
if ID['FE']:
    miss = [fe for fe in ID['FE'] if not any(re.search(r'\bG[1-4]\b', l) for l in lines_with(fe))]
    add('FAIL' if miss else 'PASS', 'C3',
        ('feared events missing a severity G1-4: ' + ", ".join(miss)) if miss else 'every FE carries a severity')
else:
    add('SKIP', 'C3', 'no FE# ids found (tag feared events FE1, FE2, ...)')

# C3b — likelihood on every operational scenario
if ID['OS']:
    miss = [o for o in ID['OS'] if not any(re.search(r'\bV[1-4]\b', l) for l in lines_with(o))]
    add('FAIL' if miss else 'PASS', 'C3b',
        ('operational scenarios missing a likelihood V1-4: ' + ", ".join(miss)) if miss else 'every OS carries a likelihood')
else:
    add('SKIP', 'C3b', 'no OS# ids found')

# C4 — chaining
def mentions_any(idstr, universe):
    uni = [u for u in universe if u != idstr]
    for l in lines_with(idstr):
        if any(re.search(r'\b' + re.escape(u) + r'\b', l) for u in uni):
            return True
    return False
roto = ID['RO'] + ID['TO'] + ID['ROTO']
if ID['SS'] and roto:
    bad = [s for s in ID['SS'] if not mentions_any(s, roto)]
    add('FAIL' if bad else 'PASS', 'C4',
        ('strategic scenarios not chained to an RO/TO: ' + ", ".join(bad)) if bad else 'every SS chains to an RO/TO')
else:
    add('SKIP', 'C4', 'need SS# and RO/TO ids to check strategic chaining')
ssap = ID['SS'] + ID['AP']
if ID['OS'] and ssap:
    bad = [o for o in ID['OS'] if not mentions_any(o, ssap)]
    add('FAIL' if bad else 'PASS', 'C4b',
        ('operational scenarios not chained to an SS/AP: ' + ", ".join(bad)) if bad else 'every OS chains to an SS/AP')
else:
    add('SKIP', 'C4b', 'need OS# and SS/AP ids to check operational chaining')

# C5 — coverage: high-severity feared events must be carried into a downstream scenario
if ID['FE'] and spans.get(1):
    w1 = wtext([1]); outside = txt.replace(w1, '')
    high = [fe for fe in ID['FE'] if any(re.search(r'\bG[34]\b', l) for l in lines_with(fe))]
    if not high:
        add('WARN', 'C5', 'no high-severity (G3/G4) feared events found — check the severities')
    else:
        unc = [fe for fe in high if not re.search(r'\b' + re.escape(fe) + r'\b', outside)]
        add('FAIL' if unc else 'PASS', 'C5',
            ('high-severity FE not carried into any downstream scenario: ' + ", ".join(unc)) if unc
            else 'every high-severity FE appears downstream of W1')
else:
    add('SKIP', 'C5', 'need FE# ids and a Workshop 1 section')

# C7 — agile volume sanity (WARN, not FAIL)
nba = len(ID['BA'])
if nba: add('PASS' if 5 <= nba <= 10 else 'WARN', 'C7', 'business assets: %d %s [5,10]' % (nba, 'in' if 5 <= nba <= 10 else 'outside'))
else:   add('SKIP', 'C7', 'no BA# ids')
nrt = len(set(ID['RO']) | set(ID['ROTO']))
if nrt: add('PASS' if 3 <= nrt <= 6 else 'WARN', 'C7', 'RO/TO pairs: %d %s [3,6]' % (nrt, 'in' if 3 <= nrt <= 6 else 'outside'))

# C8 — endogeneity tripwire: no code artifacts in W1-W3
w123 = wtext([1, 2, 3])
code = re.compile(r'(?:\b\w+\.(?:c|h|cpp|cc|rs)\b|#include|#define|\b0x[0-9a-fA-F]+\b|::|->)')
hits = sorted(set(m.group(0) for m in code.finditer(w123)))
if w123.strip():
    add('FAIL' if hits else 'PASS', 'C8',
        ('code artifacts in W1-W3 (ENDOGENEITY — author saw the source?): ' + ", ".join(hits[:8])) if hits
        else 'no code artifacts in W1-W3 (exogenous)')
else:
    add('SKIP', 'C8', 'no W1-W3 text to scan')

# C9 — STRIDE coverage ledger structural validation (SKIP-honest, single-file only).
# SKIPs when no ledger table is present (so every existing report stays exit 0). When a ledger IS
# present (a markdown table with the six S,T,R,I,D,E columns per crosswalk-template §3.3), validate
# STRUCTURE: every cell holds exactly one valid lifecycle token, and every high-value asset (an SA
# driving a G3/G4 feared event) has a row. The cross-run RATCHET regression is NOT done here — that
# is frama-c-monitoring's CI gate (crosswalk-template §3.2); C9 is single-file structural only.
def c9_high_value_assets():
    # an SA is high-value if it appears on a line that also carries a G3/G4 (high) severity
    hv = []
    for a in ID.get('SA', []):
        if any(re.search(r'\bG[34]\b', l) for l in lines_with(a)):
            hv.append(a)
    return sorted(set(hv))
def c9_cell_token(cell):
    s = re.sub(r'[`*_]', '', cell).strip()
    s = re.sub(r'\s*\((?:RR\d+|[^)]*)\)\s*$', '', s).strip()   # drop an optional (RR#) annotation
    for tok in ('TRUSTED-PENDING', 'UNMODELED', 'PROVED', 'TRUSTED', 'N/A'):
        if s == tok:
            return tok
    return None
def c9_find_ledger():
    hdr_rx = re.compile(r'^\s*\|(.+)\|\s*$')
    sep_rx = re.compile(r'^\s*\|[\s:|-]+\|\s*$')
    for i, ln in enumerate(lines):
        m = hdr_rx.match(ln)
        if not m:
            continue
        cells = [c.strip() for c in m.group(1).split('|')]
        cols = [re.match(r'^\**`?([STRIDE])\b', c) for c in cells]
        letters = [c.group(1) for c in cols if c]
        if set(letters) >= set('STRIDE') and i + 1 < len(lines) and sep_rx.match(lines[i+1]):
            idx = {}
            for j, c in enumerate(cols):
                if c and c.group(1) not in idx:
                    idx[c.group(1)] = j
            return i, idx          # asset = column 0 (the leftmost), per template §3.3
    return None
_led = c9_find_ledger()
if not _led:
    add('SKIP', 'C9', 'no STRIDE coverage ledger table present (six S,T,R,I,D,E columns) — '
                      'cross-run ratchet is frama-c-monitoring CI, not here')
else:
    hdr_i, lidx = _led
    rows, badcells = {}, []
    k = hdr_i + 2
    while k < len(lines):
        m = re.match(r'^\s*\|(.+)\|\s*$', lines[k])
        if not m:
            break
        cells = [c.strip() for c in m.group(1).split('|')]
        if re.match(r'^[\s:|-]+$', '|'.join(cells)):
            k += 1; continue
        asset = re.sub(r'[`*_]', '', cells[0]).strip()
        rt = {}
        for L in 'STRIDE':
            ci = lidx[L]
            cell = cells[ci] if ci < len(cells) else ''
            tok = c9_cell_token(cell)
            rt[L] = tok
            if tok is None:
                badcells.append('%s/%s="%s"' % (asset or ('row%d' % k), L, cell.strip()))
        rows[asset] = rt
        k += 1
    add('INFO', 'C9', 'STRIDE coverage ledger parsed: %d asset row(s)' % len(rows))
    for a, rt in rows.items():
        add('INFO', 'C9', '  %-7s S=%s T=%s R=%s I=%s D=%s E=%s'
            % (a, rt['S'], rt['T'], rt['R'], rt['I'], rt['D'], rt['E']))
    if badcells:
        add('FAIL', 'C9', 'ledger cells without exactly one valid lifecycle token '
            '(UNMODELED|PROVED|TRUSTED-PENDING|TRUSTED|N/A[(RR#)]): ' + ", ".join(badcells[:10]))
    else:
        add('PASS', 'C9', 'every ledger cell carries exactly one valid lifecycle token')
    row_ids = set()
    for a in rows:
        row_ids |= set(re.findall(r'\b(SA[0-9]+)\b', a))
    hv = c9_high_value_assets()
    missing = [a for a in hv if a not in row_ids]
    if hv:
        if missing:
            add('FAIL', 'C9', 'high-value asset (drives a G3/G4 feared event) with no ledger row: '
                + ", ".join(missing))
        else:
            add('PASS', 'C9', 'every high-value asset has a ledger row (%d): %s'
                % (len(hv), ", ".join(hv)))
    else:
        add('WARN', 'C9', 'ledger present but no high-value (G3/G4) SA detected to require a row')

for lvl, code_, msg in res:
    print("  %-4s %-4s %s" % (lvl, code_, msg))
print()
fails = [r for r in res if r[0] == 'FAIL']
if fails:
    print("EBIOS-LINT FAIL (%d violation%s) — structure/coverage/endogeneity" % (len(fails), '' if len(fails) == 1 else 's'))
    sys.exit(1)
print("EBIOS-LINT OK (structure + coverage + endogeneity). Content REALISM is the human terminus — not checked here.")
sys.exit(0)
PYLINT
