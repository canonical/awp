(
    set -eu
    set -o pipefail
    umask 022
    export PATH="/usr/local/bin:$PATH"
    if ! command -v copilot >/dev/null; then
        # The standalone installer supports a system-wide prefix; no Node is needed.
        unset GITHUB_TOKEN GH_TOKEN COPILOT_GITHUB_TOKEN
        curl -fsSL https://gh.io/copilot-install | PREFIX=/usr/local bash
    fi
    copilot --version
)
