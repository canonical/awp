#!/usr/bin/env bash
# Runs inside the workshop, as the workshop user, from a login shell (so
# /etc/profile.d/creusot.sh applies). Called by run.sh:
#
#   in-workshop.sh <cases dir> <work dir> <log dir>
#
# The work dir is under /tmp, never under /project: `cargo creusot new/init`
# writes why3find.json next to the nearest parent Cargo.toml (the workspace
# pitfall of workshop-autowp-rust-base-spec.md §5). Prints one PASS:/FAIL:
# line per check; run.sh counts them.
set -uo pipefail
CASES=$1 W=$2 LOGS=$3
rm -rf "$W"
mkdir -p "$W" "$LOGS"
touch "$W/.stamp"
# One target directory for every project: creusot-std is compiled once per
# mode (Creusot, plain rustc), not once per case.
export CARGO_TARGET_DIR="$W/target"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1: ${2:-}"; }
# The last lines of a log, on one line, for a FAIL message.
tailof() { grep -v -e '^ *Compiling' -e '^ *Checking' -e 'inexistent file in source location' "$1" | tail -"${2:-4}" | tr '\n' ' '; }

# A fresh copy of case $1 in $W/$2 (default: the case name), with why3find.json
# added by `cargo creusot init` as for any existing crate.
setup() {
    local c=$1 d="$W/${2:-$1}"
    rm -rf "$d"
    cp -r "$CASES/$c" "$d"
    rm -f "$d/expect"
    (cd "$d" && cargo creusot init >/dev/null 2>&1) && [ -f "$d/why3find.json" ]
}

# run_creusot <dir> <log> <command...>: runs the command in <dir>, output to
# <log>, exit status in $rc. why3find measures each prover's speed on a
# calibration goal the first time a goal needs more than the fast pass; under
# heavy host load that goal can overrun its 5 s budget and why3find aborts
# ("can not calibrate prover"), whatever the crate. That one signature is
# retried once, and reported as an INFO line; anything else is final.
run_creusot() {
    local d=$1 log=$2
    shift 2
    (cd "$d" && "$@") >"$log" 2>&1; rc=$?
    if grep -q 'can not calibrate prover' "$log"; then
        echo "INFO: $(basename "$log"): why3find calibration failed ($(grep -m1 'can not calibrate' "$log")); retrying once; first log in $(basename "$log").calib"
        mv "$log" "$log.calib"
        (cd "$d" && "$@") >"$log" 2>&1; rc=$?
    fi
}

crate_of() { sed -n 's/^name = "\(.*\)"$/\1/p' "$1/Cargo.toml" | head -1; }

# Restricts the project in $1 to one prover.
only_prover() {
    python3 -I - "$1/why3find.json" "$2" <<'EOF'
import json, sys
f, p = sys.argv[1], sys.argv[2]
d = json.load(open(f))
d["provers"] = [p]
d["profile"] = [x for x in d.get("profile", []) if x["prover"] == p + "@"]
json.dump(d, open(f, "w"), indent=2)
EOF
}

# The provers that proof.json files under $1 record, sorted and unique.
provers_used() {
    find "$1/verif" -name proof.json -exec cat {} + 2>/dev/null \
        | grep -o '"prover": *"[^"]*"' | sed 's/.*: *"//; s/"$//' | sort -u | tr '\n' ' '
}

# Runs a positive case: everything in `expect` must be proved.
positive() {
    local c=$1 d="$W/$1" log="$LOGS/$1.prove.log" crate n rc ok=1 why=""
    setup "$c" || { fail "$c.prove" "cargo creusot init failed"; return; }
    crate=$(crate_of "$d")
    run_creusot "$d" "$log" cargo creusot
    n=$(grep -c '^proved ' "$CASES/$c/expect")
    [ "$rc" -eq 0 ] || { ok=0; why="exit $rc"; }
    grep -q 'proof failed' "$log" && { ok=0; why="$why; 'proof failed' in the log"; }
    if [ "$n" -eq 1 ]; then
        grep -q '^Proved (verif/.*\.coma) ✔' "$log" || { ok=0; why="$why; no Proved line"; }
    else
        grep -q "^Proved ($n files) ✔" "$log" || { ok=0; why="$why; no 'Proved ($n files)' line"; }
    fi
    while read -r what f; do
        [ "$what" = proved ] || continue
        [ -f "$d/verif/${crate}_rlib/$f.coma" ] || { ok=0; why="$why; no $f.coma"; }
        [ -f "$d/verif/${crate}_rlib/$f/proof.json" ] || { ok=0; why="$why; no $f/proof.json"; }
    done <"$CASES/$c/expect"
    if [ "$ok" = 1 ]; then pass "$c.prove ($n functions)"; else fail "$c.prove" "$why | $(tailof "$log")"; fi
}

