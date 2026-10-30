#!/bin/sh
# framac-canary.sh — seeded coherent-and-wrong canaries; assert the gates FIRE.
# (WS4 of fc-sl-loops-improve-plan.md.) Self-contained: no corpus needed.
# Exit 0 iff BOTH canaries' gates fire; 1 otherwise (the wiring is broken).
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"   # the project root (this script is in bin/)
CAN="$HERE/config/skills/frama-c-monitoring/canaries"
PY="${ROCQ_PYTHON_BIN:-python3}"
eval "$(opam env --switch=framac-coq8 --set-switch)" 2>/dev/null || true

# all-proved? prints "yes"/"no" given a C file
wp_green() {
  out=$(frama-c -wp -wp-prover alt-ergo -wp-timeout 10 "$1" 2>&1 | grep -oE 'Proved goals:[ ]*[0-9]+ / [0-9]+' | tail -1)
  echo "$out" | "$PY" -c "import sys,re;m=re.search(r'(\d+) / (\d+)',sys.stdin.read());print('yes' if m and m.group(1)==m.group(2) and int(m.group(2))>0 else 'no')"
}
# executable-C fingerprint (strip comments+whitespace) — the faithfulness gate's core
fp() { gcc -fpreprocessed -dD -E -P "$1" 2>/dev/null | tr -d '[:space:]'; }

fail=0

echo "## Canary 1 — faithfulness (hard side)"
orig="$CAN/faithfulness/inc.c"; fab=/tmp/canary_inc_fab.c
# derive a fabricated proof from the pristine: add a (false-for-original) ensures + edit the body
"$PY" - "$orig" > "$fab" <<'PYF'
import sys
s=open(sys.argv[1]).read()
body=s[s.index("unsigned inc"):]               # drop the pristine comment block
body=body.replace("return x + 1u;","return x;")# edit EXECUTABLE C so WP discharges the false ensures
print("/*@ ensures result_eq: \\result == x; */")
print(body, end="")
PYF
fab_green=$(wp_green "$fab")
if [ "$(fp "$orig")" != "$(fp "$fab")" ]; then faith_fired=yes; else faith_fired=no; fi
echo "   fabricated proof WP-green: $fab_green   (a green proof of a false postcondition)"
echo "   faithfulness gate (strip-ACSL == pristine) fired: $faith_fired"
[ "$faith_fired" = yes ] || { echo "   !! FAIL: faithfulness gate did NOT catch the executable-C edit"; fail=1; }

echo "## Canary 2 — soft side (valid-but-wrong-question)"
real_green=$(wp_green "$CAN/soft/sort2.c")
triv_green=$(wp_green "$CAN/soft/sort2_trivial.c")
echo "   real body, weak spec: WP-green=$real_green"
echo "   trivial witness (zero-fill), same spec: WP-green=$triv_green"
# soft canary fires iff the trivial witness ALSO proves green => the spec is too weak =>
# Gate C'/the disjoint completeness oracle MUST flag it; WP alone (green on both) cannot.
if [ "$real_green" = yes ] && [ "$triv_green" = yes ]; then soft_fired=yes; else soft_fired=no; fi
echo "   soft hole detected (trivial witness satisfies spec; catch belongs to Gate C', not WP): $soft_fired"
[ "$soft_fired" = yes ] || { echo "   !! FAIL: trivial witness did not expose the weak spec"; fail=1; }

echo
echo "## Canary table"
echo "| Canary | Seeded c-a-w | Expected catch site | Fired |"
echo "|---|---|---|---|"
echo "| faithfulness | fabricated proof (edited C, false ensures, WP-green=$fab_green) | faithfulness gate (strip==pristine) | $faith_fired |"
echo "| soft-side | valid-but-wrong-question spec (trivial witness WP-green=$triv_green) | Gate C′ / disjoint completeness oracle | $soft_fired |"
[ "$fail" -eq 0 ] && echo "CANARY OK — both gates fire" || echo "CANARY FAIL — wiring broken (see above)"
exit $fail
