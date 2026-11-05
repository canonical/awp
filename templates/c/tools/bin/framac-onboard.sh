#!/usr/bin/env bash
# framac-onboard.sh — derive a target's Frama-C build context + run the parse oracle.
#
# The frama-c-launch prober's primary L oracle. Given a vendored clone, it:
#   1. checks the toolchain        (frama-c -wp-detect + the framac-coq8 opam switch)
#   2. initialises submodules      (a bare clone often won't preprocess otherwise)
#   3. finds/derives compile_commands.json (reports how to generate it; --build attempts it)
#   4. runs the PARSE ORACLE on a sample of units (do they preprocess + parse under Frama-C,
#      with no dropped-annotation warnings?) and reports N/M parse-clean.
# It prints a structured onboarding report (the §1/§2 rows of templates/onboarding-package.md),
# marking each oracle PASS / DEPENDENCY-UNMET. It NEVER fakes a PASS (sl-monitoring-sl honesty).
# It does NOT pick the feature profile or prove anything — that is Gate A_launch / framac-smoke.sh.
#
# Usage:
#   framac-onboard.sh <target-dir> [opts]
# Options:
#   --build           attempt to generate compile_commands.json (bear -- make / cmake) if absent
#   --switch NAME     opam switch to source for the toolchain check (default: framac-coq8)
#   --sample N        how many units to run the parse oracle on (default: 3)
#   --cpp "FLAGS"     extra -cpp-extra-args applied to every parse probe (force-includes etc.)
#   --db FILE         path to compile_commands.json (default: <target-dir>/compile_commands.json)
# Exit: 0 if toolchain OK AND the parse oracle is all-clean; 1 otherwise (blocking onboarding).
set -uo pipefail

DIR=""; BUILD=0; SWITCH="framac-coq8"; SAMPLE=3; CPP=""; DB=""
while [ $# -gt 0 ]; do
  case "$1" in
    --build)  BUILD=1; shift;;
    --switch) SWITCH="$2"; shift 2;;
    --sample) SAMPLE="$2"; shift 2;;
    --cpp)    CPP="$2"; shift 2;;
    --db)     DB="$2"; shift 2;;
    -h|--help) sed -n '2,28p' "$0"; exit 0;;
    -*) echo "framac-onboard: unknown option $1" >&2; exit 2;;
    *)  DIR="$1"; shift;;
  esac
done
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "usage: framac-onboard.sh <target-dir> [opts]" >&2; exit 2; }
DIR=$(cd "$DIR" && pwd)
[ -n "$DB" ] || DB="$DIR/compile_commands.json"
rc=0
say() { printf '%s\n' "$*"; }
hdr() { printf '\n== %s ==\n' "$*"; }

say "# frama-c-launch onboarding report — $DIR"

# ---- 1. toolchain ----------------------------------------------------------
hdr "toolchain (U.2)"
[ -n "$SWITCH" ] && eval "$(opam env --switch="$SWITCH" --set-switch 2>/dev/null)" || true
if command -v frama-c >/dev/null 2>&1; then
  say "frama-c: $(frama-c -version 2>/dev/null | head -1)   PASS"
  provers=$(frama-c -wp-detect 2>/dev/null | grep -E '^\[wp\] Prover ' | sed 's/^\[wp\] /    /')
  say "-wp-detect:"; printf '%s\n' "${provers:-    (no provers detected — DEPENDENCY-UNMET)}"
  [ -z "$provers" ] && rc=1
else
  say "frama-c: NOT on PATH — DEPENDENCY-UNMET (source the opam switch: opam switch $SWITCH)"; rc=1
fi
if [ -n "${FRAMA_C_SDK_SWITCH:-}" ] && [ "$FRAMA_C_SDK_SWITCH" = "$SWITCH" ]; then
  # In a workshop: the frama-c-sdk SDK's read-only switch, no opam root of the user's.
  say "opam switch '$SWITCH': present   PASS  (frama-c-sdk SDK, $FRAMA_C_SDK_SRC; Coq escalation available)"
elif opam switch list 2>/dev/null | grep -q "$SWITCH"; then
  say "opam switch '$SWITCH': present   PASS  (Coq escalation available)"
else
  say "opam switch '$SWITCH': ABSENT — DEPENDENCY-UNMET (bitmask/induction residue will not close in Coq)"
fi

# ---- 2. submodules ---------------------------------------------------------
hdr "submodules"
if [ -f "$DIR/.gitmodules" ]; then
  if git -C "$DIR" submodule update --init --recursive >/dev/null 2>&1; then
    say "submodules: initialised   PASS"
  else
    say "submodules: .gitmodules present but init FAILED — DEPENDENCY-UNMET"; rc=1
  fi
else
  say "submodules: none"
fi

