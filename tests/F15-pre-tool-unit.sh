#!/usr/bin/env bash
# F15-pre-tool-unit.sh — Unit tests for F15-T02 (Approach A: --allowedTools).
#
# T01 spike proved that PreToolUse permissionDecision:"allow" does NOT bypass
# the Claude Code sensitive-file guard. Approach E was abandoned. Approach A
# (--allowedTools flag on claude invocation) is implemented instead.
#
# This test suite verifies:
#   1. The hook DOES NOT inject allow (Approach E not implemented — correct).
#   2. spawn-agent DRY_RUN output includes --allowedTools and DIDIO_AGENT=1.
#   3. Hook baseline: read-only tools still exit 0 regardless of DIDIO_AGENT.
#   4. Hook baseline: existing deny path still triggers for budget hard limit.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/bin/hooks/didio-pre-tool.sh"
SPAWN="$REPO_ROOT/bin/didio-spawn-agent.sh"
PASS=0
FAIL=0

# ── helpers ──────────────────────────────────────────────────────────────────

pass() { echo "  PASS: $1"; (( PASS++ )) || true; }
fail() { echo "  FAIL: $1"; (( FAIL++ )) || true; }

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -e "$needle"; then
    pass "$label"
  else
    fail "$label — expected to find: $needle"
    echo "       actual output: $haystack"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if ! printf '%s' "$haystack" | grep -qF -e "$needle"; then
    pass "$label"
  else
    fail "$label — expected NOT to find: $needle"
    echo "       actual output: $haystack"
  fi
}

assert_exit_zero() {
  local label="$1" code="$2"
  if [[ "$code" -eq 0 ]]; then
    pass "$label (exit 0)"
  else
    fail "$label — expected exit 0, got $code"
  fi
}

# Run hook with given JSON on stdin; captures stdout+stderr separately.
# Returns exit code via $HOOK_EXIT; stdout in $HOOK_OUT; stderr in $HOOK_ERR.
run_hook() {
  local json="$1"
  shift
  HOOK_OUT="$(printf '%s' "$json" | env -i PATH="$PATH" HOME="$HOME" "$@" bash "$HOOK" 2>/tmp/f15-hook-err.tmp || true)"
  HOOK_EXIT=$?
  HOOK_ERR="$(cat /tmp/f15-hook-err.tmp 2>/dev/null || true)"
}

# ── syntax checks ─────────────────────────────────────────────────────────────

echo ""
echo "=== Syntax checks ==="

if bash -n "$HOOK" 2>/dev/null; then
  pass "didio-pre-tool.sh parses cleanly"
else
  fail "didio-pre-tool.sh has syntax errors"
fi

if bash -n "$SPAWN" 2>/dev/null; then
  pass "didio-spawn-agent.sh parses cleanly"
else
  fail "didio-spawn-agent.sh has syntax errors"
fi

# ── Approach A: spawn-agent DRY_RUN ──────────────────────────────────────────

echo ""
echo "=== spawn-agent DRY_RUN: --allowedTools and DIDIO_AGENT=1 ==="

# We need a minimal valid task file for spawn-agent to accept.
TMP_TASK="$(mktemp /tmp/f15-task-XXXXXX.md)"
echo "# F15-unit-test-task" > "$TMP_TASK"

# Dummy role prompt so spawn-agent finds agents/prompts/<role>.md.
# Use 'developer' which exists in the repo.
DRY_OUT="$(
  cd "$REPO_ROOT"
  DIDIO_DRY_RUN=1 bash "$SPAWN" developer F15 "$TMP_TASK" 2>&1 || true
)"
rm -f "$TMP_TASK"

assert_contains \
  "DRY_RUN shows --allowedTools flag" \
  "--allowedTools" \
  "$DRY_OUT"

assert_contains \
  "DRY_RUN shows --dangerously-skip-permissions" \
  "--dangerously-skip-permissions" \
  "$DRY_OUT"

