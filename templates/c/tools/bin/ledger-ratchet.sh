#!/usr/bin/env bash
# ledger-ratchet.sh — the cross-run RATCHET CI gate over a crosswalk's STRIDE coverage ledger.
#
# The cross-RUN half of the lower bound (L) of the frama-c-monitoring loop. Where rmf-lint.sh /
# ebios-lint.sh check a single ledger's STRUCTURE (C9: one valid token per cell, every high-value
# asset has a row), THIS gate checks the ledger's MOVEMENT against a frozen baseline — the ratchet
# of crosswalk-template §3.2. It is regression-ONLY: a merely-incomplete matrix never fails (Issue 2
# — a too-strict gate gets disabled), only a backslide does.
#
# Usage:   ./ledger-ratchet.sh CROSSWALK.md [--baseline FILE] [--stage N] [--emit-baseline]
# Exit:    0 = PASS (or bootstrap, or SKIP) — 1 = REGRESSION (gate fails) — 2 = usage/format error.
#
# FORMAT CONTRACT (authoritative): config/skills/frama-c-monitoring/templates/crosswalk-template.md
#   §3.1 cell lifecycle  : UNMODELED | PROVED | TRUSTED-PENDING | TRUSTED | N/A[(RR#)]
#   §3.2 ratchet rule    : FAIL only on regression (a PROVED/TRUSTED cell now UNMODELED; a high-value
#                          asset row present in baseline now gone). WARN (never fail) on any current
#                          UNMODELED / TRUSTED-PENDING cell. First run emits the frozen baseline + PASS.
#   §3.2 WS1 stage-1     : while only WS1 stage-1 ships, a race/concurrency-family cell may NOT be
#                          PROVED — it stays TRUSTED until WS1 stage-2. Marker in the crosswalk:
#                          a line "# ws1-stage: N" (default stage = 1; --stage overrides).
#
# Baseline default: <CROSSWALK>.ledger-baseline.tsv  (TSV: asset<TAB>S<TAB>T<TAB>R<TAB>I<TAB>D<TAB>E).
# SKIP-honest: no ledger table present -> SKIP + exit 0 (so a crosswalk without a §3 matrix never fails).
set -uo pipefail
PY="${ROCQ_PYTHON_BIN:-python3}"

XWALK="" ; BASELINE="" ; STAGE="" ; EMIT_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline)      BASELINE="${2:-}"; shift 2 ;;
    --stage)         STAGE="${2:-}";    shift 2 ;;
    --emit-baseline) EMIT_ONLY=1;       shift   ;;
    -h|--help)       echo "usage: ledger-ratchet.sh CROSSWALK.md [--baseline FILE] [--stage N] [--emit-baseline]"; exit 2 ;;
    -*)              echo "ledger-ratchet: unknown option '$1'" >&2; exit 2 ;;
    *)               [ -z "$XWALK" ] && XWALK="$1" || { echo "ledger-ratchet: extra arg '$1'" >&2; exit 2; }; shift ;;
  esac
done
[ -n "$XWALK" ] || { echo "usage: ledger-ratchet.sh CROSSWALK.md [--baseline FILE] [--stage N] [--emit-baseline]" >&2; exit 2; }
[ -f "$XWALK" ] || { echo "ledger-ratchet: '$XWALK' not found" >&2; exit 2; }
[ -n "$BASELINE" ] || BASELINE="${XWALK}.ledger-baseline.tsv"

XWALK="$XWALK" BASELINE="$BASELINE" STAGE="$STAGE" EMIT_ONLY="$EMIT_ONLY" "$PY" - <<'PYRATCHET'
import os, re, sys

XWALK    = os.environ["XWALK"]
BASELINE = os.environ["BASELINE"]
STAGE    = os.environ["STAGE"]
EMIT_ONLY= os.environ["EMIT_ONLY"] == "1"

txt   = open(XWALK, encoding="utf-8", errors="replace").read()
lines = txt.splitlines()

TOKENS = ('TRUSTED-PENDING', 'UNMODELED', 'PROVED', 'TRUSTED', 'N/A')

# --- WS1 stage marker -------------------------------------------------------
# A line "# ws1-stage: N" in the crosswalk sets the shipped WS1 stage; --stage overrides; default 1.
def find_stage():
    if STAGE.strip():
        try: return int(STAGE.strip())
        except ValueError:
            print("ledger-ratchet: --stage must be an integer", file=sys.stderr); sys.exit(2)
    m = re.search(r'(?im)^\s*#?\s*ws1-stage:\s*([0-9]+)\b', txt)
    return int(m.group(1)) if m else 1
ws1_stage = find_stage()

# Which STRIDE column the concurrency/race family lands in, and which asset rows are race-bearing.
# Per template §3.2 the race-family cell lives under the relevant asset; concurrency is most commonly
# a Tampering (T) or Denial-of-Service (D) concern. We treat a cell as race-family when its column is
# tagged race/concurrency in the header, OR the matrix has a dedicated race column. Conservative
# default: scan for an explicit "race"/"concurrency"/"WS1" marker on the header or asset cell.
RACE_RX = re.compile(r'(?i)\b(race|concurren|data-?race|ws1)\b')

