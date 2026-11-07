#!/usr/bin/env bash
# fips-lint.sh — structure + coverage + source-honesty + endogeneity linter for a
# FIPS 140-3 requirement study.
#
# The mechanical lower bound (L) of the fips-sl loop (config/skills/fips-sl). It checks the STRUCTURE
# of a requirement study, not its content realism — realism, and whether a src:PDF-… requirement
# really says what the cited section says, are the human terminus (a disjoint reviewer + the owner of
# the protected information / the agency's responsible authority, Ann. 13). Faithful sibling of
# rmf-lint.sh (NIST RMF R1-R5 -> FIPS F1-F5).
#
# Usage:   ./fips-lint.sh REPORT.md
# Exit:    0 = all checks pass (WARN/INFO allowed) - 1 = violations - 2 = usage/format error.
#
# FORMAT CONTRACT (authoritative): config/skills/fips-sl/references/report-format.md — the PINNED
# tag convention. The report author writes to it and this linter parses it, so they cannot drift.
# In brief: section headings holding F1..F5; one artifact per line/row with its tokens on that same
# line; every defined tag (MOD SV RL SSP IF ST RQ FM VO RR) has exactly one home line; every RQ# home
# line carries exactly one AR# and exactly one src: token; chaining FM->RQ, VO->FM+RQ+class+priority,
# RR->plane+(FM|RQ|AR|STANDING); a bare "level: N" line in F1.
#
# The target level comes from config/auto-wp.json (fips_level) in the current directory — the project
# root; the manifest is the single place the level is stored (fips-skill-spec.md 3). FIPS_LEVEL=N in
# the environment overrides it. That override is a test hook only.
#
# Checks (fips-skill-spec.md 5):
#   F-C0  every MOD/SV/RL/SSP/IF/ST/RQ/FM/VO/RR id has exactly one home line (referenced-without-
#         definition fails; AR# is a fixed vocabulary, not checked here)
#   F-C1  sections F1-F5 present (precondition: when it fails, it is reported alone)
#   F-C2  exactly one bare "level: [1-4]" line, inside F1, equal to the manifest's fips_level
#   F-C3  each of AR1-AR11 named on an RQ# home line or on an N/A line with a reason, in F2
#   F-C4  every RQ# home line names exactly one AR# and carries exactly one src: token
#   F-C5  the src: token of an RQ# home line is src:PDF-ann6|7|10|13 or src:UNSOURCED; every other
#         src:PDF-… token anywhere is in the full token set
#   F-C6  chaining on home lines: FM#->RQ#; VO#->FM#+RQ#+class+P1-P3 with its RQ# set equal to the
#         union of its FM# home lines' RQ#; RR#->plane+(FM#/RQ#/AR#/STANDING); every RQ# named on a
#         VO# or RR# home line
#   F-C7  no RQ# home line with min-level K greater than the target level
#   F-C8  F5 holds an RR# line for each standing plane: crypto ENV physical side-channel supply-chain
#         validation
#   F-C9  endogeneity tripwire (FAIL): no code artifacts in F1-F4 (same regex as rmf-lint.sh C8)
#   F-C10 volume within the Gate-A budget for the level (WARN; the budgets are placeholders)
#   F-C11 count of src:UNSOURCED requirements (INFO)
set -uo pipefail
PY="${ROCQ_PYTHON_BIN:-python3}"
[ "${1:-}" ] || { echo "usage: fips-lint.sh REPORT.md" >&2; exit 2; }
[ -f "$1" ]  || { echo "fips-lint: '$1' not found" >&2; exit 2; }

"$PY" - "$1" <<'PYLINT'
import json, os, re, sys

report_path = sys.argv[1]

# --- the target level: FIPS_LEVEL env (test hook) or the manifest -------------
lvl_env = os.environ.get("FIPS_LEVEL")
if lvl_env is not None:
    if lvl_env not in ("1", "2", "3", "4"):
        print("fips-lint: FIPS_LEVEL must be 1, 2, 3 or 4", file=sys.stderr)
        sys.exit(2)
    level = int(lvl_env)
else:
    man = "config/auto-wp.json"
    if not os.path.exists(man):
        print("fips-lint: config/auto-wp.json not found in the current directory "
              "(run from the project root, or set FIPS_LEVEL)", file=sys.stderr)
        sys.exit(2)
    try:
        m = json.load(open(man))
    except (OSError, ValueError):
        print("fips-lint: config/auto-wp.json is not valid JSON", file=sys.stderr)
        sys.exit(2)
    if not isinstance(m, dict) or "fips_level" not in m:
        print("fips-lint: config/auto-wp.json has no fips_level "
              "(generate the project with --driver fips --level N)", file=sys.stderr)
        sys.exit(2)
    level = int(m["fips_level"])

