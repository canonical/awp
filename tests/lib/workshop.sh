#!/usr/bin/env bash
# Runs a level 3 campaign in the workshop of a project generated on the host
# (gzip-test.md 7, sudo-rs-test.md 4). Source it after lib/lxc.sh and before
# lib/harness.sh, and call ws_init first: it switches the in-guest helpers of
# lib/lxc.sh to `workshop exec` and sets CAMPAIGN_DIR=/project.
#
#   ws_init <project-name>          WS_PARENT, WS_PROJECT, WS; trap ws_cleanup
#   ws_generate <c|rust> <sdk>      W.1: auto-wp.py on the host, the definition
#   ws_adapt <apt-package>...       the test's edits of the generated files
#   ws_launch                       W.2: workshop launch, status ready
#   ws_egress                       gitlab.freedesktop.org and github.com
#   ws_install_claude               step 2 of the README's quick start A
#
# Environment:
#   WORKSHOP_BASE=ubuntu@26.04   rewrites `base:` of the generated definition
#   WORKSHOP_TRY="rocq lean"     try-<name> (packed with `sdkcraft try` on this
#                                host) instead of the Store, for SDKs not
#                                released yet
#   WORKSHOP_DIR=<dir>           where the project is generated (default a new
#                                directory under ~/.awp, removed at the end;
#                                on disk, since /tmp may be a tmpfs and a
#                                campaign's work would then be lost on reboot)
#   KEEP=1                       keeps the workshop and the project

WS=autowp                       # the workshop name auto-wp.py writes

ws() { workshop -p "$WS_PROJECT" "$@"; }

ws_init() {
    local name=$1
    command -v workshop >/dev/null || die "workshop not found (sudo snap install --classic workshop)"
    if [ -n "${WORKSHOP_DIR:-}" ]; then WS_PARENT=$WORKSHOP_DIR WS_OWN=0
    else
        mkdir -p "$HOME/.awp"
        WS_PARENT=$(mktemp -d "$HOME/.awp/autowp-$name-ws.XXXXXX") WS_OWN=1
    fi
    WS_PROJECT=$WS_PARENT/$name
    autowp_use_workshop "$WS_PROJECT"
    CAMPAIGN_DIR=/project
    CAMPAIGN_GENERATED=1
    trap ws_cleanup EXIT
    trap 'exit 130' INT TERM
}

ws_cleanup() {
    local status=$?
    if [ "${KEEP:-0}" = 1 ]; then
        echo "INFO: cleanup: KEEP=1, keeping workshop $WS and $WS_PROJECT" \
             "(cd $WS_PROJECT && workshop shell; workshop remove $WS)" >&2
    else
        if [ -d "$WS_PROJECT/.workshop" ]; then ws remove "$WS" >/dev/null 2>&1 || true; fi
        # The workshop wrote as the host user (uid 1000 mapping), so this works.
        # A WORKSHOP_DIR given by the user is the user's: only the project goes.
        if [ "$WS_OWN" = 1 ]; then rm -rf "$WS_PARENT"; else rm -rf "$WS_PROJECT"; fi
        echo "--- removed workshop $WS and $WS_PROJECT" >&2
    fi
    return "$status"
}

# ws_generate <c|rust> <sdk>: W.1. auto-wp.py on the host, as the README's
# quick start A says; the definition lists <sdk>, rocq, lean and the
# project-local SDK.
ws_generate() {
    local lang=$1 sdk=$2 def out s missing=""
    out=$(python3 "$AUTOWP_REPO/auto-wp.py" "--$lang" "$WS_PROJECT" 2>&1) \
        || { fail W.1 "auto-wp.py failed: $(tail -2 <<<"$out" | tr '\n' ' ')"; return 1; }
    def=$WS_PROJECT/.workshop/autowp.yaml
    [ -f "$def" ] && grep -qx 'name: autowp' "$def" || missing=" name:autowp"
    for s in "$sdk" rocq lean project-autowp-packages; do
        grep -qE "^ +- name: $s( |\$)" "$def" 2>/dev/null || missing="$missing $s"
    done
    [ -x "$WS_PROJECT/.workshop/autowp-packages/hooks/setup-base" ] || missing="$missing setup-base"
    if [ -z "$missing" ]; then pass W.1
    else fail W.1 "$def lacks:$missing"; return 1; fi
}

