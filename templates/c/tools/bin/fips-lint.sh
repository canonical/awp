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
# line carries exactly one AR# and at least one src: token; chaining FM->RQ, VO->FM+RQ+class+priority,
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
#   F-C4  every RQ# home line names exactly one AR# and carries at least one src: token
#   F-C5  the src: tokens of an RQ# home line are src:UNSOURCED (alone), src:PDF-ann6|7|10|13, or
#         src:<DOC>:<LOC> with DOC an id of specs/MANIFEST.tsv (src:FIPS140-3:<LOC> as src:PDF-<LOC>);
#         every other src: token anywhere is a PDF section token or names a manifest document
#   F-C6  chaining on home lines: FM#->RQ#; VO#->FM#+RQ#+class+P1-P3 with its RQ# set equal to the
#         union of its FM# home lines' RQ#; RR#->plane+(FM#/RQ#/AR#/STANDING); every RQ# named on a
#         VO# or RR# home line
#   F-C7  no RQ# home line with min-level K greater than the target level
#   F-C8  F5 holds an RR# line for each standing plane: crypto ENV physical side-channel supply-chain
#         validation
#   F-C9  endogeneity tripwire (FAIL): no code artifacts in F1-F4 (same regex as rmf-lint.sh C8)
#   F-C10 volume within the Gate-A budget for the level (WARN; the budgets are placeholders)
#   F-C11 count of src:UNSOURCED requirements (INFO; WARN when the corpus is present and more than
#         half the requirements are UNSOURCED)
#   F-C12 every src:<DOC>:<LOC> locator occurs in specs/text/<DOC>.txt (WARN: text extraction can
#         lose headings; a missing locator is a fabricated or drifted citation until checked)
#   F-C13 no RQ# home line sourced only from draft documents (WARN: drafts are not binding)
#   F-C14 every chk:<ID> reference names an item of specs/checklist/data/*.jsonl (FAIL)
#
# The corpus is specs/ under the current directory (auto-wp.py --driver fips installs it):
# specs/MANIFEST.tsv, specs/text/<DOC>.txt, specs/checklist/data/*.jsonl. FIPS_SPECS=DIR overrides
# the location (test hook).
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

# --- the corpus: specs/ (MANIFEST.tsv, text/, checklist/) ----------------------
specs = os.environ.get("FIPS_SPECS", "specs")
corpus = {}        # DOC id -> manifest row
man_path = os.path.join(specs, "MANIFEST.tsv")
if os.path.exists(man_path):
    header = None
    for ln in open(man_path, encoding="utf-8"):
        ln = ln.rstrip("\n")
        if not ln or ln.startswith("#"):
            continue
        cells = ln.split("\t")
        if header is None:
            header = cells
            continue
        row = dict(zip(header, cells))
        corpus[row["id"]] = row
chk_ids = None     # checklist item ids, when the checklist is present
chk_dir = os.path.join(specs, "checklist", "data")
if os.path.isdir(chk_dir):
    chk_ids = set()
    for f in sorted(os.listdir(chk_dir)):
        if f.endswith(".jsonl"):
            for ln in open(os.path.join(chk_dir, f), encoding="utf-8"):
                if ln.strip():
                    try:
                        chk_ids.add(json.loads(ln)["id"])
                    except (ValueError, KeyError):
                        pass
texts = {}
def doc_text(doc):
    if doc not in texts:
        p = os.path.join(specs, "text", doc + ".txt")
        texts[doc] = open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else None
    return texts[doc]
SRC_RX = re.compile(r'src:[A-Za-z0-9.\-]+(?::[A-Za-z0-9._\-]*[A-Za-z0-9])?')
def src_tokens(ln):
    return SRC_RX.findall(ln)
def split_src(tok):
    """src:DOC:LOC -> (DOC, LOC); src:PDF-x -> ('FIPS140-3', x); src:UNSOURCED -> (None, None)."""
    body = tok[4:]
    if body.startswith("PDF-"):
        return "FIPS140-3", body[4:]
    if ":" in body:
        return tuple(body.split(":", 1))
    return None, None

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
RQ_PDF = {"ann6", "ann7", "ann10", "ann13"}
FULL_PDF = (["abs"] + ["ann%d" % n for n in range(1, 15)] + ["sec1", "sec2", "sec3"] +
            ["sec3.%d" % i for i in range(1, 5)] + ["tab1"])
CLASS_RX = (r'\b(approved-only|output-inhibit|role-gate|integrity-first|zeroize|'
            r'no-plain-ssp-out|selftest-order|error-state|fsm)\b')
