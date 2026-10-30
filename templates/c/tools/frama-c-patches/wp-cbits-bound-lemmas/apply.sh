#!/usr/bin/env bash
# Apply (or --check) the cbits.mlw BOUND axioms against the installed WP share.
# NOTE: this applies only the runtime .mlw axioms; the Cbits.v realization (Cbits.v.realization) must be
# merged and the coqwp Coq lib rebuilt separately (see README "Soundness status").
#
# SHIFT axiom (lsl_mul_pow2): NO LONGER inserted globally. Adding it to the shared cbits theory regressed
# the shift-free ecdsa loop_invariant_xform_preserved goal (Alt-Ergo search-space enlargement). It now
# ships in the OPT-IN theory ../lsl-mul-pow2-regression/mitigation-1-optin/ (mitigation M1, adopted
# 2026-07-14), pulled in per-unit via -wp-driver/-wp-library only for shift-heavy units. This script
# therefore keeps the global theory LEAN and, if it finds a stale global lsl_mul_pow2, STRIPS it.
set -eu
cd "$(dirname "$0")"
eval "$(opam env --switch=framac-coq8)" 2>/dev/null
MLW="$(frama-c -print-share-path)/wp/why3/frama_c_wp/cbits.mlw"

# Ensure the global cbits theory is LEAN (no shift axiom): strip lsl_mul_pow2 + its comment block + the
# now-orphaned `use int.Power` if a previous run inserted them. Idempotent.
strip_shift() {
  python3 - "$1" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); orig=s
s=s.replace("  use int.Int\n  use int.Power\n","  use int.Int\n",1)
block=('  (** ** SHIFT class (wp-cbits-bound-lemmas addendum): lsl as multiplication -> closes\n'
       '      byte<<k overflow (crc16/xmodem/packet assembly). Sound — realized in coqwp/Cbits.v from\n'
       '      Zbits.lsl_pos + Zbits.lsl_arithmetic_shift: 0<=n -> lsl x n = x * two_power_nat n. *)\n'
       '  axiom lsl_mul_pow2: forall x n:int [lsl x n]. 0 <= n -> lsl x n = x * (power 2 n)\n')
if block in s: s=s.replace(block,"",1)
else: s="".join(l for l in s.splitlines(keepends=True) if 'lsl_mul_pow2' not in l)
open(p,"w").write(s)
print("  shift-mul: stripped from global (opt-in via M1 driver)" if s!=orig else "  shift-mul: already lean (global)")
PY
}

case "${1:-apply}" in
  --check)
    patch --dry-run "$MLW" < cbits.mlw.patch
    grep -q 'lsl_mul_pow2' "$MLW" && echo "shift-mul: PRESENT globally — WOULD strip (M1: opt-in only)" || echo "shift-mul: already lean (global); opt-in via ../lsl-mul-pow2-regression/mitigation-1-optin/"
    ;;
  apply)
    if grep -q 'land_le_l' "$MLW"; then echo "bound axioms: already applied";
    else patch "$MLW" < cbits.mlw.patch && echo "bound axioms: applied to $MLW"; fi
    strip_shift "$MLW"
    echo "Done. SHIFT axiom is OPT-IN (M1): pass \$OT_SHIFT_OPTIN (driver+library) to shift-heavy units."
    echo "     (Cbits.v realization for the bound axioms still to merge + recompile — see README.)"
    ;;
  *) echo "usage: $0 [apply|--check]"; exit 2 ;;
esac
