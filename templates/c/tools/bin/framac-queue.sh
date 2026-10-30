#!/usr/bin/env bash
# framac-queue.sh — build the {file, flags} work queue for the framac-monitoring
# Workflow from a Clang-style compile_commands.json.
#
# Unlike the Creusot port (which rode `cargo`), Frama-C needs each file's
# PREPROCESSING context (-I include dirs, -D defines). We derive them per file
# from the compilation database and emit them so the Workflow `args` can carry a
# self-contained command per unit.
#
# Output: a JSON array on stdout, each element { "file": <rel>, "flags": [..] },
# filtered to files NOT already recorded in framac/.verdicts.tsv.
#
# Usage:
#   ./framac-queue.sh [compile_commands.json] [verdicts.tsv] > queue.json
# Requires: jq. Generate the DB with e.g. `bear -- make`, CMake
# (-DCMAKE_EXPORT_COMPILE_COMMANDS=ON), or Frama-C's own
# `-json-compilation-database`.
set -euo pipefail
DB="${1:-compile_commands.json}"
TSV="${2:-framac/.verdicts.tsv}"
[ -f "$DB" ]  || { echo "framac-queue: '$DB' not found (generate a compile_commands.json first)" >&2; exit 2; }
touch "$TSV"

# Files already processed (column 1 of the verdict log), as a JSON array.
done_json=$(cut -f1 "$TSV" | sed '/^$/d' | jq -R . | jq -s .)

# From each DB entry keep the source file and the -I / -D / -include flags that
# matter for preprocessing; drop the compiler, -c, -o, and the source itself.
jq --argjson done "$done_json" '
  map({
    file: (.file | sub("^\\./"; "")),
    flags: ((.arguments // (.command | split(" "))) as $a
            | $a | map(select(
                startswith("-I") or startswith("-D") or startswith("-include")
                or . == "-isystem" )))
  })
  | map(select(.file as $f | ($done | index($f)) | not))
  | unique_by(.file)
' "$DB"