# ---- 3. compile_commands.json ---------------------------------------------
# The build oracle (U.1) precedes every other oracle: if the target was not ACTUALLY
# compiled for the chosen profile there is no real compile_commands.json, and that is a
# HARD FAIL (exit 3) — un-built != BLOCKED, no hand-synthesized-flags / leaf-driver
# fallback (the framac-launch-build-oracle rule).
build_failed=0
hdr "preprocess context (U.1)"
if [ ! -f "$DB" ] && [ "$BUILD" = 1 ]; then
  if [ -f "$DIR/CMakeLists.txt" ] && command -v cmake >/dev/null 2>&1; then
    say "attempting: cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON (build dir _fc_build)"
    ( cd "$DIR" && cmake -S . -B _fc_build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null 2>&1 ) || true
    [ -f "$DIR/_fc_build/compile_commands.json" ] && DB="$DIR/_fc_build/compile_commands.json"
  elif command -v bear >/dev/null 2>&1 && [ -f "$DIR/Makefile" -o -f "$DIR/configure" ]; then
    say "attempting: bear -- make  (run ./configure first if needed)"
    ( cd "$DIR" && bear -- make >/dev/null 2>&1 ) || true
    [ -f "$DIR/compile_commands.json" ] && DB="$DIR/compile_commands.json"
  fi
fi
if [ -f "$DB" ]; then
  n=$(grep -c '"file"' "$DB" 2>/dev/null || echo 0)
  if [ "$n" -gt 0 ]; then
    say "compile_commands.json: $DB  ($n entries)   PASS"
  else
    say "compile_commands.json: $DB present but 0 entries — BUILD-NOT-DONE (the build produced no"
    say "  compile commands; the target was not actually compiled). HARD FAIL — un-built != BLOCKED."
    build_failed=1; rc=1
  fi
else
  say "compile_commands.json: ABSENT — BUILD-NOT-DONE (the target was not actually compiled for the profile)"
  say "  generate one:  bear -- make   |   cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
  say "  un-built != BLOCKED: this is a HARD FAIL (exit 3), not a residual — NO hand-built"
  say "  -cpp-extra-args / leaf-driver fallback (the build oracle precedes every other oracle)."
  build_failed=1; rc=1
fi

# ---- 4. parse oracle -------------------------------------------------------
hdr "parse oracle (L.1) — sample $SAMPLE units"
if ! command -v frama-c >/dev/null 2>&1; then
  say "skipped — frama-c not on PATH"; rc=1
else
  # Build the sample list of "file<TAB>flags". Prefer the DB (real per-unit flags); else find *.c.
  tmp=$(mktemp)
  if [ -f "$DB" ] && command -v jq >/dev/null 2>&1; then
    jq -r --arg dir "$DIR" '
      .[:'"$SAMPLE"'][] |
      ((.file) ) as $f |
      ((.arguments // (.command|split(" "))) | map(select(
         startswith("-I") or startswith("-D") or startswith("-include") or .=="-isystem"))
       | join(" ")) as $fl |
      "\($f)\t\($fl)"' "$DB" 2>/dev/null > "$tmp" || true
  fi
  if [ ! -s "$tmp" ]; then
    # fallback: first $SAMPLE .c files, flags = whatever --cpp supplies
    while IFS= read -r f; do printf '%s\t\n' "$f"; done \
      < <(find "$DIR" -name '*.c' -type f 2>/dev/null | head -n "$SAMPLE") > "$tmp"
  fi
  total=0; clean=0
  while IFS=$'\t' read -r f fl; do
    [ -n "$f" ] || continue
    case "$f" in /*) src="$f";; *) src="$DIR/$f";; esac
    [ -f "$src" ] || continue
    total=$((total+1))
    perr=$(cd "$DIR" && frama-c -cpp-extra-args="$fl $CPP" "$src" 2>&1); ec=$?
    if [ "$ec" -ne 0 ] || printf '%s' "$perr" | grep -qiE 'syntax error|parse error|fatal error|user error|No such file'; then
      say "  PARSE-FAIL  $f  (frama-c exit $ec)"
      printf '%s\n' "$perr" | grep -iE 'error' | head -2 | sed 's/^/      /'
    elif printf '%s' "$perr" | grep -qiE 'unbound logic|annot-error|ignoring (the )?annotation|dropping (the )?annotation|unexpected token'; then
      # ACSL-specific drop (a stripped type chain), NOT a benign "Ignoring unknown attribute: mode".
      say "  DROPPED-ANNOT  $f  (stripped type chain? add a force-include via --cpp)"
    else
      say "  parse-clean  $f"; clean=$((clean+1))
    fi
  done < "$tmp"
  rm -f "$tmp"
  if [ "$total" -gt 0 ] && [ "$clean" = "$total" ]; then
    say "parse oracle: $clean/$total clean   PASS"
  else
    say "parse oracle: $clean/$total clean — DEPENDENCY-UNMET (fix flags/force-includes in the queue)"
    rc=1
  fi
fi

# ---- verdict ---------------------------------------------------------------
hdr "onboarding verdict"
if [ "$rc" = 0 ]; then
  say "ONBOARD-READY — toolchain + parse oracle green. Next: Gate A_launch (pick the SHIPPED feature"
  say "profile), scaffold <target>-acsl/, then bin/framac-smoke.sh on the highest-value leaf unit."
elif [ "$build_failed" = 1 ]; then
  say "BUILD-NOT-DONE — HARD FAIL (exit 3). The target was not actually compiled for the chosen profile"
  say "  (no real compile_commands.json). un-built != BLOCKED: the build oracle (U.1) precedes every"
  say "  other oracle and admits NO fallback (no hand-synthesized flags, no leaf-driver). This is NOT a"
  say "  residual to record and hand off — fix the build, then re-run. Do NOT hand off."
  exit 3
else
  say "ONBOARD-BLOCKED — one or more oracles DEPENDENCY-UNMET (see above). Do NOT hand off."
fi
exit $rc
