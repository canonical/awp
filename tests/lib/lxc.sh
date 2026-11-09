#!/usr/bin/env bash
# Shared LXD helpers for the auto-wp container tests (tests.md 3.1).
#
# Source it from a test script:   . "$(dirname "$0")/../lib/lxc.sh"
#
# Provides:
#   reporting   pass/fail/info/skip, autowp_summary (exit status)
#   setup       autowp_ensure_pool, autowp_ensure_network, autowp_image
#   containers  autowp_launch_fresh, autowp_copy_snapshot, autowp_register,
#               autowp_wait_ready, autowp_egress_check, autowp_cleanup (trap)
#   in-guest    autowp_exec_root, autowp_exec_user, autowp_push, autowp_push_project
#
# Environment:
#   KEEP=1             keep the containers this script created
#   IMAGE=<ref>        image to launch (default: the cached ubuntu 24.04 fingerprint,
#                      else ubuntu:24.04)
#   AUTOWP_POOL=<name> storage pool (default: autowp, created with zfs; falls
#                      back to default)
#   AUTOWP_POOL_SIZE   size of a new zfs pool (default 40GiB)
#   AUTOWP_NET=<name>  managed bridge (default autowp-net)
#   AUTOWP_OUT=<dir>   where scripts write logs/artifacts (default tests/out)
#   AUTOWP_BACKEND     (not from the environment) lxc: <container> is an LXD container, the
#                      user is ubuntu; workshop: <container> is a workshop of
#                      the project $AUTOWP_WS_PROJECT, the user is workshop
#                      (autowp_use_workshop sets the three)
#
# Never touches containers, networks, profiles or pools it did not create,
# except that it creates the pool `autowp` and the network `autowp-net` when
# they are missing and leaves them in place.

# shellcheck disable=SC2034  # variables are used by the sourcing scripts
AUTOWP_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=selection.sh
. "$AUTOWP_LIB/selection.sh"
AUTOWP_REPO=$(cd "$AUTOWP_LIB/../.." && pwd)
AUTOWP_OUT=${AUTOWP_OUT:-$AUTOWP_REPO/tests/out}
AUTOWP_NET=${AUTOWP_NET:-autowp-net}
AUTOWP_POOL_SIZE=${AUTOWP_POOL_SIZE:-40GiB}
AUTOWP_CONTAINERS=()
AUTOWP_PASS=0
AUTOWP_FAIL=0
AUTOWP_SKIP=0
AUTOWP_BACKEND=lxc
AUTOWP_USER=ubuntu
AUTOWP_HOME=/home/ubuntu
AUTOWP_WS_PROJECT=

# --- reporting -------------------------------------------------------------

