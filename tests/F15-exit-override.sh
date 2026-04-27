#!/usr/bin/env bash
# F15-exit-override.sh — unit tests for didio-jsonl-errors.py and the
# spawn-agent exit-code override logic.
# Run: bash tests/F15-exit-override.sh
# Exit 0 = all assertions pass.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARSER="$PROJECT_ROOT/bin/didio-jsonl-errors.py"
FIXTURES_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURES_DIR"' EXIT

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"
    ((PASS++)) || true
  else
    echo "  FAIL: $desc — expected=$expected got=$actual"
    ((FAIL++)) || true
  fi
}

# Helper: write a fixture JSONL and return the path
make_fixture() {
  local name="$1"
  local path="$FIXTURES_DIR/${name}.jsonl"
  shift
  printf '%s\n' "$@" > "$path"
  echo "$path"
}

echo "=== Parser unit tests (didio-jsonl-errors.py) ==="

# 1. One tool_result error → count 1
F=$(make_fixture "one_error" \
  '{"message":{"content":[{"type":"tool_result","is_error":true,"content":"denied"}]}}')
assert_eq "one tool_result error → count 1" "1" "$(python3 "$PARSER" "$F")"

# 2. All clean tool_results → count 0
F=$(make_fixture "no_errors" \
  '{"message":{"content":[{"type":"tool_result","is_error":false,"content":"ok"}]}}' \
  '{"message":{"content":[{"type":"tool_use","id":"x"}]}}')
assert_eq "zero tool_result errors → count 0" "0" "$(python3 "$PARSER" "$F")"

# 3. Malformed line + one error → count 1
F=$(make_fixture "malformed_plus_error" \
  'NOT VALID JSON {{{{' \
  '{"message":{"content":[{"type":"tool_result","is_error":true}]}}')
assert_eq "malformed line + one error → count 1" "1" "$(python3 "$PARSER" "$F")"

# 4. Multiple errors → correct count
F=$(make_fixture "multi_error" \
  '{"message":{"content":[{"type":"tool_result","is_error":true},{"type":"tool_result","is_error":true}]}}' \
  '{"message":{"content":[{"type":"tool_result","is_error":true}]}}')
assert_eq "5 tool errors across events → count 3" "3" "$(python3 "$PARSER" "$F")"

# 5. Empty file → count 0
F=$(make_fixture "empty")
assert_eq "empty JSONL → count 0" "0" "$(python3 "$PARSER" "$F")"

# 6. Missing file → count 0 (defensive)
assert_eq "missing file → count 0" "0" "$(python3 "$PARSER" "$FIXTURES_DIR/no_such_file.jsonl")"

# 7. Lines with is_error=null / missing → not counted
F=$(make_fixture "no_is_error_field" \
  '{"message":{"content":[{"type":"tool_result"}]}}' \
  '{"message":{"content":[{"type":"tool_result","is_error":null}]}}' \
  '{"message":{"content":[{"type":"tool_result","is_error":false}]}}')
assert_eq "is_error absent/null/false → count 0" "0" "$(python3 "$PARSER" "$F")"

echo ""
echo "=== Exit-code override logic (bash simulation) ==="

# Simulate the spawn-agent override block inline.
# Returns the final EXIT_CODE after applying the override.
simulate_override() {
  local log_file="$1"
  local initial_exit="$2"

  # Replicate the block from didio-spawn-agent.sh
  local TOOL_ERRORS EXIT_CODE
  EXIT_CODE="$initial_exit"
  TOOL_ERRORS=$(python3 "$PARSER" "$log_file" 2>/dev/null || echo 0)
  TOOL_ERRORS="${TOOL_ERRORS:-0}"
  if [[ "$TOOL_ERRORS" -gt 0 && "$EXIT_CODE" -eq 0 ]]; then
    EXIT_CODE=2
  fi
  echo "$EXIT_CODE"
}

# 8. Happy: zero errors, CLI exit 0 → stays 0
F=$(make_fixture "happy" \
  '{"message":{"content":[{"type":"tool_result","is_error":false}]}}')
assert_eq "zero errors, CLI exit 0 → exit 0 (no override)" "0" "$(simulate_override "$F" 0)"

# 9. Bug-reproducer: one error, CLI exit 0 → exit 2
F=$(make_fixture "bug_repro" \
  '{"message":{"content":[{"type":"tool_result","is_error":true}]}}')
assert_eq "one error, CLI exit 0 → exit 2" "2" "$(simulate_override "$F" 0)"

# 10. No-downgrade: CLI exit 1, zero errors → stays 1
F=$(make_fixture "no_downgrade_a" \
  '{"message":{"content":[{"type":"tool_result","is_error":false}]}}')
assert_eq "CLI exit 1, zero errors → exit 1 (untouched)" "1" "$(simulate_override "$F" 1)"

# 11. No-downgrade: CLI exit 1, parser errors → stays 1 (preserve original)
F=$(make_fixture "no_downgrade_b" \
  '{"message":{"content":[{"type":"tool_result","is_error":true}]}}')
assert_eq "CLI exit 1 AND parser errors → exit 1 (preserve original)" "1" "$(simulate_override "$F" 1)"

# 12. Multi-error: 5 errors, CLI exit 0 → exit 2
F=$(make_fixture "multi5" \
  '{"message":{"content":[{"type":"tool_result","is_error":true},{"type":"tool_result","is_error":true},{"type":"tool_result","is_error":true},{"type":"tool_result","is_error":true},{"type":"tool_result","is_error":true}]}}')
assert_eq "5 errors, CLI exit 0 → exit 2" "2" "$(simulate_override "$F" 0)"

# 13. Missing JSONL, CLI exit 0 → stays 0 (parser returns 0 defensively)
assert_eq "missing JSONL, CLI exit 0 → exit 0 (no override)" "0" "$(simulate_override "$FIXTURES_DIR/missing.jsonl" 0)"

echo ""
echo "=== bash -n syntax check ==="
if bash -n "$PROJECT_ROOT/bin/didio-spawn-agent.sh" 2>&1; then
  echo "  PASS: bash -n didio-spawn-agent.sh"
  ((PASS++)) || true
else
  echo "  FAIL: bash -n didio-spawn-agent.sh"
  ((FAIL++)) || true
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
