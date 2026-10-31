# /etc/profile.d/autowp-rocq.sh, installed by the autowp-rocq SDK.
# Puts Rocq 9.2 (rocq, coqc, coqtop, coqdep) on PATH from the SDK's
# read-only opam switch. Users do not opam-install into it.
if [ -r /opt/autowp-rocq/env.sh ]; then
    . /opt/autowp-rocq/env.sh
fi
# The rocq skill's capability table reads this.
export ROCQ_PYTHON_BIN=/usr/bin/python3
