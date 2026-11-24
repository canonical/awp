# /etc/profile.d/rocq.sh, installed by the rocq SDK.
# Puts Rocq 9.2 (rocq, coqc, coqtop, coqdep) on PATH from the SDK's
# read-only opam switch. Users do not opam-install into it.
if [ -r /opt/rocq/env.sh ]; then
    . /opt/rocq/env.sh
fi
# The rocq skill's capability table reads this.
export ROCQ_PYTHON_BIN=/usr/bin/python3
# coq-lsp/Petanque adapter (spec/rocq-mcp.md §4): the venv bin on PATH and a
# marker the skill's capability table can probe.  The venv lives OUTSIDE the
# read-only /opt/rocq switch.
case ":$PATH:" in
    *":/opt/rocq-mcp/venv/bin:"*) ;;
    *) PATH="$PATH:/opt/rocq-mcp/venv/bin" ;;
esac
export PATH
export ROCQ_MCP_BIN=/opt/rocq-mcp/venv/bin/rocq-mcp
