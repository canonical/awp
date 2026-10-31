#!/usr/bin/env bash
# Launches a throwaway workshop with the tried SDK(s) and checks them.
#
#   sdks/test-sdk.sh autowp-lean [autowp-rocq ...]     KEEP=1 keeps the workshop
#
# Each SDK must have been packed with `sdkcraft try` in sdks/<name>/ first
# (`make sdk-<short name>` does both). The workshop uses the SDKs as
# try-<name>, in a temporary project. Prints PASS/FAIL per check; exit 0 only
# if every check passed.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -ge 1 ] || { echo "usage: $0 <sdk> [<sdk>...]" >&2; exit 2; }

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1: ${2:-}"; }

P=$(mktemp -d "${TMPDIR:-/tmp}/autowp-sdk-test.XXXXXX")
mkdir -p "$P/.workshop"
{
    echo "name: sdktest"
    echo "base: ubuntu@24.04"
    echo "sdks:"
    for s in "$@"; do echo "  - name: try-$s"; done
} > "$P/.workshop/sdktest.yaml"
cleanup() {
    if [ "${KEEP:-0}" = 1 ]; then
        echo "INFO: keeping the workshop; project $P (workshop -p $P remove sdktest)"
    else
        workshop -p "$P" remove sdktest >/dev/null 2>&1 || true
        rm -rf "$P"
    fi
}
trap cleanup EXIT

wx() { workshop -p "$P" exec sdktest -- bash -lc "$1"; }

echo "--- launching try-$* in $P"
if workshop -p "$P" launch sdktest; then pass launch
else fail launch "workshop launch failed"; workshop -p "$P" changes 2>&1 | tail -5; exit 1; fi

info=$(workshop -p "$P" info sdktest 2>&1)
echo "$info" | sed 's/^/    | /'

for s in "$@"; do
    # A tried SDK is listed under its own name, from the try area. The
    # workshop only reaches "ready" once every SDK's check-health said okay.
    if grep -qE "^ +$s:" <<<"$info" && grep -q "tracking: *.*/try/$s" <<<"$info" \
        && grep -qE "^status: +ready" <<<"$info"; then
        pass "$s.health"
    else
        fail "$s.health" "workshop not ready, or $s not installed from the try area"
    fi
    case "$s" in
        autowp-lean)
            out=$(wx 'lean --version && lake --version && rg --version | head -1 && lean-lsp-mcp --help >/dev/null && echo MCP-OK' 2>&1)
            grep -q "Lean (version 4" <<<"$out" && grep -q MCP-OK <<<"$out" \
                && pass "$s.tools" || fail "$s.tools" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            out=$(wx 'd=$(mktemp -d) && cd "$d" && lake new hello >/dev/null && cd hello && lake build 2>&1 | tail -2 && ./.lake/build/bin/hello' 2>&1)
            grep -q "Hello, world" <<<"$out" && pass "$s.lake-build" || fail "$s.lake-build" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            ;;
        autowp-rocq)
            out=$(wx 'coqc --version && d=$(mktemp -d) && cd "$d" && printf "From Stdlib Require Import Arith.\nLemma t (n : nat) : n * 1 = n.\nProof. now rewrite Nat.mul_1_r. Qed.\nPrint Assumptions t.\n" > T.v && coqc T.v' 2>&1)
            grep -q "version 9.2" <<<"$out" && grep -q "Closed under the global context" <<<"$out" \
                && pass "$s.prove" || fail "$s.prove" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            ;;
        autowp-framac)
            out=$(wx 'frama-c -version && frama-c -wp-detect 2>&1 | grep -iE "alt-ergo|z3|coq"' 2>&1)
            grep -q "^32\.1" <<<"$out" && grep -qi coq <<<"$out" \
                && pass "$s.detect" || fail "$s.detect" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            out=$(wx 'd=$(mktemp -d) && cd "$d" && printf "/*@ requires n >= 0 && n < 1000;\n    ensures \\\\result == n + 1; */\nint inc(int n) { return n + 1; }\n" > inc.c && frama-c -wp -wp-rte inc.c 2>&1 | grep -E "Proved goals"' 2>&1)
            if grep -qE "Proved goals: +([0-9]+) / \1\b" <<<"$out"; then pass "$s.wp"
            else fail "$s.wp" "$out"; fi
            out=$(wx 'frama-c -load-module "$AUTOWP_FRAMAC_MACSL" -version' 2>&1)
            grep -q "^32\.1" <<<"$out" && pass "$s.macsl" || fail "$s.macsl" "$(tail -2 <<<"$out" | tr '\n' ' ')"
            # The Coq on Frama-C's side must not be on PATH (it is 8.20.1).
            out=$(wx 'command -v coqc || echo none' 2>&1)
            case " $* " in
                *" autowp-rocq "*) ;;
                *) [ "$out" = none ] && pass "$s.no-coqc-on-path" || fail "$s.no-coqc-on-path" "$out" ;;
            esac
            ;;
    esac
done

echo "SUMMARY: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