txt = open(report_path, encoding="utf-8", errors="replace").read()

res = []
def add(lvl, cid, msg):
    res.append((lvl, cid, msg))

# --- sections (F-C1 is a precondition: the other checks presuppose F1-F5) ------
def section_lines(name):
    out, inside = [], False
    for ln in txt.splitlines():
        if re.match(r'^#{1,6}\s', ln):
            if re.search(r'\b%s\b' % name, ln) and not inside:
                inside = True
                continue
            if inside:
                break
    if inside:
        # collect to the next heading
        collecting = False
        for ln in txt.splitlines():
            if re.match(r'^#{1,6}\s', ln):
                if re.search(r'\b%s\b' % name, ln) and not collecting:
                    collecting = True
                    continue
                if collecting:
                    break
            if collecting:
                out.append(ln)
    return out

secs = {n: section_lines(n) for n in ("F1", "F2", "F3", "F4", "F5")}
present = [n for n in ("F1", "F2", "F3", "F4", "F5")
           if any(re.match(r'^#{1,6}\s.*\b%s\b' % n, l) for l in txt.splitlines())]
if len(present) != 5:
    add('FAIL', 'F-C1', "sections F1-F5 not all present as headings (found: %s)"
        % (", ".join(present) or "none"))
    for lvl, cid, msg in res:
        print("%-4s %-5s %s" % (lvl, cid, msg))
    print("\nFIPS-LINT FAIL (F-C1 is a precondition — the other checks presuppose the five sections)")
    sys.exit(1)

# --- tags and home lines -------------------------------------------------------
HOME_TAGS = ["MOD", "SV", "RL", "SSP", "IF", "ST", "RQ", "FM", "VO", "RR"]
HOME = {"MOD": "F1", "SV": "F1", "RL": "F1", "SSP": "F1", "IF": "F1", "ST": "F1",
        "RQ": "F2", "FM": "F3", "VO": "F4", "RR": "F5"}
ID_RX = re.compile(r'\b(MOD|SV|RL|SSP|IF|ST|RQ|FM|VO|RR|AR)(\d+)\b')

def first_tag(ln):
    s = re.sub(r'^[\s\-*|>]+', '', ln)
    s = re.sub(r'^(`\*|`|\*\*)?', '', s)
    m = re.match(r'(' + "|".join(HOME_TAGS) + r')(\d+)\b', s)
    return (m.group(1), m.group(2)) if m else (None, None)

def ids_on(ln):
    return ID_RX.findall(ln)

home = {}          # (tag, n) -> count of home lines
home_lines = {}    # (tag, n) -> the line text
for tag, sec in HOME.items():
    for ln in secs[sec]:
        t, n = first_tag(ln)
        if t == tag:
            home[(tag, n)] = home.get((tag, n), 0) + 1
            home_lines.setdefault((tag, n), ln)

# F-C0
for (tag, n), count in sorted(home.items()):
    if count > 1:
        add('FAIL', 'F-C0', "%s%s has %d home lines — exactly one (rule F0)" % (tag, n, count))
seen = set()
for ln in txt.splitlines():
    for t, n in ids_on(ln):
        if t in HOME and (t, n) not in home:
            if (t, n) not in seen:
                seen.add((t, n))
                add('FAIL', 'F-C0', "%s%s referenced but has no home line in %s (rule F0)" % (t, n, HOME[t]))

# F-C2 — the level line
lvl_lines = [l for l in txt.splitlines() if re.match(r'^level: [1-4]$', l.strip())]
lvl_in_f1 = [l for l in lvl_lines if l in secs["F1"]]
if len(lvl_lines) != 1 or len(lvl_in_f1) != 1:
    add('FAIL', 'F-C2', "expected exactly one bare 'level: N' line inside F1, found %d in the report, "
        "%d in F1 (rule F6)" % (len(lvl_lines), len(lvl_in_f1)))
elif int(lvl_in_f1[0].strip().split()[1]) != level:
    add('FAIL', 'F-C2', "level line '%s' does not match the manifest's fips_level %d" % (lvl_in_f1[0].strip(), level))
else:
    add('PASS', 'F-C2', "level line matches the manifest (level %d)" % level)

# F-C3 — every area covered
rq_lines = [l for l in secs["F2"] if first_tag(l)[0] == "RQ"]
na_lines = [l for l in secs["F2"] if re.search(r'\bN/A\b', l)]
covered_areas = set()
for l in rq_lines:
    covered_areas |= {n for t, n in ids_on(l) if t == "AR"}
for l in na_lines:
    if re.match(r'^\s*[-*]?\s*AR(\d+)\s+N/A\s*[—–-]\s*\S', l):
        covered_areas |= {n for t, n in ids_on(l) if t == "AR"}
