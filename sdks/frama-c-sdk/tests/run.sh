#!/usr/bin/env bash
# Real Frama-C/WP tests of the frama-c-sdk SDK, in a throwaway workshop.
#
#   sdks/frama-c-sdk/tests/run.sh                  base ubuntu@24.04
#   BASE=ubuntu@26.04 sdks/frama-c-sdk/tests/run.sh
#   KEEP=1 ...                                       keep the workshop
#   SDK=frama-c-sdk ...                            SDK to test (default
#                                                    try-frama-c-sdk, the
#                                                    one `sdkcraft try` packed)
#   LOGDIR=dir ...                                   keep every check's
#                                                    frama-c output there
#   REUSE=<project dir> NAME=<workshop> ...          run the checks in an
#                                                    already launched workshop
#                                                    (no launch, no removal)
#
# Copies cases/ into a temporary project (mounted at /project), runs each
# check in the workshop, prints PASS:/FAIL: per check and a SUMMARY: line.
# Exit 0 only if every check passed. See README.md for what each case checks.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=${BASE:-ubuntu@24.04}
SDK=${SDK:-try-frama-c-sdk}
NAME=${NAME:-framac-tests}
REUSE=${REUSE:-}
TIMEOUT=10                       # -wp-timeout, as the frama-c skills use

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1: ${2:-}"; }

if [ -n "$REUSE" ]; then
    P=$REUSE
    rm -rf "$P/cases"
else
    P=$(mktemp -d "${TMPDIR:-/tmp}/frama-c-sdk-tests.XXXXXX")
    mkdir -p "$P/.workshop"
    printf 'name: %s\nbase: %s\nsdks:\n  - name: %s\n' "$NAME" "$BASE" "$SDK" \
        > "$P/.workshop/$NAME.yaml"
fi
cp -a "$HERE/cases" "$P/cases"
LOGDIR=${LOGDIR:-}
[ -n "$LOGDIR" ] && mkdir -p "$LOGDIR"

cleanup() {
    if [ -n "$REUSE" ]; then
        rm -rf "$P/cases"
    elif [ "${KEEP:-0}" = 1 ]; then
        echo "INFO: keeping the workshop; project $P (workshop -p $P remove $NAME)"
    else
        workshop -p "$P" remove "$NAME" >/dev/null 2>&1 || true
        rm -rf "$P"
    fi
}
trap cleanup EXIT

# Runs a command in the workshop, in a fresh copy of the cases (so WP's
# session and output files never leak from one check to the next). Ends the
# output with "EXIT=<status of the command>".
wx() { workshop -p "$P" exec "$NAME" -- bash -lc "$1" 2>&1; }
run() {   # run <check> <command>
    local out
    out=$(wx "W=\$(mktemp -d) && cp -a /project/cases/. \"\$W\" && cd \"\$W\" && { $2; } 2>&1; echo EXIT=\$?")
    [ -n "$LOGDIR" ] && printf '%s\n' "$out" > "$LOGDIR/$1.log"
    printf '%s\n' "$out"
}
last() { tail -"${2:-4}" <<<"$1" | tr '\n' ' '; }

# WP's flags, as the frama-c skills run it.
WP="frama-c -wp -wp-rte -wp-timeout $TIMEOUT -wp-cache none"

# No parse error, no crash: frama-c exited 0 and printed a WP summary.
clean_run() {
    grep -qx "EXIT=0" <<<"$1" && grep -qE "Proved goals: +[0-9]+ / [0-9]+" <<<"$1" \
        && ! grep -qE "User Error|Fatal error|Unexpected error|aborted|Plug-in .* aborted" <<<"$1"
}
# All goals proved, and there is at least one.
all_proved() {
    clean_run "$1" && grep -qE "Proved goals: +([1-9][0-9]*) / \1$" <<<"$1"
}
# Some goal is unproved, and a goal whose name matches $2 is among them.
unproved() {
    clean_run "$1" || return 1
    grep -qE "Proved goals: +([0-9]+) / ([0-9]+)$" <<<"$1" || return 1
    ! grep -qE "Proved goals: +([0-9]+) / \1$" <<<"$1" || return 1
    grep -qE "^\[wp\] \[(Timeout|Unknown|Failed|Stepout|Valid\?|Unsuccess)[^]]*\] .*$2" <<<"$1"
}
# Number of goals a prover proved, from WP's summary ("  Alt-Ergo 2.6.4: 12").
proved_by() { sed -nE "s/^ +$2 [^:]*: +([0-9]+).*/\1/p" <<<"$1" | head -1; }