# --- token normalization ----------------------------------------------------
def cell_token(cell):
    s = re.sub(r'[`*_]', '', cell).strip()
    s = re.sub(r'\s*\((?:RR\d+|[^)]*)\)\s*$', '', s).strip()   # drop optional (RR#) / note
    for tok in TOKENS:
        if s == tok:
            return tok
    return None

# --- locate the §3.3 ledger table (six S,T,R,I,D,E columns) -----------------
def find_ledger():
    hdr_rx = re.compile(r'^\s*\|(.+)\|\s*$')
    sep_rx = re.compile(r'^\s*\|[\s:|-]+\|\s*$')
    for i, ln in enumerate(lines):
        m = hdr_rx.match(ln)
        if not m:
            continue
        cells = [c.strip() for c in m.group(1).split('|')]
        cols  = [re.match(r'^\**`?([STRIDE])\b', c) for c in cells]
        letters = [c.group(1) for c in cols if c]
        if set(letters) >= set('STRIDE') and i + 1 < len(lines) and sep_rx.match(lines[i+1]):
            idx, raw_hdr = {}, {}
            for j, c in enumerate(cols):
                if c and c.group(1) not in idx:
                    idx[c.group(1)] = j
                    raw_hdr[c.group(1)] = cells[j]
            return i, idx, raw_hdr, cells
    return None

_led = find_ledger()
if not _led:
    print("  SKIP  no STRIDE coverage ledger table in '%s' (six S,T,R,I,D,E columns) — nothing to ratchet" % XWALK)
    print("\nLEDGER-RATCHET SKIP (no ledger present) — exit 0")
    sys.exit(0)

hdr_i, lidx, raw_hdr, hdr_cells = _led

# Race-family cell sources (template §3.2 — the cell "under the relevant asset"):
#   (a) a STRIDE column whose HEADER is tagged race/concurrency (concurrency commonly lands in T or D);
#   (b) a DEDICATED extra column (e.g. "Race (WS1)") that is not one of the six STRIDE letters.
# Stage-1 forbids PROVED in any of these (plus a race-bearing asset ROW, handled per-row below).
race_cols = {L: lidx[L] for L in 'STRIDE' if RACE_RX.search(raw_hdr.get(L, ''))}
claimed = set(lidx.values())
for j, h in enumerate(hdr_cells):
    if j not in claimed and RACE_RX.search(h):
        race_cols['#%d' % j] = j      # dedicated race column, keyed by position

# --- parse the matrix rows --------------------------------------------------
def parse_rows():
    rows, badcells = {}, []
    k = hdr_i + 2
    order = []
    while k < len(lines):
        m = re.match(r'^\s*\|(.+)\|\s*$', lines[k])
        if not m:
            break
        cells = [c.strip() for c in m.group(1).split('|')]
        if re.match(r'^[\s:|-]+$', '|'.join(cells)):
            k += 1; continue
        asset_raw = re.sub(r'[`*_]', '', cells[0]).strip()
        # canonical asset key = leading SA#/IA# tag if present, else the cleaned label
        mtag = re.match(r'^((?:SA|IA)[0-9]+)\b', asset_raw)
        asset = mtag.group(1) if mtag else asset_raw
        race_row = bool(RACE_RX.search(asset_raw))
        rt = {}
        for L in 'STRIDE':
            ci   = lidx[L]
            cell = cells[ci] if ci < len(cells) else ''
            tok  = cell_token(cell)
            rt[L] = tok
            if tok is None:
                badcells.append('%s/%s="%s"' % (asset or ('row%d' % k), L, cell.strip()))
        # dedicated race columns (keyed '#<pos>') — token captured for the stage-1 rule only.
        race_tok = {}
        for key, ci in race_cols.items():
            if key.startswith('#'):
                race_tok[key] = cell_token(cells[ci]) if ci < len(cells) else None
        if asset not in rows:
            order.append(asset)
        rows[asset] = {'tok': rt, 'race_row': race_row, 'race_tok': race_tok}
        k += 1
    return order, rows, badcells

order, rows, badcells = parse_rows()

res = []
def add(level, msg): res.append((level, msg))

if badcells:
    add('FAIL', "ledger cells without exactly one valid lifecycle token "
        "(UNMODELED|PROVED|TRUSTED-PENDING|TRUSTED|N/A[(RR#)]): " + ", ".join(badcells[:10]))

# --- TSV (baseline) serialization -------------------------------------------
def to_tsv(order, rows):
    out = ["# ledger-baseline.tsv — frozen STRIDE ledger (crosswalk-template §3.2); ratchet moves forward only.",
           "# asset\tS\tT\tR\tI\tD\tE"]
    for a in order:
        rt = rows[a]['tok']
        out.append("\t".join([a] + [(rt[L] or 'UNMODELED') for L in 'STRIDE']))
    return "\n".join(out) + "\n"