missing_areas = [str(i) for i in range(1, 12) if str(i) not in covered_areas]
if missing_areas:
    add('FAIL', 'F-C3', "areas with no RQ# and no N/A-with-reason line in F2 (rule F2): AR"
        + ", AR".join(missing_areas))
else:
    add('PASS', 'F-C3', "all eleven areas covered (requirement or N/A with a reason)")

# F-C4 / F-C5 / F-C7 — the RQ# home lines
RQ_SRC = {"src:PDF-ann6", "src:PDF-ann7", "src:PDF-ann10", "src:PDF-ann13", "src:UNSOURCED"}
FULL_SRC = (["src:PDF-abs"] + ["src:PDF-ann%d" % n for n in range(1, 15)] +
            ["src:PDF-sec1", "src:PDF-sec2", "src:PDF-sec3"] +
            ["src:PDF-sec3.%d" % i for i in range(1, 5)] + ["src:PDF-tab1"])
CLASS_RX = (r'\b(approved-only|output-inhibit|role-gate|integrity-first|zeroize|'
            r'no-plain-ssp-out|selftest-order|error-state|fsm)\b')
unsourced = 0
for l in rq_lines:
    n = first_tag(l)[1]
    ars = [x for t, x in ids_on(l) if t == "AR"]
    srcs = re.findall(r'src:[A-Za-z0-9.\-]+', l)
    if len(ars) != 1:
        add('FAIL', 'F-C4', "RQ%s names %d AR# — exactly one (rule F3)" % (n, len(ars)))
    if len(srcs) != 1:
        add('FAIL', 'F-C4', "RQ%s carries %d src: tokens — exactly one (rule F3)" % (n, len(srcs)))
    elif srcs[0] not in RQ_SRC:
        add('FAIL', 'F-C5', "RQ%s src %s is not allowed on a requirement line — src:PDF-ann6, "
            "src:PDF-ann7, src:PDF-ann10, src:PDF-ann13 or src:UNSOURCED (rule F3)" % (n, srcs[0]))
    if srcs and srcs[0] == "src:UNSOURCED":
        unsourced += 1
    mm = re.search(r'\bmin-level\s+([1-4])\b', l)
    if mm and int(mm.group(1)) > level:
        add('FAIL', 'F-C7', "RQ%s min-level %s is above the target level %d — it does not belong in "
            "the report (rule F5)" % (n, mm.group(1), level))
if rq_lines:
    add(('PASS' if unsourced == 0 else 'INFO'), 'F-C11',
        "%d of %d requirement(s) are src:UNSOURCED (honest state, never hidden — reviewed at the terminus)"
        % (unsourced, len(rq_lines)))
else:
    add('SKIP', 'F-C11', 'no RQ# home lines')
for ln in txt.splitlines():
    for s in re.findall(r'src:[A-Za-z0-9.\-]+', ln):
        if s.startswith("src:PDF-") and s not in FULL_SRC:
            add('FAIL', 'F-C5', "%s is not a PDF section token (rule F3: src:PDF-abs, src:PDF-ann1..14, "
                "src:PDF-sec1..3, src:PDF-sec3.1..3.4, src:PDF-tab1)" % s)

# F-C6 — chaining
fm_rq = {}
for l in secs["F3"]:
    t, n = first_tag(l)
    if t == "FM":
        fm_rq[n] = {x for tt, x in ids_on(l) if tt == "RQ"}
        if not fm_rq[n]:
            add('FAIL', 'F-C6', "FM%s names no RQ# (rule F4)" % n)
vo_rq = {}
for l in secs["F4"]:
    t, n = first_tag(l)
    if t == "VO":
        fms = [x for tt, x in ids_on(l) if tt == "FM"]
        rqs = {x for tt, x in ids_on(l) if tt == "RQ"}
        cls = re.search(CLASS_RX, l)
        pri = re.search(r'\bP[1-3]\b', l)
        if not fms:
            add('FAIL', 'F-C6', "VO%s names no FM# (rule F4)" % n)
        if not cls:
            add('FAIL', 'F-C6', "VO%s has no property class (rule F4/F7: area-properties.md tokens)" % n)
        if not pri:
            add('FAIL', 'F-C6', "VO%s has no priority P1-P3 (rule F4/F7)" % n)
        union = set()
        for f in fms:
            union |= fm_rq.get(f, set())
        if rqs != union:
            add('FAIL', 'F-C6', "VO%s RQ set {%s} != the union of its FM# home lines' RQ {%s} (rule F4: "
                "none missing, none extra)" % (n, ",".join(sorted(rqs)) or "empty", ",".join(sorted(union)) or "empty"))
        vo_rq[n] = rqs