t0=$(date +%s)
if [ -z "$REUSE" ]; then
    echo "--- launching $SDK on $BASE in $P"
    if workshop -p "$P" launch "$NAME"; then pass launch
    else fail launch "workshop launch failed"; workshop -p "$P" changes 2>&1 | tail -5; exit 1; fi
    echo "INFO: launch took $(( $(date +%s) - t0 ))s"
fi
info=$(workshop -p "$P" info "$NAME" 2>&1)
grep -qE "^status: +ready" <<<"$info" && pass health || fail health "$(last "$info" 6)"

# --- the installation ---------------------------------------------------
out=$(run version 'frama-c -version; why3 --version; alt-ergo --version; z3 --version')
grep -q "^32\.1" <<<"$out" && grep -q "Why3 platform, version 1\.8" <<<"$out" \
    && grep -qE "^v?2\.6\.4" <<<"$out" && grep -q "Z3 version" <<<"$out" \
    && pass versions || fail versions "$(last "$out" 6)"

out=$(run wp-detect 'frama-c -wp-detect')
grep -qiE "Alt-Ergo +2\.6\.4" <<<"$out" && grep -qiE "Z3 +[0-9]" <<<"$out" \
    && grep -qiE "Coq +8\.20\.1" <<<"$out" \
    && pass wp-detect || fail wp-detect "$(last "$out" 8)"

out=$(run why3-provers 'why3 config list-provers')
grep -qE "^Coq 8\.20\.1" <<<"$out" && grep -qE "^Alt-Ergo 2\.6\.4" <<<"$out" \
    && grep -qE "^Z3 " <<<"$out" && ! grep -q partial <<<"$out" \
    && pass why3-provers || fail why3-provers "$(last "$out" 6)"

# The switch's coqc is not on PATH (it would shadow rocq's Rocq).
out=$(run no-coqc 'command -v coqc || echo none')
grep -qx none <<<"$out" && pass no-coqc-on-path || fail no-coqc-on-path "$(last "$out")"

# The patched sources are installed, and WP's share has the patched cbits.
out=$(run sources 'ls "$FRAMA_C_SDK_SRC"/src/kernel_internals/typing/cabs2cil.ml && grep -c has_unsized_flexible_array_member "$FRAMA_C_SDK_SRC"/src/kernel_internals/typing/cabs2cil.ml && grep -c land_le_l "$(frama-c -print-share-path)/wp/why3/frama_c_wp/cbits.mlw"')
grep -qx "EXIT=0" <<<"$out" && pass patched-sources || fail patched-sources "$(last "$out")"

# Alt-Ergo's non-commercial licence ships with the SDK (spec open point 11).
out=$(run licence 'ls /opt/frama-c-sdk/share/licenses/alt-ergo/')
grep -qx "LICENSE.md" <<<"$out" && grep -qx "OCamlPro-Non-Commercial-License.txt" <<<"$out" \
    && pass alt-ergo-licence || fail alt-ergo-licence "$(last "$out")"

# --- the provers on their own ------------------------------------------
out=$(run why3-prove 'why3 prove -P alt-ergo why3/arith.mlw; why3 prove -P z3 why3/arith.mlw')
[ "$(grep -cE "Valid" <<<"$out")" -ge 2 ] && grep -qx "EXIT=0" <<<"$out" \
    && pass why3-prove || fail why3-prove "$(last "$out" 6)"

