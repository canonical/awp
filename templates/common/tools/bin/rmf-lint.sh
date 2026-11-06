#!/usr/bin/env bash
# rmf-lint.sh — structure + coverage + endogeneity linter for a NIST RMF risk assessment.
#
# The mechanical lower bound (L) of the rmf-sl loop (config/skills/rmf-sl). It checks the STRUCTURE
# of a risk assessment, not its content realism — realism is the human terminus (a disjoint reviewer
# + the Authorizing Official). Honest: checks whose required tags are absent report SKIP, never a
# silent PASS. Faithful sibling of ebios-lint.sh (EBIOS W1-W5 -> RMF R1-R5).
#
# Usage:   ./rmf-lint.sh REPORT.md
# Exit:    0 = all checks pass (WARN/SKIP allowed) - 1 = violations - 2 = usage/format error.
#
# FORMAT CONTRACT (authoritative): config/skills/rmf-sl/references/report-format.md — the PINNED
# tag convention. The report author writes to it and this linter parses it, so they cannot drift.
# In brief: section headings "Section N"/"RN" (N in 1..5); one artifact per line/row with its tokens
# + parent IDs on that same line (locality rule); tags IA# SA# IM#(+Lo/Mod/Hi) TS#(+ADV/ACC/ENV)
# TE# VU# RS#(+L1-4) CTL# RR#.
# Checks:
#   C1  R1-R5 sections present (and no gap in the middle)
#   C3  every IM carries an impact Lo/Mod/Hi ; C3b every RS carries a likelihood L1-4
#   C4  chaining: every TE -> a TS
#   C4b chaining: every RS -> a TE AND a VU
#   C4c chaining: every RS -> a CTL (800-53 control)
#   C5  coverage: every Hi-impact IM is carried into a downstream RS that also names a CTL
#   C6  origin coverage (WARN): all three threat-source classes ADV/ACC/ENV present (the 800-30 DNA)
#   C7  volume sanity (WARN): information assets 5-10 ; threat sources 3-6
#   C8  endogeneity tripwire (FAIL): no code artifacts in R1-R4 — C (.c/.h, #include, #define,
#       0xHEX, ::, ->) or Rust (.rs, fn name(, impl, unsafe {, #[attr], &mut, Vec<, macro!( ...)
#   C9  STRIDE coverage ledger (SKIP-honest): SKIP when absent; else validate the §3.3 matrix
#       structure — each S/T/R/I/D/E cell holds one lifecycle token (UNMODELED|PROVED|TRUSTED-PENDING|
#       TRUSTED|N/A[(RR#)]) and every Hi/High SA/IA has a row. Single-file only; the cross-run ratchet
#       regression is frama-c-monitoring's CI gate (crosswalk-template §3.2), not here.
set -uo pipefail
PY="${ROCQ_PYTHON_BIN:-python3}"
[ "${1:-}" ] || { echo "usage: rmf-lint.sh REPORT.md" >&2; exit 2; }
[ -f "$1" ]  || { echo "rmf-lint: '$1' not found" >&2; exit 2; }

"$PY" - "$1" <<'PYLINT'
import re, sys
txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
lines = txt.splitlines()

def section_spans(t):
    hs = [(int(m.group(1) or m.group(2)), m.start())
          for m in re.finditer(r'(?im)^#{1,6}\s*(?:section\s*([1-5])|r([1-5]))\b', t)]
    hs.sort(key=lambda x: x[1])
    spans = {}
    for i, (n, s) in enumerate(hs):
        e = hs[i+1][1] if i+1 < len(hs) else len(t)
        spans.setdefault(n, []).append((s, e))
    return spans
spans = section_spans(txt)
def rtext(ns):
    return "\n".join(txt[s:e] for n in ns for (s, e) in spans.get(n, []))

def find_ids(tag):
    return sorted(set(re.findall(r'\b(' + tag + r'[0-9]+)\b', txt)))
ID = {t: find_ids(t) for t in ['IA','SA','IM','TS','TE','VU','RS','CTL','RR']}
def lines_with(idstr):
    rx = re.compile(r'\b' + re.escape(idstr) + r'\b')
    return [ln for ln in lines if rx.search(ln)]

res = []
def add(level, code, msg): res.append((level, code, msg))

# C1 — R1-R5 sections present
present = sorted(spans)
if not present:
    add('FAIL', 'C1', 'no RMF sections found (need headings like "## R1" or "## Section 1")')