covered_rqs = set()
for l in secs["F4"] + secs["F5"]:
    covered_rqs |= {x for tt, x in ids_on(l) if tt == "RQ"}
for l in rq_lines:
    n = first_tag(l)[1]
    if n not in covered_rqs:
        add('FAIL', 'F-C6', "RQ%s is named on no VO# or RR# home line (rule F4 coverage)" % n)
if rq_lines and not [1 for l in secs["F4"] + secs["F5"] if first_tag(l)[0] in ("VO", "RR")]:
    add('FAIL', 'F-C6', "no VO#/RR# home lines carry the RQ# coverage")
standing_planes = {"crypto", "ENV", "physical", "side-channel", "supply-chain", "validation"}
rr_planes = set()
for l in secs["F5"]:
    if first_tag(l)[0] == "RR":
        rr_planes |= set(re.findall(r'\b(crypto|ENV|physical|side-channel|supply-chain|logic|validation)\b', l))
        anchor = ([x for tt, x in ids_on(l) if tt in ("FM", "RQ", "AR")] +
                  (["STANDING"] if re.search(r'\bSTANDING\b', l) else []))
        if not anchor:
            add('FAIL', 'F-C6', "RR%s leaves nothing open — name an FM#, RQ#, AR# or STANDING (rule F4)" % first_tag(l)[1])
for p in sorted(standing_planes):
    if p not in rr_planes:
        add('FAIL', 'F-C8', "F5 holds no RR# line for the standing plane %s (rule F4)" % p)
if standing_planes <= rr_planes:
    add('PASS', 'F-C8', "all six standing planes named in F5")
if vo_rq or fm_rq:
    add('PASS', 'F-C6', "chaining well-formed on the home lines")

# F-C9 — endogeneity (same regex as rmf-lint.sh C8; F5 is not scanned)
code = re.compile(r'(?:\b\w+\.(?:c|h|cpp|cc|rs)\b|#include|#define|\b0x[0-9a-fA-F]+\b|::|->'
                  r'|\bfn\s+\w+\s*[(<]|\bimpl(?:\s+\w|\s*<)|\bunsafe\s*\{|#\[\w+|&mut\b'
                  r'|\b(?:Vec|Option|Result|Box|Rc|Arc)<|\b\w+!\(|\.unwrap\(\))')
f1234 = "\n".join(ln for s in ("F1", "F2", "F3", "F4") for ln in secs[s])
hits = sorted(set(m.group(0) for m in code.finditer(f1234)))
if f1234.strip():
    add('FAIL' if hits else 'PASS', 'F-C9',
        ('code artifacts in F1-F4 (ENDOGENEITY — author saw the source?): ' + ", ".join(hits[:8])) if hits
        else 'no code artifacts in F1-F4 (exogenous)')
else:
    add('SKIP', 'F-C9', 'no F1-F4 text to scan')

# F-C10 — volume (WARN; the budgets are placeholders — fips-skill-spec.md 4.6)
BUDGET = {1: (1, 3), 2: (2, 4), 3: (2, 5), 4: (3, 6)}
if rq_lines:
    na_areas = set()
    for l in na_lines:
        if re.match(r'^\s*[-*]?\s*AR(\d+)\s+N/A\s*[—–-]\s*\S', l):
            na_areas |= {n for t, n in ids_on(l) if t == "AR"}
    applicable = len(covered_areas - na_areas)
    if applicable:
        lo, hi = BUDGET[level]
        avg = len(rq_lines) / applicable
        add('PASS' if lo <= avg <= hi else 'WARN', 'F-C10',
            "requirements per applicable area: %.1f [%d,%d] at level %d over %d area(s) — placeholders "
            "(fips-skill-spec.md 9, open point 3)" % (avg, lo, hi, level, applicable))
    else:
        add('SKIP', 'F-C10', 'no applicable area (all N/A)')

# --- report ------------------------------------------------------------------
for lvl, cid, msg in res:
    print("%-4s %-5s %s" % (lvl, cid, msg))
print()
fails = [r for r in res if r[0] == 'FAIL']
warns = [r for r in res if r[0] == 'WARN']
if fails:
    print("FIPS-LINT FAIL (%d violation%s%s) — the report is the fips-sl deliverable; the pinned "
          "format is config/skills/fips-sl/references/report-format.md"
          % (len(fails), '' if len(fails) == 1 else 's',
             ", %d warning%s" % (len(warns), '' if len(warns) == 1 else 's') if warns else ""))
    sys.exit(1)
print("FIPS-LINT PASS (%d check%s)%s" % (len(res), '' if len(res) == 1 else 's',
      " — %d warning%s" % (len(warns), '' if len(warns) == 1 else 's') if warns else ""))
sys.exit(0)
PYLINT
