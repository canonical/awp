#!/usr/bin/env bash
# launch_lxc.sh — step 1 of the README quick start: create the LXD container,
# mount this project into it, install the packages, and open a shell in it.
#
#   bin/launch_lxc.sh            (from any directory)
#
# Environment:
#   CT=<name>    container name (default wp-<project directory name>)
#   NET=<name>   managed LXD bridge (default lxdbr0, created if missing)
#
# The project is mounted, not copied: everything the run writes is in the
# project directory on the host. See the README for why each step is there.
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"   # the project root (this script is in bin/)
DIR="$(basename "$PROJECT")"
CT="${CT:-wp-$DIR}"
NET="${NET:-lxdbr0}"

case "$CT" in
    *[!A-Za-z0-9-]* | -* | "")
        echo "launch_lxc: container name '$CT' must contain only letters, digits and hyphens; set CT=<name>" >&2
        exit 2 ;;
esac
if lxc info "$CT" >/dev/null 2>&1; then
    echo "launch_lxc: container $CT already exists." >&2
    echo "  open a shell in it:  lxc exec $CT -- sudo -iu ubuntu" >&2
    echo "  or start over:       lxc delete --force $CT" >&2
    exit 1
fi

lxc network show "$NET" >/dev/null 2>&1 || lxc network create "$NET"
lxc launch ubuntu:24.04 "$CT" --network "$NET" </dev/null
lxc exec "$CT" -- cloud-init status --wait
lxc config device add "$CT" "$DIR" disk source="$PROJECT" \
    path="/home/ubuntu/$DIR" shift=true
lxc exec "$CT" --env DEBIAN_FRONTEND=noninteractive -- sh -c 'apt-get update &&
    apt-get install -y git python3 tmux \
    curl opam build-essential pkg-config libgtk-3-dev libgraphviz-dev \
    libgtksourceview-3.0-dev bear autoconf automake autopoint gettext bison \
    flex libtool libdevmapper-dev libfreetype-dev libfuse3-dev liblzma-dev \
    fonts-unifont unzip rsync m4 libgmp-dev zlib1g-dev'
lxc exec "$CT" -- sh -c 'ln -sf /etc/apparmor.d/opam /etc/apparmor.d/disable/ &&
    apparmor_parser -R /etc/apparmor.d/opam'
exec lxc exec "$CT" -- sudo -iu ubuntu
