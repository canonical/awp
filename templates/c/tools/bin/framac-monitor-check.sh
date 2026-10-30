#!/usr/bin/env bash
# framac-monitor-check.sh — base-SL monitor faithfulness gate for the Frama-C loop.
#
# An annotated C file must contain the SAME executable code as the pristine
# original — the annotator may only ADD ACSL (which lives entirely in `/*@ ... */`
# and `//@ ...` comments, plus `/*@ ghost ... */` blocks), never invent/alter C.
# The stripped C must be byte-identical to the pristine original.
# Prints ACCEPT | FABRICATED | NOORIG | MISSING.
#
# This is the conservative-transformation gate from sl-monitoring-sl:
#   strip(annotated) MUST equal original  <=>  the change was a pure extension.
#
# TWO MODES:
#   framac-monitor-check.sh <rel>          mirror mode  : compare framac/<rel> to framac-orig/<rel>
#   framac-monitor-check.sh --git <file>   git-HEAD mode: compare <file> (in-place annotated, in the
#                                          working tree) to `git show HEAD:<file>` in the file's
#                                          OWNING repo. For a vendored clone overlay (mbedtls/wolfssl
#                                          style) there is no framac-orig/ mirror — the pristine
#                                          baseline is the clone's own HEAD. CRITICAL: the owning repo
#                                          is resolved per file, so a file inside a SUBMODULE is diffed
#                                          against the SUBMODULE's HEAD (not the parent) — the
#                                          submodule-vs-parent faithfulness trap a single-repo diff
#                                          would falsely PASS (see frama-c-launch learned-onboard-monitor).
set -uo pipefail

# Strip ACSL: (1) block annotations /*@ ... */ (possibly multi-line, non-nesting), which also covers
# /*@ ghost ... */; (2) line annotations //@ ... to end of line. Ordinary C comments (/* ... */
# without '@', // ...) are NOT touched — they belong to the original and must survive identically.
strip_acsl() {
  perl -0777 -pe '
    s{/\*\@.*?\*/}{}gs;     # block ACSL  /*@ ... */   (non-greedy, dotall)
    s{//\@[^\n]*}{}g;       # line  ACSL  //@ ...
  ' "$1"
}
# Normalise away whitespace-only differences the strip leaves behind (blank lines,
# trailing/leading run-spaces) — identical policy to the Creusot monitor.
norm() { grep -vE '^[[:space:]]*$' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'; }

if [ "${1:-}" = "--git" ]; then
  file="${2:-}"
  [ -n "$file" ] || { echo "usage: framac-monitor-check.sh --git <file>" >&2; exit 2; }
  [ -f "$file" ] || { echo "MISSING"; exit 0; }
  dir=$(cd "$(dirname "$file")" && pwd) || { echo "MISSING"; exit 0; }
  base=$(basename "$file")
  # Owning repo toplevel — resolves to the SUBMODULE root if the file lives in a submodule.
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || { echo "NOORIG"; exit 0; }
  if [ "$dir" = "$top" ]; then relpath="$base"; else relpath="${dir#"$top"/}/$base"; fi
  # Pristine = the file at HEAD in its owning repo. Untracked / not-in-HEAD => NOORIG.
  git -C "$top" cat-file -e "HEAD:$relpath" 2>/dev/null || { echo "NOORIG"; exit 0; }
  if diff -q <(strip_acsl "$file" | norm) \
            <(git -C "$top" show "HEAD:$relpath" 2>/dev/null | norm) >/dev/null 2>&1; then
    echo ACCEPT
  else
    echo FABRICATED
  fi
  exit 0
fi

# --- mirror mode (default) ---
rel="${1:-}"
[ -n "$rel" ] || { echo "usage: framac-monitor-check.sh <rel> | --git <file>" >&2; exit 2; }
orig="framac-orig/$rel"
cur="framac/$rel"
[ -f "$orig" ] || { echo "NOORIG"; exit 0; }
[ -f "$cur" ]  || { echo "MISSING"; exit 0; }
if diff -q <(strip_acsl "$cur" | norm) <(norm < "$orig") >/dev/null 2>&1; then
  echo ACCEPT
else
  echo FABRICATED
fi
