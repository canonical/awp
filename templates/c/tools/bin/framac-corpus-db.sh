#!/usr/bin/env bash
# framac-corpus-db.sh — synthesize a compile_commands.json for the framac/ corpus
# when the source project has no Clang compilation database (e.g. a Makefile-based
# tree like StandardAlgorithms).
#
# Each .c under the corpus (excluding pilot/) becomes one unit. The -I set is the
# corpus root PLUS every subdirectory that contains a header, so any quoted sibling
# include resolves regardless of which dir the unit lives in. System headers
# (<...>) come from Frama-C's own libc, so they need no -I.
#
# Usage:  ./framac-corpus-db.sh [corpus-dir] [out.json]
#         ./framac-corpus-db.sh framac compile_commands.json
# Requires: jq. The emitted file is consumed by framac-queue.sh / `make framac-queue`.
set -euo pipefail
CORPUS="${1:-framac}"
OUT="${2:-compile_commands.json}"
ROOT="$(pwd)"
command -v jq >/dev/null || { echo "framac-corpus-db: jq not found" >&2; exit 2; }
[ -d "$CORPUS" ] || { echo "framac-corpus-db: corpus dir '$CORPUS' not found" >&2; exit 2; }

# -I set: corpus root + every dir under it that holds a .h header (deduped, sorted).
incs=()
while IFS= read -r d; do incs+=( "-I$d" ); done \
  < <( { echo "$CORPUS"; find "$CORPUS" -name '*.h' -printf '%h\n'; } | sort -u )
inc_json=$(printf '%s\n' "${incs[@]}" | jq -R . | jq -s .)

# One entry per .c unit (paths relative to repo root; frama-c is run from there).
find "$CORPUS" -name '*.c' -not -path "$CORPUS/pilot/*" | sort | \
  jq -R --arg root "$ROOT" --argjson inc "$inc_json" \
     '{ directory: $root, file: ., arguments: (["cc"] + $inc + ["-c", .]) }' \
  | jq -s . > "$OUT"
echo "wrote $OUT ($(jq length "$OUT") units, ${#incs[@]} include dirs)"
