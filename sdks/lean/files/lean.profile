# /etc/profile.d/lean.sh, installed by the lean SDK.
# elan lives in the user's home (a mount plug keeps it across refreshes), so
# a project's lean-toolchain file can select another toolchain.
export ELAN_HOME="$HOME/.elan"
case ":$PATH:" in
    *":$ELAN_HOME/bin:"*) ;;
    *) PATH="$ELAN_HOME/bin:$PATH" ;;
esac
case ":$PATH:" in
    *":/opt/lean/venv/bin:"*) ;;
    *) PATH="$PATH:/opt/lean/venv/bin" ;;
esac
export PATH
# The lean skill's capability table reads this.
export LEAN4_PYTHON_BIN=/usr/bin/python3
