#!/usr/bin/env bash
# F34-T03: Verify Claude CLI bridge in commands.rs
set -euo pipefail

PASS=0
FAIL=0
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD="$PROJECT_ROOT/blackhawk-desktop/src-tauri/src/commands.rs"
NOTIF="$PROJECT_ROOT/blackhawk-desktop/src-tauri/src/notifications.rs"

pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== F34-T03 Claude CLI Bridge Tests ==="

# 1. call_claude_cli function exists
if grep -q 'fn call_claude_cli' "$CMD"; then
    pass "call_claude_cli function exists"
else
    fail "call_claude_cli function missing"
fi

# 2. Old generate_alpha_response stub removed
if grep -q 'fn generate_alpha_response' "$CMD"; then
    fail "Old generate_alpha_response stub still present"
else
    pass "Old generate_alpha_response stub removed"
fi

# 3. claude -p invocation pattern
if grep -q 'Command::new("claude")' "$CMD"; then
    pass "Spawns claude binary"
else
    fail "Missing Command::new(\"claude\") call"
fi

if grep -q '\.arg("-p")' "$CMD"; then
    pass "Uses -p flag for prompt mode"
else
    fail "Missing -p flag"
fi

# 4. parse_alpha_output function exists
if grep -q 'fn parse_alpha_output' "$CMD"; then
    pass "parse_alpha_output function exists"
else
    fail "parse_alpha_output function missing"
fi

# 5. ACTION parsing pattern
if grep -q '\[ACTION: ' "$CMD"; then
    pass "ACTION prefix pattern present in parser"
else
    fail "ACTION parsing pattern missing"
fi

# 6. NotFound error handling (graceful degradation)
if grep -q 'NotFound' "$CMD"; then
    pass "Handles NotFound error (claude not on PATH)"
else
    fail "Missing NotFound error handling"
fi

# 7. Graceful error in chat (not Err)
if grep -q 'format!("\[Error\]' "$CMD"; then
    pass "Errors returned as chat content (graceful degradation)"
else
    fail "Missing graceful error handling in send_chat"
fi

# 8. chat_lock Mutex in AppState
if grep -q 'chat_lock: Mutex<()>' "$NOTIF"; then
    pass "chat_lock field in AppState"
else
    fail "chat_lock missing from AppState"
fi

# 9. chat_lock initialized in new()
if grep -q 'chat_lock: Mutex::new(())' "$NOTIF"; then
    pass "chat_lock initialized in AppState::new()"
else
    fail "chat_lock not initialized"
fi

# 10. send_chat acquires chat_lock
if grep -q 'state.chat_lock.lock()' "$CMD"; then
    pass "send_chat acquires chat_lock"
else
    fail "send_chat does not acquire chat_lock"
fi

# 11. System prompt contains Black Hawk Alpha identity
if grep -q 'Black Hawk Alpha' "$CMD"; then
    pass "System prompt includes Black Hawk Alpha identity"
else
    fail "System prompt missing Black Hawk Alpha identity"
fi

# 12. chat-response event still emitted
if grep -q 'emit("chat-response"' "$CMD"; then
    pass "chat-response event still emitted"
else
    fail "chat-response event emission missing"
fi

# 13. JSONL persistence (append_chat_message called for both messages)
APPEND_COUNT=$(grep -c 'append_chat_message' "$CMD" || true)
if [ "$APPEND_COUNT" -ge 2 ]; then
    pass "append_chat_message called for both operator and alpha messages"
else
    fail "append_chat_message not called for both messages (found $APPEND_COUNT)"
fi

# 14. Cargo check passes
if command -v cargo &>/dev/null || [ -f "/c/Users/eduar/.cargo/bin/cargo.exe" ]; then
    export PATH="/c/Users/eduar/.cargo/bin:$PATH"
    echo "  Running cargo check..."
    if (cd "$PROJECT_ROOT/blackhawk-desktop/src-tauri" && cargo check 2>&1); then
        pass "cargo check passes with no errors"
    else
        fail "cargo check failed"
    fi
else
    echo "  SKIP: cargo not found, skipping compilation check"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
