#!/usr/bin/env bash
# Level 2, C (tests.md 5.2): auto-wp.py --c with the stock ubuntu:24.04
# python3 and git, then the README's clone step, in a fresh container.
#
#   tests/c/install-test.sh            KEEP=1 keeps the container
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib/lxc.sh
. "$HERE/../lib/lxc.sh"

autowp_require_lxc
autowp_install_trap
autowp_ensure_pool
autowp_ensure_network

C=autowp-c-l2-$(autowp_timestamp)
autowp_launch_fresh "$C"
autowp_wait_ready "$C"
autowp_egress_check "$C"
autowp_push_project "$C"
info versions "$(autowp_exec_user "$C" 'python3 --version; git --version' | tr '\n' ' ')"

# The quick-start lines this test runs, from the directory containing foobar.
CLONE_URL=https://gitlab.freedesktop.org/gnu-grub/grub.git
RUN_LINES=("cd foobar" "git clone $CLONE_URL")

# --- C2.1 ------------------------------------------------------------------
set +e
out=$(autowp_exec_user "$C" 'cd ~ && python3 auto-wp/auto-wp.py --c foobar' 2>&1)
rc=$?
set -e
printf '%s\n' "$out" | sed 's/^/    | /'
if [ "$rc" -ne 0 ]; then
    fail C2.1 "auto-wp.py --c foobar exited $rc"
elif ! grep -qx '  skills:   23' <<<"$out"; then
    fail C2.1 "output lacks 'skills:   23'"
elif ! grep -qx '  commands: 3' <<<"$out"; then
    fail C2.1 "output lacks 'commands: 3'"
else
    pass C2.1
fi