# Runs a negative case: `failed` functions must be reported as unproved
# goals, `proved` ones must still prove on their own; no other goal fails and
# the compile stage must succeed (a crash is not a pass).
negative() {
    local c=$1 d="$W/$1" log="$LOGS/$1.prove.log" crate rc ok=1 why="" g
    setup "$c" || { fail "$c.refute" "cargo creusot init failed"; return; }
    crate=$(crate_of "$d")
    run_creusot "$d" "$log" cargo creusot
    [ "$rc" -ne 0 ] || { ok=0; why="exit 0: the bug was proved"; }
    grep -qE "Compilation failed|^error(\[|:)" "$log" && { ok=0; why="$why; compile error"; }
    grep -q "'why3find prove' failed" "$log" || { ok=0; why="$why; why3find did not report a failed proof"; }
    local expected_failed=" "
    while read -r what f; do
        [ "$what" = failed ] || continue
        g=vc_$(basename "$f")
        expected_failed="$expected_failed$g "
        [ -f "$d/verif/${crate}_rlib/$f.coma" ] || { ok=0; why="$why; no $f.coma"; }
        grep -q "^Goal Coma\.$g: ✘" "$log" || { ok=0; why="$why; $f not reported unproved"; }
    done <"$CASES/$c/expect"
    # No unexpected failed goal.
    for g in $(sed -n 's/^Goal Coma\.\(vc_[A-Za-z0-9_]*\): ✘.*/\1/p' "$log" | sort -u); do
        case "$expected_failed" in *" $g "*) ;; *) ok=0; why="$why; unexpected failure $g" ;; esac
    done
    if [ "$ok" = 1 ]; then pass "$c.refute (expected failures reported)"; else fail "$c.refute" "$why | $(tailof "$log")"; fi
    # The correct functions of the same crate prove on their own.
    while read -r what f; do
        [ "$what" = proved ] || continue
        local plog="$LOGS/$c.$(basename "$f").log"
        run_creusot "$d" "$plog" cargo creusot "verif/${crate}_rlib/$f.coma"
        if [ "$rc" -eq 0 ] && grep -q "^Proved (verif/${crate}_rlib/$f.coma) ✔" "$plog"; then
            pass "$c.proves-$(basename "$f")"
        else
            fail "$c.proves-$(basename "$f")" "exit $rc | $(tailof "$plog")"
        fi
    done <"$CASES/$c/expect"
}

cargo_test() {
    local c=$1 log="$LOGS/$1.test.log" rc n
    (cd "$W/$c" && cargo test) >"$log" 2>&1; rc=$?
    n=$(sed -n 's/^test result: ok\. \([0-9]*\) passed.*/\1/p' "$log" | head -1)
    if [ "$rc" -eq 0 ] && [ "${n:-0}" -gt 0 ]; then pass "$c.cargo-test ($n tests)"
    else fail "$c.cargo-test" "exit $rc | $(tailof "$log")"; fi
}

START=$SECONDS
echo "INFO: $(cargo creusot version 2>&1 | head -1), $(rustc --version), $(. /etc/os-release && echo "$PRETTY_NAME")"