pass() { AUTOWP_PASS=$((AUTOWP_PASS + 1)); echo "PASS: $1"; }
fail() { AUTOWP_FAIL=$((AUTOWP_FAIL + 1)); echo "FAIL: $1: ${2:-}"; }
info() { echo "INFO: $1: ${2:-}"; }
skip() { AUTOWP_SKIP=$((AUTOWP_SKIP + 1)); echo "SKIP: $1: ${2:-}"; }
note() { echo "--- $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 2; }

# check <id> <reason-if-false> <command...>: PASS if the command succeeds.
check() {
    local id=$1 reason=$2
    shift 2
    if "$@"; then pass "$id"; else fail "$id" "$reason"; fi
}

autowp_summary() {
    echo "SUMMARY: $AUTOWP_PASS passed, $AUTOWP_FAIL failed, $AUTOWP_SKIP skipped"
    [ "$AUTOWP_FAIL" -eq 0 ]
}

autowp_timestamp() { date -u +%Y%m%d-%H%M%S; }

autowp_require_lxc() {
    command -v lxc >/dev/null || die "lxc not found"
    lxc list --format csv -c n >/dev/null 2>&1 || die "lxc is not usable by $(id -un)"
}

# --- pool, network, image --------------------------------------------------

# Sets AUTOWP_POOL. Creates the zfs pool `autowp` if needed.
autowp_ensure_pool() {
    if [ -n "${AUTOWP_POOL:-}" ]; then
        lxc storage show "$AUTOWP_POOL" >/dev/null 2>&1 \
            || die "storage pool $AUTOWP_POOL does not exist"
        return
    fi
    if lxc storage show autowp >/dev/null 2>&1; then
        AUTOWP_POOL=autowp
        return
    fi
    note "creating storage pool autowp (zfs, $AUTOWP_POOL_SIZE)"
    if lxc storage create autowp zfs size="$AUTOWP_POOL_SIZE" >&2; then
        AUTOWP_POOL=autowp
    else
        echo "WARNING: could not create a zfs pool; using the 'default' pool" \
             "(every copy and snapshot is a full copy)" >&2
        AUTOWP_POOL=default
    fi
}

# Creates the managed bridge autowp-net (NAT, DHCP) if needed.
autowp_ensure_network() {
    if lxc network show "$AUTOWP_NET" >/dev/null 2>&1; then
        return
    fi
    note "creating network $AUTOWP_NET"
    lxc network create "$AUTOWP_NET" ipv4.address=auto ipv4.nat=true \
        ipv4.dhcp=true ipv6.address=none >&2
}

# Prints the image to launch: $IMAGE, else the cached ubuntu 24.04 amd64
# image (so tests do not silently pick up a newer serial), else ubuntu:24.04.
autowp_image() {
    if [ -n "${IMAGE:-}" ]; then
        echo "$IMAGE"
        return
    fi
    local fp
    fp=$(lxc image list --format csv -c fd 2>/dev/null \
         | awk -F, '$2 ~ /^ubuntu 24\.04 LTS amd64/ { print $1; exit }')
    if [ -n "$fp" ]; then echo "$fp"; else echo "ubuntu:24.04"; fi
}

# --- containers ------------------------------------------------------------

autowp_register() { AUTOWP_CONTAINERS+=("$1"); }

autowp_cleanup() {
    local status=$?
    local c
    for c in "${AUTOWP_CONTAINERS[@]}"; do
        case "$c" in
            autowp-c-base|autowp-rust-base) continue ;;  # never deleted here
            autowp-*) ;;
            *) continue ;;
        esac
        if [ "${KEEP:-0}" = 1 ]; then
            echo "INFO: cleanup: KEEP=1, keeping container $c" >&2
        elif lxc info "$c" >/dev/null 2>&1; then
            lxc delete --force "$c" >/dev/null 2>&1 \
                && echo "--- deleted container $c" >&2 \
                || echo "WARNING: could not delete container $c" >&2
        fi
    done
    return "$status"
}

autowp_install_trap() { trap autowp_cleanup EXIT; trap 'exit 130' INT TERM; }

# autowp_init <image> <name>: create (not start) a container on the test
# pool, with eth0 on autowp-net (lxc init --network names the device eth0).
autowp_init() {
    lxc init "$1" "$2" -s "$AUTOWP_POOL" -n "$AUTOWP_NET" >/dev/null
    lxc config device get "$2" eth0 network 2>/dev/null | grep -qx "$AUTOWP_NET" \
        || lxc config device add "$2" eth0 nic network="$AUTOWP_NET" name=eth0 >/dev/null
}

# autowp_launch_fresh <name>: a fresh container from the stock image.
autowp_launch_fresh() {
    local c=$1 img
    img=$(autowp_image)
    note "launching $c from $img on pool $AUTOWP_POOL"
    autowp_register "$c"
    autowp_init "$img" "$c"
    lxc start "$c"
}

# autowp_copy_snapshot <base> <snapshot> <name>: a copy of a provisioned base.
autowp_copy_snapshot() {
    local base=$1 snap=$2 c=$3
    lxc info "$base" >/dev/null 2>&1 || die "base container $base does not exist (run its provision.sh)"
    lxc query "/1.0/instances/$base/snapshots/$snap" >/dev/null 2>&1 \
        || die "snapshot $base/$snap does not exist (run its provision.sh)"
    note "copying $base/$snap to $c"
    autowp_register "$c"
    lxc copy "$base/$snap" "$c" -s "$AUTOWP_POOL" >/dev/null
    lxc start "$c"
}

# Waits until cloud-init has finished (the ubuntu user exists) and DNS works.
autowp_wait_ready() {
    local c=$1 i
    for i in $(seq 1 60); do
        lxc exec "$c" -- true >/dev/null 2>&1 && break
        sleep 2
    done
    lxc exec "$c" -- cloud-init status --wait >/dev/null 2>&1 || true
    for i in $(seq 1 60); do
        if lxc exec "$c" -- id -u ubuntu >/dev/null 2>&1 \
           && lxc exec "$c" -- getent hosts gitlab.freedesktop.org >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    lxc exec "$c" -- id -u ubuntu >/dev/null 2>&1 || die "$c: user ubuntu does not exist"
    return 0  # DNS may still fail; the egress check reports it precisely
}

