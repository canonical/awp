#!/usr/bin/env bash
# Builds the reusable Rust base container autowp-rust-base and its snapshot
# `ready` (tests.md 6.1). Takes an hour or more (Creusot's ./INSTALL).
#
#   tests/rust/provision.sh
#
# Environment:
#   CREUSOT_COMMIT=<sha>   Creusot commit (default f15b985, auto-wp.md 4.3.6)
#   FORCE=1                delete an existing autowp-rust-base first
#   KEEP=1                 keep a half-built base on failure
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib/lxc.sh
. "$HERE/../lib/lxc.sh"

BASE=autowp-rust-base
CREUSOT_COMMIT=${CREUSOT_COMMIT:-f15b985}

command -v claude >/dev/null || die "claude not found on the host PATH (tests.md 3.3)"
autowp_require_lxc
autowp_ensure_pool
autowp_ensure_network

if lxc info "$BASE" >/dev/null 2>&1; then
    if [ "${FORCE:-0}" = 1 ]; then lxc delete --force "$BASE"
    else die "$BASE already exists (FORCE=1 rebuilds it)"; fi
fi

done_ok=0
provision_cleanup() {
    local status=$?
    if [ "$done_ok" != 1 ]; then
        if [ "${KEEP:-0}" = 1 ]; then
            echo "INFO: provision failed; KEEP=1, keeping half-built $BASE" >&2
        else
            echo "--- provision failed; deleting half-built $BASE" >&2
            lxc delete --force "$BASE" >/dev/null 2>&1 || true
        fi
    fi
    return "$status"
}
trap provision_cleanup EXIT
trap 'exit 130' INT TERM

img=$(autowp_image)
note "creating $BASE from $img"
autowp_init "$img" "$BASE"
lxc start "$BASE"
autowp_wait_ready "$BASE"
autowp_egress_check "$BASE"

# --- 1. packages (GTK: creusot-deps.opam depends on why3-ide) -----------------
note "step 1: packages"
autowp_exec_root "$BASE" bash -c 'export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get install -y -q git python3 tmux curl opam build-essential \
        libcairo2-dev libgtk-3-dev libgtksourceview-3.0-dev \
        pkg-config libgmp-dev zlib1g-dev unzip m4'
# Ubuntu 24.04's AppArmor profile for opam denies network sockets inside an
# LXD container (opam init: "Could not resolve host"); the README unloads it.
autowp_exec_root "$BASE" sh -c 'ln -sf /etc/apparmor.d/opam /etc/apparmor.d/disable/ &&
    apparmor_parser -R /etc/apparmor.d/opam'
pass R-prov.1

# --- 2. opam, rustup, Creusot ----------------------------------------------------
note "step 2: opam, rustup, Creusot $CREUSOT_COMMIT (long)"
autowp_exec_user "$BASE" "set -euo pipefail
    opam init --disable-sandboxing -y --bare
    curl -sSf https://sh.rustup.rs | sh -s -- -y
    . ~/.cargo/env
    mkdir -p ~/git
    git clone https://github.com/creusot-rs/creusot.git ~/git/creusot
    cd ~/git/creusot
    git checkout -q $CREUSOT_COMMIT
    ./INSTALL"
version=$(autowp_exec_user "$BASE" '. ~/.cargo/env; cargo creusot version 2>&1' || true)
printf '%s\n' "$version" | sed 's/^/    | /'
for t in Why3 why3find Alt-Ergo Z3 CVC4 CVC5; do
    check "R-prov.2-$t" "cargo creusot version does not list $t" grep -qi -- "$t" <<<"$version"
done
info R-prov.2 "creusot commit $(autowp_exec_user "$BASE" 'git -C ~/git/creusot rev-parse --short HEAD')"

# --- 3. Agent harnesses (no credentials) and git -----------------------------------
# Claude Code always; OpenCode too when its binary is on the host, so the
# base serves HARNESS=claude and HARNESS=opencode runs alike.
note "step 3: Claude Code, OpenCode and git identity"
claude_bin=$(readlink -f "$(command -v claude)")
autowp_exec_user "$BASE" 'mkdir -p ~/.local/bin ~/.claude'
lxc file push "$claude_bin" "$BASE/home/ubuntu/.local/bin/claude" --uid 1000 --gid 1000 --mode 0755
autowp_exec_user "$BASE" 'python3 - <<EOF
import json, os
json.dump({"hasCompletedOnboarding": True, "projects": {}},
          open(os.path.expanduser("~/.claude.json"), "w"), indent=2)
json.dump({"skipDangerousModePermissionPrompt": True},
          open(os.path.expanduser("~/.claude/settings.json"), "w"), indent=2)
EOF
grep -q DISABLE_AUTOUPDATER ~/.profile || echo "export DISABLE_AUTOUPDATER=1" >> ~/.profile
git config --global user.name "auto-wp test"
git config --global user.email "autowp-test@localhost"'
host_ver=$(claude --version 2>/dev/null | head -1)
guest_ver=$(autowp_exec_user "$BASE" 'DISABLE_AUTOUPDATER=1 claude --version 2>/dev/null | head -1')
check R-prov.3-claude "container claude '$guest_ver' differs from host '$host_ver'" test "$host_ver" = "$guest_ver"
if command -v opencode >/dev/null; then
    opencode_bin=$(readlink -f "$(command -v opencode)")
    lxc file push "$opencode_bin" "$BASE/home/ubuntu/.local/bin/opencode" --uid 1000 --gid 1000 --mode 0755
    autowp_exec_user "$BASE" 'mkdir -p ~/.config/opencode
cat > ~/.config/opencode/opencode.json <<JSON
{"\$schema": "https://opencode.ai/config.json",
 "permissions": [
     {"action": "*", "resource": "*", "effect": "allow"},
     {"action": "read", "resource": "*.env", "effect": "allow"},
     {"action": "read", "resource": "*.env.*", "effect": "allow"}
 ]}
JSON
cat > ~/.config/opencode/cli.json <<JSON
{"highlights": false}
JSON
opencode service set disabled true'
    host_ver=$(opencode --version 2>/dev/null | head -1)
    guest_ver=$(autowp_exec_user "$BASE" 'opencode --version 2>/dev/null | head -1')
    check R-prov.3-opencode "container opencode '$guest_ver' differs from host '$host_ver'" test "$host_ver" = "$guest_ver"
else
    skip R-prov.3-opencode "opencode not on the host PATH; the base serves HARNESS=claude only"
fi

# --- 4. snapshot -----------------------------------------------------------------
if autowp_summary; then
    lxc stop "$BASE"
    lxc snapshot "$BASE" ready
    done_ok=1
    echo "INFO: $BASE/ready created"
else
    exit 1
fi
