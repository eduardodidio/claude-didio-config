#!/usr/bin/env bash
# F34-T06: Integration test — Board, Alerts, Chat, Frontend wiring
# Creates fixture files and validates the full desktop wiring stack.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
ERRORS=""

# Fixture paths (test-only, cleaned up at exit)
AGENTS_DIR="$PROJECT_ROOT/logs/agents"
FLAGS_DIR="$AGENTS_DIR/flags"
OVERLORD_DIR="$PROJECT_ROOT/logs/overlord"

cleanup() {
  rm -f "$AGENTS_DIR/pipeline-F99.state.json"
  rm -f "$AGENTS_DIR/pipeline-F98.state.json"
  rm -f "$AGENTS_DIR/pipeline-F97.state.json"
  rm -f "$FLAGS_DIR/F99_blocked_test.json"
  rm -f "$FLAGS_DIR/F99_legacy_test.json"
  rm -f "$FLAGS_DIR/F99_resolved_test.json"
  rm -f "$OVERLORD_DIR/chat-2099-01-01.jsonl"
}

trap cleanup EXIT

check() {
  local desc="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  [PASS] $desc"
  else
    FAIL=$((FAIL + 1))
    ERRORS="$ERRORS\n  [FAIL] $desc"
    echo "  [FAIL] $desc"
  fi
}

echo "=== F34-T06: Desktop Wiring Integration Test ==="
echo ""

# ------------------------------------------------------------------
# 1. Create fixture directories
# ------------------------------------------------------------------
echo "--- Creating fixture directories ---"
mkdir -p "$AGENTS_DIR" "$FLAGS_DIR" "$OVERLORD_DIR"

# ------------------------------------------------------------------
# 2. Create pipeline state fixtures
# ------------------------------------------------------------------
echo "--- Creating pipeline state fixtures ---"

cat > "$AGENTS_DIR/pipeline-F99.state.json" << 'FIXTURE'
{
  "run_id": "test-F99-001",
  "feature": "F99",
  "status": "running",
  "stage": "waves",
  "stages_completed": ["handler_gate", "architect", "readiness", "tea"],
  "started_at": "2099-01-01T00:00:00Z"
}
FIXTURE

cat > "$AGENTS_DIR/pipeline-F98.state.json" << 'FIXTURE'
{
  "run_id": "test-F98-001",
  "feature": "F98",
  "status": "completed",
  "stage": "post_review",
  "stages_completed": ["handler_gate", "architect", "readiness", "tea", "waves", "techlead", "qa", "post_review"],
  "started_at": "2099-01-01T00:00:00Z",
  "exit_code": 0
}
FIXTURE

cat > "$AGENTS_DIR/pipeline-F97.state.json" << 'FIXTURE'
{
  "run_id": "test-F97-001",
  "feature": "F97",
  "status": "failed",
  "stage": "waves",
  "stages_completed": ["handler_gate", "architect"],
  "started_at": "2099-01-01T00:00:00Z",
  "exit_code": 1
}
FIXTURE

# ------------------------------------------------------------------
# 3. Create flag fixtures
# ------------------------------------------------------------------
echo "--- Creating flag fixtures ---"

# flags-lib format (modern)
cat > "$FLAGS_DIR/F99_blocked_test.json" << 'FIXTURE'
{
  "flag_id": "F99-BLK-001",
  "feature": "F99",
  "task": "F99-T01",
  "type": "blocked",
  "message": "Test blockage for integration test",
  "raised_at": "2099-01-01T00:00:00Z",
  "resolved": false
}
FIXTURE

# Legacy format (backward compat)
cat > "$FLAGS_DIR/F99_legacy_test.json" << 'FIXTURE'
{
  "id": "F99-LEG-001",
  "feature": "F99",
  "task": "F99-T02",
  "severity": "warning",
  "message": "Legacy format flag for backward compat test",
  "created_at": "2099-01-01T01:00:00Z",
  "resolved": false
}
FIXTURE

# Resolved flag
cat > "$FLAGS_DIR/F99_resolved_test.json" << 'FIXTURE'
{
  "flag_id": "F99-RES-001",
  "feature": "F99",
  "task": "F99-T03",
  "type": "blocked",
  "message": "Resolved flag for integration test",
  "raised_at": "2099-01-01T00:00:00Z",
  "resolved": true,
  "resolved_at": "2099-01-01T02:00:00Z"
}
FIXTURE

# ------------------------------------------------------------------
# 4. Create chat history fixture
# ------------------------------------------------------------------
echo "--- Creating chat history fixture ---"

cat > "$OVERLORD_DIR/chat-2099-01-01.jsonl" << 'FIXTURE'
{"id":"chat-test-001","role":"operator","content":"Hello Alpha","actions":[],"timestamp":"2099-01-01T00:00:00Z"}
{"id":"chat-test-002","role":"alpha","content":"Hello Operator. All systems nominal.","actions":[{"label":"Run triage","command":"triage","confirmed":false}],"timestamp":"2099-01-01T00:00:01Z"}
FIXTURE

