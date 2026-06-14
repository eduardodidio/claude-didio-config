#!/usr/bin/env bash
#
# claude-driver.sh — Claude Code execution driver.
#
# Reproduces today's `claude -p` invocation verbatim (see
# tasks/features/F01-multi-model-providers/_brief/01-execution-provider-abstraction.md,
# "Current invocation"). Consumes the driver contract env vars defined in
# drivers/DRIVER_CONTRACT.md (F01-T02): DIDIO_PROMPT, DIDIO_MODEL,
# DIDIO_FALLBACK, DIDIO_EFFORT, DIDIO_LOG_FILE, DIDIO_ROLE, DIDIO_FEATURE,
# DIDIO_TASK_ID.
#
# AC3 fidelity: this reproduces the CURRENT didio-spawn-agent.sh invocation
# byte-for-byte, which DOES pass --effort (when DIDIO_EFFORT is set) and
# --allowedTools. (The F01 plan was written against an older snapshot that
# lacked these flags; preserving today's real behavior is what AC3 requires.)

set -uo pipefail

set +e
claude \
  -p "$DIDIO_PROMPT" \
  --output-format stream-json \
  --verbose \
  ${DIDIO_MODEL:+--model "$DIDIO_MODEL"} \
  ${DIDIO_FALLBACK:+--fallback-model "$DIDIO_FALLBACK"} \
  ${DIDIO_EFFORT:+--effort "$DIDIO_EFFORT"} \
  --dangerously-skip-permissions \
  --allowedTools "Edit Write MultiEdit Read Bash Glob Grep" \
  > "$DIDIO_LOG_FILE" 2>&1
EXIT_CODE=$?
set -e

exit $EXIT_CODE