# 1. Offline first, while ~/.cargo holds only the SDK's registry seed: a
#    non-trivial crate (named smoke, to match the seed's Cargo.lock) proves
#    and tests with Cargo forbidden to use the network, and any HTTP attempt
#    sent to a dead proxy.
d="$W/smoke"
if (cd "$W" && cargo creusot new smoke >/dev/null 2>&1) \
        && cp /opt/creusot/share/smoke/Cargo.lock "$d/" \
        && cp "$CASES/binsearch_reverse/src/lib.rs" "$d/src/lib.rs"; then
    log="$LOGS/offline.prove.log"
    run_creusot "$d" "$log" env CARGO_NET_OFFLINE=true CARGO_HTTP_PROXY=http://127.0.0.1:9 \
        https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 cargo creusot
    if [ "$rc" -eq 0 ] && grep -q '^Proved (3 files) ✔' "$log"; then pass "offline.prove (binary_search, reverse, argmax)"
    else fail "offline.prove" "exit $rc | $(tailof "$log")"; fi
    log="$LOGS/offline.test.log"
    (cd "$d" && CARGO_NET_OFFLINE=true CARGO_HTTP_PROXY=http://127.0.0.1:9 cargo test) >"$log" 2>&1; rc=$?
    if [ "$rc" -eq 0 ] && grep -q '^test result: ok\. 3 passed' "$log"; then pass "offline.cargo-test"
    else fail "offline.cargo-test" "exit $rc | $(tailof "$log")"; fi
    cmp -s /opt/creusot/share/smoke/Cargo.lock "$d/Cargo.lock" \
        && pass "offline.lock-unchanged" || fail "offline.lock-unchanged" "Cargo.lock was rewritten"
else
    fail "offline.prove" "cargo creusot new smoke failed"
fi
echo "INFO: offline done at $((SECONDS - START))s"

# 2. Positive cases: proofs, then cargo test on the same code.
for c in loops binsearch_reverse sort lemma_ghost overflow tyinv_model; do
    positive "$c"
    cargo_test "$c"
    echo "INFO: $c done at $((SECONDS - START))s"
done

# 3. Replay: the proofs recorded in verif/**/proof.json replay unchanged.
log="$LOGS/loops.replay.log"
run_creusot "$W/loops" "$log" cargo creusot --replay
if [ "$rc" -eq 0 ] && grep -q '^Proved (4 files) ✔' "$log"; then pass "loops.replay"
else fail "loops.replay" "exit $rc | $(tailof "$log")"; fi

# 4. Negative cases: the bug must be reported, nothing else.
for c in neg_wrong_spec neg_off_by_one neg_missing_invariant neg_overflow neg_tyinv neg_variant; do
    negative "$c"
    echo "INFO: $c done at $((SECONDS - START))s"
done

# 5. Each prover alone (why3find.json "provers": [P]): it proves `loops` by
#    itself, its proof.json files name only it, and it does not prove the
#    wrong spec.
# CVC4 has no arm64 build: the SDK lists the provers it ships.
PROVERS="alt-ergo z3 cvc5"
grep -q "cvc4" /opt/creusot/share/provers && PROVERS="$PROVERS cvc4"
for p in $PROVERS; do
    d="$W/prover-$p"
    log="$LOGS/prover-$p.log"
    if setup loops "prover-$p" && only_prover "$d" "$p"; then
        run_creusot "$d" "$log" cargo creusot
        used=$(provers_used "$d")
        if [ "$rc" -eq 0 ] && grep -q '^Proved (4 files) ✔' "$log" && [ "$used" = "$p " ]; then
            pass "prover-$p.prove (loops, proofs by: $used)"
        else
            fail "prover-$p.prove" "exit $rc, proofs by: '$used' | $(tailof "$log")"
        fi
    else
        fail "prover-$p.prove" "setup failed"
    fi
    d="$W/prover-$p-neg"
    log="$LOGS/prover-$p-neg.log"
    if setup neg_wrong_spec "prover-$p-neg" && only_prover "$d" "$p"; then
        run_creusot "$d" "$log" cargo creusot
        if [ "$rc" -ne 0 ] && grep -q '^Goal Coma\.vc_max_wrong_spec: ✘' "$log" \
                && ! grep -q '^Goal Coma\.vc_max_ok: ✘' "$log"; then
            pass "prover-$p.refute (max_wrong_spec)"
        else
            fail "prover-$p.refute" "exit $rc | $(tailof "$log")"
        fi
    else
        fail "prover-$p.refute" "setup failed"
    fi
done

# 6. Nothing was written into the read-only SDK.
if [ -z "$(find /opt/creusot/ -newer "$W/.stamp" -print -quit 2>/dev/null)" ]; then
    pass "sdk-untouched"
else
    fail "sdk-untouched" "$(find /opt/creusot/ -newer "$W/.stamp" 2>/dev/null | head -3 | tr '\n' ' ')"
fi
echo "INFO: in-workshop run took $((SECONDS - START))s"