else:
    add('PASS', 'C1', 'sections present: ' + ", ".join("R%d" % n for n in present))
    for n in range(min(present), max(present) + 1):
        if n not in spans:
            add('WARN', 'C1', 'gap: R%d missing inside the R%d-R%d range' % (n, min(present), max(present)))

# C3 — impact on every IM
if ID['IM']:
    miss = [im for im in ID['IM'] if not any(re.search(r'\b(?:Lo|Mod|Hi)\b', l) for l in lines_with(im))]
    add('FAIL' if miss else 'PASS', 'C3',
        ('system elements missing an impact Lo/Mod/Hi: ' + ", ".join(miss)) if miss else 'every IM carries an impact')
else:
    add('SKIP', 'C3', 'no IM# ids found (tag categorized elements IM1, IM2, ...)')

# C3b — likelihood on every RS
if ID['RS']:
    miss = [r for r in ID['RS'] if not any(re.search(r'\bL[1-4]\b', l) for l in lines_with(r))]
    add('FAIL' if miss else 'PASS', 'C3b',
        ('risk scenarios missing a likelihood L1-4: ' + ", ".join(miss)) if miss else 'every RS carries a likelihood')
else:
    add('SKIP', 'C3b', 'no RS# ids found')

# helpers
def mentions_any(idstr, universe):
    uni = [u for u in universe if u != idstr]
    for l in lines_with(idstr):
        if any(re.search(r'\b' + re.escape(u) + r'\b', l) for u in uni):
            return True
    return False

# C4 — every TE chains to a TS
if ID['TE'] and ID['TS']:
    bad = [t for t in ID['TE'] if not mentions_any(t, ID['TS'])]
    add('FAIL' if bad else 'PASS', 'C4',
        ('threat events not chained to a TS: ' + ", ".join(bad)) if bad else 'every TE chains to a TS')
else:
    add('SKIP', 'C4', 'need TE# and TS# ids to check threat chaining')

# C4b — every RS chains to a TE AND a VU
if ID['RS'] and ID['TE'] and ID['VU']:
    bad_te = [r for r in ID['RS'] if not mentions_any(r, ID['TE'])]
    bad_vu = [r for r in ID['RS'] if not mentions_any(r, ID['VU'])]
    bad = sorted(set(bad_te) | set(bad_vu))
    if bad:
        msg = 'risk scenarios missing a TE and/or VU link: '
        if bad_te: msg += 'no-TE=' + ",".join(bad_te) + ' '
        if bad_vu: msg += 'no-VU=' + ",".join(bad_vu)
        add('FAIL', 'C4b', msg.strip())
    else:
        add('PASS', 'C4b', 'every RS chains to a TE and a VU')
else:
    add('SKIP', 'C4b', 'need RS#, TE# and VU# ids to check risk chaining')

# C4c — every RS chains to a CTL (800-53 control)
if ID['RS'] and ID['CTL']:
    bad = [r for r in ID['RS'] if not mentions_any(r, ID['CTL'])]
    add('FAIL' if bad else 'PASS', 'C4c',
        ('risk scenarios with no selected control CTL: ' + ", ".join(bad)) if bad else 'every RS chains to a CTL')
else:
    add('SKIP', 'C4c', 'need RS# and CTL# ids to check control selection')

# C5 — coverage: every Hi-impact IM is carried into a downstream RS that also names a CTL
if ID['IM'] and spans.get(1) and ID['RS'] and ID['CTL']:
    high = [im for im in ID['IM'] if any(re.search(r'\bHi\b', l) for l in lines_with(im))]
    if not high:
        add('WARN', 'C5', 'no Hi-impact (Hi) system elements found — check the impact levels')
    else:
        unc = []
        for im in high:
            covered = False
            for r in ID['RS']:
                rls = lines_with(r)
                if any(re.search(r'\b' + re.escape(im) + r'\b', l) for l in rls) and \
                   any(re.search(r'\b(?:' + "|".join(re.escape(c) for c in ID['CTL']) + r')\b', l) for l in rls):
                    covered = True; break
            if not covered: unc.append(im)
        add('FAIL' if unc else 'PASS', 'C5',
            ('Hi-impact IM not covered by an RS with a selected control: ' + ", ".join(unc)) if unc
            else 'every Hi-impact IM has a downstream RS with a selected control')
else:
    add('SKIP', 'C5', 'need IM#, RS#, CTL# ids and an R1 section')