# ws_adapt <apt-package>...: the test's edits of the generated files, each
# reported as INFO: the base, try- SDKs, and the apt packages the code under
# study needs (the README tells users to edit setup-base for their code).
ws_adapt() {
    local def=$WS_PROJECT/.workshop/autowp.yaml hook=$WS_PROJECT/.workshop/autowp-packages/hooks/setup-base s
    if [ -n "${WORKSHOP_BASE:-}" ]; then
        sed -i "s/^base: [^ ]*/base: $WORKSHOP_BASE/" "$def"
        info W.1 "base set to $WORKSHOP_BASE (WORKSHOP_BASE)"
    fi
    for s in ${WORKSHOP_TRY:-}; do
        python3 - "$def" "$s" <<'PY' || die "WORKSHOP_TRY: no Store entry for $s"
import re, sys
p, s = sys.argv[1], sys.argv[2]
t = open(p).read()
t2 = re.sub(r"(?m)^( +- name: )%s(\b[^\n]*)\n +channel: [^\n]*\n" % re.escape(s), r"\1try-%s\2\n" % s, t)
if t2 == t:
    sys.exit(1)
open(p, "w").write(t2)
PY
        info W.1 "$s replaced by try-$s (WORKSHOP_TRY)"
    done
    if [ $# -gt 0 ]; then
        sed -i "s/^apt-get install tmux curl/apt-get install tmux curl $*/" "$hook"
        grep -q "^apt-get install tmux curl $*" "$hook" || die "could not add $* to $hook"
        info W.1 "added to .workshop/autowp-packages/hooks/setup-base: $*"
    fi
}

# W.2: launch, and the workshop reaches `ready` (every SDK's check-health).
ws_launch() {
    local t0 out
    t0=$(date +%s)
    note "workshop launch $WS in $WS_PROJECT (downloads the SDKs)"
    if ! out=$(ws launch "$WS" 2>&1); then
        fail W.2 "workshop launch failed: $(tail -3 <<<"$out" | tr '\n' ' ')"
        ws changes 2>&1 | tail -5 | sed 's/^/    | /'
        return 1
    fi
    info W.2 "launched in $(( $(date +%s) - t0 )) s"
    out=$(ws info "$WS" 2>&1)
    sed -n '/^sdks:/,$p' <<<"$out" | sed 's/^/    | /'
    if grep -qE '^status: +ready' <<<"$out"; then pass W.2
    else fail W.2 "workshop not ready: $(grep -E '^(status|notes):' <<<"$out" | tr '\n' ' ')"; return 1; fi
}

# Egress, as autowp_egress_check does for a container; exits on failure.
ws_egress() {
    local u
    for u in https://gitlab.freedesktop.org https://github.com; do
        if autowp_exec_user "$WS" "curl -sSfI --max-time 30 $u >/dev/null"; then
            info egress "$u reachable from the workshop"
        else
            fail egress "the workshop cannot reach $u"; autowp_summary; exit 1
        fi
    done
}

# The agent harness, as step 2 of the README's quick start A; exits on
# failure. HARNESS picks the binary (default claude).
ws_install_claude() {
    local out
    if out=$(autowp_exec_user "$WS" 'curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1; . ~/.profile; claude --version' 2>&1); then
        info setup "Claude Code $(tail -1 <<<"$out")"
    else
        fail setup "Claude Code install failed: $(tail -2 <<<"$out" | tr '\n' ' ')"; autowp_summary; exit 1
    fi
}

ws_install_opencode() {
    local out
    if out=$(autowp_exec_user "$WS" 'curl -fsSL https://opencode.ai/install | bash >/dev/null 2>&1; . ~/.profile; opencode --version' 2>&1); then
        info setup "OpenCode $(tail -1 <<<"$out")"
    else
        fail setup "OpenCode install failed: $(tail -2 <<<"$out" | tr '\n' ' ')"; autowp_summary; exit 1
    fi
}

# ws_install_harness: the ws_install_* call matching $HARNESS.
ws_install_harness() {
    case ${HARNESS:-claude} in
        opencode) ws_install_opencode ;;
        *)        ws_install_claude ;;
    esac
}
