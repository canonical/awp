# /etc/profile.d/autowp-framac.sh, installed by the autowp-framac SDK.
# Only the SDK's wrappers go on PATH; each one runs its tool in the SDK's
# read-only opam switch. The switch's coqc (Coq 8.20.1, pinned for WP) is not
# put on PATH, so it cannot shadow autowp-rocq's Rocq.
case ":$PATH:" in
    *":/opt/autowp-framac/bin:"*) ;;
    *) PATH="/opt/autowp-framac/bin:$PATH" ;;
esac
export PATH
export AUTOWP_FRAMAC_SWITCH=framac-coq8
export AUTOWP_FRAMAC_MACSL=/opt/autowp-framac/macsl/macsl.cmxs
export AUTOWP_FRAMAC_SRC=/opt/autowp-framac/src/frama-c-32.1
