#!/usr/bin/env bash
# Level 4, C (tests.md 5.4): the real README example, `/time-loop grub 72`,
# plus a resume run. The main run lasts 72 hours, so `start` returns and the
# other sub-commands report on it.
#
#   tests/c/acceptance.sh start      copy base, level 2 steps, tools, origin, token,
#                                    harness: /time-loop grub 72   (needs ACCEPT_COST=1)
#   tests/c/acceptance.sh status     elapsed, cycles, time rate-limited, latest
#                                    feedback file, last pushed commit
#   tests/c/acceptance.sh attach     tmux attach inside the container
#   tests/c/acceptance.sh check      C4.1-C4.5 (after the run ends)
#   tests/c/acceptance.sh stop       stop the harness, keep the container
#   tests/c/acceptance.sh restart    new harness session, same command (re-sends the token)
#   tests/c/acceptance.sh destroy    delete the container
#   tests/c/acceptance.sh resume     the resume run (C4.6, C4.6b, C4.7, C4.8) in a
#                                    separate container, budget 4 h; runs in the
#                                    foreground for about 6 h (needs ACCEPT_COST=1)
#
# `status` also samples the pane for a usage-limit message; run it
# periodically (for example `watch -n 600 tests/c/acceptance.sh status`) so
# the time spent rate-limited, used by C4.2, is measured.
#
# Environment: ACCEPT_COST=1 (required by start/restart/resume),
# ACCEPT_TOKEN_EXPIRY=1 (unknown token lifetime), AUTOWP_TOKEN_FILE, KEEP=1.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib/lxc.sh
. "$HERE/../lib/lxc.sh"
# shellcheck source=../lib/secret.sh
. "$HERE/../lib/secret.sh"
# shellcheck source=../lib/harness.sh
. "$HERE/../lib/harness.sh"

SUB=${1:-}
STATE_DIR=$AUTOWP_OUT/acceptance
MAIN_HOURS=72
RESUME_HOURS=4
F=/home/ubuntu/foobar/grub-analysis-acsl/time-loop.state
LIMIT_RE='usage limit|rate limit|limit reached|resets at'

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

require_cost() {
    if [ "${ACCEPT_COST:-0}" != 1 ]; then
        echo "ERROR: $SUB runs on the host session's harness subscription and shares its" >&2
        echo "       usage limits (tests.md 2). Set ACCEPT_COST=1 to start it, preferably while" >&2
        echo "       the host session is idle." >&2
        exit 2
    fi
}

container() {
    [ -f "$STATE_DIR/main.container" ] || die "no acceptance run started (no $STATE_DIR/main.container)"
    cat "$STATE_DIR/main.container"
}

# start_run <container> <hours> <tag>: everything up to the harness (K4).
start_run() {
    local c=$1 hours=$2 tag=$3
    autowp_copy_snapshot autowp-c-base ready "$c"
    autowp_wait_ready "$c"
    autowp_egress_check "$c"
    autowp_push_project "$c"
    campaign_setup_c "$c"
    if [ -f "$HOME/.local-llm-machine-ip.txt" ]; then
        lxc file push "$HOME/.local-llm-machine-ip.txt" "$c/home/ubuntu/.local-llm-machine-ip.txt" \
            --uid 1000 --gid 1000 --mode 0644
    fi
    secret_push "$c"
    harness_start "$c" /home/ubuntu/foobar "/time-loop grub $hours" || return 1
    if harness_confirm "$c" time-loop 300; then
        echo pass > "$STATE_DIR/$tag.k4"; pass "$tag-K4"
    else
        echo fail > "$STATE_DIR/$tag.k4"; fail "$tag-K4" "time-loop not loaded within 5 minutes"
    fi
    date -u +%s > "$STATE_DIR/$tag.started"
}