# C6 — origin coverage (WARN): all three classes ADV/ACC/ENV in R2 (the 800-30 DNA difference)
r2 = rtext([2])
if ID['TS'] and r2.strip():
    classes = {c for c in ('ADV', 'ACC', 'ENV') if re.search(r'\b' + c + r'\b', r2)}
    miss = [c for c in ('ADV', 'ACC', 'ENV') if c not in classes]
    add('PASS' if not miss else 'WARN', 'C6',
        'all three threat-source origin classes present (ADV/ACC/ENV)' if not miss
        else 'threat-source origin classes missing (800-30 weights accidental+environmental too): ' + ", ".join(miss))
else:
    add('SKIP', 'C6', 'no TS# / R2 text to check origin coverage')

# C7 — volume sanity (WARN)
nia = len(ID['IA'])
if nia: add('PASS' if 5 <= nia <= 10 else 'WARN', 'C7', 'information assets: %d %s [5,10]' % (nia, 'in' if 5 <= nia <= 10 else 'outside'))
else:   add('SKIP', 'C7', 'no IA# ids')
nts = len(ID['TS'])
if nts: add('PASS' if 3 <= nts <= 6 else 'WARN', 'C7', 'threat sources: %d %s [3,6]' % (nts, 'in' if 3 <= nts <= 6 else 'outside'))

# C8 — endogeneity tripwire: no code artifacts in R1-R4 (C and Rust source artifacts; the report
# is language-neutral, so both families are scanned whatever the code under study is written in).
r1234 = rtext([1, 2, 3, 4])
code = re.compile(r'(?:\b\w+\.(?:c|h|cpp|cc|rs)\b|#include|#define|\b0x[0-9a-fA-F]+\b|::|->'
                  r'|\bfn\s+\w+\s*[(<]|\bimpl(?:\s+\w|\s*<)|\bunsafe\s*\{|#\[\w+|&mut\b'
                  r'|\b(?:Vec|Option|Result|Box|Rc|Arc)<|\b\w+!\(|\.unwrap\(\))')
hits = sorted(set(m.group(0) for m in code.finditer(r1234)))
if r1234.strip():
    add('FAIL' if hits else 'PASS', 'C8',
        ('code artifacts in R1-R4 (ENDOGENEITY — author saw the source?): ' + ", ".join(hits[:8])) if hits
        else 'no code artifacts in R1-R4 (exogenous)')
else:
    add('SKIP', 'C8', 'no R1-R4 text to scan')

# C9 — STRIDE coverage ledger structural validation (SKIP-honest, single-file only).
# SKIPs when no ledger table is present (so every existing report stays exit 0). When a ledger IS
# present (a markdown table with the six S,T,R,I,D,E columns per crosswalk-template §3.3), validate
# STRUCTURE: every cell holds exactly one valid lifecycle token, and every high-value asset (an
# SA/IA driving a Hi/High scenario) has a row. The cross-run RATCHET regression is NOT done here —
# that is frama-c-monitoring's CI gate (crosswalk-template §3.2); C9 is single-file structural only.
LEDGER_ASSET_TAGS = ['SA', 'IA']           # RMF supporting/information assets carry the ledger rows
def c9_high_value_assets():
    # an asset is high-value if it appears on a line that also carries a High risk level / Hi impact
    hv = []
    for tag in LEDGER_ASSET_TAGS:
        for a in ID.get(tag, []):
            if any(re.search(r'\b(?:High|Hi)\b', l) for l in lines_with(a)):
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
        row_ids |= set(re.findall(r'\b((?:SA|IA)[0-9]+)\b', a))
    hv = c9_high_value_assets()
    missing = [a for a in hv if a not in row_ids]
    if hv:
        if missing:
            add('FAIL', 'C9', 'high-value asset (drives a Hi/High scenario) with no ledger row: '
                + ", ".join(missing))
        else:
            add('PASS', 'C9', 'every high-value asset has a ledger row (%d): %s'
                % (len(hv), ", ".join(hv)))
    else:
        add('WARN', 'C9', 'ledger present but no high-value (Hi/High) SA/IA detected to require a row')

for lvl, code_, msg in res:
    print("  %-4s %-4s %s" % (lvl, code_, msg))
print()
fails = [r for r in res if r[0] == 'FAIL']
if fails:
    print("RMF-LINT FAIL (%d violation%s) — structure/coverage/endogeneity" % (len(fails), '' if len(fails) == 1 else 's'))
    sys.exit(1)
print("RMF-LINT OK (structure + coverage + endogeneity). Content REALISM is the human terminus — not checked here.")
sys.exit(0)
PYLINT