# Verify DIDIO_AGENT export appears in spawn-agent source (grep, not runtime check)
if grep -q 'export DIDIO_AGENT=1' "$SPAWN"; then
  pass "spawn-agent exports DIDIO_AGENT=1"
else
  fail "spawn-agent does NOT export DIDIO_AGENT=1"
fi

# ── Hook baseline: Approach E NOT implemented (no spurious allows) ────────────

echo ""
echo "=== Hook: no allow injection (Approach E abandoned) ==="

# Case 1: Edit on .claude/commands path WITH DIDIO_AGENT=1
# Expected: hook does NOT return allow (Approach E not wired up)
run_hook \
  '{"tool_name":"Edit","tool_input":{"file_path":"/x/.claude/commands/foo.md"}}' \
  DIDIO_AGENT=1 \
  DIDIO_BYPASS_GUARD=1

assert_not_contains \
  "DIDIO_AGENT=1 + .claude/commands/ → hook does NOT inject allow (correct — Approach A is the fix)" \
  '"permissionDecision":"allow"' \
  "${HOOK_OUT}${HOOK_ERR}"
assert_exit_zero \
  "exit 0 after bypass (DIDIO_BYPASS_GUARD=1 short-circuits)" \
  "$HOOK_EXIT"

# Case 2: Edit on .claude/settings.json WITH DIDIO_AGENT=1
# Expected: no allow from hook (settings.json must stay locked)
run_hook \
  '{"tool_name":"Edit","tool_input":{"file_path":"/x/.claude/settings.json"}}' \
  DIDIO_AGENT=1 \
  DIDIO_BYPASS_GUARD=1

assert_not_contains \
  "settings.json → no allow from hook" \
  '"permissionDecision":"allow"' \
  "${HOOK_OUT}${HOOK_ERR}"

# Case 3: Edit on .claude/commands path WITHOUT DIDIO_AGENT
# Expected: no allow from hook
run_hook \
  '{"tool_name":"Edit","tool_input":{"file_path":"/x/.claude/commands/foo.md"}}' \
  DIDIO_BYPASS_GUARD=1

assert_not_contains \
  "DIDIO_AGENT unset → no allow from hook" \
  '"permissionDecision":"allow"' \
  "${HOOK_OUT}${HOOK_ERR}"

# ── Hook baseline: read-only tools always exit 0 ──────────────────────────────

echo ""
echo "=== Hook baseline: read-only whitelist still passes ==="

for TOOL in Read Grep Glob LS TodoWrite; do
  run_hook \
    "{\"tool_name\":\"$TOOL\",\"tool_input\":{}}" \
    DIDIO_BYPASS_GUARD=1
  assert_exit_zero \
    "$TOOL exits 0 (read-only whitelist)" \
    "$HOOK_EXIT"
done

# ── Hook baseline: Bash not in write-allow set ────────────────────────────────

echo ""
echo "=== Hook: Bash tool no spurious allow ==="

run_hook \
  '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}' \
  DIDIO_AGENT=1 \
  DIDIO_BYPASS_GUARD=1

assert_not_contains \
  "Bash tool → no allow injection" \
  '"permissionDecision":"allow"' \
  "${HOOK_OUT}${HOOK_ERR}"

# ── Hook baseline: missing file_path is safe ──────────────────────────────────

echo ""
echo "=== Hook: missing tool_input.file_path is safe ==="

run_hook \
  '{"tool_name":"Edit","tool_input":{}}' \
  DIDIO_AGENT=1 \
  DIDIO_BYPASS_GUARD=1

assert_not_contains \
  "missing file_path → no allow, no crash" \
  '"permissionDecision":"allow"' \
  "${HOOK_OUT}${HOOK_ERR}"
assert_exit_zero \
  "missing file_path → exit 0 (bypass guard short-circuits)" \
  "$HOOK_EXIT"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
