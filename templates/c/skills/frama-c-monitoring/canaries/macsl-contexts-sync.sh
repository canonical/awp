#!/usr/bin/env bash
# macsl-contexts-sync canary — catches SKILL↔TOOL drift of the HAPPY \context vocabulary.
#
# Root cause it institutionalizes: macsl grew WS1/WS3/WS4/WS6/WS7 contexts (\authorized,
# \noninterference, \fuel, \guarded_by, …) but the skills never learned them, so campaigns defaulted
# to \writing/\total and hand-rolled authorization. This check fails when the tool's context set and
# the catalog reference disagree — forcing the catalog (and the skills that link it) to be updated in
# the SAME change that adds a context to the tool.
#
# Source of truth = the tool:  frama-c -load-module $MACSL_CMXS -macsl-list-contexts
# Catalog under check        = config/skills/frama-c-api/references/macsl-contexts.md
#
# Exit: 0 = in sync · 1 = DRIFT (tool/catalog context sets differ) · 2 = tool unavailable (cannot check)
set -u

CMXS="${MACSL_CMXS:-$HOME/git/use-frama-c/macsl/_build/default/src/macsl.cmxs}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG="${MACSL_CATALOG:-$HERE/../../frama-c-api/references/macsl-contexts.md}"

[ -f "$CATALOG" ] || { echo "FAIL: catalog not found: $CATALOG"; exit 1; }
if ! command -v frama-c >/dev/null 2>&1 || [ ! -f "$CMXS" ]; then
  echo "SKIP(2): macsl plugin not built ($CMXS) or frama-c absent — build 'dune build' in use-frama-c/macsl, then re-run."
  exit 2
fi

# Base context tokens (strip arg-modifiers \secret/\cost/\declassify; fold the cost variant into the
# base \noninterference) from each source, as a sorted unique set.
norm() { grep -oE '\\(writing|reading|postcond|precond|noninterference|total|guarded_by|stable_check|authorized|tamper_evident|fuel|flow)\b' \
         | sort -u; }

# The tool prints "[macsl] \writing | ... | ...": norm pulls the base tokens from anywhere.
TOOL="$(frama-c -no-autoload-plugins -load-module "$CMXS" -macsl-list-contexts 2>&1 | norm)"
# Catalog: norm the markdown table rows (lines starting with '|').
DOC="$(grep -E '^\|' "$CATALOG" | norm)"

if [ -z "$TOOL" ]; then echo "FAIL: -macsl-list-contexts produced no tokens (flag missing? rebuild macsl)"; exit 1; fi

ONLY_TOOL="$(comm -23 <(printf '%s\n' "$TOOL") <(printf '%s\n' "$DOC"))"
ONLY_DOC="$(comm -13 <(printf '%s\n' "$TOOL") <(printf '%s\n' "$DOC"))"

if [ -n "$ONLY_TOOL" ] || [ -n "$ONLY_DOC" ]; then
  echo "DRIFT(1): macsl context set and catalog disagree."
  [ -n "$ONLY_TOOL" ] && { echo "  in TOOL but NOT in catalog (add them — the skills are blind to these):"; echo "$ONLY_TOOL" | sed 's/^/    /'; }
  [ -n "$ONLY_DOC" ]  && { echo "  in catalog but NOT in TOOL (stale — remove or the tool regressed):";    echo "$ONLY_DOC"  | sed 's/^/    /'; }
  echo "  -> update config/skills/frama-c-api/references/macsl-contexts.md (regen from -macsl-list-contexts)."
  exit 1
fi

echo "OK: macsl context vocabulary in sync ($(printf '%s\n' "$TOOL" | wc -l | tr -d ' ') contexts: $(printf '%s ' $TOOL))"
exit 0