unsourced = 0
draft_only = []
for l in rq_lines:
    n = first_tag(l)[1]
    ars = [x for t, x in ids_on(l) if t == "AR"]
    srcs = src_tokens(l)
    if len(ars) != 1:
        add('FAIL', 'F-C4', "RQ%s names %d AR# — exactly one (rule F3)" % (n, len(ars)))
    if not srcs:
        add('FAIL', 'F-C4', "RQ%s carries no src: token — at least one (rule F3)" % n)
    elif "src:UNSOURCED" in srcs:
        if len(srcs) > 1:
            add('FAIL', 'F-C5', "RQ%s mixes src:UNSOURCED with other sources — UNSOURCED stands alone "
                "(rule F3)" % n)
        unsourced += 1
    else:
        docs = []
        for s in srcs:
            doc, loc = split_src(s)
            if doc == "FIPS140-3":
                if loc not in RQ_PDF:
                    add('FAIL', 'F-C5', "RQ%s src %s: of the FIPS 140-3 PDF only ann6, ann7, ann10 and "
                        "ann13 are normative (rule F3)" % (n, s))
            elif doc is None or not loc:
                add('FAIL', 'F-C5', "RQ%s src %s is not src:UNSOURCED, src:PDF-annN or src:<DOC>:<LOC> "
                    "(rule F3)" % (n, s))
                continue
            elif doc not in corpus:
                add('FAIL', 'F-C5', "RQ%s src %s: %s is not a document of %s (rule F3)"
                    % (n, s, doc, man_path if corpus else "the corpus — no " + man_path))
                continue
            docs.append(doc)
        if docs and all(corpus.get(d, {}).get("status") == "draft" for d in docs):
            draft_only.append(n)
    mm = re.search(r'\bmin-level\s+([1-4])\b', l)
    if mm and int(mm.group(1)) > level:
        add('FAIL', 'F-C7', "RQ%s min-level %s is above the target level %d — it does not belong in "
            "the report (rule F5)" % (n, mm.group(1), level))
if rq_lines:
    if unsourced == 0:
        lvl_u = 'PASS'
    elif corpus and unsourced * 2 > len(rq_lines):
        lvl_u = 'WARN'
    else:
        lvl_u = 'INFO'
    add(lvl_u, 'F-C11',
        "%d of %d requirement(s) are src:UNSOURCED (honest state, never hidden — reviewed at the terminus%s)"
        % (unsourced, len(rq_lines),
           "; the corpus is present, so most requirements should cite it" if lvl_u == 'WARN' else ""))
else:
    add('SKIP', 'F-C11', 'no RQ# home lines')
for n in draft_only:
    add('WARN', 'F-C13', "RQ%s cites only draft documents — not binding; cite the final document or mark "
        "the item as forward-looking in F5 (rule F3)" % n)
unanchored, unchecked, seen_src = [], 0, set()
for ln in txt.splitlines():
    for s in src_tokens(ln):
        if s in seen_src or s == "src:UNSOURCED":
            continue
        seen_src.add(s)
        doc, loc = split_src(s)
        if doc == "FIPS140-3":
            if loc not in FULL_PDF:
                add('FAIL', 'F-C5', "%s is not a PDF section token (rule F3: src:PDF-abs, src:PDF-ann1..14, "
                    "src:PDF-sec1..3, src:PDF-sec3.1..3.4, src:PDF-tab1)" % s)
            continue
        if doc is None or not loc:
            add('FAIL', 'F-C5', "%s is not src:UNSOURCED, src:PDF-<section> or src:<DOC>:<LOC> (rule F3)" % s)
            continue
        if doc not in corpus:
            add('FAIL', 'F-C5', "%s: %s is not a document of %s (rule F3)"
                % (s, doc, man_path if corpus else "the corpus — no " + man_path))
            continue
        t = doc_text(doc)
        if t is None:
            unchecked += 1
            continue
        e = re.escape(loc)
        if not re.search(r'(?<![\w.])' + e + r'(?!\w|\.\w)', t):
            unanchored.append(s)
if unanchored:
    add('WARN', 'F-C12', "locator(s) not found in specs/text/: %s — check the citation by hand (rule F3)"
        % ", ".join(unanchored[:8]) + (" …" if len(unanchored) > 8 else ""))
elif any(split_src(s)[0] not in (None, "FIPS140-3") for s in seen_src):
    add('PASS', 'F-C12', "every checkable src:<DOC>:<LOC> locator occurs in its document's text")
if unchecked:
    add('INFO', 'F-C12', "%d citation(s) not checkable: no specs/text/<DOC>.txt (e.g. a restricted "
        "document not imported)" % unchecked)
chk_refs = sorted(set(re.findall(r'\bchk:([A-Z]+-\d+)\b', txt)))
if chk_refs:
    if chk_ids is None:
        add('SKIP', 'F-C14', "%d chk: reference(s), but no %s to check them" % (len(chk_refs), chk_dir))
    else:
        bad = [c for c in chk_refs if c not in chk_ids]
        if bad:
            add('FAIL', 'F-C14', "chk: reference(s) to no checklist item: %s (rule F3)" % ", ".join(bad[:8]))
        else:
            add('PASS', 'F-C14', "%d chk: reference(s), all in the checklist" % len(chk_refs))

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
# Without the corpus: the original placeholders. With it: the per-area volume the ISO/IEC 24759
# assertions and the IG imply (specs/checklist ISO-* items per area: about 5 to 50 at level 1).
BUDGET = ({1: (3, 40), 2: (4, 50), 3: (5, 60), 4: (6, 70)} if corpus
          else {1: (1, 3), 2: (2, 4), 3: (2, 5), 4: (3, 6)})
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
