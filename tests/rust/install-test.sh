#!/usr/bin/env bash
# Level 2, Rust (tests.md 6.2): auto-wp.py --rust with the stock
# ubuntu:24.04 python3 and git, in a fresh container.
#
#   tests/rust/install-test.sh         KEEP=1 keeps the container
#
# Expected skills: the 19 of auto-wp.md 4.3.2, minus the pending roadmap
# skills whose template is absent (auto-wp.md 4.3.7: "Until a step is done,
# its files are absent"). Today that is creusot-launch (step 1); it is
# reported as SKIP, not passed silently.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib/lxc.sh
. "$HERE/../lib/lxc.sh"

T=$AUTOWP_REPO/templates
COMMON_SPEC=(directory-structure ebios-risk-manager ebios-sl fips-sl lean polish-skill rmf-sl rocq stride workshop)
RUST_SPEC=(creusot creusot-launch creusot-monitoring creusot-sl sl-auditor sl-builder sl-internal sl-monitoring-sl time-loop)
PENDING=(creusot-launch)   # roadmap step 1 (auto-wp.md 4.3.7)

is_pending() { local p; for p in "${PENDING[@]}"; do [ "$p" = "$1" ] && return 0; done; return 1; }

# Derive the expected set on the host, before starting anything.
expected=() absent_pending=() absent_other=()
for s in "${COMMON_SPEC[@]}"; do
    if [ -d "$T/common/skills/$s" ]; then expected+=("$s"); else absent_other+=("common/$s"); fi
done
for s in "${RUST_SPEC[@]}"; do
    if [ -d "$T/rust/skills/$s" ]; then expected+=("$s")
    elif is_pending "$s"; then absent_pending+=("$s")
    else absent_other+=("rust/$s"); fi
done
expected_sorted=$(printf '%s\n' "${expected[@]}" | LC_ALL=C sort)
n_expected=${#expected[@]}

autowp_require_lxc
autowp_install_trap
autowp_ensure_pool
autowp_ensure_network

C=autowp-rust-l2-$(autowp_timestamp)
autowp_launch_fresh "$C"
autowp_wait_ready "$C"
autowp_egress_check "$C"
autowp_push_project "$C"
info versions "$(autowp_exec_user "$C" 'python3 --version; git --version' | tr '\n' ' ')"

for s in "${absent_pending[@]}"; do
    skip "R2.1-$s" "$s not written yet (auto-wp.md 4.3.7 roadmap step 1); expecting $n_expected skills instead of 19"
done
if [ "${#absent_other[@]}" -gt 0 ]; then
    fail R2.1-templates "templates missing for skills of auto-wp.md 4.3.2 that are not pending: ${absent_other[*]}"
fi

# --- R2.1 ------------------------------------------------------------------
set +e
out=$(autowp_exec_user "$C" "cd ~ && python3 auto-wp/auto-wp.py --rust --harness '$HARNESS' foobar" 2>&1)
rc=$?
set -e
printf '%s\n' "$out" | sed 's/^/    | /'
installed=$(autowp_exec_user "$C" 'cd ~/foobar/config/skills 2>/dev/null && for d in */; do echo "${d%/}"; done' | LC_ALL=C sort || true)
if [ "$rc" -ne 0 ]; then
    fail R2.1 "auto-wp.py --rust foobar exited $rc"
elif ! grep -qx "  skills:   $n_expected" <<<"$out"; then
    fail R2.1 "output lacks 'skills:   $n_expected'"
elif ! grep -qx '  commands: 1' <<<"$out"; then
    fail R2.1 "output lacks 'commands: 1'"
elif [ "$installed" != "$expected_sorted" ]; then
    fail R2.1 "installed skills differ: $(diff <(echo "$expected_sorted") <(echo "$installed") | grep '^[<>]' | tr '\n' ' ')"
else
    pass R2.1
fi
if [ "${#absent_pending[@]}" -eq 0 ]; then
    check R2.1-19 "spec count is 19" grep -qx '  skills:   19' <<<"$out"
fi

# --- R2.2 ------------------------------------------------------------------
if ! autowp_exec_user "$C" 'test -f ~/foobar/README.md'; then
    fail R2.2 "foobar/README.md does not exist"
elif ! autowp_exec_user "$C" 'grep -q creusot-launch ~/foobar/README.md'; then
    fail R2.2 "README does not mention creusot-launch"
else
    pass R2.2
fi
case $HARNESS in
    claude) install_url=https://claude.ai/install.sh; start_line='claude --dangerously-skip-permissions' ;;
    opencode) install_url=https://opencode.ai/v2/install; start_line=opencode ;;
esac
check R2.2-harness "README lacks the selected $HARNESS install/start lines" \
    autowp_exec_user "$C" "grep -qF '$install_url' ~/foobar/README.md && grep -qxF '$start_line' ~/foobar/README.md"

# --- R2.3 ------------------------------------------------------------------
top=$(autowp_exec_user "$C" 'git -C ~/foobar rev-parse --show-toplevel' 2>/dev/null || true)
check R2.3 "foobar is not a git work tree (toplevel: '$top')" test "$top" = /home/ubuntu/foobar

# --- R2.4 ------------------------------------------------------------------
before=$(autowp_manifest "$C" /home/ubuntu/foobar .git)
set +e
autowp_exec_user "$C" "cd ~ && python3 auto-wp/auto-wp.py --rust --harness '$HARNESS' foobar" >/dev/null 2>&1
again_rc=$?
set -e
after=$(autowp_manifest "$C" /home/ubuntu/foobar .git)
if [ "$again_rc" -ne 1 ]; then
    fail R2.4 "second run exited $again_rc, expected 1"
elif [ "$before" != "$after" ]; then
    fail R2.4 "second run changed foobar: $(diff <(echo "$before") <(echo "$after") | head -5 | tr '\n' ' ')"
else
    pass R2.4
fi

autowp_summary
