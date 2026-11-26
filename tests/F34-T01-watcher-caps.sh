#!/usr/bin/env bash
# F34-T01: Verify watcher paths, capabilities, and board schema
set -euo pipefail

PASS=0
FAIL=0
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== F34-T01 Watcher + Capabilities Tests ==="

# 1. WATCH_PATHS includes logs/agents/flags (not logs/flags)
if grep -q '"logs/agents/flags"' "$PROJECT_ROOT/blackhawk-desktop/src-tauri/src/watcher.rs"; then
    pass "WATCH_PATHS has logs/agents/flags"
else
    fail "WATCH_PATHS missing logs/agents/flags"
fi

# Verify old logs/flags is gone
if grep -q '"logs/flags"' "$PROJECT_ROOT/blackhawk-desktop/src-tauri/src/watcher.rs"; then
    fail "Old logs/flags still present in WATCH_PATHS"
else
    pass "Old logs/flags removed"
fi

# 2. WATCH_PATHS includes logs/agents
if grep -q '"logs/agents"' "$PROJECT_ROOT/blackhawk-desktop/src-tauri/src/watcher.rs"; then
    pass "WATCH_PATHS has logs/agents"
else
    fail "WATCH_PATHS missing logs/agents"
fi

# 3. Pipeline state detection in event routing
if grep -q 'pipeline-' "$PROJECT_ROOT/blackhawk-desktop/src-tauri/src/watcher.rs"; then
    pass "Event routing checks for pipeline- files"
else
    fail "Event routing missing pipeline- check"
fi

# 4. Capabilities include write permissions
CAPS="$PROJECT_ROOT/blackhawk-desktop/src-tauri/capabilities/default.json"
if grep -q 'fs:write-files' "$CAPS"; then
    pass "Capabilities include fs:write-files"
else
    fail "Capabilities missing fs:write-files"
fi

if grep -q 'fs:create-app-specific-dirs' "$CAPS"; then
    pass "Capabilities include fs:create-app-specific-dirs"
else
    fail "Capabilities missing fs:create-app-specific-dirs"
fi

# 5. Board schema exists and is valid JSON
SCHEMA="$PROJECT_ROOT/schemas/board-status.schema.json"
if [ -f "$SCHEMA" ]; then
    pass "board-status.schema.json exists"
else
    fail "board-status.schema.json missing"
fi

if python3 -m json.tool "$SCHEMA" > /dev/null 2>&1; then
    pass "board-status.schema.json is valid JSON"
else
    fail "board-status.schema.json is invalid JSON"
fi

# 6. Existing watch paths still present (no regression)
for path in "logs/warroom" "logs/overlord" "tasks/features"; do
    if grep -q "\"$path\"" "$PROJECT_ROOT/blackhawk-desktop/src-tauri/src/watcher.rs"; then
        pass "WATCH_PATHS still has $path"
    else
        fail "WATCH_PATHS lost $path (regression)"
    fi
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