# --- C2.2 (README check) and running its lines --------------------------------
# The in-container block of the quick start (step 2) is the one that starts
# with `cd foobar`; it must start with the lines run here and end with claude.
readme_block=$(autowp_exec_user "$C" "awk '
    /^## Quick start/ { q = 1; next }
    q && /^## / { exit }
    q && /^\`\`\`/ { if (inb) { inb = 0; if (keep) exit; next } inb = 1; first = 1; next }
    q && inb && first { first = 0; keep = (\$0 == \"cd foobar\") }
    q && inb && keep { print }' ~/foobar/README.md" || true)
head_lines=$(printf '%s\n' "$readme_block" | head -n "${#RUN_LINES[@]}")
last_line=$(printf '%s\n' "$readme_block" | tail -n 1)
expected=$(printf '%s\n' "${RUN_LINES[@]}")
if ! autowp_exec_user "$C" 'test -f ~/foobar/README.md'; then
    fail C2.2 "foobar/README.md does not exist"
elif [ "$head_lines" != "$expected" ]; then
    fail C2.2 "in-container quick-start block does not start with the lines run: $(echo "$readme_block" | head -3 | tr '\n' '|')"
elif [ "$last_line" != "claude --dangerously-skip-permissions" ]; then
    fail C2.2 "in-container quick-start block does not end with claude: '$last_line'"
elif ! autowp_exec_user "$C" \
        'grep -q "https://opencode.ai/install" ~/foobar/README.md && grep -q "^opencode$" ~/foobar/README.md'; then
    fail C2.2 "README does not document the OpenCode harness (install URL and start line)"
else
    pass C2.2
    info C2.2 "the rest of the block (tools, remote, claude) is not run at level 2 (covered by level 3)"
fi

# Run the README lines (all but 'claude') in one shell, from ~.
script="cd ~"
for l in "${RUN_LINES[@]}"; do script="$script && $l"; done
set +e
clone_out=$(autowp_exec_user "$C" "$script" 2>&1)
clone_rc=$?
set -e
printf '%s\n' "$clone_out" | tail -5 | sed 's/^/    | /'

# --- C2.3 ------------------------------------------------------------------
if [ "$clone_rc" -ne 0 ]; then
    fail C2.3 "git clone exited $clone_rc: $(echo "$clone_out" | tail -2 | tr '\n' ' ')"
elif [ "$(autowp_exec_user "$C" 'git -C ~/foobar/grub rev-parse --is-inside-work-tree' 2>/dev/null)" != true ]; then
    fail C2.3 "foobar/grub is not a git work tree"
elif [ "$(autowp_exec_user "$C" 'git -C ~/foobar/grub rev-parse --show-toplevel')" != /home/ubuntu/foobar/grub ]; then
    fail C2.3 "foobar/grub is not the top of its own work tree"
else
    pass C2.3
    info C2.3 "grub commit $(autowp_exec_user "$C" 'git -C ~/foobar/grub rev-parse --short HEAD')"
fi

# --- C2.4 ------------------------------------------------------------------
top=$(autowp_exec_user "$C" 'git -C ~/foobar rev-parse --show-toplevel' 2>/dev/null || true)
if [ "$top" != /home/ubuntu/foobar ]; then
    fail C2.4 "foobar is not a git work tree (toplevel: '$top')"
elif autowp_exec_user "$C" 'cd ~/foobar && git ls-files --error-unmatch grub >/dev/null 2>&1'; then
    fail C2.4 "grub/ is tracked by foobar"
elif autowp_exec_user "$C" 'test -e ~/foobar/.gitmodules'; then
    fail C2.4 "foobar has a .gitmodules"
elif [ -n "$(autowp_exec_user "$C" 'git -C ~/foobar rev-list --all 2>/dev/null')" ]; then
    fail C2.4 "foobar has commits (auto-wp.py must not commit)"
else
    pass C2.4
fi

# --- C2.5 ------------------------------------------------------------------
before=$(autowp_manifest "$C" /home/ubuntu/foobar grub .git)
set +e
again=$(autowp_exec_user "$C" 'cd ~ && python3 auto-wp/auto-wp.py --c foobar' 2>&1)
again_rc=$?
set -e
after=$(autowp_manifest "$C" /home/ubuntu/foobar grub .git)
if [ "$again_rc" -ne 1 ]; then
    fail C2.5 "second run exited $again_rc, expected 1"
elif [ "$before" != "$after" ]; then
    fail C2.5 "second run changed foobar: $(diff <(echo "$before") <(echo "$after") | head -5 | tr '\n' ' ')"
else
    pass C2.5
    info C2.5 "second run said: $(echo "$again" | head -1)"
fi

# --- C2.6: the fips driver (fips-skill-spec.md 8) ------------------------------
set +e
fips_out=$(autowp_exec_user "$C" 'cd ~ && python3 auto-wp/auto-wp.py --driver fips --level 2 fipsbar' 2>&1)
fips_rc=$?
set -e
printf '%s\n' "$fips_out" | sed 's/^/    | /'
if [ "$fips_rc" -ne 0 ]; then
    fail C2.6 "auto-wp.py --driver fips --level 2 exited $fips_rc"
elif ! grep -qxF '  driver:   fips (FIPS 140-3 level 2)' <<<"$fips_out"; then
    fail C2.6 "output lacks the fips driver line"
elif ! grep -qxF '  skills:   23' <<<"$fips_out"; then
    fail C2.6 "output lacks 'skills:   23'"
elif ! grep -qxF '  commands: 3' <<<"$fips_out"; then
    fail C2.6 "output lacks 'commands: 3'"
elif ! autowp_exec_user "$C" \
        'test -f ~/fipsbar/config/commands/fips.md && test -f ~/fipsbar/config/commands/ebios.md && test -f ~/fipsbar/config/commands/time-loop.md && test ! -e ~/fipsbar/config/commands/rmf.md'; then
    fail C2.6 "fipsbar/config/commands/ is not ebios, fips, time-loop (rmf.md must be absent)"
elif autowp_exec_user "$C" "python3 -c \"import json,sys; m=json.load(open('/home/ubuntu/fipsbar/config/auto-wp.json')); sys.exit(0 if (m.get('driver')=='fips' and m.get('fips_level')==2) else 1)\""; then
    pass C2.6
    info C2.6 "manifest: driver=fips, fips_level=2"
else
    fail C2.6 "the manifest lacks driver=fips / fips_level=2"
fi

autowp_summary
