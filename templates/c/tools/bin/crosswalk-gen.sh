#!/usr/bin/env bash
# crosswalk-gen.sh — emit <PREFIX>-crosswalk.md natively from a campaign's artifacts.
#
# Move 5 of extended-stride-coverage-impl.md: the threat<->verification JOIN should be
# generated from the live report + verdicts, not transcribed by hand (a hand-built join
# drifts from the verdicts it summarizes). This is the generator.
#
# Seating (the load-bearing separation — keep each half in its own loop's evidence base):
#   §1 assets / §2 scenarios / §5 residuals  <-  the CODE-BLIND report  (rmf-sl / ebios-sl)
#   §4 verdict join                          <-  verdicts.tsv           (frama-c-monitoring)
#   §3 STRIDE ledger                         <-  stride-ledger.tsv      (the code-aware architect)
# The §3 ledger is the architect's coverage ASSESSMENT (necessarily broader than the verdicts:
# it carries UNMODELED/TRUSTED cells that no proof backs). The generator does NOT invent it — it
# transcribes the structured TSV and MACHINE-CHECKS it: every PROVED cell must be backed by a
# non-vacuous Valid/PROVED verdict for that SA in verdicts.tsv, or the run FAILS (a PROVED claim
# can never drift from the proof — the no-blend invariant, enforced).
#
# Usage:
#   ./crosswalk-gen.sh PREFIX [--kind rmf|ebios] [--out FILE] [--check]
#     PREFIX        e.g. s2n-tls-analysis  (expects PREFIX-{rmf,ebios}-report.md + PREFIX-acsl/)
#     --kind        rmf (default) or ebios; auto-detected from which report exists
#     --out FILE    output path (default PREFIX-crosswalk.md)
#     --check       do not write; regenerate to a temp file and diff against the committed
#                   crosswalk — exit 1 on drift (the CI sync gate). Implies faithfulness check.
#
# Inputs (per PREFIX):
#   PREFIX-rmf-report.md | PREFIX-ebios-report.md   (the code-blind report)
#   PREFIX-acsl/verdicts.tsv                          (unit\tSA#\t...\tverdict\t...)
#   PREFIX-acsl/stride-ledger.tsv                     (SA\tS\tT\tR\tI\tD\tE\tattack — the §3 matrix)
# Exit: 0 ok · 1 faithfulness violation / drift · 2 usage / missing input.
set -uo pipefail

PY="${ROCQ_PYTHON_BIN:-python3}"
prefix="" ; kind="" ; out="" ; check=0
while [ $# -gt 0 ]; do
  case "$1" in
    --kind) kind="$2"; shift 2;;
    --out)  out="$2";  shift 2;;
    --check) check=1; shift;;
    -*) echo "crosswalk-gen: unknown flag $1" >&2; exit 2;;
    *) prefix="$1"; shift;;
  esac
done
[ -n "$prefix" ] || { echo "usage: crosswalk-gen.sh PREFIX [--kind rmf|ebios] [--out FILE] [--check]" >&2; exit 2; }

# locate the report + decide kind
rmf_report="${prefix}-rmf-report.md"
ebios_report="${prefix}-ebios-report.md"
if [ -z "$kind" ]; then
  if   [ -f "$rmf_report" ];   then kind=rmf
  elif [ -f "$ebios_report" ]; then kind=ebios
  else echo "crosswalk-gen: no ${prefix}-rmf-report.md or ${prefix}-ebios-report.md" >&2; exit 2; fi
fi
report="${prefix}-${kind}-report.md"
[ -f "$report" ] || { echo "crosswalk-gen: report '$report' not found" >&2; exit 2; }
overlay="${prefix}-acsl"
verdicts="${overlay}/verdicts.tsv"
ledger="${overlay}/stride-ledger.tsv"
[ -n "$out" ] || out="${prefix}-crosswalk.md"

tmp="$(mktemp)"
"$PY" - "$report" "$kind" "$verdicts" "$ledger" "$prefix" >"$tmp" 2>"$tmp.err" <<'PYGEN'
import re, sys, os
report, kind, verdicts_p, ledger_p, prefix = sys.argv[1:6]
rep = open(report, encoding="utf-8", errors="replace").read()

FAM = ["S","T","R","I","D","E"]
warn = []

