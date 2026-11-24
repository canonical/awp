# /etc/profile.d/creusot.sh, installed by the creusot SDK.
# Creusot's data (Why3/why3find switch, provers, creusot-rustc) is read-only
# in the SDK; rustup and cargo live in the user's home (mount plugs), so a
# crate's own rust-toolchain.toml and `rustup target add` keep working.
# $DATA/bin (why3, provers) is deliberately not on PATH: cargo-creusot adds
# it for its own children, and it would clash with frama-c-sdk's wrappers.
export CREUSOT_DATA_HOME=/opt/creusot/data
export CREUSOT_SDK_SRC=/opt/creusot/src/creusot
export CREUSOT_SDK_COMMIT=f15b985
case ":$PATH:" in
    *":$HOME/.cargo/bin:"*) ;;
    *) PATH="$HOME/.cargo/bin:$PATH" ;;
esac
case ":$PATH:" in
    *":/opt/creusot/bin:"*) ;;
    *) PATH="/opt/creusot/bin:$PATH" ;;
esac
export PATH
# The creusot/creusot-sl/creusot-monitoring skills probe for this (the MCP's
# canary). The venv lives OUTSIDE the read-only /opt/creusot overlay (O-3);
# $CREUSOT_DATA_HOME/bin stays off PATH, so the MCP never exposes a prover.
export CREUSOT_MCP_BIN=/opt/creusot-mcp/venv/bin/creusot-mcp
