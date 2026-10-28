#!/usr/bin/env bash
# Level 3, C (tests.md 5.3): a 3-hour `/time-loop grub 3` run through the
# interactive harness, in a copy of autowp-c-base/ready.
#
#   tests/c/smoke-test.sh              KEEP=1 keeps the container
#
# Needs the Claude token (tests.md 7, AUTOWP_TOKEN_FILE). Waits for the loop
# to stop, at most 5 hours, then runs C3.1-C3.10.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib/lxc.sh
. "$HERE/../lib/lxc.sh"
# shellcheck source=../lib/secret.sh
. "$HERE/../lib/secret.sh"
# shellcheck source=../lib/harness.sh
. "$HERE/../lib/harness.sh"

HOURS=3
HARD_LIMIT=$((5 * 3600))
CMD="/time-loop grub $HOURS"

secret_check_file || exit 1
autowp_require_lxc
autowp_install_trap
autowp_ensure_pool
autowp_ensure_network

C=autowp-c-l3-$(autowp_timestamp)
autowp_copy_snapshot autowp-c-base ready "$C"
autowp_wait_ready "$C"
autowp_egress_check "$C"
autowp_push_project "$C"
campaign_setup_c "$C"

secret_push "$C"
if ! harness_start "$C" /home/ubuntu/foobar "$CMD"; then
    fail C3.1 "harness did not start"
    autowp_summary
    exit 1
fi
if harness_confirm "$C" time-loop 300; then pass C3.1; else fail C3.1 "time-loop not loaded within 5 minutes (K4)"; fi

wait_loop_stopped "$C" /home/ubuntu/foobar/grub-analysis-acsl/time-loop.state "$HARD_LIMIT" || true
harness_pane "$C" | tail -15 | sed 's/^/    | /'
harness_stop "$C"

campaign_checks_c "$C" "$HOURS" C3.
report_check_c "$C" C3.10 interim

autowp_summary
