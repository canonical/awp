#!/usr/bin/env bash
# framac-compare.sh — diff the loop's re-specified contracts (framac/) against the
# human-written gold (framac-gold/), per unit.
#
# The executable C is byte-identical across framac-orig/, framac/ and framac-gold/
# (only ACSL annotations and #include "*.acsl" lines differ), so each unified diff
# isolates the SPEC difference: what the loop produced vs. what a human wrote.
#
# Before any loop run, framac/ is the stripped baseline (no ACSL) so every unit
# DIFFERS by exactly the gold's annotations (shown as '-' lines = "to reproduce").
# After a run, the diff shows where the loop's contracts agree with / diverge from
# the human spec.
#
# Usage:  ./framac-compare.sh [gold-dir] [work-dir] [out-dir]
set -uo pipefail
GOLD="${1:-framac-gold}"
WORK="${2:-framac}"
OUT="${3:-build/framac/spec-compare}"
[ -d "$GOLD" ] || { echo "framac-compare: '$GOLD' not found — run 'make framac-gold' first" >&2; exit 2; }
[ -d "$WORK" ] || { echo "framac-compare: '$WORK' not found" >&2; exit 2; }

mkdir -p "$OUT"
find "$OUT" -name '*.diff' -delete 2>/dev/null || true
summary="$OUT/summary.tsv"; : > "$summary"
match=0; differ=0; missing=0

# Compare every .c/.h that exists in gold (the comparable units; .acsl are context).
while IFS= read -r g; do
  rel="${g#"$GOLD"/}"
  w="$WORK/$rel"
  if [ ! -f "$w" ]; then printf '%s\tMISSING_IN_WORK\t0\n' "$rel" >> "$summary"; missing=$((missing+1)); continue; fi
  if diff -q "$g" "$w" >/dev/null 2>&1; then
    printf '%s\tIDENTICAL\t0\n' "$rel" >> "$summary"; match=$((match+1))
  else
    d="$OUT/$(echo "$rel" | tr '/' '_').diff"
    diff -u "$g" "$w" > "$d" || true
    n=$(grep -cE '^[+-]' "$d" 2>/dev/null || echo 0)
    printf '%s\tDIFFERS\t%s\n' "$rel" "$n" >> "$summary"; differ=$((differ+1))
  fi
done < <(find "$GOLD" \( -name '*.c' -o -name '*.h' \) | sort)

total=$((match+differ+missing))
echo "spec comparison vs gold: $total files — IDENTICAL $match, DIFFERS $differ, MISSING $missing"
echo "per-file summary: $summary    per-file diffs: $OUT/*.diff"
echo "top divergences (spec lines changed):"
sort -t"$(printf '\t')" -k3 -rn "$summary" | head -8 | awk -F'\t' '{printf "  %-44s %-14s %s spec lines\n", $1, $2, $3}'
