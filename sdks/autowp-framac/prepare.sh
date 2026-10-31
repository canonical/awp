#!/usr/bin/env bash
# Copies the files the SDK build needs from the auto-wp templates into
# vendor/ (sdkcraft builds in a container that only sees this directory).
# Run by `make sdk-framac`; vendor/ is not committed.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLS=$HERE/../../templates/c/tools
rm -rf "$HERE/vendor"
mkdir -p "$HERE/vendor/bin"
cp "$TOOLS/bin/fetch-sources.sh" "$HERE/vendor/bin/"
cp -a "$TOOLS/frama-c-patches" "$HERE/vendor/"
find "$HERE/vendor" -name '*~' -delete
echo "vendor/ ready: bin/fetch-sources.sh and frama-c-patches/ from templates/c/tools"
