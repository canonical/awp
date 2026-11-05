#!/usr/bin/env bash
# Tests the rocq SDK for real proof work: launches a throwaway
# workshop with try-rocq, copies check.sh and cases/ into its
# project (mounted at /project), runs check.sh there as the workshop user
# and removes the workshop.
#
#   sdks/rocq/tests/run.sh
#   BASE=ubuntu@26.04 sdks/rocq/tests/run.sh    (default ubuntu@24.04)
#   KEEP=1 sdks/rocq/tests/run.sh               keeps the workshop
#   LOGDIR=/some/dir sdks/rocq/tests/run.sh     keeps the step logs
#
# The SDK must have been packed with `sdkcraft try` in sdks/rocq/
# first (`make sdk-rocq`); this script never builds it. Prints PASS:/FAIL:
# per check and a SUMMARY: line; exit 0 only if every check passed.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=${BASE:-ubuntu@24.04}
NAME=rocq-tests
SDK=rocq

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1: ${2:-}"; }
t0=$(date +%s)
elapsed() { echo "$(( $(date +%s) - t0 ))s"; }

P=$(mktemp -d "${TMPDIR:-/tmp}/rocq-tests.XXXXXX")
mkdir -p "$P/.workshop" "$P/rocq-tests"
cat > "$P/.workshop/$NAME.yaml" <<EOF
name: $NAME
base: $BASE
sdks:
  - name: try-$SDK
EOF
cp -r "$HERE/check.sh" "$HERE/cases" "$P/rocq-tests/"
cleanup() {
    if [ -n "${LOGDIR:-}" ] && [ -d "$P/work/logs" ]; then
        mkdir -p "$LOGDIR" && cp -r "$P/work/logs/." "$LOGDIR/" && echo "INFO: step logs copied to $LOGDIR"
    fi
    if [ "${KEEP:-0}" = 1 ]; then
        echo "INFO: keeping the workshop; project $P (workshop -p $P remove $NAME)"
    else
        workshop -p "$P" remove "$NAME" >/dev/null 2>&1 || true
        rm -rf "$P"
    fi
}
trap cleanup EXIT

echo "--- launching try-$SDK on $BASE in $P"
if workshop -p "$P" launch "$NAME"; then pass "launch ($(elapsed))"
else fail launch "workshop launch failed"; workshop -p "$P" changes 2>&1 | tail -5
     echo "SUMMARY: $PASS passed, $FAIL failed"; exit 1; fi

info=$(workshop -p "$P" info "$NAME" 2>&1)
echo "$info" | sed 's/^/    | /'
# Installed from the try area, and ready: check-health said okay.
if grep -qE "^ +$SDK:" <<<"$info" && grep -q "tracking: *.*/try/$SDK" <<<"$info" \
    && grep -qE "^status: +ready" <<<"$info"; then
    pass "health"
else
    fail "health" "workshop not ready, or $SDK not installed from the try area"
fi

# check.sh prints its own PASS:/FAIL: lines; count them into ours.
t1=$(date +%s)
out=$(workshop -p "$P" exec "$NAME" -- bash -lc 'bash /project/rocq-tests/check.sh /project/work' 2>&1)
rc=$?
sed 's/^SUMMARY: /INFO: check.sh: /' <<<"$out"
inner_pass=$(grep -c '^PASS: ' <<<"$out")
inner_fail=$(grep -c '^FAIL: ' <<<"$out")
PASS=$((PASS + inner_pass)); FAIL=$((FAIL + inner_fail))
if ! grep -q '^SUMMARY: ' <<<"$out"; then
    fail "check.sh" "did not finish (rc=$rc)"
elif [ "$rc" -ne 0 ] && [ "$inner_fail" -eq 0 ]; then
    fail "check.sh" "exit $rc without a FAIL line"
fi
echo "INFO: checks took $(( $(date +%s) - t1 ))s, total $(elapsed); logs in $P/work/logs (KEEP=1 to keep)"

echo "SUMMARY: $PASS passed, $FAIL failed ($BASE)"
[ "$FAIL" -eq 0 ]
