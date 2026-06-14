#!/usr/bin/env bash
# Smoke test for drivers/DRIVER_CONTRACT.md using echo-driver.sh as fixture.
set -euo pipefail

DIDIO_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER="${DIDIO_HOME}/drivers/echo-driver.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- Happy path: writes >=1 valid JSON line, exit 0 ---
log="$tmpdir/happy.jsonl"
DIDIO_PROMPT="hello" DIDIO_MODEL="opus" DIDIO_FALLBACK="sonnet" \
  DIDIO_EFFORT="high" DIDIO_LOG_FILE="$log" DIDIO_ROLE="developer" \
  DIDIO_FEATURE="F01" DIDIO_TASK_ID="F01-T02" \
  "$DRIVER"
status=$?
[ "$status" -eq 0 ] || fail "happy path exit code $status != 0"
[ -s "$log" ] || fail "happy path log file empty"
lines=$(wc -l < "$log")
[ "$lines" -ge 1 ] || fail "happy path expected >=1 line, got $lines"
python3 -c "import json,sys; json.loads(open('$log').readline())" \
  || fail "happy path output is not valid JSON"
echo "PASS: happy path"

# --- Edge case: empty MODEL/FALLBACK does not error ---
log="$tmpdir/edge.jsonl"
DIDIO_PROMPT="hello" DIDIO_MODEL="" DIDIO_FALLBACK="" \
  DIDIO_EFFORT="" DIDIO_LOG_FILE="$log" DIDIO_ROLE="developer" \
  DIDIO_FEATURE="F01" DIDIO_TASK_ID="F01-T02" \
  "$DRIVER"
status=$?
[ "$status" -eq 0 ] || fail "edge case (empty model/fallback) exit code $status != 0"
[ -s "$log" ] || fail "edge case log file empty"
echo "PASS: edge case (empty model/fallback)"

# --- Error scenario: non-zero exit propagates ---
log="$tmpdir/error.jsonl"
set +e
DIDIO_PROMPT="hello" DIDIO_LOG_FILE="$log" DIDIO_ROLE="developer" \
  DIDIO_FEATURE="F01" DIDIO_TASK_ID="F01-T02" DIDIO_ECHO_EXIT_CODE=7 \
  "$DRIVER"
status=$?
set -e
[ "$status" -eq 7 ] || fail "error scenario expected exit 7, got $status"
echo "PASS: error scenario (exit 7 propagates)"

# --- Boundary values: prompt with quotes/newlines preserved ---
log="$tmpdir/boundary.jsonl"
prompt=$'line one with "quotes"\nline two'
DIDIO_PROMPT="$prompt" DIDIO_LOG_FILE="$log" DIDIO_ROLE="developer" \
  DIDIO_FEATURE="F01" DIDIO_TASK_ID="F01-T02" \
  "$DRIVER"
status=$?
[ "$status" -eq 0 ] || fail "boundary case exit code $status != 0"
expected_len=${#prompt}
actual_len=$(python3 -c "import json; print(json.loads(open('$log').readline())['prompt_len'])")
[ "$actual_len" -eq "$expected_len" ] || fail "boundary case prompt_len $actual_len != $expected_len"
echo "PASS: boundary values (quotes/newlines preserved)"

echo "All F01 driver contract tests passed."
