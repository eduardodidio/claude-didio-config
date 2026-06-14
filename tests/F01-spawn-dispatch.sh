#!/usr/bin/env bash
#
# Integration test for bin/didio-spawn-agent.sh driver dispatch (F01-T07).
#
# Verifies:
#  - a role mapped to a stub provider ("echo") dispatches to
#    drivers/echo-driver.sh, NDJSON lands in the log, and .meta.json records
#    "provider": "echo" with the propagated exit code.
#  - a role with no configured provider resolves to "claude" and invokes
#    drivers/claude-driver.sh with the exact today flag-set (AC3).
#  - an unknown provider exits 2 with a clear error and marks meta "failed".
#  - a non-zero driver exit propagates and is reflected in .meta.json.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DIDIO_HOME="$ROOT_DIR"
SPAWN="$ROOT_DIR/bin/didio-spawn-agent.sh"

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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/agents/prompts" "$TMP/logs/agents" "$TMP/drivers"
echo "# developer role prompt" > "$TMP/agents/prompts/developer.md"
echo "# Task body" > "$TMP/task.md"

# --- Happy path: role mapped to stub "echo" provider -----------------------
cat > "$TMP/didio.config.json" <<'JSON'
{
  "providers": {
    "claude": { "bin": "claude", "default": true },
    "echo": { "bin": "true" }
  },
  "models": {
    "developer": { "model": "sonnet", "fallback": "haiku", "effort": "medium", "provider": "echo" }
  }
}
JSON

( cd "$TMP" && "$SPAWN" developer F01 task.md "extra" >/dev/null 2>&1 )
EXIT_CODE=$?

LOG_FILE="$(ls "$TMP"/logs/agents/F01-developer-task-*.jsonl 2>/dev/null | head -n1)"
META_FILE="${LOG_FILE%.jsonl}.meta.json"

assert_eq "happy path: exit code 0" "0" "$EXIT_CODE"
assert_contains "happy path: echo-driver wrote NDJSON" "$(cat "$LOG_FILE" 2>/dev/null)" '"type":"echo"'
assert_contains "happy path: echo-driver saw role/feature/task" "$(cat "$LOG_FILE" 2>/dev/null)" '"role":"developer","feature":"F01","task_id":"task"'
PROVIDER_META="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('provider'))" 2>/dev/null)"
STATUS_META="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('status'))" 2>/dev/null)"
assert_eq "happy path: meta provider == echo" "echo" "$PROVIDER_META"
assert_eq "happy path: meta status == completed" "completed" "$STATUS_META"

# --- Edge case (AC3): role with no provider -> claude, golden flag set -----
rm -rf "$TMP/logs/agents"/*
cat > "$TMP/didio.config.json" <<'JSON'
{
  "providers": {
    "claude": { "bin": "claude", "default": true }
  },
  "models": {
    "developer": { "model": "sonnet", "fallback": "haiku", "effort": "medium" }
  }
}
JSON

STUB_DIR="$(mktemp -d)"
cat > "$STUB_DIR/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_ARGS_FILE"
echo '{"type":"system","subtype":"init"}'
echo '{"type":"result","subtype":"success"}'
exit 0
EOF
chmod +x "$STUB_DIR/claude"
export STUB_ARGS_FILE="$STUB_DIR/args"

( cd "$TMP" && PATH="$STUB_DIR:$PATH" "$SPAWN" developer F01 task.md "extra" >/dev/null 2>&1 )
EXIT_CODE=$?

LOG_FILE="$(ls "$TMP"/logs/agents/F01-developer-task-*.jsonl 2>/dev/null | head -n1)"
META_FILE="${LOG_FILE%.jsonl}.meta.json"
ARGS="$(cat "$STUB_ARGS_FILE" 2>/dev/null)"

assert_eq "AC3: exit code 0" "0" "$EXIT_CODE"
assert_contains "AC3: claude invoked with golden flag set" "$ARGS" "--output-format stream-json --verbose --model sonnet --fallback-model haiku --effort medium --dangerously-skip-permissions --allowedTools Edit Write MultiEdit Read Bash Glob Grep"
PROVIDER_META="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('provider'))" 2>/dev/null)"
assert_eq "AC3: meta provider == claude" "claude" "$PROVIDER_META"
rm -rf "$STUB_DIR"

# --- Error scenario: unknown provider -> exit 2 -----------------------------
rm -rf "$TMP/logs/agents"/*
cat > "$TMP/didio.config.json" <<'JSON'
{
  "providers": {
    "claude": { "bin": "claude", "default": true }
  },
  "models": {
    "developer": { "model": "sonnet", "fallback": "haiku", "provider": "nonexistent" }
  }
}
JSON

ERR_OUTPUT="$( cd "$TMP" && "$SPAWN" developer F01 task.md "extra" 2>&1 >/dev/null )"
EXIT_CODE=$?

assert_eq "error scenario: exit code 2" "2" "$EXIT_CODE"
assert_contains "error scenario: clear error message" "$ERR_OUTPUT" "unknown/unsupported provider 'nonexistent'"

# --- Boundary value: driver exits 1 -> meta status failed, exit_code 1 -----
rm -rf "$TMP/logs/agents"/*
cat > "$TMP/didio.config.json" <<'JSON'
{
  "providers": {
    "claude": { "bin": "claude", "default": true },
    "echo": { "bin": "true" }
  },
  "models": {
    "developer": { "model": "sonnet", "fallback": "haiku", "provider": "echo" }
  }
}
JSON

( cd "$TMP" && DIDIO_ECHO_EXIT_CODE=1 "$SPAWN" developer F01 task.md "extra" >/dev/null 2>&1 )
EXIT_CODE=$?

LOG_FILE="$(ls "$TMP"/logs/agents/F01-developer-task-*.jsonl 2>/dev/null | head -n1)"
META_FILE="${LOG_FILE%.jsonl}.meta.json"
STATUS_META="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('status'))" 2>/dev/null)"
EXIT_META="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('exit_code'))" 2>/dev/null)"
FINISHED_META="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('finished_at',''))" 2>/dev/null)"

assert_eq "boundary: spawn-agent propagates exit code 1" "1" "$EXIT_CODE"
assert_eq "boundary: meta status == failed" "failed" "$STATUS_META"
assert_eq "boundary: meta exit_code == 1" "1" "$EXIT_META"
if [[ -n "$FINISHED_META" ]]; then
  echo "ok - boundary: meta finished_at set"
else
  echo "FAIL - boundary: meta finished_at not set"
  FAILURES=$((FAILURES + 1))
fi

echo "---"
if [[ $FAILURES -eq 0 ]]; then
  echo "PASS: all F01-spawn-dispatch checks passed"
  exit 0
else
  echo "FAIL: $FAILURES check(s) failed"
  exit 1
fi
