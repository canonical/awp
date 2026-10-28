#!/usr/bin/env bash
# Moves the Claude token into a container (tests.md 7.1), and the K2 check.
#
# Source it after lib/lxc.sh. The token never appears on a command line, in a
# process list, in LXD's configuration, or in this script's output: it is
# streamed through stdin into a tmpfs file (/run/autowp/token) that the
# launcher (lib/harness.sh) reads into its environment and deletes.
#
# Environment:
#   AUTOWP_TOKEN_FILE   default ~/.config/auto-wp/claude-oauth-token
#                       (created once with `claude setup-token`, mode 600)
#   ACCEPT_TOKEN_EXPIRY=1  accept an unknown token lifetime (acceptance.sh)

AUTOWP_TOKEN_FILE=${AUTOWP_TOKEN_FILE:-$HOME/.config/auto-wp/claude-oauth-token}

# secret_check_file: the token file exists, is a non-empty regular file, and
# is readable only by its owner. Never reads its content.
secret_check_file() {
    local f=$AUTOWP_TOKEN_FILE mode
    if [ ! -e "$f" ]; then
        echo "ERROR: token file $f not found." >&2
        echo "       Create it once on the host with 'claude setup-token' (tests.md 7.1)." >&2
        return 1
    fi
    if [ ! -f "$f" ] || [ ! -s "$f" ]; then
        echo "ERROR: token file $f is not a non-empty regular file" >&2
        return 1
    fi
    mode=$(stat -c %a "$f")
    case "$mode" in
        600|400) ;;
        *) echo "ERROR: token file $f has mode $mode; expected 600" >&2; return 1 ;;
    esac
    return 0
}

# secret_check_expiry <hours>: refuse if the token would expire within <hours>
# from now. The .created file holds the creation date (line 1, YYYY-MM-DD) and,
# when `claude setup-token` stated it, a line `expires=YYYY-MM-DD` or
# `lifetime_days=N`. Unknown lifetime needs ACCEPT_TOKEN_EXPIRY=1.
secret_check_expiry() {
    local hours=$1 meta="$AUTOWP_TOKEN_FILE.created" created expires="" days now end exp_s
    if [ ! -f "$meta" ]; then
        echo "ERROR: $meta not found (record the token's creation date, tests.md 7.1)" >&2
        return 1
    fi
    created=$(head -n1 "$meta")
    date -u -d "$created" +%s >/dev/null 2>&1 || {
        echo "ERROR: $meta: first line '$created' is not a date" >&2; return 1; }
    expires=$(sed -n 's/^expires=//p' "$meta" | head -n1)
    days=$(sed -n 's/^lifetime_days=//p' "$meta" | head -n1)
    if [ -z "$expires" ] && [ -n "$days" ]; then
        expires=$(date -u -d "$created + $days days" +%F)
    fi
    if [ -z "$expires" ]; then
        if [ "${ACCEPT_TOKEN_EXPIRY:-0}" = 1 ]; then
            echo "WARNING: token lifetime unknown; continuing (ACCEPT_TOKEN_EXPIRY=1)" >&2
            return 0
        fi
        echo "ERROR: token lifetime unknown (no expires= or lifetime_days= in $meta);" \
             "set ACCEPT_TOKEN_EXPIRY=1 to run anyway" >&2
        return 1
    fi
    now=$(date -u +%s)
    end=$((now + hours * 3600))
    exp_s=$(date -u -d "$expires" +%s)
    if [ "$exp_s" -le "$end" ]; then
        echo "ERROR: token expires $expires, before the run would end" \
             "($(date -u -d "@$end" +%FT%TZ))" >&2
        return 1
    fi
    return 0
}

# secret_push <container> [<name>]: stream the token into /run/autowp/<name>
# (default: token) as ubuntu, mode 600.
secret_push() {
    local c=$1 name=${2:-token}
    secret_check_file || return 1
    lxc exec "$c" -- install -d -m 700 -o ubuntu -g ubuntu /run/autowp
    lxc exec "$c" --user 1000 --group 1000 -- \
        sh -c "umask 077; cat > /run/autowp/$name" < "$AUTOWP_TOKEN_FILE"
}

secret_remove() {
    local c=$1 name=${2:-token}
    lxc exec "$c" -- rm -f "/run/autowp/$name"
}

# secret_k2 <container> <id>: K2 of tests.md 4. The pattern comes from a file,
# so it never appears on a command line; only file names are printed.
secret_k2() {
    local c=$1 id=${2:-K2} hits rc=0
    secret_push "$c" k2pattern || { fail "$id" "could not stream the token for the check"; return; }
    hits=$(autowp_exec_user "$c" \
        'grep -rlF -f /run/autowp/k2pattern ~ /tmp 2>/dev/null; true')
    if [ -n "$hits" ]; then
        fail "$id" "token found in $(echo "$hits" | head -5 | tr '\n' ' ')"
        rc=1
    fi
    if autowp_exec_user "$c" '[ -d ~/remote.git ]'; then
        if autowp_exec_user "$c" \
            'git -C ~/remote.git log -p --all 2>/dev/null | grep -qF -f /run/autowp/k2pattern'; then
            fail "$id" "token found in ~/remote.git history"
            rc=1
        fi
    fi
    secret_remove "$c" k2pattern
    [ "$rc" -eq 0 ] && pass "$id"
    return 0
}

# Standalone use: `tests/lib/secret.sh check` checks the token file only.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    case "${1:-check}" in
        check) secret_check_file && echo "token file $AUTOWP_TOKEN_FILE looks usable" ;;
        expiry) secret_check_expiry "${2:?hours}" && echo "token valid for ${2} more hours" ;;
        *) echo "usage: $0 [check | expiry <hours>]" >&2; exit 2 ;;
    esac
fi
