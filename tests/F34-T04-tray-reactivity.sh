#!/usr/bin/env bash
# F34-T04: Verify tray icon wiring to alert state changes
set -euo pipefail

PASS=0
FAIL=0
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHER="$PROJECT_ROOT/blackhawk-desktop/src-tauri/src/watcher.rs"

pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== F34-T04 Tray Reactivity Tests ==="

# 1. update_tray_from_alerts function exists
if grep -q 'fn update_tray_from_alerts' "$WATCHER"; then
    pass "update_tray_from_alerts function exists"
else
    fail "update_tray_from_alerts function missing"
fi

# 2. update_tray_from_alerts is called after emit_alert_update
if grep -A2 'emit_alert_update(&app_handle)' "$WATCHER" | grep -q 'update_tray_from_alerts'; then
    pass "update_tray_from_alerts called after emit_alert_update"
else
    fail "update_tray_from_alerts not called after emit_alert_update"
fi

# 3. Silent mode check present
if grep -q 'silent_mode.lock()' "$WATCHER"; then
    pass "Silent mode check present in watcher"
else
    fail "Silent mode check missing"
fi

# 4. TrayStatus::Muted used for silent mode
if grep -q 'TrayStatus::Muted' "$WATCHER"; then
    pass "TrayStatus::Muted used for silent mode"
else
    fail "TrayStatus::Muted not found"
fi

# 5. TrayStatus::Alert used for critical alerts
if grep -q 'TrayStatus::Alert' "$WATCHER"; then
    pass "TrayStatus::Alert used for critical alerts"
else
    fail "TrayStatus::Alert not found"
fi

# 6. TrayStatus::Nominal used when no critical alerts
if grep -q 'TrayStatus::Nominal' "$WATCHER"; then
    pass "TrayStatus::Nominal used for clear state"
else
    fail "TrayStatus::Nominal not found"
fi

# 7. Filters for active + critical alerts
if grep -q 'a.status == "active"' "$WATCHER" && grep -q 'a.severity == "critical"' "$WATCHER"; then
    pass "Filters for active critical alerts"
else
    fail "Missing active/critical filter logic"
fi

# 8. Active total count computed
if grep -q 'active_total' "$WATCHER"; then
    pass "Active total count computed"
else
    fail "Active total count not found"
fi

# 9. tauri::Manager imported (needed for app.state::<T>())
if grep -q 'use tauri::Manager' "$WATCHER"; then
    pass "tauri::Manager imported"
else
    fail "tauri::Manager import missing"
fi

# 10. AppState accessed from app handle
if grep -q 'app.state::<crate::notifications::AppState>' "$WATCHER"; then
    pass "AppState accessed via app.state()"
else
    fail "AppState access not found"
fi

# 11. Cargo check passes
if "C:/Users/eduar/.cargo/bin/cargo.exe" check --manifest-path "$PROJECT_ROOT/blackhawk-desktop/src-tauri/Cargo.toml" 2>&1 | tail -1 | grep -q 'Finished'; then
    pass "cargo check passes"
else
    fail "cargo check failed"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || exit 1
