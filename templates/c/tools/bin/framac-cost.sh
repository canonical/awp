#!/bin/sh
# framac-cost.sh — per-unit cost telemetry for the loop (WS8). Records the structural multiple
# (role-invocations per item) and tokens/wall-clock, and contrasts the one-time proof cost with
# the cheap replay cost (the H4 amortization the paper flags as un-instrumented, §10).
#
# Usage:
#   ./framac-cost.sh add <campaign> <unit> <role> <tokens> <wall_s> <tool_uses> "<note>"
#   ./framac-cost.sh summary [cost.tsv]      # default framac/cost.tsv
#
# TSV columns: campaign  unit  role  tokens  wall_s  tool_uses  note
set -eu
TSV_DEFAULT="framac/cost.tsv"
cmd="${1:-summary}"; shift || true

if [ "$cmd" = add ]; then
  tsv="$TSV_DEFAULT"
  [ -f "$tsv" ] || printf 'campaign\tunit\trole\ttokens\twall_s\ttool_uses\tnote\n' > "$tsv"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "${7:-}" >> "$tsv"
  echo "recorded: $1/$2/$3"
  exit 0
fi

tsv="${1:-$TSV_DEFAULT}"
[ -f "$tsv" ] || { echo "no cost log: $tsv" >&2; exit 2; }
"${ROCQ_PYTHON_BIN:-python3}" - "$tsv" <<'PY'
import sys, collections
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
hdr, rows = rows[0], [r for r in rows[1:] if len(r) >= 6]
tok = sum(int(r[3]) for r in rows if r[3].isdigit())
wall = sum(int(r[4]) for r in rows if r[4].isdigit())
units = collections.Counter(r[1] for r in rows)
roles = collections.Counter(r[2] for r in rows)
replay_tok = sum(int(r[3]) for r in rows if 'replay' in r[2].lower() and r[3].isdigit())
proof_tok = tok - replay_tok
print(f"# Cost telemetry — {len(rows)} role-invocations over {len(units)} unit(s)")
print(f"- total agent tokens: {tok:,}   wall-clock: {wall:,}s ({wall/3600:.2f}h)")
print(f"- structural multiple: {len(rows)/max(1,len(units)):.1f} role-invocations / unit "
      f"(paper §10: a low single-digit multiple per item)")
print("- role-invocations:", ", ".join(f"{k}×{v}" for k, v in roles.most_common()))
print(f"- H4 amortization: one-time proof ≈ {proof_tok:,} agent-tokens; replay (verify.sh-style, "
      f"WP re-run, no agent) ≈ {replay_tok:,} agent-tokens — the cost is paid once and the proof "
      f"re-verifies cheaply on every later change / re-clone, so it amortizes on long regression "
      f"horizons (and is a dead loss on one-shot tasks).")
print("\n| campaign | unit | role | tokens | wall_s | tool_uses |")
print("|---|---|---|---|---|---|")
for r in rows:
    print(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} |")
PY
