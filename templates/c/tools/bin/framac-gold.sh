#!/usr/bin/env bash
# framac-gold.sh — populate framac-gold/ with the human-written ACSL reference,
# extracted from git history (the StandardAlgorithms corpus BEFORE the ACSL strip).
#
# This is a read-only ORACLE, not part of the loop's squeeze: compare the loop's
# re-specified contracts (framac/) against framac-gold/ with framac-compare.sh.
# It is NOT framac-orig/ — the faithfulness gate's reference must be the
# UN-annotated baseline, whereas gold is the fully-annotated human version.
#
# Files are byte-identical to the historical StandardAlgorithms blobs, so git
# stores them once (shared blobs); committing framac-gold/ is near-free.
#
# Usage:  ./framac-gold.sh [gold-dir] [git-ref]
#   gold-dir : output dir (default framac-gold)
#   git-ref  : commit holding the pristine ACSL corpus (default: auto-detect)
set -euo pipefail
GOLD_DIR="${1:-framac-gold}"
REF="${2:-}"
SRC_PREFIX="StandardAlgorithms"

case "$GOLD_DIR" in ""|.|/|..) echo "framac-gold: refusing unsafe gold dir '$GOLD_DIR'" >&2; exit 2;; esac

# Auto-detect the pristine (with-ACSL) commit if no ref was given.
if [ -z "$REF" ]; then
  REF=$(git log -1 --format=%H --grep='ACSL verification corpus' || true)
  [ -n "$REF" ] || { echo "framac-gold: could not auto-detect the pristine ACSL commit; pass a git-ref" >&2; exit 2; }
fi
git cat-file -e "$REF^{commit}" 2>/dev/null || { echo "framac-gold: '$REF' is not a commit" >&2; exit 2; }

rm -rf "$GOLD_DIR"
# Extract every .c/.h/.acsl that existed under the prefix in that commit.
git ls-tree -r --name-only "$REF" -- "$SRC_PREFIX" \
  | grep -E '\.(c|h|acsl)$' \
  | while IFS= read -r path; do
      rel="${path#"$SRC_PREFIX"/}"
      mkdir -p "$GOLD_DIR/$(dirname "$rel")"
      git show "$REF:$path" > "$GOLD_DIR/$rel"
    done
echo "populated $GOLD_DIR from ${REF:0:12} ($(find "$GOLD_DIR" -type f | wc -l) files: .c/.h units + .acsl logic defs)"