cmd_start() {
    require_cost
    secret_check_file || exit 1
    secret_check_expiry $((MAIN_HOURS + 4)) || exit 1
    mkdir -p "$STATE_DIR"
    if [ -f "$STATE_DIR/main.container" ] && lxc info "$(cat "$STATE_DIR/main.container")" >/dev/null 2>&1; then
        die "a run already exists: $(cat "$STATE_DIR/main.container") (destroy it first)"
    fi
    autowp_require_lxc
    autowp_ensure_pool
    autowp_ensure_network
    local c
    c=autowp-c-l4-$(autowp_timestamp)
    echo "$c" > "$STATE_DIR/main.container"
    : > "$STATE_DIR/main.ratelimit"
    # On failure before the harness runs, delete the container; afterwards keep it.
    autowp_register "$c"
    autowp_install_trap
    start_run "$c" "$MAIN_HOURS" main
    AUTOWP_CONTAINERS=()   # the run continues: keep the container
    echo "INFO: started $c; follow it with: $0 status"
}

cmd_status() {
    local c S now started cycles fb commit pane limited=0 prev_t="" prev_l=""
    c=$(container)
    now=$(date -u +%s)
    started=$(cat "$STATE_DIR/main.started" 2>/dev/null || echo "$now")
    pane=$(harness_pane "$c" || true)
    if grep -qiE "$LIMIT_RE" <<<"$pane"; then echo "$now 1" >> "$STATE_DIR/main.ratelimit"
    else echo "$now 0" >> "$STATE_DIR/main.ratelimit"; fi
    while read -r t l; do
        if [ -n "$prev_t" ] && [ "$prev_l" = 1 ] && [ "$l" = 1 ]; then limited=$((limited + t - prev_t)); fi
        prev_t=$t; prev_l=$l
    done < "$STATE_DIR/main.ratelimit"
    echo "$limited" > "$STATE_DIR/main.ratelimited-seconds"
    S=$(state_json "$c" "$F")
    cycles=$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1]).get("cycles") or []))' "$S")
    fb=$(autowp_exec_user "$c" 'ls ~/foobar/grub-analysis-monitor-feedback-*.md 2>/dev/null | sort | tail -1' || true)
    commit=$(autowp_exec_user "$c" 'git -C ~/remote.git log --all -1 --format="%h %cI %s" 2>/dev/null' || true)
    echo "container:       $c"
    echo "elapsed:         $(( (now - started) / 3600 )) h $(( (now - started) % 3600 / 60 )) min"
    echo "harness running: $(harness_running "$c" && echo yes || echo no)"
    echo "cycles:          $cycles"
    echo "rate-limited:    $((limited / 60)) min (from $(wc -l < "$STATE_DIR/main.ratelimit") samples)"
    echo "latest feedback: ${fb:-none}"
    echo "last pushed:     ${commit:-none}"
}

cmd_attach() {
    local c
    c=$(container)
    exec lxc exec "$c" -t --user 1000 --group 1000 --env HOME=/home/ubuntu --env TERM="${TERM:-xterm}" \
        -- tmux attach -t "$HARNESS_SESSION"
}

cmd_stop() { harness_stop "$(container)"; echo "INFO: harness stopped; container kept"; }

cmd_restart() {
    require_cost
    local c
    c=$(container)
    secret_check_expiry 8 || exit 1
    harness_running "$c" && harness_stop "$c"
    secret_push "$c"
    harness_start "$c" /home/ubuntu/foobar "/time-loop grub $MAIN_HOURS"
    harness_confirm "$c" time-loop 300 && pass restart-K4 || fail restart-K4 "time-loop not loaded"
}

cmd_destroy() {
    local c
    c=$(container)
    lxc delete --force "$c"
    rm -f "$STATE_DIR"/main.*
    echo "INFO: deleted $c"
}

