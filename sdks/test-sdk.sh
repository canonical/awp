#!/usr/bin/env bash
# Launches a throwaway workshop with the tried SDK(s) and checks them.
#
#   sdks/test-sdk.sh lean [rocq ...]     KEEP=1 keeps the workshop
#   (SDKs: lean, rocq, frama-c-sdk, creusot)
#   BASE=ubuntu@26.04 sdks/test-sdk.sh ...             base of the workshop
#                                                      (default ubuntu@24.04)
#
# Each SDK must have been packed with `sdkcraft try` in sdks/<name>/ first
# (`make sdk-<short name>` does both). The workshop uses the SDKs as
# try-<name>, in a temporary project. Prints PASS/FAIL per check; exit 0 only
# if every check passed.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -ge 1 ] || { echo "usage: $0 <sdk> [<sdk>...]" >&2; exit 2; }
BASE=${BASE:-ubuntu@24.04}

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1: ${2:-}"; }

P=$(mktemp -d "${TMPDIR:-/tmp}/autowp-sdk-test.XXXXXX")
mkdir -p "$P/.workshop"
{
    echo "name: sdktest"
    echo "base: $BASE"
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

echo "--- launching try-$* on $BASE in $P"
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
        lean)
            out=$(wx 'lean --version && lake --version && rg --version | head -1 && lean-lsp-mcp --help >/dev/null && echo MCP-OK' 2>&1)
            grep -q "Lean (version 4" <<<"$out" && grep -q MCP-OK <<<"$out" \
                && pass "$s.tools" || fail "$s.tools" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            out=$(wx 'd=$(mktemp -d) && cd "$d" && lake new hello >/dev/null && cd hello && lake build 2>&1 | tail -2 && ./.lake/build/bin/hello' 2>&1)
            grep -q "Hello, world" <<<"$out" && pass "$s.lake-build" || fail "$s.lake-build" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            ;;
        rocq)
            out=$(wx 'coqc --version && d=$(mktemp -d) && cd "$d" && printf "From Stdlib Require Import Arith.\nLemma t (n : nat) : n * 1 = n.\nProof. now rewrite Nat.mul_1_r. Qed.\nPrint Assumptions t.\n" > T.v && coqc T.v' 2>&1)
            grep -q "version 9.2" <<<"$out" && grep -q "Closed under the global context" <<<"$out" \
                && pass "$s.prove" || fail "$s.prove" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            ;;
        frama-c-sdk)
            out=$(wx 'frama-c -version && frama-c -wp-detect 2>&1 | grep -iE "alt-ergo|z3|coq"' 2>&1)
            grep -q "^32\.1" <<<"$out" && grep -qi coq <<<"$out" \
                && pass "$s.detect" || fail "$s.detect" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            out=$(wx 'd=$(mktemp -d) && cd "$d" && printf "/*@ requires n >= 0 && n < 1000;\n    ensures \\\\result == n + 1; */\nint inc(int n) { return n + 1; }\n" > inc.c && frama-c -wp -wp-rte inc.c 2>&1 | grep -E "Proved goals"' 2>&1)
            if grep -qE "Proved goals: +([0-9]+) / \1\b" <<<"$out"; then pass "$s.wp"
            else fail "$s.wp" "$out"; fi
            out=$(wx 'frama-c -load-module "$FRAMA_C_SDK_MACSL" -version' 2>&1)
            grep -q "^32\.1" <<<"$out" && pass "$s.macsl" || fail "$s.macsl" "$(tail -2 <<<"$out" | tr '\n' ' ')"
            # The Coq on Frama-C's side must not be on PATH (it is 8.20.1).
            out=$(wx 'command -v coqc || echo none' 2>&1)
            case " $* " in
                *" rocq "*) ;;
                *) [ "$out" = none ] && pass "$s.no-coqc-on-path" || fail "$s.no-coqc-on-path" "$out" ;;
            esac
            ;;
        creusot)
            # workshop-autowp-rust-base-spec.md §6. Projects go under /tmp,
            # never under /project (cargo creusot new's workspace pitfall).
            out=$(wx 'cargo creusot version 2>&1 | head -8; rustc +nightly-2026-08-03 --version; /opt/creusot/data/bin/why3 --version' 2>&1)
            grep -q "^cargo-creusot 0.15.0-dev" <<<"$out" && grep -q "^alt-ergo 2.6.4" <<<"$out" \
                && grep -q "cvc5 1.4.1" <<<"$out" && grep -q "^rustc 1.99.0-nightly" <<<"$out" \
                && grep -q "version 1.8.2" <<<"$out" \
                && pass "$s.tools" || fail "$s.tools" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            # The generated add_one, then the mutant, then cargo test.
            out=$(wx 'd=$(mktemp -d) && cd "$d" && cargo creusot new smoke >/dev/null && cd smoke && cargo creusot 2>&1 | tail -2' 2>&1)
            grep -q "^Proved .*add_one" <<<"$out" && pass "$s.prove" || fail "$s.prove" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            # Offline: the SDK's registry seed and Cargo.lock suffice.
            out=$(wx 'd=$(mktemp -d) && cd "$d" && cargo creusot new smoke >/dev/null && cp /opt/creusot/share/smoke/Cargo.lock smoke/ && cd smoke && CARGO_NET_OFFLINE=true cargo creusot 2>&1 | tail -2' 2>&1)
            grep -q "^Proved .*add_one" <<<"$out" && pass "$s.offline" || fail "$s.offline" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            out=$(wx 'd=$(mktemp -d) && cd "$d" && cargo creusot new smoke >/dev/null && cd smoke && printf "use creusot_std::prelude::*;\n\n#[requires(x@ < u32::MAX@)]\n#[ensures(result@ == x@ + 1)]\npub fn f(x: u32) -> u32 {\n    x + 2\n}\n" > src/lib.rs && if cargo creusot >log 2>&1; then echo MUTANT-PROVED; else grep -c "proof failed" log; fi' 2>&1)
            grep -qx "[1-9][0-9]*" <<<"$(tail -1 <<<"$out")" && pass "$s.mutant" || fail "$s.mutant" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            out=$(wx 'd=$(mktemp -d) && cd "$d" && cargo creusot new smoke >/dev/null && cd smoke && cargo test 2>&1 | tail -3' 2>&1)
            grep -q "test result: ok" <<<"$out" && pass "$s.cargo-test" || fail "$s.cargo-test" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            out=$(wx 'ls /opt/creusot/share/licenses/alt-ergo/' 2>&1)
            grep -q "^LICENSE.md$" <<<"$out" && grep -q "^OCamlPro-Non-Commercial-License.txt$" <<<"$out" \
                && pass "$s.licence" || fail "$s.licence" "$out"
            out=$(wx 'rustup target add x86_64-unknown-uefi >/dev/null 2>&1 && rustup target list --installed' 2>&1)
            grep -q "^x86_64-unknown-uefi$" <<<"$out" && pass "$s.target" || fail "$s.target" "$(tail -3 <<<"$out" | tr '\n' ' ')"
            # A refresh of an unchanged definition is a no-op ("no updates
            # available"), so add a second tried SDK to force a real one: the
            # container is rebuilt and every hook reruns; the mounts must hold.
            extra=
            for e in rocq lean frama-c-sdk; do
                case " $* " in *" $e "*) ;; *) extra=$e; break ;; esac
            done
            [ -n "$extra" ] && echo "  - name: try-$extra" >> "$P/.workshop/sdktest.yaml"
            wx 'sudo touch /etc/autowp-persist-marker' >/dev/null 2>&1
            if [ -n "$extra" ] && workshop -p "$P" refresh sdktest >/dev/null 2>&1 \
                && [ "$(wx 'test -e /etc/autowp-persist-marker && echo kept || echo rebuilt' 2>&1)" = rebuilt ]; then
                out=$(wx 'rustup target list --installed; rustup default; grep -c "creusot-std" ~/.cargo/config.toml' 2>&1)
                grep -q "^x86_64-unknown-uefi$" <<<"$out" && grep -q "^nightly-2026-08-03" <<<"$out" \
                    && grep -qx "[1-9]" <<<"$(tail -1 <<<"$out")" \
                    && pass "$s.persist" || fail "$s.persist" "$(tr '\n' ' ' <<<"$out")"
            else
                fail "$s.persist" "no SDK to add, refresh failed, or the container was not rebuilt"
            fi
            ;;
    esac
done

echo "SUMMARY: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
