#!/usr/bin/env bash
# Real-use tests of the creusot SDK: launches a throwaway workshop with
# try-creusot, copies the test crates of cases/ in, and proves,
# refutes and tests them (see README.md).
#
#   sdks/creusot/tests/run.sh
#   BASE=ubuntu@26.04 sdks/creusot/tests/run.sh   (default ubuntu@24.04)
#   KEEP=1 ...      keep the workshop (and its project directory)
#   LOGDIR=dir ...  where the per-case logs are copied (default: a new
#                   directory under ${TMPDIR:-/tmp}, printed at the end)
#
# The SDK must already be packed in the try area for that base
# (`make sdk-creusot`); this script does not build it. Prints PASS:/FAIL:
# per check and a SUMMARY: line; exits 0 only if every check passed.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=${BASE:-ubuntu@24.04}
NAME=creusot-tests
SDK=creusot
LOGDIR=${LOGDIR:-$(mktemp -d "${TMPDIR:-/tmp}/creusot-tests-logs.XXXXXX")}
mkdir -p "$LOGDIR"

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1: ${2:-}"; }

P=$(mktemp -d "${TMPDIR:-/tmp}/creusot-tests.XXXXXX")
mkdir -p "$P/.workshop"
printf 'name: %s\nbase: %s\nsdks:\n  - name: try-%s\n' "$NAME" "$BASE" "$SDK" \
    > "$P/.workshop/$NAME.yaml"
# The test material, visible in the workshop under /project.
cp -r "$HERE/cases" "$P/cases"
cp "$HERE/in-workshop.sh" "$P/in-workshop.sh"
chmod -R a+rX "$P"

cleanup() {
    if [ "${KEEP:-0}" = 1 ]; then
        echo "INFO: keeping the workshop; project $P (workshop -p $P remove $NAME)"
    else
        workshop -p "$P" remove "$NAME" >/dev/null 2>&1 || true
        rm -rf "$P"
    fi
}
trap cleanup EXIT

START=$SECONDS
echo "--- launching try-$SDK on $BASE in $P"
if workshop -p "$P" launch "$NAME"; then pass launch
else
    fail launch "workshop launch failed"
    workshop -p "$P" changes 2>&1 | tail -5
    echo "SUMMARY: $PASS passed, $FAIL failed (base $BASE)"
    exit 1
fi
echo "INFO: launched in $((SECONDS - START))s"

info=$(workshop -p "$P" info "$NAME" 2>&1)
if grep -qE "^ +$SDK:" <<<"$info" && grep -q "tracking: *.*/try/$SDK" <<<"$info" \
        && grep -qE "^status: +ready" <<<"$info"; then
    pass health
else
    fail health "workshop not ready, or $SDK not installed from the try area"
    echo "$info" | sed 's/^/    | /'
fi

# The cases are copied out of /project into /tmp (in-workshop.sh's header
# says why); logs go to /tmp too and are streamed back with tar.
workshop -p "$P" exec "$NAME" -- bash -lc \
    'rm -rf /tmp/ct-cases && cp -r /project/cases /tmp/ct-cases && bash /project/in-workshop.sh /tmp/ct-cases /tmp/creusot-tests /tmp/creusot-tests-logs' 2>&1 \
    | tee "$LOGDIR/in-workshop.out"
out=$(cat "$LOGDIR/in-workshop.out")
while IFS= read -r line; do
    case "$line" in
        PASS:*) PASS=$((PASS + 1)) ;;
        FAIL:*) FAIL=$((FAIL + 1)) ;;
    esac
done <<<"$out"
grep -q "^INFO: in-workshop run took" <<<"$out" \
    || fail in-workshop "the in-workshop script did not finish: $(tail -3 <<<"$out" | tr '\n' ' ')"

workshop -p "$P" exec "$NAME" -- bash -lc 'tar -C /tmp/creusot-tests-logs -cf - .' 2>/dev/null \
    | tar -C "$LOGDIR" -xf - 2>/dev/null || echo "INFO: could not copy the per-case logs"

echo "INFO: logs in $LOGDIR"
echo "INFO: total $((SECONDS - START))s on $BASE"
echo "SUMMARY: $PASS passed, $FAIL failed (base $BASE)"
[ "$FAIL" -eq 0 ]
