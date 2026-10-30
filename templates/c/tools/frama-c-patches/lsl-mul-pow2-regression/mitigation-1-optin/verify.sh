#!/usr/bin/env bash
# Reproduce the mitigation-1 opt-in measurements (A) and (B).
#
#   (A) shift-FREE unit recovers when lsl_mul_pow2 is NOT globally present:
#       opentitan ecdsa sigverify_encoded_message_check loop_invariant_xform_preserved.
#   (B) shift-HEAVY units that OPT IN still close their shift goals:
#       crc16 21/21 and xmodem_recv_frame 54/55 (both -wp-model bytes).
#
# NEVER modifies the installed opam switch: it copies $(frama-c -print-share-path)/wp into a
# scratch dir, strips lsl_mul_pow2 from the COPY (= the "lean default" of mitigation-1), and drives
# WP with -wp-share <copy>.  The opt-in half (driver + why3 library) needs NO share edit at all.
set -eu
cd "$(dirname "$0")"
MIT="$(pwd)"
eval "$(opam env --switch=framac-coq8 --set-switch)" 2>/dev/null || true

OT="${OT:-/home/fabrice/git/use-frama-c/opentitan}"
AN="${AN:-/home/fabrice/git/use-frama-c/opentitan-analysis-acsl}"
CPP="-iquote $OT -I$OT -I$AN/gen-include -I$AN/include -include opentitan_tcb.h -DOPENTITAN_IS_EARLGREY -DMANIFEST_UNIT_TEST_ -ffreestanding"
COMMON=(-machdep gcc_x86_32 -cpp-extra-args="$CPP" -wp -wp-rte -wp-prover alt-ergo,z3 -wp-timeout 20 -wp-cache none)

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
SRC="$(frama-c -print-share-path)/wp"
cp -r "$SRC" "$WORK/wp-clean"
# strip the global shift axiom from the COPY (this is what a mitigation-1 deployment ships as default)
python3 - "$WORK/wp-clean/why3/frama_c_wp/cbits.mlw" <<'PY'
import sys
p=sys.argv[1]; L=open(p).read().splitlines(keepends=True)
open(p,'w').write(''.join(l for l in L if 'lsl_mul_pow2' not in l))
PY
CLEAN=(-wp-share "$WORK/wp-clean")
OPTIN=(-wp-share "$WORK/wp-clean" -wp-driver="$MIT/shift_lemmas.driver" -wp-library="$MIT/wp-library")

echo "==================================================================="
echo "(A) ecdsa sigverify_encoded_message_check — FULL function context"
echo "    (the borderline xform goal only tips over in full context)"
echo "-------------------------------------------------------------------"
echo -n "    CLEAN default (no shift axiom): "
frama-c "${COMMON[@]}" "${CLEAN[@]}" "$AN/units/ecdsa_verify_sa2auth.c" \
  -wp-fct sigverify_encoded_message_check 2>&1 \
  | grep -oiE "Proved goals: +[0-9]+ / [0-9]+"; \
frama-c "${COMMON[@]}" "${CLEAN[@]}" "$AN/units/ecdsa_verify_sa2auth.c" \
  -wp-fct sigverify_encoded_message_check 2>&1 \
  | grep -qi "xform_preserved.*Timeout\|Timeout.*xform_preserved" \
  && echo "    -> xform: TIMEOUT (regressed)" || echo "    -> xform: proved (recovered)"

echo
echo "==================================================================="
echo "(B) shift-heavy units OPT IN (clean default + shift driver+library)"
echo "-------------------------------------------------------------------"
for fct in crc16 xmodem_recv_frame; do
  echo "  --- $fct (bytes model) ---"
  echo -n "    CLEAN, no opt-in : "
  frama-c "${COMMON[@]}" "${CLEAN[@]}" -wp-model bytes "$AN/units/xmodem.c" -wp-fct "$fct" 2>&1 \
    | grep -oiE "Proved goals: +[0-9]+ / [0-9]+"
  echo -n "    CLEAN + OPT-IN   : "
  frama-c "${COMMON[@]}" "${OPTIN[@]}" -wp-model bytes "$AN/units/xmodem.c" -wp-fct "$fct" 2>&1 \
    | grep -oiE "Proved goals: +[0-9]+ / [0-9]+"
done
