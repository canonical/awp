#!/usr/bin/env bash
# Shared, fail-closed selection before any container or credential operation.
HARNESS=${HARNESS:-claude}
HARNESS_CREDENTIAL=${HARNESS_CREDENTIAL:-file}
case $HARNESS in
    claude|opencode) ;;
    *) echo "ERROR: HARNESS=$HARNESS: unknown harness (copilot is not implemented yet)" >&2; exit 2 ;;
esac
case $HARNESS_CREDENTIAL in
    file) ;;
    persisted) echo "ERROR: persisted credentials require the unverified Route A connection flow" >&2; exit 2 ;;
    *) echo "ERROR: HARNESS_CREDENTIAL=$HARNESS_CREDENTIAL: unknown credential mode" >&2; exit 2 ;;
esac
if [ "$HARNESS" = opencode ] &&
   ! [[ ${AUTOWP_OPENCODE_KEY_ENV:-ANTHROPIC_API_KEY} =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "ERROR: AUTOWP_OPENCODE_KEY_ENV must be an environment variable name" >&2
    exit 2
fi