# ------------------------------------------------------------------
# 5. Validate fixture JSON
# ------------------------------------------------------------------
echo ""
echo "--- Validating fixture JSON ---"

for f in \
  "$AGENTS_DIR/pipeline-F99.state.json" \
  "$AGENTS_DIR/pipeline-F98.state.json" \
  "$AGENTS_DIR/pipeline-F97.state.json" \
  "$FLAGS_DIR/F99_blocked_test.json" \
  "$FLAGS_DIR/F99_legacy_test.json" \
  "$FLAGS_DIR/F99_resolved_test.json"; do
  check "Valid JSON: $(basename "$f")" python3 -m json.tool "$f"
done

# JSONL: validate each line
check "Valid JSONL: chat-2099-01-01.jsonl" bash -c '
  while IFS= read -r line; do
    echo "$line" | python3 -m json.tool > /dev/null || exit 1
  done < "'"$OVERLORD_DIR/chat-2099-01-01.jsonl"'"
'

# ------------------------------------------------------------------
# 6. Validate fixture schema (structural checks)
# ------------------------------------------------------------------
echo ""
echo "--- Validating fixture schemas ---"

check "Pipeline F99 has status=running" bash -c '
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert d[\"status\"] == \"running\", f\"expected running, got {d[\"status\"]}\"
assert d[\"stage\"] == \"waves\", f\"expected waves, got {d[\"stage\"]}\"
" "'"$AGENTS_DIR/pipeline-F99.state.json"'"
'

check "Pipeline F98 has status=completed" bash -c '
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert d[\"status\"] == \"completed\"
" "'"$AGENTS_DIR/pipeline-F98.state.json"'"
'

check "Pipeline F97 has status=failed" bash -c '
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert d[\"status\"] == \"failed\"
" "'"$AGENTS_DIR/pipeline-F97.state.json"'"
'

check "Flag blocked has flag_id and type=blocked" bash -c '
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert \"flag_id\" in d, \"missing flag_id\"
assert d[\"type\"] == \"blocked\"
assert \"raised_at\" in d, \"missing raised_at\"
" "'"$FLAGS_DIR/F99_blocked_test.json"'"
'

check "Flag legacy has id and severity fields" bash -c '
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert \"id\" in d, \"missing id\"
assert \"severity\" in d, \"missing severity\"
assert \"created_at\" in d, \"missing created_at\"
" "'"$FLAGS_DIR/F99_legacy_test.json"'"
'

check "Flag resolved has resolved=true" bash -c '
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert d[\"resolved\"] is True
assert \"resolved_at\" in d
" "'"$FLAGS_DIR/F99_resolved_test.json"'"
'

check "Chat JSONL has 2 messages" bash -c '
  COUNT=$(wc -l < "'"$OVERLORD_DIR/chat-2099-01-01.jsonl"'")
  [ "$COUNT" -eq 2 ]
'

# ------------------------------------------------------------------
# 7. Structural grep checks (wiring verification)
# ------------------------------------------------------------------
echo ""
echo "--- Structural wiring checks ---"

SRC_TAURI="$PROJECT_ROOT/blackhawk-desktop/src-tauri/src"
SRC_TS="$PROJECT_ROOT/blackhawk-desktop/src"

check "commands.rs reads from logs/agents/flags" \
  grep -q 'logs/agents.*flags\|agents.*flags\|flags_dir\|"flags"' "$SRC_TAURI/commands.rs"

check "commands.rs reads pipeline- state files" \
  grep -q 'pipeline-' "$SRC_TAURI/commands.rs"

check "tauriBridge.ts exports onChatExternalUpdate" \
  grep -q 'onChatExternalUpdate' "$SRC_TS/lib/tauriBridge.ts"

check "useBlackhawkChat.ts listens for chat-external-update" \
  grep -q 'chat-external-update' "$SRC_TS/hooks/useBlackhawkChat.ts"

check "watcher.rs calls update_tray_from_alerts" \
  grep -q 'update_tray_from_alerts' "$SRC_TAURI/watcher.rs"

check "watcher.rs emits chat-external-update" \
  grep -q 'chat-external-update' "$SRC_TAURI/watcher.rs"

check "watcher.rs watches logs/agents/flags" \
  grep -q 'logs/agents/flags' "$SRC_TAURI/watcher.rs"

# ------------------------------------------------------------------
# 8. cargo check (Rust compilation)
# ------------------------------------------------------------------
echo ""
echo "--- Rust compilation check ---"

check "cargo check passes" bash -c '
  cd "'"$PROJECT_ROOT/blackhawk-desktop"'" && cargo check 2>&1
'

# ------------------------------------------------------------------
# 9. Frontend tests (Vitest)
# ------------------------------------------------------------------
echo ""
echo "--- Frontend tests (Vitest) ---"

check "npm run test passes" bash -c '
  cd "'"$PROJECT_ROOT/blackhawk-desktop"'" && npm run test 2>&1
'

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
  exit 1
fi

echo ""
echo "All checks passed."
exit 0
