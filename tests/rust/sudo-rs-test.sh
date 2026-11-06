#!/usr/bin/env bash
# Level 3, Rust (sudo-rs-test.md, tests.md 6.5): a time-boxed Creusot
# campaign on sudo-rs v0.2.15, driven by creusot-monitoring through the
# interactive harness. The Rust counterpart of tests/c/gzip-test.sh.
#
#   tests/rust/sudo-rs-test.sh             in a copy of autowp-rust-base/ready
#   WORKSHOP=1 tests/rust/sudo-rs-test.sh  in the generated project's workshop,
#                                          the toolchain from the creusot SDK
#   KEEP=1                                 keeps the container, or the
#                                          workshop and its project
#   SUDORS_HOURS=<n>                       the budget (default 2): the run is
#                                          stopped at n hours + 30 min
#   SETUP_ONLY=1                           stops after S.0 (and W.1-W.3): no
#                                          token, minutes instead of hours
#   WORKSHOP_BASE, WORKSHOP_TRY, WORKSHOP_DIR   see tests/lib/workshop.sh
#
# Until creusot-launch exists (auto-wp.md 4.3.7 roadmap step 1), the request
# asks creusot-monitoring for the overlay itself (sudo-rs-test.md 3). It also
# asks for the code-blind RMF risk study (rmf-sl), checked by S.8 with
# bin/rmf-lint.sh as the C test's G.3 does.
# Needs the Claude token (tests.md 7, AUTOWP_TOKEN_FILE) unless SETUP_ONLY=1.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib/lxc.sh
. "$HERE/../lib/lxc.sh"
# shellcheck source=../lib/secret.sh
. "$HERE/../lib/secret.sh"

SUDORS_URL=https://github.com/trifectatechfoundation/sudo-rs.git
SUDORS_TAG=v0.2.15
SUDORS_COMMIT=e4cfa9cf7b71e287dd5046633c0f5276072d147d   # v0.2.15^{}, read 2026-11-05

WORKSHOP=${WORKSHOP:-0}
SETUP_ONLY=${SETUP_ONLY:-0}
HOURS=${SUDORS_HOURS:-2}
CAMPAIGN_PROJECT=sudo-rs-analyze
if [ "$WORKSHOP" = 1 ]; then
    # shellcheck source=../lib/workshop.sh
    . "$HERE/../lib/workshop.sh"
    ws_init "$CAMPAIGN_PROJECT"
fi
CAMPAIGN_SRC=sudo-rs
CAMPAIGN_SRC_KIND=repo
CAMPAIGN_COMMIT_FILE=.autowp-sudors-commit
# shellcheck source=../lib/harness.sh
. "$HERE/../lib/harness.sh"
D=$CAMPAIGN_DIR
OVERLAY=sudo-rs-creusot
RMF_REPORT=sudo-rs-analysis-rmf-report.md   # the code-blind risk study (S.8)
CARGO_ENV='[ -f ~/.cargo/env ] && . ~/.cargo/env;'

REQUEST="Analyze the crate sudo-rs in directory sudo-rs with creusot-monitoring. \
Guidance: a security audit. First, before anything reads the code, have a fresh sub-agent that \
never sees sudo-rs/ write a code-blind NIST RMF risk study of sudo-rs with the rmf-sl skill to \
$RMF_REPORT, next to sudo-rs/; it must pass bin/rmf-lint.sh $RMF_REPORT. creusot-monitoring \
then uses its risk levels to rank what to prove. Never modify sudo-rs/; put every Creusot artifact in the overlay \
$OVERLAY/ next to it, a Cargo workspace of its own that depends on creusot-std (see \
config/skills/creusot/references/install.md), since creusot-launch is not available. \
Rank files by exposure to untrusted input: the sudoers parser (src/sudoers) and command-line \
parsing first. Prove absence of panics, overflows and out-of-bounds accesses; treat \
sudo-rs/proofs/sudoers.mlw as a reference model of the sudoers policy. Record PAM, exec, \
terminal and other FFI or system-state code as out of reach rather than modelling it. \
You have $HOURS hour(s): before they end, write the report of the run to sudo-rs.md, next \
to sudo-rs/ (what was proved, what failed, what is out of reach, and the architecture findings)."