# Egress check, before any other step (tests.md 3.1).
autowp_egress_check() {
    local c=$1 out
    if out=$(lxc exec "$c" -- curl -sSfI --max-time 30 https://gitlab.freedesktop.org 2>&1); then
        info egress "https://gitlab.freedesktop.org reachable from $c"
        return 0
    fi
    echo "FAIL: egress: $c cannot reach https://gitlab.freedesktop.org: $out" >&2
    echo "FAIL: egress: curl -sSfI https://gitlab.freedesktop.org failed in $c:" \
         "$(echo "$out" | head -3 | tr '\n' ' ')"
    echo "      (on hosts with Docker, its firewall rules often block other bridges;" \
         "see tests.md 3.1)"
    AUTOWP_FAIL=$((AUTOWP_FAIL + 1))
    autowp_summary || true
    exit 1
}

# --- running and copying ---------------------------------------------------

# autowp_use_workshop <project-dir>: run the in-guest helpers below in the
# workshops of <project-dir> (workshop exec) instead of LXD containers.
autowp_use_workshop() {
    AUTOWP_BACKEND=workshop
    AUTOWP_WS_PROJECT=$1
    AUTOWP_USER=workshop
    AUTOWP_HOME=/home/workshop
}

# autowp_exec_root <container> <argv...>: as root.
autowp_exec_root() {
    local c=$1; shift
    if [ "$AUTOWP_BACKEND" = workshop ]; then
        workshop -p "$AUTOWP_WS_PROJECT" exec -I --uid 0 --gid 0 --cwd / "$c" -- "$@"
    else
        lxc exec "$c" -- "$@"
    fi
}

# autowp_exec_user <container> '<shell code>': as the user, login environment.
autowp_exec_user() {
    local c=$1
    shift
    if [ "$AUTOWP_BACKEND" = workshop ]; then
        workshop -p "$AUTOWP_WS_PROJECT" exec -I --cwd "$AUTOWP_HOME" "$c" -- bash -lc "$*"
    else
        lxc exec "$c" --user 1000 --group 1000 --cwd /home/ubuntu \
            --env HOME=/home/ubuntu --env USER=ubuntu --env LOGNAME=ubuntu \
            -- bash -lc "$*"
    fi
}

# autowp_exec_user_argv <container> <argv...>: as the user, no login shell
# (tmux send-keys, stdin pipes).
autowp_exec_user_argv() {
    local c=$1; shift
    if [ "$AUTOWP_BACKEND" = workshop ]; then
        workshop -p "$AUTOWP_WS_PROJECT" exec -I --cwd "$AUTOWP_HOME" "$c" -- "$@"
    else
        lxc exec "$c" --user 1000 --group 1000 --env HOME=/home/ubuntu -- "$@"
    fi
}

# autowp_push <container> <src-dir> <dst-dir> [tar options/files...]
# Tar pipe, never a bind mount; then chown to ubuntu.
autowp_push() {
    local c=$1 src=$2 dst=$3
    shift 3
    lxc exec "$c" -- install -d -o ubuntu -g ubuntu "$dst"
    tar -C "$src" -cf - "$@" | lxc exec "$c" -- tar -C "$dst" -xf -
    lxc exec "$c" -- chown -R ubuntu:ubuntu "$dst"
}

# auto-wp.py alone is not enough: it reads templates/ next to itself.
autowp_push_project() {
    local c=$1
    autowp_push "$c" "$AUTOWP_REPO" /home/ubuntu/auto-wp \
        --exclude='*~' --exclude='__pycache__' auto-wp.py templates
}

# Manifest of a directory tree (types, modes, link targets, sha256), for
# "changes nothing" checks. Excludes the given top-level names.
#   autowp_manifest <container> <dir> [excluded-name...]
autowp_manifest() {
    local c=$1 dir=$2
    shift 2
    local prune="" n
    for n in "$@"; do prune="$prune -path ./$n -prune -o"; done
    autowp_exec_user "$c" "cd $dir && find . $prune -printf '%y %m %p -> %l\n' | LC_ALL=C sort \
        && find . $prune -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum"
}
