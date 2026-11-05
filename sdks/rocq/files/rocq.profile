# /etc/profile.d/rocq.sh, installed by the rocq SDK.
# Puts Rocq 9.2 (rocq, coqc, coqtop, coqdep) on PATH from the SDK's
# read-only opam switch. Users do not opam-install into it.
if [ -r /opt/rocq/env.sh ]; then
    . /opt/rocq/env.sh
fi
# The rocq skill's capability table reads this.
export ROCQ_PYTHON_BIN=/usr/bin/python3
