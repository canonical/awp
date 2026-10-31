#!/usr/bin/env bash
# Level 3, C (gzip-test.md, tests.md 5.5): a one-hour `/time-loop gzip-1.9 1`
# run on GNU gzip 1.9 through the interactive harness, in a copy of
# autowp-c-base/ready.
#
#   tests/c/gzip-test.sh               KEEP=1 keeps the container
#
# Needs the Claude token (tests.md 7, AUTOWP_TOKEN_FILE). Downloads and checks
# gzip-1.9.zip (G.0) before the token is moved in, waits for the loop to stop,
# at most 3 hours, then runs G.1-G.11.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib/lxc.sh
. "$HERE/../lib/lxc.sh"
# shellcheck source=../lib/secret.sh
. "$HERE/../lib/secret.sh"

CAMPAIGN_PROJECT=gzip-analyze
CAMPAIGN_SRC=gzip-1.9
CAMPAIGN_SRC_KIND=tracked
CAMPAIGN_COMMIT_FILE=.autowp-gzip-commit
CAMPAIGN_WAKES=info
CAMPAIGN_LINT=1
# shellcheck source=../lib/harness.sh
. "$HERE/../lib/harness.sh"

HOURS=1
HARD_LIMIT=$((3 * 3600))
CMD="/time-loop $CAMPAIGN_SRC $HOURS"

# g11 <container> <id>: at least one unit with PROVED goals (gzip-test.md 5),
# plus the counts of what the hour produced, as INFO.
g11() {
    local c=$1 id=$2 counts proved
    counts=$(autowp_exec_user "$c" "cd ~/$CAMPAIGN_PROJECT && python3 - '$CAMPAIGN_SRC'" <<'PY'
import os, re, sys
src = sys.argv[1]
ok = re.compile(r"\b(Valid|PROVED|GREEN)\b")
units, proved, goals = set(), set(), 0
for root, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d not in (".git", src, "framac-src", "macsl")]
    for f in files:
        if not f.endswith("verdicts.tsv"):
            continue
        for line in open(os.path.join(root, f), errors="replace"):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            cells = line.rstrip("\n").split("\t")
            if cells[0].strip().lower() in ("unit", "function", "sa#", "vo#"):
                continue
            units.add(cells[0].strip())
            if any(ok.search(x) for x in cells[1:]):
                proved.add(cells[0].strip())
                goals += 1
issues = 0
p = src + "-analysis-found-issues.md"
if os.path.exists(p):
    issues = sum(1 for l in open(p, errors="replace") if re.match(r"\s*(#{2,3} |[-*] )", l))
print(len(units), len(proved), goals, issues)
PY
    ) || counts="0 0 0 0"
    read -r units proved_units goals issues <<<"$counts"
    info "$id" "units in verdicts: $units; units with PROVED goals: $proved_units; PROVED rows: $goals; found-issues entries: $issues"
    proved=$proved_units
    if [ "${proved:-0}" -ge 1 ]; then pass "$id"
    else fail "$id" "no unit has PROVED goals; read the pane transcript before blaming the skills (rate limits, slow onboarding)"; fi
}

secret_check_file || exit 1
autowp_require_lxc
autowp_install_trap
autowp_ensure_pool
autowp_ensure_network

C=autowp-c-gzip-$(autowp_timestamp)
autowp_copy_snapshot autowp-c-base ready "$C"
autowp_wait_ready "$C"
autowp_egress_check "$C"
autowp_push_project "$C"

# G.0: download, sha256, signature, layout. Nothing else runs if it fails.
if setup=$(campaign_setup_c_gzip "$C" 2>&1); then
    pass G.0
    info G.0 "$(grep '^mirror:' <<<"$setup")"
else
    fail G.0 "$(tail -3 <<<"$setup" | tr '\n' ' ')"
    autowp_summary
    exit 2
fi

secret_push "$C"
if ! harness_start "$C" "/home/ubuntu/$CAMPAIGN_PROJECT" "$CMD"; then
    fail G.1 "harness did not start"
    autowp_summary
    exit 1
fi
if harness_confirm "$C" time-loop 300; then pass G.1; else fail G.1 "time-loop not loaded within 5 minutes (K4)"; fi

wait_loop_stopped "$C" "$(campaign_state_file)" "$HARD_LIMIT" || true
harness_pane "$C" | tail -15 | sed 's/^/    | /'
harness_stop "$C"

campaign_checks_c "$C" "$HOURS" G.
report_check_c "$C" G.10 interim
g11 "$C" G.11

autowp_summary
