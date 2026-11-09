# Install outside /root so the workshop user can execute the native binary.
(
    set -eu
    set -o pipefail
    umask 022
    if ! command -v claude >/dev/null; then
        install -d -m 755 /opt/autowp/claude
        curl -fsSL https://claude.ai/install.sh | HOME=/opt/autowp/claude bash
        ln -sf /opt/autowp/claude/.local/bin/claude /usr/local/bin/claude
    fi
    claude --version
)
