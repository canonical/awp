#!/usr/bin/env bash
# Fetches the two source trees the C skills need that are too large to ship
# in this directory, and puts them where the skills expect them:
#
#   framac-src/  Frama-C 32.1 source (the release archive that opam's
#                frama-c.32.1 package uses, checksum verified), with
#                frama-c-patches/ applied. frama-c-launch builds and installs it.
#   macsl/       the macsl Frama-C plugin, pinned to the commit below.
#
# Usage: bin/fetch-sources.sh      (needs curl, sha256sum, tar, git, patch, network)
# An existing framac-src/ or macsl/ is left as it is.
#
# In a workshop with the frama-c-sdk SDK, FRAMA_C_SDK_SRC names the same
# patched tree, read-only in the SDK: framac-src is then a symbolic link to
# it instead of a download (the SDK's build applied the same patches with
# this script). macsl/ is still cloned: the SDK ships only the built plugin
# (FRAMA_C_SDK_MACSL), and the skills that read macsl's sources want the tree.
set -euo pipefail
cd "$(dirname "$0")/.."   # the project root (this script is in bin/)

FRAMAC_VERSION=32.1
# url { src checksum } of opam's frama-c.32.1 package
FRAMAC_URL=https://www.frama-c.com/download/frama-c-32.1-Germanium.tar.gz
FRAMAC_SHA256=dd5d6e89df5dde6a40b38bead302d0a5b9860b1c3b65bcd85360a778087c13e2
MACSL_URL=https://github.com/canonical/macsl.git
MACSL_COMMIT=b7a472e2b6b944ffb2f70e66802ad5e162d74605
P=frama-c-patches

if [ -d framac-src ]; then
    echo "framac-src/ exists, kept"
elif [ -n "${FRAMA_C_SDK_SRC:-}" ] && [ -d "$FRAMA_C_SDK_SRC" ]; then
    ln -s "$FRAMA_C_SDK_SRC" framac-src
    echo "framac-src -> $FRAMA_C_SDK_SRC (the frama-c-sdk SDK's patched sources)"
else
    tmp=framac-src.tmp
    rm -rf "$tmp" "$tmp.tar.gz"
    curl -fsSL -o "$tmp.tar.gz" "$FRAMAC_URL"
    echo "$FRAMAC_SHA256  $tmp.tar.gz" | sha256sum -c --quiet
    mkdir "$tmp"
    tar -C "$tmp" --strip-components=1 -xzf "$tmp.tar.gz"
    rm "$tmp.tar.gz"
    FRAMAC_SRC=$tmp "$P"/apply.sh | grep -e "^==" -e applied   # 0001, 0002
    (cd "$tmp" && patch -s -p0 < "../$P/cabs2cil-c23-auto/cabs2cil-c23-auto.patch")
    patch -s "$tmp/src/plugins/wp/share/why3/frama_c_wp/cbits.mlw" \
        < "$P/wp-cbits-bound-lemmas/cbits.mlw.patch"
    cat "$P/wp-cbits-bound-lemmas/Cbits.v.realization" \
        >> "$tmp/src/plugins/wp/share/coqwp/Cbits.v"
    find "$tmp" -name '*.orig' -delete
    grep -q land_le_l "$tmp/src/plugins/wp/share/why3/frama_c_wp/cbits.mlw"
    mv "$tmp" framac-src
    echo "framac-src/ ready: Frama-C $FRAMAC_VERSION with $P/ applied"
fi

if [ -d macsl ]; then
    echo "macsl/ exists, kept"
else
    git clone -q "$MACSL_URL" macsl
    git -C macsl checkout -q "$MACSL_COMMIT"
    echo "macsl/ ready at ${MACSL_COMMIT:0:7}"
fi