# S.0: the clone is the pinned commit with the expected layout.
s0() {
    local c=$1 out
    if out=$(autowp_exec_user "$c" "set -e; touch ~/.autowp-t0; sleep 1
        cd '$D'
        git clone -q --branch $SUDORS_TAG --depth 1 $SUDORS_URL sudo-rs 2>&1
        cd sudo-rs
        [ \"\$(git rev-parse HEAD)\" = $SUDORS_COMMIT ] || { echo \"HEAD is \$(git rev-parse HEAD), expected $SUDORS_COMMIT\"; exit 2; }
        grep -qx 'name = \"sudo-rs\"' Cargo.toml && [ -d src/sudoers ] && [ -f proofs/sudoers.mlw ] \
            || { echo 'unexpected layout'; exit 2; }
        git rev-parse HEAD > ~/$CAMPAIGN_COMMIT_FILE
        cd ..
        git init -q --bare ~/remote.git
        git remote add origin ~/remote.git" 2>&1); then
        pass S.0
    else
        fail S.0 "$(tail -2 <<<"$out" | tr '\n' ' ')"
        autowp_summary
        exit 2
    fi
}

# W.3: the toolchain is the creusot SDK's.
w3() {
    local out
    out=$(autowp_exec_user "$WS" "$CARGO_ENV cargo creusot version 2>&1 | head -3; command -v cargo-creusot; echo \"src=\$CREUSOT_SDK_SRC commit=\$CREUSOT_SDK_COMMIT\"" 2>&1) || true
    if grep -q '^cargo-creusot 0\.15' <<<"$out" && grep -q '^src=/opt/creusot/' <<<"$out"; then
        pass W.3; info W.3 "$(grep '^src=' <<<"$out")"
    else
        fail W.3 "cargo creusot from the creusot SDK not found: $(tr '\n' ' ' <<<"$out")"
    fi
}

# --- setup ---------------------------------------------------------------------

[ "$SETUP_ONLY" = 1 ] || secret_check_file || exit 1
if [ "$WORKSHOP" = 1 ]; then
    C=$WS
    ws_generate rust creusot || { autowp_summary; exit 1; }
    ws_adapt libpam0g-dev      # sudo-rs links libpam (its README)
    ws_launch || { autowp_summary; exit 1; }
    w3
    ws_egress
    [ "$SETUP_ONLY" = 1 ] || ws_install_claude
else
    autowp_require_lxc
    autowp_install_trap
    autowp_ensure_pool
    autowp_ensure_network
    C=autowp-rust-sudors-$(autowp_timestamp)
    autowp_copy_snapshot autowp-rust-base ready "$C"
    autowp_wait_ready "$C"
    autowp_egress_check "$C"
    autowp_exec_root "$C" sh -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y -q libpam0g-dev >/dev/null' \
        || die "could not install libpam0g-dev"
    autowp_push_project "$C"
    autowp_exec_user "$C" "python3 auto-wp/auto-wp.py --rust $CAMPAIGN_PROJECT >/dev/null"
fi
s0 "$C"
# sudo-rs builds here, as shipped (libpam found): the baseline for the overlay.
if out=$(autowp_exec_user "$C" "$CARGO_ENV cd '$D/sudo-rs' && cargo build -q --target-dir /tmp/sudors-target 2>&1 | tail -3"); then
    info S.0 "sudo-rs builds as shipped"
else
    info S.0 "sudo-rs does not build as shipped: $(tr '\n' ' ' <<<"$out")"
fi
if [ "$SETUP_ONLY" = 1 ]; then
    info setup "SETUP_ONLY=1: stopping before the campaign"
    autowp_summary
    exit
fi

# --- the campaign ----------------------------------------------------------------

secret_push "$C"
if ! harness_start "$C" "$D" "$REQUEST"; then
    fail S.1 "harness did not start"
    autowp_summary
    exit 1
fi
if harness_confirm "$C" creusot-monitoring 600; then pass S.1
else fail S.1 "creusot-monitoring not loaded within 10 minutes (K4)"; fi

# No time-loop for Rust: stop at the budget plus 30 minutes for the report,
# or earlier when the transcript has been idle for IDLE_S (default 1800 s).
wait_loop_stopped "$C" "$D/sudo-rs.md" $(( HOURS * 3600 + 1800 )) || true
harness_pane "$C" | tail -15 | sed 's/^/    | /'
harness_stop "$C"

# --- checks (sudo-rs-test.md 5) ---------------------------------------------------

# S.2 K1: sudo-rs/ is the pinned commit, unchanged, with no Creusot file in it.
base=$(autowp_exec_user "$C" "cat ~/$CAMPAIGN_COMMIT_FILE")
k1 "$C" "$D/sudo-rs" "$base" S.2
if autowp_exec_user "$C" "cd '$D/sudo-rs' && [ ! -e why3find.json ] && ! git status --porcelain --ignored | grep -qE '(why3find\\.json|\\.gitignore|\\.coma)\$'"; then :
else fail S.2-overlay "Creusot files written inside sudo-rs/"; fi

# S.3: the overlay is a workspace of its own that depends on creusot-std.
check S.3 "$OVERLAY/ missing, not a [workspace], or no creusot-std dependency" \
    autowp_exec_user "$C" "cd '$D' && test -f $OVERLAY/Cargo.toml \
        && grep -q '^\\[workspace\\]' $OVERLAY/Cargo.toml && grep -rqs 'creusot-std' $OVERLAY/Cargo.toml $OVERLAY/*/Cargo.toml"

# S.4: `cargo creusot` in the overlay, run by the test: at least one goal proved.
out=$(autowp_exec_user "$C" "$CARGO_ENV cd '$D/$OVERLAY' 2>/dev/null && timeout 1800 cargo creusot >/tmp/s4.log 2>&1; echo rc=\$?; \
    grep -c '^Proved ' /tmp/s4.log; grep -ciE 'proof failed|not proved|unknown' /tmp/s4.log" 2>&1) || true
read -r rc proved failed <<<"$(tr '\n' ' ' <<<"$out")"
info S.4 "cargo creusot ${rc:-rc=?}; Proved lines: ${proved:-0}; failed/unknown lines: ${failed:-0}"
if [ "${proved:-0}" -ge 1 ] 2>/dev/null; then pass S.4
else fail S.4 "no goal proved by cargo creusot in $OVERLAY/ (see /tmp/s4.log in the guest)"; fi

# S.5: the run's report, next to sudo-rs/; INFO on the architecture report.
check S.5 "sudo-rs.md missing or empty" autowp_exec_user "$C" "test -s '$D/sudo-rs.md'"
info S.5 "architecture report: $(autowp_exec_user "$C" "cd '$D' && grep -rliE 'architecture|attack surface' --include='*.md' . 2>/dev/null \
    | grep -vE '^\\./(config|sudo-rs)/' | head -3 | tr '\n' ' '")"
info S.5 "routed: $(autowp_exec_user "$C" "cd '$D' && find config/skills/creusot-monitoring/getting-better config/skills/creusot-monitoring/bugs-to-report \
    -name '*.md' -newer ~/.autowp-t0 2>/dev/null | wc -l") new getting-better/bugs-to-report file(s)"

# S.6 K2, S.7 K3 (informational).
secret_k2 "$C" S.6
k3 "$C" S.7

# S.8: the code-blind RMF risk study, as the C test's G.3: present, not
# empty, and bin/rmf-lint.sh (structure, chaining, endogeneity) exits 0 on it.
if ! autowp_exec_user "$C" "test -s '$D/$RMF_REPORT'"; then
    fail S.8 "$RMF_REPORT missing or empty"
elif ! out=$(autowp_exec_user "$C" "cd '$D' && bin/rmf-lint.sh $RMF_REPORT 2>&1"); then
    fail S.8 "bin/rmf-lint.sh fails on $RMF_REPORT: $(grep -E '^ *FAIL' <<<"$out" | head -3 | tr -s ' \n' ' ')"
else
    pass S.8
fi

autowp_summary
