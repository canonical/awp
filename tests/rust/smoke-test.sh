#!/usr/bin/env bash
# Level 3, Rust (tests.md 6.4): creusot-launch + creusot-monitoring on a
# small crate, in a copy of autowp-rust-base/ready, through the harness.
#
#   MYCRATE_URL=<url> MYCRATE_COMMIT=<sha> tests/rust/smoke-test.sh
#
# Until creusot-launch exists (auto-wp.md 4.3.7 roadmap step 1) it prints
# SKIP and exits 0. The crate is still to be chosen (tests.md 8, item 8):
# a small crate with no dependencies, pinned by URL and commit.
#
# Environment: KEEP=1, AUTOWP_TOKEN_FILE (lib/secret.sh), SMOKE_HOURS (hard
# limit for the run, default 4).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib/lxc.sh
. "$HERE/../lib/lxc.sh"
# shellcheck source=../lib/secret.sh
. "$HERE/../lib/secret.sh"
# shellcheck source=../lib/harness.sh
. "$HERE/../lib/harness.sh"

if [ ! -d "$AUTOWP_REPO/templates/rust/skills/creusot-launch" ]; then
    echo "SKIP: creusot-launch not written yet"
    exit 0
fi
if [ -z "${MYCRATE_URL:-}" ] || [ -z "${MYCRATE_COMMIT:-}" ]; then
    echo "FAIL: setup: no crate chosen; set MYCRATE_URL and MYCRATE_COMMIT (tests.md 6.4, 8 item 8)"
    exit 1
fi
secret_check_file || exit 1

REQUEST="onboard the crate mycrate with creusot-launch, then analyze it with creusot-monitoring"
LIMIT=$(( ${SMOKE_HOURS:-4} * 3600 ))

autowp_require_lxc
autowp_install_trap
autowp_ensure_pool
autowp_ensure_network

C=autowp-rust-l3-$(autowp_timestamp)
autowp_copy_snapshot autowp-rust-base ready "$C"
autowp_wait_ready "$C"
autowp_egress_check "$C"
autowp_push_project "$C"
autowp_exec_user "$C" "set -e; touch ~/.autowp-t0; sleep 1
    python3 auto-wp/auto-wp.py --rust foobar
    cd foobar
    git clone -q '$MYCRATE_URL' mycrate
    git -C mycrate checkout -q '$MYCRATE_COMMIT'
    git init -q --bare ~/remote.git
    git remote add origin ~/remote.git"
base_commit=$(autowp_exec_user "$C" 'git -C ~/foobar/mycrate rev-parse HEAD')

secret_push "$C"
harness_start "$C" /home/ubuntu/foobar "$REQUEST" || { fail R4.0 "harness did not start"; autowp_summary; exit 1; }
if harness_confirm "$C" creusot-launch 300; then pass R4.0-K4; else fail R4.0-K4 "creusot-launch not loaded within 5 minutes"; fi

# Wait: the request is a single task; done when the transcript has been idle
# for 20 minutes, or at the hard limit.
start=$(date +%s)
while :; do
    sleep 300
    now=$(date +%s)
    [ $((now - start)) -ge "$LIMIT" ] && { info wait "hard limit reached"; break; }
    idle=$(autowp_exec_user "$C" "case $HARNESS in
        opencode) t=~/.local/share/opencode/opencode.db ;;
        *) t=\$(ls -t ~/.claude/projects/*/*.jsonl | head -1) ;;
    esac; echo \$( (\$(date +%s) - \$(stat -c %Y \"\$t\")) )")
    [ "$idle" -ge 1200 ] && break
done
harness_stop "$C"

# R4.1
check R4.1 "overlay mycrate-creusot/ with [workspace] and why3find.json missing" \
    autowp_exec_user "$C" 'cd ~/foobar && test -d mycrate-creusot \
        && grep -q "^\[workspace\]" mycrate-creusot/Cargo.toml && test -f mycrate-creusot/why3find.json'
# R4.2 (K1 on mycrate/, plus no why3find.json/.gitignore added)
check R4.2 "mycrate/ changed" autowp_exec_user "$C" "cd ~/foobar/mycrate \
    && [ \"\$(git rev-parse HEAD)\" = '$base_commit' ] && git diff --quiet HEAD \
    && [ -z \"\$(git status --porcelain --untracked-files=no)\" ] \
    && ! git status --porcelain --ignored | grep -qE '(why3find\.json|\.gitignore)\$' \
    && [ ! -e why3find.json ]"
# R4.3
check R4.3 "cargo creusot fails in the overlay" \
    autowp_exec_user "$C" '. ~/.cargo/env; cd ~/foobar/mycrate-creusot && cargo creusot >/tmp/r43.log 2>&1'
# R4.4
pkg=$(autowp_exec_user "$C" 'cd ~/foobar && grep -rliE "onboarding" --include="*.md" . 2>/dev/null | grep -v "^./config/" | grep -v "^./mycrate/" | head -1')
if [ -z "$pkg" ]; then
    fail R4.4 "no onboarding package found"
else
    for w in "toolchain|version" "trusted" "faithfulness"; do
        check "R4.4-${w%%|*}" "onboarding package $pkg lacks '$w'" \
            autowp_exec_user "$C" "grep -qiE '$w' ~/foobar/$pkg"
    done
fi
# R4.5
secret_k2 "$C" R4.5-K2
info R4.5-K3 "$(autowp_exec_user "$C" 'find ~ /tmp -xdev -newer ~/.autowp-t0 -type f 2>/dev/null \
    | grep -vE "^/home/ubuntu/(foobar|\.claude|\.opencode|\.cache|\.local/share/claude|\.local/share/opencode|\.local/state/opencode|\.config|\.cargo|\.rustup|\.opam|\.local/share/creusot|remote\.git|\.bash_history|\.gitconfig|\.claude\.json)|^/tmp/" | head -20 | tr "\n" " "')"

autowp_summary
