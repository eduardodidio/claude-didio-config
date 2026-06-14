#!/usr/bin/env bash
#
# Smoke test for drivers/claude-driver.sh (F01-T05).
#
# Stubs `claude` on PATH to assert the driver forwards the exact flag set
# used by today's didio-spawn-agent.sh invocation (golden string compare,
# protects AC3), writes NDJSON to $DIDIO_LOG_FILE, and propagates exit code.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER="$ROOT_DIR/drivers/claude-driver.sh"

FAILURES=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc (expected to contain: $needle)"
    echo "  actual: $haystack"
    FAILURES=$((FAILURES + 1))
  fi
}

# Build a stub `claude` that records its args, emits canned NDJSON, and
# exits with a code controlled via $STUB_EXIT_CODE.
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT

cat > "$STUB_DIR/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_ARGS_FILE"
echo '{"type":"system","subtype":"init"}'
echo '{"type":"result","subtype":"success"}'
exit "${STUB_EXIT_CODE:-0}"
EOF
chmod +x "$STUB_DIR/claude"

export PATH="$STUB_DIR:$PATH"
export STUB_ARGS_FILE="$STUB_DIR/args"
LOG_FILE="$STUB_DIR/agent.jsonl"

# --- Happy path: full flag set, golden string compare ---------------------
export DIDIO_PROMPT="hello world"
export DIDIO_MODEL="sonnet"
export DIDIO_FALLBACK="haiku"
export DIDIO_EFFORT="high"
export DIDIO_LOG_FILE="$LOG_FILE"
export DIDIO_ROLE="developer"
export DIDIO_FEATURE="F01"
export DIDIO_TASK_ID="F01-T05"
export STUB_EXIT_CODE=0

"$DRIVER"
EXIT_CODE=$?

ARGS="$(cat "$STUB_ARGS_FILE")"
EXPECTED_ARGS='-p hello world --output-format stream-json --verbose --model sonnet --fallback-model haiku --effort high --dangerously-skip-permissions --allowedTools Edit Write MultiEdit Read Bash Glob Grep'
assert_eq "happy path: exit code 0" "0" "$EXIT_CODE"
assert_eq "happy path: golden flag set (AC3)" "$EXPECTED_ARGS" "$ARGS"
assert_contains "happy path: NDJSON written to log file" "$(cat "$LOG_FILE")" '"type":"system"'
if [[ "$ARGS" == *"--effort high"* ]]; then
  echo "ok - happy path: --effort passed from DIDIO_EFFORT (AC3: matches current spawn-agent)"
else
  echo "FAIL - happy path: --effort must be passed when DIDIO_EFFORT is set"
  FAILURES=$((FAILURES + 1))
fi
if [[ "$ARGS" == *"--allowedTools"* ]]; then
  echo "ok - happy path: --allowedTools passed (AC3: matches current spawn-agent)"
else
  echo "FAIL - happy path: --allowedTools must be passed"
  FAILURES=$((FAILURES + 1))
fi

# --- Edge case: empty DIDIO_MODEL/DIDIO_FALLBACK → flags omitted -----------
rm -f "$STUB_ARGS_FILE" "$LOG_FILE"
export DIDIO_MODEL=""
export DIDIO_FALLBACK=""
export STUB_EXIT_CODE=0

"$DRIVER"
EXIT_CODE=$?

ARGS="$(cat "$STUB_ARGS_FILE")"
EXPECTED_ARGS='-p hello world --output-format stream-json --verbose --effort high --dangerously-skip-permissions --allowedTools Edit Write MultiEdit Read Bash Glob Grep'
assert_eq "edge case: exit code 0" "0" "$EXIT_CODE"
assert_eq "edge case: no --model/--fallback-model when empty" "$EXPECTED_ARGS" "$ARGS"

# --- Error scenario: stub claude exits 1 → driver exits 1 ------------------
rm -f "$STUB_ARGS_FILE" "$LOG_FILE"
export DIDIO_MODEL="sonnet"
export DIDIO_FALLBACK="haiku"
export STUB_EXIT_CODE=1

"$DRIVER"
EXIT_CODE=$?

assert_eq "error scenario: driver propagates exit code 1" "1" "$EXIT_CODE"
assert_contains "error scenario: NDJSON still written to log file" "$(cat "$LOG_FILE")" '"type":"result"'

echo "---"
if [[ $FAILURES -eq 0 ]]; then
  echo "PASS: all F01-claude-driver checks passed"
  exit 0
else
  echo "FAIL: $FAILURES check(s) failed"
  exit 1
fi
