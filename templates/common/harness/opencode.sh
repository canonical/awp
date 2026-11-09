# Install outside /root so the workshop user can execute the native binary.
(
    set -eu
    set -o pipefail
    umask 022
    if ! command -v opencode >/dev/null; then
        install -d -m 755 /opt/autowp/opencode
        curl -fsSL https://opencode.ai/v2/install | HOME=/opt/autowp/opencode bash
        ln -sf /opt/autowp/opencode/.opencode/bin/opencode /usr/local/bin/opencode
    fi
    version=$(opencode --version)
    case "$version" in
        "opencode v2."*|2.*) printf '%s\n' "$version" ;;
        *) echo "OpenCode V2 required; found $version" >&2; exit 1 ;;
    esac
)