def from_tsv(path):
    base = {}
    for ln in open(path, encoding="utf-8", errors="replace").read().splitlines():
        if not ln.strip() or ln.lstrip().startswith('#'):
            continue
        parts = ln.split('\t')
        if len(parts) < 7:
            continue
        a = parts[0].strip()
        base[a] = {L: parts[1+i].strip() for i, L in enumerate('STRIDE')}
    return base

# --- WS1 stage-1 rule: race-family cell may not be PROVED while only stage 1 ships --------------
# A cell is race-family if it sits in a race/concurrency COLUMN or a race/concurrency ROW.
stage_viol = []
stride_race_cols = {L for L in 'STRIDE' if L in race_cols}
if ws1_stage < 2:
    for a in order:
        rt       = rows[a]['tok']
        race_row = rows[a]['race_row']
        # (a) STRIDE cells that are race-family (race column header) or on a race-bearing asset row
        for L in 'STRIDE':
            is_race_cell = (L in stride_race_cols) or race_row
            if is_race_cell and rt.get(L) == 'PROVED':
                stage_viol.append("%s/%s" % (a, L))
        # (b) dedicated race columns
        for key, tok in rows[a]['race_tok'].items():
            if tok == 'PROVED':
                stage_viol.append("%s/race[%s]" % (a, key))
if stage_viol:
    add('FAIL', "WS1 stage-%d: race/concurrency-family cell marked PROVED — it must stay TRUSTED "
        "until WS1 stage-2 (rely-guarantee) lands (template §3.2): %s" % (ws1_stage, ", ".join(stage_viol)))
elif ws1_stage < 2 and (race_cols or any(rows[a]['race_row'] for a in order)):
    add('INFO', "WS1 stage-%d: race/concurrency family present and correctly NOT PROVED (TRUSTED until stage-2)" % ws1_stage)

# --- WARN on every current UNMODELED / TRUSTED-PENDING cell (surfaced, never blocking) ---------
warn_cells = []
for a in order:
    rt = rows[a]['tok']
    for L in 'STRIDE':
        if rt.get(L) in ('UNMODELED', 'TRUSTED-PENDING'):
            warn_cells.append('%s/%s=%s' % (a, L, rt[L]))
if warn_cells:
    add('WARN', "incomplete cells (ratcheted toward PROVED/TRUSTED, NOT blocking): " + ", ".join(warn_cells))

# --- the ratchet: compare against the frozen baseline ---------------------------------------
bootstrap = False
if EMIT_ONLY or not os.path.exists(BASELINE):
    # First run (or explicit emit): freeze the current ledger as the baseline and PASS. §3.2 rule 4.
    open(BASELINE, "w", encoding="utf-8").write(to_tsv(order, rows))
    bootstrap = True
    add('INFO', "no baseline at '%s' — emitted frozen baseline from current ledger (%d asset row%s)"
        % (BASELINE, len(order), '' if len(order) == 1 else 's'))
else:
    base = from_tsv(BASELINE)
    add('INFO', "baseline: %s (%d asset row%s)" % (BASELINE, len(base), '' if len(base) == 1 else 's'))

    # Regression 1 (§3.2.1): a cell PROVED/TRUSTED in baseline is now UNMODELED.
    reg_cells = []
    for a, brt in base.items():
        cur = rows.get(a, {}).get('tok')
        for L in 'STRIDE':
            was = brt.get(L)
            now = cur.get(L) if cur else None
            if was in ('PROVED', 'TRUSTED') and now == 'UNMODELED':
                reg_cells.append('%s/%s: %s -> UNMODELED' % (a, L, was))
    if reg_cells:
        add('FAIL', "RATCHET regression — a PROVED/TRUSTED cell backslid to UNMODELED (template §3.2.1): "
            + "; ".join(reg_cells))

    # Regression 2 (§3.2.2): a high-value asset row present in baseline is now MISSING.
    missing = [a for a in base if a not in rows]
    if missing:
        add('FAIL', "RATCHET regression — asset row present in baseline now MISSING (template §3.2.2): "
            + ", ".join(sorted(missing)))

    if not reg_cells and not missing:
        add('PASS', "no regression vs baseline (no PROVED/TRUSTED -> UNMODELED, no dropped asset row)")

# --- report -----------------------------------------------------------------
for a in order:
    rt = rows[a]['tok']
    add('INFO', "  %-9s S=%s T=%s R=%s I=%s D=%s E=%s"
        % (a, rt['S'], rt['T'], rt['R'], rt['I'], rt['D'], rt['E']))

for lvl, msg in res:
    print("  %-4s %s" % (lvl, msg))
print()
fails = [r for r in res if r[0] == 'FAIL']
if fails:
    print("LEDGER-RATCHET FAIL (%d regression%s) — the ratchet moves FORWARD only (template §3.2)"
          % (len(fails), '' if len(fails) == 1 else 's'))
    sys.exit(1)
if bootstrap:
    print("LEDGER-RATCHET PASS (bootstrap — frozen baseline emitted; cross-run ratchet armed for next run)")
else:
    print("LEDGER-RATCHET PASS (regression-only gate; incompleteness WARNs, never fails — crosswalk-template §3.2)")
sys.exit(0)
PYRATCHET