cmd_check() {
    local c S cycles ncommits nfb n expected_kind
    c=$(container)
    # C4.1: C3.1-C3.6, C3.8, C3.9 on this run
    if [ "$(cat "$STATE_DIR/main.k4" 2>/dev/null)" = pass ]; then pass C4.1-C3.1
    else fail C4.1-C3.1 "time-loop was not confirmed loaded at start (K4)"; fi
    local limited
    limited=$(cat "$STATE_DIR/main.ratelimited-seconds" 2>/dev/null || echo 0)
    # C3.7 with the rate-limited allowance is C4.2(a); the rest are C4.1.
    campaign_checks_c "$c" "$MAIN_HOURS" C4.1-C3. "$limited" C4.2a-bound
    S=$(state_json "$c" "$F")
    # C4.2: deadline stop (a) or true terminus (b)
    if [ "$(json_get "$S" gate_t_pass)" = true ]; then
        pass C4.2; info C4.2 "terminus stop (Gate-T PASS recorded)"; expected_kind=final
    else
        local last deadline
        deadline=$(json_get "$S" deadline)
        last=$(python3 -c 'import json,sys; w=json.loads(sys.argv[1]).get("wakes") or [0]; print(max(w))' "$S")
        if [ -n "$deadline" ] && [ "$last" -ge $(( deadline - 7200 )) ]; then
            pass C4.2; info C4.2 "deadline stop (rate-limited allowance $((limited / 60)) min)"
        else
            fail C4.2 "stopped before the deadline without a Gate-T PASS (a stop for an unallowed reason)"
        fi
        expected_kind=interim
    fi
    # C4.3
    cycles=$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1]).get("cycles") or []))' "$S")
    ncommits=$(autowp_exec_user "$c" 'git -C ~/remote.git rev-list --all 2>/dev/null | wc -l' || echo 0)
    check C4.3 "$ncommits commits for $cycles cycles" test "$ncommits" -ge "$cycles"
    # C4.4: feedback files numbered 01.. without gaps, one per verdict-change cycle
    nfb=$(autowp_exec_user "$c" 'ls ~/foobar/ 2>/dev/null | grep -E "^grub-analysis-monitor-feedback-[0-9]+\.md$" | sort' || true)
    n=0; local gap=""
    for f in $nfb; do
        n=$((n + 1))
        [ "$f" = "$(printf 'grub-analysis-monitor-feedback-%02d.md' "$n")" ] || gap="$gap $f"
    done
    local changes
    changes=$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1]).get("verdict_change_cycles") or []))' "$S")
    if [ -n "$gap" ]; then fail C4.4 "feedback numbering has gaps:$gap"
    elif [ "$changes" -gt 0 ] && [ "$n" -ne "$changes" ]; then
        fail C4.4 "$n feedback files for $changes verdict-change cycles"
    else
        pass C4.4
        [ "$changes" -eq 0 ] && info C4.4 "state file names no verdict-change cycles; only numbering checked"
    fi
    # C4.5
    if autowp_exec_user "$c" 'test -s ~/foobar/grub-analysis-found-issues.md'; then
        report_check_c "$c" C4.5 "$expected_kind"
        info C4.5 "grub.md versions pushed: $(autowp_exec_user "$c" 'git -C ~/remote.git log --all --oneline -- grub.md | wc -l')"
    else
        fail C4.5 "grub-analysis-found-issues.md missing"
    fi
    autowp_summary
}

# --- resume run (C4.6, C4.6b, C4.7, C4.8) ------------------------------------

onboarding_manifest() {
    autowp_exec_user "$1" 'cd ~/foobar/grub-analysis-acsl 2>/dev/null && \
        find . -maxdepth 2 -type f -iname "*onboard*" -printf "%T@ %p\n" | sort; \
        find . -maxdepth 2 -type f -iname "*onboard*" -print0 | sort -z | xargs -0 -r sha256sum'
}

wait_first_cycle() {
    local c=$1 i
    for i in $(seq 1 120); do   # up to 10 h
        sleep 300
        [ "$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1]).get("cycles") or []))' \
            "$(state_json "$c" "$F")")" -ge 1 ] && return 0
    done
    return 1
}