# ---- §1 assets: "- SAn <role>: <desc>"  or  "- SAn <role>" ----
assets = []  # (id, role)
for m in re.finditer(r'(?m)^[-*]\s+(SA\d+)\s+(.+)$', rep):
    sid, rest = m.group(1), m.group(2).strip()
    # role = up to the first ": " or surrounded dash separator (NOT a bare "." — "X.509")
    role = re.split(r'\s+[—–-]\s+|:\s', rest, maxsplit=1)[0].strip()
    assets.append((sid, role))
# dedupe keep first
seen=set(); _a=[]
for sid,role in assets:
    if sid not in seen: seen.add(sid); _a.append((sid,role))
assets=_a

# ---- §2 scenarios: RMF "RSn: ... (SAn) ... likelihood Lk — risk R ... CTLn"
#                    EBIOS "SSn: ... FEn ... via SAn — severity Gk — attack path APn" ----
scen = []  # dict
if kind == "rmf":
    for m in re.finditer(r'(?m)^[-*]\s+(RS\d+):\s*(.+)$', rep):
        rid, body = m.group(1), m.group(2)
        sa  = (re.search(r'\((SA\d+)\)', body) or re.search(r'\b(SA\d+)\b', body))
        lk  = re.search(r'likelihood\s+(L\d)', body)
        rk  = re.search(r'risk\s+(\w+)', body)
        im  = re.search(r'\b(IM\d+)\b', body)
        ctl = re.search(r'\b(CTL\d+)\b', body)
        scen.append(dict(id=rid, sa=sa.group(1) if sa else "?", fe=im.group(1) if im else "",
                         lk=lk.group(1) if lk else "?", risk=rk.group(1) if rk else "?",
                         ctl=ctl.group(1) if ctl else ""))
else:
    for m in re.finditer(r'(?m)^[-*]\s+(SS\d+):\s*(.+)$', rep):
        rid, body = m.group(1), m.group(2)
        sa  = re.search(r'\b(SA\d+)\b', body)
        fe  = re.search(r'\b(FE\d+)\b', body)
        sev = re.search(r'severity\s+(G\d)', body)
        ap  = re.search(r'\b(AP\d+)\b', body)
        scen.append(dict(id=rid, sa=sa.group(1) if sa else "?", fe=fe.group(1) if fe else "",
                         lk="", risk=sev.group(1) if sev else "?", ctl=ap.group(1) if ap else ""))

# ---- verdicts.tsv: SA# -> has a non-vacuous Valid/PROVED verdict? ----
verds = []           # rows (dict)
proved_sa = set()    # SA with a Valid/PROVED row
sa_units = {}        # SA -> ordered list of distinct translation units (code-aware)
if os.path.exists(verdicts_p):
    rows = [l.rstrip("\n").split("\t") for l in open(verdicts_p, encoding="utf-8", errors="replace")
            if l.strip() and not l.lstrip().startswith("#")]
    if rows:
        hdr = [h.strip().lower().rstrip("#") for h in rows[0]]
        def col(r, name):
            try: return r[hdr.index(name)].strip()
            except (ValueError, IndexError): return ""
        for r in rows[1:]:
            sa = col(r,"sa"); vd = col(r,"verdict") or col(r,"status"); unit = col(r,"unit")
            verds.append(dict(sa=sa, fn=col(r,"function") or unit,
                              verdict=vd, goals=col(r,"goals"), note=col(r,"notes")))
            for s in re.split(r'[/,]', sa):
                s=s.strip()
                if not s: continue
                # VERIFIED is time-loop's per-unit word (time-loop/SKILL.md §5 schema)
                if re.search(r'\b(Valid|PROVED|GREEN|VERIFIED)\b', vd, re.I): proved_sa.add(s)
                if unit and not re.fullmatch(r'SA\d+', unit):   # skip SA# placeholders used by BLOCKED rows
                    sa_units.setdefault(s, [])
                    if unit not in sa_units[s]: sa_units[s].append(unit)
else:
    warn.append(f"no {verdicts_p} — §4 verdict join will be empty")

