#!/usr/bin/env bash
#
# Smoke test for drivers/codex-driver.sh (F01-T08).
#
# Stubs `codex` on PATH to assert the driver forwards `exec --json --yolo
# [--model X]`, delivers the prompt via stdin, writes NDJSON to
# $DIDIO_LOG_FILE, and propagates exit code.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER="$ROOT_DIR/drivers/codex-driver.sh"

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

# Build a stub `codex` that records its args + stdin, emits canned NDJSON,
# and exits with a code controlled via $STUB_EXIT_CODE.
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT

cat > "$STUB_DIR/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_ARGS_FILE"
cat > "$STUB_STDIN_FILE"
echo '{"type":"item.completed","item":{"type":"agent_message"}}'
echo '{"type":"turn.completed"}'
exit "${STUB_EXIT_CODE:-0}"
EOF
chmod +x "$STUB_DIR/codex"

export PATH="$STUB_DIR:$PATH"
export STUB_ARGS_FILE="$STUB_DIR/args"
export STUB_STDIN_FILE="$STUB_DIR/stdin"
LOG_FILE="$STUB_DIR/agent.jsonl"

# --- Happy path: full flag set ---------------------------------------------
export DIDIO_PROMPT="hello world"
export DIDIO_MODEL="gpt-5-codex"
export DIDIO_FALLBACK="haiku"
export DIDIO_EFFORT="high"
export DIDIO_LOG_FILE="$LOG_FILE"
export DIDIO_ROLE="developer"
export DIDIO_FEATURE="F01"
export DIDIO_TASK_ID="F01-T08"
export STUB_EXIT_CODE=0

"$DRIVER"
EXIT_CODE=$?

ARGS="$(cat "$STUB_ARGS_FILE")"
EXPECTED_ARGS='exec --json --yolo --model gpt-5-codex -'
assert_eq "happy path: exit code 0" "0" "$EXIT_CODE"
assert_eq "happy path: golden flag set" "$EXPECTED_ARGS" "$ARGS"
assert_eq "happy path: prompt delivered via stdin" "hello world" "$(cat "$STUB_STDIN_FILE")"
assert_contains "happy path: NDJSON written to log file" "$(cat "$LOG_FILE")" '"type":"item.completed"'

if [[ "$ARGS" == *"--effort"* ]]; then
  echo "FAIL - happy path: --effort must not be passed"
  FAILURES=$((FAILURES + 1))
else
  echo "ok - happy path: --effort not passed despite DIDIO_EFFORT set"
fi

if [[ "$ARGS" == *"--fallback"* ]]; then
  echo "FAIL - happy path: --fallback-model must not be passed"
  FAILURES=$((FAILURES + 1))
else
  echo "ok - happy path: --fallback-model not passed despite DIDIO_FALLBACK set"
fi

# --- Edge case: empty DIDIO_MODEL → --model omitted -------------------------
rm -f "$STUB_ARGS_FILE" "$STUB_STDIN_FILE" "$LOG_FILE"
export DIDIO_MODEL=""
export STUB_EXIT_CODE=0

"$DRIVER"
EXIT_CODE=$?

ARGS="$(cat "$STUB_ARGS_FILE")"
EXPECTED_ARGS='exec --json --yolo -'
assert_eq "edge case: exit code 0" "0" "$EXIT_CODE"
assert_eq "edge case: no --model when DIDIO_MODEL empty" "$EXPECTED_ARGS" "$ARGS"

# --- Error scenario: stub codex exits 2 → driver exits 2 --------------------
rm -f "$STUB_ARGS_FILE" "$STUB_STDIN_FILE" "$LOG_FILE"
export DIDIO_MODEL="gpt-5-codex"
export STUB_EXIT_CODE=2

"$DRIVER"
EXIT_CODE=$?

assert_eq "error scenario: driver propagates exit code 2" "2" "$EXIT_CODE"
assert_contains "error scenario: NDJSON still written to log file" "$(cat "$LOG_FILE")" '"type":"turn.completed"'

# --- Boundary values: multiline prompt with quotes delivered intact --------
rm -f "$STUB_ARGS_FILE" "$STUB_STDIN_FILE" "$LOG_FILE"
export DIDIO_PROMPT=$'line one "quoted"\nline two with '\''single quotes'\''\nline three'
export STUB_EXIT_CODE=0

"$DRIVER"
EXIT_CODE=$?

assert_eq "boundary: exit code 0" "0" "$EXIT_CODE"
assert_eq "boundary: multiline prompt with quotes delivered intact via stdin" "$DIDIO_PROMPT" "$(cat "$STUB_STDIN_FILE")"

echo "---"
if [[ $FAILURES -eq 0 ]]; then
  echo "PASS: all F01-codex-driver checks passed"
  exit 0
else
  echo "FAIL: $FAILURES check(s) failed"
  exit 1
fi
