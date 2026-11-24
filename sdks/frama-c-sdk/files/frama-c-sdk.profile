# /etc/profile.d/frama-c-sdk.sh, installed by the frama-c-sdk SDK.
# Only the SDK's wrappers go on PATH; each one runs its tool in the SDK's
# read-only opam switch. The switch's coqc (Coq 8.20.1, pinned for WP) is not
# put on PATH, so it cannot shadow rocq's Rocq.
case ":$PATH:" in
    *":/opt/frama-c-sdk/bin:"*) ;;
    *) PATH="/opt/frama-c-sdk/bin:$PATH" ;;
esac
export PATH
export FRAMA_C_SDK_SWITCH=framac-coq8
export FRAMA_C_SDK_MACSL=/opt/frama-c-sdk/macsl/macsl.cmxs
export FRAMA_C_SDK_SRC=/opt/frama-c-sdk/src/frama-c-32.1
# framac-mcp probe marker for the skills' MCP capability row (spec section 5/6).
# The venv lives OUTSIDE the read-only switch (open point O-3); only this marker
# is exported, PATH is not touched (the skills invoke the binary by path).
export FRAMAC_MCP_BIN=/opt/frama-c-mcp/venv/bin/framac-mcp
