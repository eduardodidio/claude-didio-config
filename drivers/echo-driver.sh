#!/usr/bin/env bash
# Test fixture driver implementing DRIVER_CONTRACT.md.
# Writes one NDJSON line to $DIDIO_LOG_FILE and exits 0 (or
# $DIDIO_ECHO_EXIT_CODE if set), to validate the contract end-to-end.
set -u

prompt_len=${#DIDIO_PROMPT}

{
  printf '{"type":"echo","role":"%s","feature":"%s","task_id":"%s","prompt_len":%d,"model":"%s","fallback":"%s","effort":"%s"}\n' \
    "${DIDIO_ROLE:-}" "${DIDIO_FEATURE:-}" "${DIDIO_TASK_ID:-}" "$prompt_len" \
    "${DIDIO_MODEL:-}" "${DIDIO_FALLBACK:-}" "${DIDIO_EFFORT:-}"
} >> "$DIDIO_LOG_FILE" 2>&1

exit "${DIDIO_ECHO_EXIT_CODE:-0}"
