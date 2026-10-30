#!/usr/bin/env bash
# framac-gen-verdicts.sh — regenerate framac/VERDICTS.md (human summary) from
# framac/.verdicts.tsv (machine log: <file>\t<verdict>\t<notes>).
# Verdicts: PROVED | PARTIAL(..) | FAILED | TRIVIAL. Used by the
# framac-monitoring batch loop (one append per file, one regen per batch).
set -euo pipefail
TSV="${1:-framac/.verdicts.tsv}"
OUT="${2:-framac/VERDICTS.md}"
touch "$TSV"
total=$(find framac -name '*.c' 2>/dev/null | wc -l | tr -d ' ')
done=$(grep -c . "$TSV" || true)
proved=$(awk -F'\t' '$2=="PROVED"{c++}  END{print c+0}' "$TSV")
partial=$(awk -F'\t' '$2 ~ /PARTIAL/{c++} END{print c+0}' "$TSV")
failed=$(awk -F'\t'  '$2=="FAILED"{c++}  END{print c+0}' "$TSV")
trivial=$(awk -F'\t' '$2=="TRIVIAL"{c++} END{print c+0}' "$TSV")
{
  echo "# framac-monitoring run — analyze all \`*.c\` in \`framac/\`"
  echo
  echo "- **Guidance (U):** specify thoroughly (RTE freedom: no overflow / div-by-zero / out-of-bounds / invalid-pointer for any input + functional intent)."
  echo "- **Ground truth (L):** \`frama-c -wp\` goal discharge (WP -> Why3 -> SMT: Alt-Ergo / Z3 / CVC5), with \`-wp-rte\`; EVA used to triage."
  echo "- **Scheduler:** independent translation units; leaf functions first; processed in parallel batches of \`framac-sl\` sub-agents; monitor-gated for faithfulness."
  echo
  echo "**Progress: $done / $total processed** — PROVED $proved, PARTIAL $partial, FAILED $failed, TRIVIAL $trivial."
  echo
  echo "| File | Verdict | Notes |"
  echo "|---|---|---|"
  sort "$TSV" | awk -F'\t' '{printf "| `%s` | %s | %s |\n", $1, $2, $3}'
} > "$OUT"
echo "wrote $OUT ($done/$total)"
