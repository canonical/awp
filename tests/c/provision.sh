#!/usr/bin/env bash
# Builds the reusable C base container autowp-c-base and its snapshot
# `ready` (tests.md 5.1). Takes hours (the Frama-C toolchain build).
#
#   tests/c/provision.sh
#
# Environment:
#   SKIP_TOOLCHAIN=1    skip step 3; /time-loop must then build the toolchain
#                       itself through frama-c-launch
#   FORCE=1             delete an existing autowp-c-base first
#   KEEP=1              keep a half-built base on failure (for debugging)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib/lxc.sh
. "$HERE/../lib/lxc.sh"

BASE=autowp-c-base
# The toolchain is built from the same tools and sources a project gets:
# templates/c/tools/ and its bin/fetch-sources.sh. No host checkout is used.
TOOLS=$AUTOWP_REPO/templates/c/tools
TC_DST=/home/ubuntu/toolchain

[ -x "$TOOLS/bin/fetch-sources.sh" ] || die "$TOOLS/bin/fetch-sources.sh missing"
command -v claude >/dev/null || die "claude not found on the host PATH (tests.md 3.3)"
autowp_require_lxc
autowp_ensure_pool
autowp_ensure_network

if lxc info "$BASE" >/dev/null 2>&1; then
    if [ "${FORCE:-0}" = 1 ]; then
        lxc delete --force "$BASE"
    else
        die "$BASE already exists (FORCE=1 rebuilds it)"
    fi
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

# --- 1. packages -------------------------------------------------------------
note "step 1: packages"
autowp_exec_root "$BASE" bash -c 'export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get install -y -q git python3 tmux curl opam build-essential pkg-config \
        libgtk-3-dev libgraphviz-dev graphviz libgtksourceview-3.0-dev \
        bear \
        autoconf automake autopoint gettext bison flex libtool \
        libdevmapper-dev libfreetype-dev libfuse3-dev liblzma-dev fonts-unifont \
        unzip rsync m4 libgmp-dev zlib1g-dev'
# Ubuntu 24.04's AppArmor profile for opam denies network sockets inside an
# LXD container (opam init: "Could not resolve host"); the README unloads it.
autowp_exec_root "$BASE" sh -c 'ln -sf /etc/apparmor.d/opam /etc/apparmor.d/disable/ &&
    apparmor_parser -R /etc/apparmor.d/opam'
pass C-prov.1

# --- 2. C tools layer (as auto-wp.py copies it into a project) ---------------
note "step 2: templates/c/tools into $TC_DST"
autowp_push "$BASE" "$TOOLS" "$TC_DST" --exclude='*~' .
pass C-prov.2

# --- 3. toolchain --------------------------------------------------------------
if [ "${SKIP_TOOLCHAIN:-0}" = 1 ]; then
    skip C-prov.3 "SKIP_TOOLCHAIN=1: /time-loop builds the toolchain through frama-c-launch"
else
    note "step 3: framac-coq8 toolchain (hours)"
    autowp_exec_user "$BASE" 'set -euo pipefail
        opam init --disable-sandboxing -y --bare
        opam switch create framac-coq8 ocaml-base-compiler.4.14.2 -y
        eval "$(opam env --switch=framac-coq8 --set-switch)"
        # Coq before Why3, Coq pinned to 8.20 (plain `coq` is Rocq 9.x now)
        # pinned: a plain install is upgraded to Coq 9.x when alt-ergo upgrades dune
        opam pin add -y coq 8.20.1
        opam install -y "why3>=1.8.0" "why3<1.9" "why3-coq>=1.8.0" "why3-coq<1.9" alt-ergo z3
        why3 config detect
        test -f "$(why3 --print-libdir)/coq/BuiltIn.vo"
        opam install -y yaml ppx_deriving_yaml ocamlgraph ppx_inline_test unionFind dune
        # opam frama-c only for the dependency base; the binary run is the patched build
        opam install -y --deps-only frama-c.32.1
        ~/toolchain/bin/fetch-sources.sh # framac-src/ with frama-c-patches/ applied, macsl/
        cd ~/toolchain/framac-src
        dune build @install
        dune install --prefix "$(opam var prefix)" frama-c frama-c-wp frama-c-rtegen \
            frama-c-region frama-c-server qed'
    ver=$(autowp_exec_user "$BASE" 'eval "$(opam env --switch=framac-coq8 --set-switch)"; frama-c -version')
    detect=$(autowp_exec_user "$BASE" 'eval "$(opam env --switch=framac-coq8 --set-switch)"; frama-c -wp-detect 2>&1')
    case "$ver" in 32.1*) pass C-prov.3-version ;; *) fail C-prov.3-version "frama-c -version: $ver" ;; esac
    for p in Alt-Ergo Z3 Coq; do
        check "C-prov.3-detect-$p" "frama-c -wp-detect does not list $p" grep -qi "$p" <<<"$detect"
    done
    # The patched build ships the cbits bound lemmas (frama-c-patches/wp-cbits-bound-lemmas).
    check C-prov.3-patched "installed Frama-C share lacks the wp-cbits-bound-lemmas patch" \
        autowp_exec_user "$BASE" 'eval "$(opam env --switch=framac-coq8 --set-switch)"
            grep -q land_le_l "$(frama-c -print-share-path)/wp/why3/frama_c_wp/cbits.mlw" \
            || grep -rqs land_le_l "$(frama-c -print-share-path)"'
fi

# --- 4. Claude Code (no credentials) and git -----------------------------------
note "step 4: Claude Code and git identity"
claude_bin=$(readlink -f "$(command -v claude)")
autowp_exec_user "$BASE" 'mkdir -p ~/.local/bin ~/.claude'
lxc file push "$claude_bin" "$BASE/home/ubuntu/.local/bin/claude" --uid 1000 --gid 1000 --mode 0755
autowp_exec_user "$BASE" 'python3 - <<EOF
import json, os
p = os.path.expanduser("~/.claude.json")
json.dump({"hasCompletedOnboarding": True, "projects": {}}, open(p, "w"), indent=2)
s = os.path.expanduser("~/.claude/settings.json")
json.dump({"skipDangerousModePermissionPrompt": True}, open(s, "w"), indent=2)
EOF
grep -q DISABLE_AUTOUPDATER ~/.profile || echo "export DISABLE_AUTOUPDATER=1" >> ~/.profile
git config --global user.name "auto-wp test"
git config --global user.email "autowp-test@localhost"'
host_ver=$(claude --version 2>/dev/null | head -1)
guest_ver=$(autowp_exec_user "$BASE" 'DISABLE_AUTOUPDATER=1 claude --version 2>/dev/null | head -1')
check C-prov.4-claude "container claude '$guest_ver' differs from host '$host_ver'" test "$host_ver" = "$guest_ver"
check C-prov.4-git "git identity not set" autowp_exec_user "$BASE" 'git config --global user.email >/dev/null'

# --- 5. snapshot ---------------------------------------------------------------
if autowp_summary; then
    lxc stop "$BASE"
    lxc snapshot "$BASE" ready
    done_ok=1
    echo "INFO: $BASE/ready created"
else
    exit 1
fi
