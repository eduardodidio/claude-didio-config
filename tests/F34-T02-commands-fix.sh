#!/usr/bin/env bash
# F34-T02: Test alerts path/field mapping and board state rewrite
# Validates changes in commands.rs via structural checks + cargo check
set -euo pipefail

PASS=0
FAIL=0
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/blackhawk-desktop/src-tauri/src/commands.rs"

pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== F34-T02: Alerts Path + Field Mapping, Board State Rewrite ==="
echo ""

# --- Alerts tests ---
echo "-- Alerts --"

# AC1: get_alerts reads from logs/agents/flags/
if grep -q '"logs".*"agents".*"flags"' "$SRC"; then
  pass "get_alerts() reads from logs/agents/flags/"
else
  fail "get_alerts() should read from logs/agents/flags/"
fi

# AC2: flag_id -> id fallback
if grep -q 'parsed\["flag_id"\]' "$SRC" && grep -q 'parsed\["id"\]' "$SRC"; then
  pass "flag_id -> id fallback chaining present"
else
  fail "flag_id -> id fallback chaining missing"
fi

# AC3: type=blocked maps to critical
if grep -q '"blocked" => "critical"' "$SRC"; then
  pass "type=blocked maps to severity=critical"
else
  fail "type=blocked should map to severity=critical"
fi

# AC4: type=needs_review maps to warning
if grep -q '"needs_review"' "$SRC" && grep -q '=> "warning"' "$SRC"; then
  pass "type=needs_review maps to severity=warning"
else
  fail "type=needs_review should map to severity=warning"
fi

# AC5: raised_at -> created_at fallback
if grep -q 'parsed\["raised_at"\]' "$SRC" && grep -q 'parsed\["created_at"\]' "$SRC"; then
  pass "raised_at -> created_at fallback chaining present"
else
  fail "raised_at -> created_at fallback chaining missing"
fi

# AC6: Old field names still work (or_else chains)
if grep -c 'or_else' "$SRC" | grep -q '[3-9]'; then
  pass "Fallback or_else chains present for backward compat"
else
  fail "Expected multiple or_else chains for backward compat"
fi

echo ""
echo "-- Board State --"

# AC7: get_board_state reads pipeline-*.state.json
if grep -q 'pipeline-' "$SRC" && grep -q '.state.json' "$SRC"; then
  pass "get_board_state() reads pipeline-*.state.json files"
else
  fail "get_board_state() should read pipeline-*.state.json"
fi

# AC8: status=running + stage=waves -> RUNNING
if grep -q '"waves" => "RUNNING"' "$SRC"; then
  pass "stage=waves maps to column RUNNING"
else
  fail "stage=waves should map to column RUNNING"
fi

# AC9: status=completed -> DONE with progress 100
if grep -q '"completed" => ("DONE"' "$SRC" && grep -q 'if status == "completed" { 100 }' "$SRC"; then
  pass "status=completed maps to DONE with progress 100"
else
  fail "status=completed should map to DONE with progress 100"
fi

# AC10: status=failed -> hasBlockage=true
if grep -q '"failed" => (stage_to_column(stage), true)' "$SRC"; then
  pass "status=failed sets hasBlockage=true"
else
  fail "status=failed should set hasBlockage=true"
fi

# AC11: Progress = stages_completed.len() / 8 * 100
if grep -q 'ALL_STAGES' "$SRC" && grep -q 'stages_completed as f64 / ALL_STAGES.len() as f64' "$SRC"; then
  pass "Progress calculated as stages_completed / ALL_STAGES * 100"
else
  fail "Progress calculation missing or incorrect"
fi

# AC12: Feature name from feature field
if grep -q 'parsed\["feature"\].as_str()' "$SRC"; then
  pass "Feature name extracted from feature field"
else
  fail "Feature name should come from feature field"
fi

# AC13: parse_status_file removed
if grep -q 'fn parse_status_file' "$SRC"; then
  fail "parse_status_file() should be removed (dead code)"
else
  pass "parse_status_file() removed"
fi

# AC14: Sort order RUNNING > REVIEW > PLANNING > BACKLOG > DONE
if grep -q '"RUNNING" => 0' "$SRC" && grep -q '"DONE" => 4' "$SRC"; then
  pass "Board cards sorted: RUNNING > REVIEW > PLANNING > BACKLOG > DONE"
else
  fail "Board card sort order incorrect"
fi

echo ""
echo "-- Cargo Check --"

# AC15: Rust compiles
export PATH="/c/Users/eduar/.cargo/bin:$PATH"
TAURI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/blackhawk-desktop/src-tauri"
if cargo check --manifest-path "$TAURI_DIR/Cargo.toml" 2>&1 | grep -v '^warning:' | grep -q 'error'; then
  fail "cargo check has errors"
else
  pass "Rust compiles (cargo check passes)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
