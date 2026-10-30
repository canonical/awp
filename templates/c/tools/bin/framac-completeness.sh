#!/usr/bin/env bash
# framac-completeness.sh — Gate C' (completeness floor): does the loop's spec ensure
# the INTENDED properties the human gold ensures?
#
# Gate C (mutation probe) proves the WRITTEN spec has teeth but cannot tell whether it
# is COMPLETE — a sort that proves Sorted(a,n) but not permutation passes Gate C yet is
# under-specified (a zero-fill body satisfies it). The gold (framac-gold/) encodes the
# intended properties, so a gold-ensured CONCEPT absent from the loop spec is a real
# under-specification. This is a FLOOR (named-predicate coverage), not a ceiling: a
# clear miss => INCOMPLETE; otherwise an editorial judge still confirms semantic match.
#
# Prints: COMPLETE | INCOMPLETE:<concepts> | NOGOLD   (+ exit 0 always)
# Usage:  ./framac-completeness.sh <unit-rel.c>    e.g.  Sorting/selection_sort.c
set -uo pipefail
rel="$1"; base="${rel%.c}"
# Prefer the gold header; fall back to the gold .c for HEADER-LESS units (e.g.
# StackAxioms/* carry their contract directly in the .c — there is no .h).
goldh="framac-gold/$base.h"
[ -f "$goldh" ] || goldh="framac-gold/$base.c"
[ -f "$goldh" ] || { echo "NOGOLD"; exit 0; }
# Loop's PROPERTY-STATING ACSL only — the ensures/behavior/predicate/logic text, NOT the
# whole file (function names / #include guards would falsely "cover" a concept: is_heap_until's
# lone `ensures \result<=n` must NOT count as covering "Heap" just because the file is named
# is_heap_until). This is a HINT for the Gate C' editorial judge, not an authoritative verdict.
work=$(grep -hiE 'ensures|behavior|predicate|logic' "framac/$base.h" "framac/$base.c" 2>/dev/null)

# Map a predicate token to a normalized intended-property concept.
concept() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    *multiset*|*permut*|*reorder*|*unchanged*) echo permutation ;;
    *sort*|*increas*|*ordered*)                echo sortedness ;;
    *partition*)                               echo partition ;;
    *) printf '%s' "$1" | tr 'A-Z' 'a-z' ;;
  esac
}
# Is a concept covered anywhere in the loop spec text?
covered() {
  case "$1" in
    permutation) printf '%s' "$work" | grep -qiE 'multiset|permut|reorder|unchanged' ;;
    sortedness)  printf '%s' "$work" | grep -qiE 'sort|increas|order' ;;
    partition)   printf '%s' "$work" | grep -qiE 'partition' ;;
    *)           printf '%s' "$work" | grep -qiE "$1" ;;
  esac
}

# Intended-property predicate names the gold uses in its ensures clauses (CamelCase,
# excluding ACSL label/builtin tokens and memory-label names).
goldpreds=$(grep -iE 'ensures' "$goldh" \
  | grep -oE '[A-Z][A-Za-z0-9_]+' \
  | grep -vE '^(Old|Here|Pre|Post|L|L1|L2|LoopEntry)$' | sort -u)

missing=""; seen=" "
for p in $goldpreds; do
  c=$(concept "$p")
  case "$seen" in *" $c "*) continue ;; esac ; seen="$seen$c "
  covered "$c" || missing="$missing $c"
done
[ -z "$missing" ] && echo "COMPLETE" || echo "INCOMPLETE:$missing"
