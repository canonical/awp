#!/usr/bin/env bash
# framac-smoke.sh — feasibility smoke proof for frama-c-launch onboarding.
#
# Run ONE (leaf) unit through Frama-C/WP and assert EVERY goal is Valid — proving the
# Frama-C -> WP -> (SMT|Coq) pipeline composes on THIS target before the campaign starts.
# This is the launch loop's L "smoke oracle": parse-green is NOT proof-green (no-blend), so
# the onboarding handoff requires an actual all-Valid unit, not merely a file that parses.
#
# Usage:
#   framac-smoke.sh [opts] FILE [FILE...]
# Options (all optional; defaults shown):
#   --fct LIST        scope goals to functions LIST            (-wp-fct LIST)
#   --model M         memory model, e.g. +cast                 (-wp-model M)
#   --machdep MD      machine model            (default gcc_x86_64)
#   --prover P        prover set               (default alt-ergo,z3; add ,coq for Coq escalation)
#   --timeout N       per-goal timeout seconds (default 20)
#   --cpp "FLAGS"     -I/-D/force-includes, appended to -cpp-extra-args
#   --switch NAME     eval `opam env --switch=NAME --set-switch` first (e.g. framac-coq8 for Coq)
#   --no-rte          omit -wp-rte (default: -wp-rte on)
#   --cache MODE      -wp-cache MODE (use `none` when replaying a Coq script — the SMT cache masks it)
# Prints "SMOKE-PASS N/N" (exit 0) | "SMOKE-FAIL N/M" | "SMOKE-ERROR ..." (exit 1).
set -uo pipefail

FCT=""; MODEL=""; MACHDEP="gcc_x86_64"; PROVER="alt-ergo,z3"; TIMEOUT="20"
CPP=""; SWITCH=""; RTE="-wp-rte"; CACHE=""; FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --fct)     FCT="$2"; shift 2;;
    --model)   MODEL="$2"; shift 2;;
    --machdep) MACHDEP="$2"; shift 2;;
    --prover)  PROVER="$2"; shift 2;;
    --timeout) TIMEOUT="$2"; shift 2;;
    --cpp)     CPP="$2"; shift 2;;
    --switch)  SWITCH="$2"; shift 2;;
    --no-rte)  RTE=""; shift;;
    --cache)   CACHE="$2"; shift 2;;
    -h|--help) sed -n '2,21p' "$0"; exit 0;;
    --)        shift; while [ $# -gt 0 ]; do FILES+=("$1"); shift; done;;
    -*)        echo "SMOKE-ERROR unknown option $1" >&2; exit 1;;
    *)         FILES+=("$1"); shift;;
  esac
done
[ ${#FILES[@]} -gt 0 ] || { echo "SMOKE-ERROR no FILE given" >&2; exit 1; }
[ -n "$SWITCH" ] && eval "$(opam env --switch="$SWITCH" --set-switch 2>/dev/null)" || true
command -v frama-c >/dev/null 2>&1 || { echo "SMOKE-ERROR frama-c not on PATH (need the opam switch? try --switch framac-coq8)"; exit 1; }

cmd=(frama-c -wp -machdep "$MACHDEP" -wp-prover "$PROVER" -wp-timeout "$TIMEOUT")
[ -n "$RTE" ]   && cmd+=("$RTE")
[ -n "$FCT" ]   && cmd+=(-wp-fct "$FCT")
[ -n "$MODEL" ] && cmd+=(-wp-model "$MODEL")
[ -n "$CACHE" ] && cmd+=(-wp-cache "$CACHE")
[ -n "$CPP" ]   && cmd+=(-cpp-extra-args="$CPP")
cmd+=("${FILES[@]}")

echo "+ ${cmd[*]}" >&2
out=$("${cmd[@]}" 2>&1) || true
echo "$out" | grep -E 'Proved goals' || true
# Parse "[wp] Proved goals:  N / M" (take the last such line = the run total).
line=$(printf '%s\n' "$out" | grep -oE 'Proved goals:[[:space:]]*[0-9]+[[:space:]]*/[[:space:]]*[0-9]+' | tail -1)
if [ -z "$line" ]; then
  echo "SMOKE-ERROR no 'Proved goals' line — parse/WP failure (see output above)"; exit 1
fi
n=$(printf '%s\n' "$line" | grep -oE '[0-9]+' | sed -n 1p)
m=$(printf '%s\n' "$line" | grep -oE '[0-9]+' | sed -n 2p)
if [ "${m:-0}" -gt 0 ] && [ "$n" = "$m" ]; then
  echo "SMOKE-PASS $n/$m"; exit 0
else
  echo "SMOKE-FAIL $n/$m"; exit 1
fi
