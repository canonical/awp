
# Register the SDKs' MCP servers with the harness (--harness claude|opencode).
#
# Appended to `setup-project`, after the local-inference snippet when there is
# one: both write the same `~/.config/opencode/opencode.json`, and that
# snippet only writes a file that does not exist yet. Registering first would
# create it and silently cost the campaign its provider configuration.
#
# Each SDK that is mounted exports the path to its server, so the loop below
# registers exactly what this project's workshop actually has: FRAMAC_MCP_BIN
# (frama-c-sdk), ROCQ_MCP_BIN (rocq), CREUSOT_MCP_BIN (creusot), and the lean
# SDK's `lean-lsp-mcp` on PATH. A C project has no creusot SDK and registers
# no creusot server; a Rust one has no frama-c SDK. Nothing is guessed: an
# absent variable means an absent SDK.
#
# The server names are the ones the SPECS and the consuming skills use --
# `framac`, `rocq`, `creusot`, `lean-lsp` (spec/{frama-c,rocq,creusot}-mcp.md,
# and `frama-c-monitoring` §4b probes "the registered `framac` MCP"). A server
# registered under any other name is invisible to the skill that would use it:
# the capability silently stays off. `sdks/frama-c-sdk/README.md` said
# `frama-c` for a while, which is exactly that trap; it now matches.
#
#   AUTOWP_MCP_REGISTER=0   skip registration entirely
#
# Copilot is deliberately excluded: the generated README starts it with
# `--disable-builtin-mcps`, so wiring servers into it would contradict the
# campaign's own launch command.
(
    set -eu
    set -o pipefail
    umask 022

    [ "${AUTOWP_MCP_REGISTER:-1}" = 1 ] || exit 0

    user=${AUTOWP_INFERENCE_USER:-workshop}
    home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6) || home=
    home=${home:-/home/$user}

    # "<name> <command>" per mounted SDK. An unset variable drops its line.
    servers=$(
        [ -n "${FRAMAC_MCP_BIN:-}" ] && printf 'framac %s\n' "$FRAMAC_MCP_BIN"
        [ -n "${ROCQ_MCP_BIN:-}" ] && printf 'rocq %s\n' "$ROCQ_MCP_BIN"
        [ -n "${CREUSOT_MCP_BIN:-}" ] && printf 'creusot %s\n' "$CREUSOT_MCP_BIN"
        command -v lean-lsp-mcp >/dev/null 2>&1 && printf 'lean-lsp %s\n' \
            "$(command -v lean-lsp-mcp)"
        true
    )
    if [ -z "$servers" ]; then
        printf 'auto-wp: no SDK exports an MCP server; nothing to register\n' >&2
        exit 0
    fi

    # `claude` and `opencode` spell this differently, so the right CLI has to
    # be the one this project was GENERATED for -- recorded in the manifest.
    # Probing PATH instead picks whichever happens to be installed, and on a
    # machine with both it silently drives the wrong one and registers
    # nothing.
    manifest=${AUTOWP_MANIFEST:-${AUTOWP_PROJECT_DIR:-/project}/config/auto-wp.json}
    harness=$(sed -n 's/.*"harness"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' \
        "$manifest" 2>/dev/null | head -1) || harness=
    if [ -z "$harness" ]; then
        printf 'auto-wp: no harness in %s; MCP servers left unregistered\n' \
            "$manifest" >&2
        exit 0
    fi
    case $harness in
        claude|opencode) ;;
        *) printf 'auto-wp: harness %s does not take MCP servers; skipped\n' \
               "$harness" >&2; exit 0 ;;
    esac
    if ! command -v "$harness" >/dev/null 2>&1; then
        printf 'auto-wp: %s is not on PATH; MCP servers left unregistered\n' \
            "$harness" >&2
        exit 0
    fi

    registered= skipped= failed=
    printf '%s\n' "$servers" | while read -r name bin; do
        [ -n "$name" ] || continue
        [ -x "$bin" ] || { printf 'auto-wp: %s MCP server not executable: %s\n' \
            "$name" "$bin" >&2; continue; }
        # Idempotent: this hook runs again on every `workshop refresh`, and a
        # second add is an error on both CLIs. It also matters that neither
        # CLI has an `mcp remove`: a server registered under the wrong name
        # can only be cleared by editing the JSON, so get the name right the
        # first time rather than relying on a later correction.
        if HOME=$home "$harness" mcp list 2>/dev/null | grep -qw -- "$name"; then
            printf 'auto-wp: MCP %s already registered\n' "$name"
            continue
        fi
        if [ "$harness" = opencode ]; then
            out=$(HOME=$home opencode mcp add "$name" --global -- "$bin" 2>&1) || out=$out
        else
            out=$(HOME=$home claude mcp add --transport stdio --scope user \
                "$name" -- "$bin" 2>&1) || out=$out
        fi
        if HOME=$home "$harness" mcp list 2>/dev/null | grep -qw -- "$name"; then
            printf 'auto-wp: registered MCP %s -> %s\n' "$name" "$bin"
        else
            # Advisory: a harness that cannot take the registration is not a
            # reason to fail provisioning. The servers stay usable by hand.
            printf 'auto-wp: WARNING could not register MCP %s (%s)\n' \
                "$name" "$(printf '%s' "$out" | head -1)" >&2
        fi
    done
)