# --- positive cases: every goal proved ---------------------------------
for c in arrays pointers rte behaviors; do
    out=$(run "$c" "$WP -wp-prover alt-ergo,z3 $c.c")
    if all_proved "$out"; then pass "$c: $(grep -oE "Proved goals: +[0-9]+ / [0-9]+" <<<"$out")"
    else fail "$c" "$(grep -E "^\[wp\] \[|Proved goals|rror" <<<"$out" | head -8 | tr '\n' ' ')"; fi
done

# -wp-rte really generated runtime-error goals (overflow among them).
out=$(run rte-goals "frama-c -rte rte.c -then -print | grep -oE 'assert rte: [a-z_]+' | sort | uniq -c")
grep -q signed_overflow <<<"$out" && grep -q index_bound <<<"$out" \
    && grep -q division_by_zero <<<"$out" && grep -q shift <<<"$out" \
    && pass "rte-goals: $(grep -oE '[0-9]+ assert rte: [a-z_]+' <<<"$out" | sed 's/assert rte: //' | tr '\n' ' ')" \
    || fail rte-goals "$(last "$out" 8)"

# complete/disjoint behaviors produce goals of their own.
out=$(run behavior-goals "$WP -wp-prover alt-ergo,z3 -wp-report-json r.json behaviors.c && grep -oE '\"[a-z_]*(complete|disjoint)[a-z_]*\"' r.json | sort -u")
grep -q typed_sign_complete <<<"$out" && grep -q typed_sign_disjoint <<<"$out" \
    && grep -q typed_clamp_complete <<<"$out" && grep -q typed_clamp_disjoint <<<"$out" \
    && pass behavior-goals || fail behavior-goals "$(last "$out" 6)"

# Each prover on its own, and the prover WP reports is the one asked for.
# (Z3 5.1.0 alone times out on a binary_search invariant, so pointers.c.)
for pr in alt-ergo z3; do
    case $pr in alt-ergo) label=Alt-Ergo other=Z3 ;; z3) label=Z3 other=Alt-Ergo ;; esac
    out=$(run "prover-$pr" "$WP -wp-prover $pr pointers.c behaviors.c")
    n=$(proved_by "$out" "$label"); m=$(proved_by "$out" "$other")
    if all_proved "$out" && [ "${n:-0}" -gt 0 ] && [ -z "$m" ]; then
        pass "prover-$pr: $(grep -oE "Proved goals: +[0-9]+ / [0-9]+" <<<"$out"), $label: $n"
    else
        fail "prover-$pr" "$(grep -E "^\[wp\] \[|Proved goals|^ +[A-Z][a-zA-Z0-9-]+ *[0-9.]*:|rror" <<<"$out" | head -10 | tr '\n' ' ')"
    fi
done
# The same, with the exact Why3 prover names -wp-detect lists ([Alt-Ergo:2.6.4]).
out=$(run prover-why3 "$WP -wp-prover \$(frama-c -wp-detect | grep -oE '\[(Alt-Ergo|Z3):[0-9.]+\]' | tr -d '[]' | paste -sd,) pointers.c")
all_proved "$out" && pass "prover-why3: $(grep -oE "Proved goals: +[0-9]+ / [0-9]+" <<<"$out")" \
    || fail prover-why3 "$(grep -E "^\[wp\] \[|Proved goals|rror" <<<"$out" | head -8 | tr '\n' ' ')"

# The skills' x86_64 machdep.
out=$(run machdep "$WP -machdep gcc_x86_64 -wp-prover alt-ergo,z3 arrays.c pointers.c")
all_proved "$out" && pass "machdep-x86_64: $(grep -oE "Proved goals: +[0-9]+ / [0-9]+" <<<"$out")" \
    || fail machdep-x86_64 "$(grep -E "^\[wp\] \[|Proved goals|rror" <<<"$out" | head -8 | tr '\n' ' ')"

# --- negative cases: the named goal must stay unproved -----------------
neg() {   # neg <check> <file> <goal regex> [extra flags]
    local out
    out=$(run "neg-$1" "$WP -wp-prover alt-ergo,z3 ${4:-} neg/$2")
    if unproved "$out" "$3"; then
        pass "neg-$1: $(grep -oE "Proved goals: +[0-9]+ / [0-9]+" <<<"$out"), unproved: $(grep -E "^\[wp\] \[[A-Z]" <<<"$out" | grep -oE "typed_[a-zA-Z0-9_]+" | tr '\n' ' ')"
    else
        fail "neg-$1" "$(grep -E "^\[wp\] \[|Proved goals|rror|EXIT" <<<"$out" | head -8 | tr '\n' ' ')"
    fi
}
neg wrong-post        wrong_post.c           'typed_add_small_ensures_wrong_post'
neg off-by-one        off_by_one.c           'typed_zero_assert_rte_mem_access'
neg missing-loop-assigns missing_loop_assigns.c 'typed_zero_loop_assigns'
neg overflow          overflow.c             'typed_add_assert_rte_signed_overflow'
neg not-separated     not_separated.c        'typed_incr_first_ensures_q_unchanged'
neg not-complete      behaviors.c            'typed_sign_complete'
neg not-disjoint      behaviors.c            'typed_succ_disjoint'
# The right postcondition next to the wrong one is still proved (WP is not
# just failing everything in that file).
out=$(run neg-wrong-post-right "$WP -wp-prover alt-ergo,z3 -wp-prop right_post neg/wrong_post.c")
all_proved "$out" && pass neg-wrong-post-right-proved \
    || fail neg-wrong-post-right-proved "$(grep -E "^\[wp\] \[|Proved goals|rror" <<<"$out" | head -6 | tr '\n' ' ')"

# --- macsl (HAPPY meta-properties), as the frama-c-monitoring skill runs it
MACSL='frama-c -no-autoload-plugins -load-module "$FRAMA_C_SDK_MACSL" -load-plugin wp -macsl'
out=$(run macsl-contexts 'frama-c -load-module "$FRAMA_C_SDK_MACSL" -macsl-list-contexts')
grep -q writing <<<"$out" && grep -q total <<<"$out" && grep -qx "EXIT=0" <<<"$out" \
    && pass macsl-list-contexts || fail macsl-list-contexts "$(last "$out")"
# Instrumentation happened: one no_tamper assertion per write site.
out=$(run macsl-print "$MACSL macsl.c -then -print")
n=$(grep -cE "assert macsl: no_tamper: meta:" <<<"$out")
[ "$n" -ge 3 ] && grep -qx "EXIT=0" <<<"$out" && pass "macsl-instrumented: $n sites" \
    || fail macsl-instrumented "$n no_tamper sites; $(last "$out" 6)"
out=$(run macsl "$MACSL -wp -wp-rte -wp-prover alt-ergo,z3 -wp-timeout $TIMEOUT -wp-cache none macsl.c")
all_proved "$out" \
    && pass "macsl-prove: $(grep -oE "Proved goals: +[0-9]+ / [0-9]+" <<<"$out")" \
    || fail macsl-prove "$(grep -E "^\[wp\] \[|Proved goals|rror|macsl" <<<"$out" | head -8 | tr '\n' ' ')"
out=$(run neg-macsl "$MACSL -wp -wp-rte -wp-prover alt-ergo,z3 -wp-timeout $TIMEOUT -wp-cache none neg/macsl.c")
if unproved "$out" 'typed_tamper_assert' \
    && ! grep -qE "^\[wp\] \[[A-Z][a-z]+\] .*typed_set_pub" <<<"$out"; then
    pass "neg-macsl: $(grep -oE "Proved goals: +[0-9]+ / [0-9]+" <<<"$out")"
else
    fail neg-macsl "$(grep -E "^\[wp\] \[|Proved goals|rror|macsl" <<<"$out" | head -8 | tr '\n' ' ')"
fi

# --- Coq through WP: the lemma SMT cannot prove, with a saved script ---
COQ_SESS='mkdir -p sess/interactive && cp coq/*.v sess/interactive/'
out=$(run coq-smt-fails "$WP -wp-prover alt-ergo,z3 -wp-timeout 5 -wp-prop sum_nonneg coq/sum.c")
unproved "$out" 'lemma_sum_nonneg' && pass coq-smt-alone-fails \
    || fail coq-smt-alone-fails "$(grep -E "^\[wp\] \[|Proved goals|rror" <<<"$out" | head -6 | tr '\n' ' ')"
out=$(run coq-prove "$COQ_SESS && $WP -wp-prover coq -wp-session sess -wp-prop sum_nonneg coq/sum.c")
all_proved "$out" && [ "$(proved_by "$out" Coq)" = 1 ] && pass "coq-script: $(grep -oE "Proved goals: +[0-9]+ / [0-9]+" <<<"$out")" \
    || fail coq-script "$(grep -E "^\[wp\] \[|Proved goals|rror|script|Coq" <<<"$out" | head -8 | tr '\n' ' ')"
# The whole file: the lemma by Coq, the function by SMT (its loop uses it).
out=$(run coq-full "$COQ_SESS && $WP -wp-prover alt-ergo,z3,coq -wp-session sess coq/sum.c")
all_proved "$out" && [ "$(proved_by "$out" Coq)" = 1 ] && pass "coq-and-smt: $(grep -oE "Proved goals: +[0-9]+ / [0-9]+" <<<"$out")" \
    || fail coq-and-smt "$(grep -E "^\[wp\] \[|Proved goals|rror|script|Coq" <<<"$out" | head -8 | tr '\n' ' ')"
# A broken script must not prove it.
out=$(run neg-coq "mkdir -p sess/interactive && for f in coq/*.v; do sed 's/lia\\./idtac./' \"\$f\" > sess/interactive/\$(basename \"\$f\"); done && $WP -wp-prover coq -wp-session sess -wp-prop sum_nonneg coq/sum.c")
unproved "$out" 'lemma_sum_nonneg' && pass neg-coq-bad-script \
    || fail neg-coq-bad-script "$(grep -E "^\[wp\] \[|Proved goals|rror|Coq" <<<"$out" | head -6 | tr '\n' ' ')"

# --- the patched frontend (frama-c-patches) ----------------------------
out=$(run patch-0002 'frama-c -machdep gcc_x86_64 patches/zero_length_nonfinal.c -print')
grep -qx "EXIT=0" <<<"$out" && grep -q "struct outer" <<<"$out" \
    && pass patch-gnu-zero-length-nonfinal || fail patch-gnu-zero-length-nonfinal "$(last "$out")"
out=$(run patch-void-return 'frama-c patches/return_void.c -print')
grep -qx "EXIT=0" <<<"$out" && pass patch-return-void-expr || fail patch-return-void-expr "$(last "$out")"

echo "INFO: total $(( $(date +%s) - t0 ))s"
echo "SUMMARY: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