# ---- stride-ledger.tsv: the §3 matrix (SA  S T R I D E  attack) ----
LEDGER_TOKENS = {"UNMODELED","PROVED","TRUSTED-PENDING","TRUSTED","N/A"}
ledger = {}   # sa -> {fam: token}, plus 'attack'
fail = []
if os.path.exists(ledger_p):
    rows = [l.rstrip("\n").split("\t") for l in open(ledger_p, encoding="utf-8", errors="replace") if l.strip() and not l.startswith("#")]
    hdr = [h.strip().lower() for h in rows[0]] if rows else []
    for r in rows[1:]:
        rec = dict(zip(hdr, [c.strip() for c in r]))
        sa = rec.get("sa","")
        if not sa: continue
        cells = {}
        for f in FAM:
            tok_raw = rec.get(f.lower(), "UNMODELED") or "UNMODELED"
            base = re.sub(r'\s*\(.*\)$','', tok_raw).strip()   # strip "(RR2)"/notes
            if base not in LEDGER_TOKENS:
                fail.append(f"{sa}/{f}: invalid token '{tok_raw}'")
            cells[f] = tok_raw
        cells["attack"] = rec.get("attack","")
        ledger[sa] = cells
    # FAITHFULNESS CHECK: every PROVED cell must be backed by a Valid verdict for that SA
    for sa, cells in ledger.items():
        for f in FAM:
            if re.sub(r'\s*\(.*\)$','',cells[f]).strip() == "PROVED" and sa not in proved_sa:
                fail.append(f"{sa}/{f}=PROVED but no Valid/PROVED verdict for {sa} in verdicts.tsv "
                            f"(no-blend: a PROVED cell must be backed by a proof)")
else:
    warn.append(f"no {ledger_p} — §3 ledger emitted as all-UNMODELED skeleton (architect must fill)")
    for sid,_ in assets:
        ledger[sid] = {f:"UNMODELED" for f in FAM}; ledger[sid]["attack"]=""

if fail:
    sys.stderr.write("FAITHFULNESS FAIL:\n  " + "\n  ".join(fail) + "\n")
    sys.exit(1)

# ---------------- emit the crosswalk (template-conforming) ----------------
TL = "EBIOS" if kind=="ebios" else "RMF"
loop = "ebios-sl" if kind=="ebios" else "rmf-sl"
P=print
P(f"# {TL} ↔ frama-c-monitoring crosswalk — {prefix}")
P("")
P(f"GENERATED by `crosswalk-gen.sh` (Move 5 — do not hand-edit; edit the sources). The threat↔"
  f"verification join for the **{prefix}** campaign: code-blind `{os.path.basename(report)}` (§1–§2,§5) "
  f"meets code-aware `{prefix}-acsl/verdicts.tsv` (§4) + `stride-ledger.tsv` (§3). Schema: "
  "[`config/skills/frama-c-monitoring/templates/crosswalk-template.md`](./config/skills/frama-c-monitoring/templates/crosswalk-template.md).")
P("")
P("> **Plane / no-blend.** Every \"covers\" is the **named property only**. A `PROVED` ledger cell is "
  "machine-checked against `verdicts.tsv` (a PROVED claim with no backing proof FAILS generation). A "
  f"green does **not** lower a risk level — only the human terminus does, downstream. Authored by {loop} "
  "(code-blind §1–2,§5) + the architect (code-aware §3–4); the report stayed code-blind.")
P("")
# §1
P("## 1. Asset crosswalk — SA# ↔ scope")
P("")
P("| SA# | Role (code-blind report) | Translation unit(s) (verdicts.tsv) | Coverage (§3 ledger) |")
P("|---|---|---|---|")
def cov(sid):
    c = ledger.get(sid, {})
    pv = [f for f in FAM if re.sub(r'\s*\(.*\)$','',c.get(f,"")).strip()=="PROVED"]
    tr = [f for f in FAM if re.sub(r'\s*\(.*\)$','',c.get(f,"")).strip() in ("TRUSTED","TRUSTED-PENDING")]
    if pv and not tr: return "**amenable** ("+",".join(pv)+" PROVED)"
    if pv and tr:     return "**split** ("+",".join(pv)+" PROVED; "+",".join(tr)+" residual)"
    if tr:            return "**BLOCKED** ("+",".join(tr)+" residual)"
    return "UNMODELED"
for sid, role in assets:
    units = ", ".join("`%s`"%u for u in sa_units.get(sid, [])) or "—"
    P(f"| **{sid}** | {role} | {units} | {cov(sid)} |")
