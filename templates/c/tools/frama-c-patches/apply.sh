#!/usr/bin/env bash
# Apply the out-of-tree Frama-C patches to a framac-src checkout.
# Usage: [FRAMAC_SRC=../framac-src] ./apply.sh [--check]
#   --check : dry-run (git apply --check) without modifying the tree.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${FRAMAC_SRC:-$HERE/../framac-src}"
[ -d "$SRC/src/plugins/wp" ] || { echo "ERROR: '$SRC' is not a Frama-C source tree (no src/plugins/wp)"; exit 2; }
DRY=0; [ "${1:-}" = "--check" ] && DRY=1

shopt -s nullglob
for p in "$HERE"/0*.patch; do
  echo "== $(basename "$p") =="
  if [ "$DRY" = 1 ]; then
    ( cd "$SRC" && git apply --check "$p" ) && echo "   would apply CLEAN" || echo "   WOULD CONFLICT (port by hand)"
  else
    if ( cd "$SRC" && git apply "$p" 2>/dev/null ); then echo "   applied (git apply)"
    elif ( cd "$SRC" && patch -p1 < "$p" ); then echo "   applied (patch -p1)"
    else echo "   FAILED — port the hunk by hand (see patch header)"; exit 1; fi
  fi
done
echo
echo "Now rebuild (WP is a dynamic plugin -> dune build @install is required):"
echo "  cd '$SRC' && eval \$(opam env --switch=framac-coq8 --set-switch) && dune build @install"