cmd_resume() {
    require_cost
    secret_check_file || exit 1
    secret_check_expiry 12 || exit 1
    mkdir -p "$STATE_DIR"
    autowp_require_lxc
    autowp_ensure_pool
    autowp_ensure_network
    autowp_install_trap
    local c S1 S2 S3 M1 M2 t_restart
    c=autowp-c-l4r-$(autowp_timestamp)
    start_run "$c" "$RESUME_HOURS" resume || { fail resume "harness did not start"; autowp_summary; exit 1; }
    wait_first_cycle "$c" || { fail C4.6 "no cycle recorded"; autowp_summary; exit 1; }
    harness_stop "$c"
    S1=$(state_json "$c" "$F"); M1=$(onboarding_manifest "$c")
    sleep 120
    t_restart=$(date -u +%s)
    secret_push "$c"; harness_start "$c" /home/ubuntu/foobar "/time-loop grub $RESUME_HOURS"
    wait_loop_stopped "$c" "$F" $((RESUME_HOURS * 3600 + 7200)) || true
    harness_stop "$c"
    S2=$(state_json "$c" "$F"); M2=$(onboarding_manifest "$c")
    # C4.6
    if [ "$(json_get "$S1" start)" != "$(json_get "$S2" start)" ] || [ -z "$(json_get "$S2" start)" ]; then
        fail C4.6 "start changed or missing: $(json_get "$S1" start) -> $(json_get "$S2" start)"
    elif [ "$(json_get "$S1" deadline)" != "$(json_get "$S2" deadline)" ]; then
        fail C4.6 "deadline changed: $(json_get "$S1" deadline) -> $(json_get "$S2" deadline) (restart at $t_restart)"
    elif ! python3 -c 'import json,sys; a=set(json.loads(sys.argv[1])["cycles"]); b=set(json.loads(sys.argv[2])["cycles"]); sys.exit(0 if a <= b and max(b) > max(a) else 1)' "$S1" "$S2"; then
        fail C4.6 "cycle counter did not continue: $(json_get "$S1" cycles) -> $(json_get "$S2" cycles)"
    else
        local last dl longest
        dl=$(json_get "$S2" deadline)
        last=$(python3 -c 'import json,sys; print(max(json.loads(sys.argv[1])["wakes"] or [0]))' "$S2")
        longest=$(python3 -c 'import json,sys; w=sorted(json.loads(sys.argv[1])["wakes"]); print(max([b-a for a,b in zip(w,w[1:])] or [0]))' "$S2")
        if [ "$last" -le $((dl + longest)) ]; then pass C4.6
        else fail C4.6 "did not stop by the original deadline plus one cycle"; fi
        info C4.6 "work-list statuses are not compared automatically; see the saved states in $STATE_DIR"
    fi
    printf '%s\n' "$S1" > "$STATE_DIR/resume-state-1.json"; printf '%s\n' "$S2" > "$STATE_DIR/resume-state-2.json"
    # C4.7
    if [ -z "$M1" ]; then fail C4.7 "no onboarding package (*onboard*) found in grub-analysis-acsl/"
    else check C4.7 "onboarding package changed after the restart" test "$M1" = "$M2"; fi
    # C4.6b: restart after the deadline
    local cycles_before t0
    cycles_before=$(json_get "$S2" cycles)
    t0=$(date -u +%s)
    secret_push "$c"; harness_start "$c" /home/ubuntu/foobar "/time-loop grub $RESUME_HOURS"
    IDLE_S=600 wait_loop_stopped "$c" "$F" 1800 || true
    harness_stop "$c"
    S3=$(state_json "$c" "$F")
    if [ "$(json_get "$S3" cycles)" != "$cycles_before" ]; then fail C4.6b "a new cycle was started after the deadline"
    elif [ "$(json_get "$S3" deadline)" != "$(json_get "$S2" deadline)" ]; then fail C4.6b "deadline changed"
    elif [ $(( $(date -u +%s) - t0 )) -gt 2400 ]; then fail C4.6b "did not stop within 30 minutes"
    elif ! autowp_exec_user "$c" "test ~/foobar/grub.md -nt ~/.autowp-harness-start"; then fail C4.6b "grub.md not rewritten"
    else pass C4.6b; fi
    # C4.8: --dir on the existing campaign
    secret_push "$c"; harness_start "$c" /home/ubuntu/foobar "/time-loop grub 1 --dir=grub-core/fs"
    wait_loop_stopped "$c" "$F" $((3 * 3600)) || true
    harness_stop "$c"
    local scope
    scope=$(json_get "$(state_json "$c" "$F")" scope)
    case "$scope" in
        grub/grub-core/fs|grub/grub-core/fs/) pass C4.8
            info C4.8 "units worked on are not checked automatically against the scope; see the transcript" ;;
        *) fail C4.8 "state file scope is '${scope:-none}', expected grub/grub-core/fs" ;;
    esac
    autowp_summary
}

case "$SUB" in
    start) cmd_start ;;
    status) cmd_status ;;
    attach) cmd_attach ;;
    check) cmd_check ;;
    stop) cmd_stop ;;
    restart) cmd_restart ;;
    destroy) cmd_destroy ;;
    resume) cmd_resume ;;
    ""|-h|--help|help) usage ;;
    *) echo "unknown sub-command: $SUB" >&2; usage ;;
esac