P("")
# §2
P("## 2. Scenario crosswalk — exogenous ranking (cited from the report)")
P("")
if kind=="rmf":
    P("| RS# | SA | impact | likelihood | risk | control |")
    P("|---|---|---|---|---|---|")
    for s in scen:
        P(f"| {s['id']} | {s['sa']} | {s['fe']} | {s['lk']} | {s['risk']} | {s['ctl']} |")
else:
    P("| SS# | SA | feared event | severity | attack path |")
    P("|---|---|---|---|---|")
    for s in scen:
        P(f"| {s['id']} | {s['sa']} | {s['fe']} | {s['risk']} | {s['ctl']} |")
P("")
# §3
P("## 3. STRIDE coverage ledger — SA × {S,T,R,I,D,E}")
P("")
P("Lifecycle per template §3.1; ratchet per §3.2 (`ledger-ratchet.sh`). PROVED cells are machine-"
  "checked against `verdicts.tsv`. `frozen baseline = this table`.")
P("")
P("| Asset | S | T | R | I | D | E | ATT&CK |")
P("|---|---|---|---|---|---|---|---|")
for sid,_ in assets:
    c = ledger.get(sid, {f:"UNMODELED" for f in FAM})
    P("| "+sid+" | "+" | ".join(c.get(f,"UNMODELED") for f in FAM)+" | "+c.get("attack","")+" |")
P("")
# §4
P("## 4. Verdict join — coverage vs ranking")
P("")
P("**Plane: the named property only.** Source: `"+os.path.basename(overlay if False else prefix+'-acsl')+"/verdicts.tsv`.")
P("")
if verds:
    P("| Unit / function | SA | verdict | goals | note |")
    P("|---|---|---|---|---|")
    for v in verds:
        if not (v["sa"] or v["fn"]): continue
        P(f"| {v['fn']} | {v['sa']} | {v['verdict']} | {v['goals']} | {v['note']} |")
else:
    P("_(no verdicts.tsv)_")
P("")
# §5
P("## 5. Residual register")
P("")
P("| RR# | Residual (from the report / BLOCKED verdicts) | Plane | Signed (human terminus) |")
P("|---|---|---|---|")
rr = sorted(set(re.findall(r'\bRR\d+\b', rep)) | set(re.findall(r'\bRR\d+\b', "\n".join(v["verdict"]+v["note"] for v in verds))),
            key=lambda x:int(x[2:]))
if rr:
    for r in rr:
        # prefer a line that DEFINES the residual ("- RR1 — ..." / "RR1:"), else any mention
        ctx = ""
        mm = (re.search(r'(?m)^[-*]?\s*'+r+r'\b[ :—–-].*$', rep)
              or re.search(r'(?m)^.*\b'+r+r'\b.*$', rep))
        if mm:
            ctx = re.sub(r'^[-*]\s*','', re.sub(r'\s+',' ', mm.group(0)).strip())
            ctx = re.sub(r'^'+r+r'\b[ :—–-]*','', ctx).strip()[:90]
        P(f"| {r} | {ctx} | residual | ☐ PENDING |")
else:
    P("_(no RR# residuals tagged)_")
P("")
P("## 6. Handoff")
P("")
P("- **Priority** = the §2 ranking. **Feedback** = likelihood deltas on the named plane only "
  "(no proof internals), keyed to the scenario IDs, via the loop's `*-feedback.md`. **Authorize: PENDING.**")
if warn:
    P("")
    P("<!-- generator warnings: " + " | ".join(warn) + " -->")
PYGEN
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "crosswalk-gen: generation failed for $prefix ($kind):" >&2
  sed 's/^/  /' "$tmp.err" >&2
  rm -f "$tmp" "$tmp.err"; exit "$rc"
fi

if [ "$check" -eq 1 ]; then
  if [ ! -f "$out" ]; then echo "crosswalk-gen --check: '$out' does not exist yet" >&2; rm -f "$tmp" "$tmp.err"; exit 1; fi
  if diff -q "$out" "$tmp" >/dev/null 2>&1; then
    echo "crosswalk-gen --check: $out in sync with its sources"; rm -f "$tmp" "$tmp.err"; exit 0
  else
    echo "crosswalk-gen --check: DRIFT — $out differs from regeneration (run without --check to refresh):" >&2
    diff "$out" "$tmp" | head -40 >&2
    rm -f "$tmp" "$tmp.err"; exit 1
  fi
fi
mv "$tmp" "$out"; rm -f "$tmp.err"
echo "crosswalk-gen: wrote $out  (kind=$kind)"
