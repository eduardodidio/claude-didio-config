#!/usr/bin/env bash
# F31-warroom-smoke.sh — TAP-compatible smoke tests for War Room CLI scripts
#
# Tests:
#   1. bash -n syntax check on all F31 scripts
#   2. Config helpers return correct values
#   3. didio warroom add creates valid JSON
#   4. Card ID generation is sequential
#   5. didio warroom list outputs expected format

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$PROJECT_ROOT/bin"

# Use a temp directory as project root so we don't pollute real data
TMPDIR_ROOT="$(mktemp -d)"
export DIDIO_PROJECT_ROOT="$TMPDIR_ROOT"

trap 'rm -rf "$TMPDIR_ROOT"' EXIT

PASS=0
FAIL=0
TOTAL=0

tap() {
  TOTAL=$((TOTAL + 1))
  local status="$1"
  local desc="$2"
  if [[ "$status" == "ok" ]]; then
    PASS=$((PASS + 1))
    echo "ok $TOTAL - $desc"
  else
    FAIL=$((FAIL + 1))
    echo "not ok $TOTAL - $desc"
  fi
}

# ---------------------------------------------------------------------------
# 1. Syntax check (bash -n) on all F31 scripts
# ---------------------------------------------------------------------------

for script in \
  "$BIN/didio-warroom.sh" \
  "$BIN/didio-overlord-triage.sh" \
  "$BIN/didio-overlord-promote.sh" \
  "$BIN/didio-overlord-defer.sh" \
  "$BIN/didio-overlord-monitor.sh"; do

  name="$(basename "$script")"
  if [[ ! -f "$script" ]]; then
    tap "not ok" "bash -n $name (file not found)"
    continue
  fi
  if bash -n "$script" 2>/dev/null; then
    tap "ok" "bash -n $name"
  else
    tap "not ok" "bash -n $name (syntax error)"
  fi
done

# ---------------------------------------------------------------------------
# 2. Config helpers — VALID_STATUSES contains expected values
# ---------------------------------------------------------------------------

warroom_help_output="$(bash "$BIN/didio-warroom.sh" --help 2>&1 || true)"
if echo "$warroom_help_output" | grep -q "incoming"; then
  tap "ok" "warroom help mentions incoming status"
else
  tap "not ok" "warroom help mentions incoming status"
fi

if echo "$warroom_help_output" | grep -q "triaging"; then
  tap "ok" "warroom help mentions triaging status"
else
  tap "not ok" "warroom help mentions triaging status"
fi

# ---------------------------------------------------------------------------
# 3. didio warroom add creates valid JSON
# ---------------------------------------------------------------------------

add_output="$(bash "$BIN/didio-warroom.sh" add "Test smoke card" --body "Smoke test body" --tags "smoke,test" --priority high 2>&1)"

if echo "$add_output" | grep -q "Created card WR-"; then
  tap "ok" "warroom add reports card creation"
else
  tap "not ok" "warroom add reports card creation"
fi

# Check a JSON file was created
card_files=("$TMPDIR_ROOT"/logs/warroom/cards/WR-*.json)
if [[ -f "${card_files[0]}" ]]; then
  tap "ok" "warroom add creates JSON file"
else
  tap "not ok" "warroom add creates JSON file"
fi

# Validate JSON structure with python3
if python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    d = json.load(f)
assert d['status'] == 'incoming', 'status should be incoming'
assert d['title'] == 'Test smoke card', 'title mismatch'
assert d['priority_suggestion'] == 'high', 'priority mismatch'
assert 'smoke' in d['tags'], 'tags should contain smoke'
assert d['card_id'].startswith('WR-'), 'card_id should start with WR-'
" "${card_files[0]}" 2>/dev/null; then
  tap "ok" "warroom add creates valid JSON with correct fields"
else
  tap "not ok" "warroom add creates valid JSON with correct fields"
fi

# ---------------------------------------------------------------------------
# 4. Card ID generation is sequential
# ---------------------------------------------------------------------------

bash "$BIN/didio-warroom.sh" add "Second card" --body "Body 2" >/dev/null 2>&1
bash "$BIN/didio-warroom.sh" add "Third card" --body "Body 3" >/dev/null 2>&1

card_count="$(ls "$TMPDIR_ROOT"/logs/warroom/cards/WR-*.json 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$card_count" -eq 3 ]]; then
  tap "ok" "sequential card IDs (3 cards created)"
else
  tap "not ok" "sequential card IDs (expected 3, got $card_count)"
fi

# Check IDs end in 001, 002, 003
today="$(date -u +"%Y%m%d")"
if [[ -f "$TMPDIR_ROOT/logs/warroom/cards/WR-${today}-001.json" ]] && \
   [[ -f "$TMPDIR_ROOT/logs/warroom/cards/WR-${today}-002.json" ]] && \
   [[ -f "$TMPDIR_ROOT/logs/warroom/cards/WR-${today}-003.json" ]]; then
  tap "ok" "card IDs are sequential (001, 002, 003)"
else
  tap "not ok" "card IDs are sequential (001, 002, 003)"
fi

# ---------------------------------------------------------------------------
# 5. didio warroom list outputs expected format
# ---------------------------------------------------------------------------

list_output="$(bash "$BIN/didio-warroom.sh" list 2>&1)"

if echo "$list_output" | grep -q "CARD_ID"; then
  tap "ok" "warroom list shows table header"
else
  tap "not ok" "warroom list shows table header"
fi

if echo "$list_output" | grep -q "WR-"; then
  tap "ok" "warroom list shows card entries"
else
  tap "not ok" "warroom list shows card entries"
fi

# JSON format
json_output="$(bash "$BIN/didio-warroom.sh" list --format json 2>&1)"
if python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert isinstance(data, list), 'should be a list'
assert len(data) == 3, f'expected 3 cards, got {len(data)}'
" "$json_output" 2>/dev/null; then
  tap "ok" "warroom list --format json outputs valid JSON array"
else
  tap "not ok" "warroom list --format json outputs valid JSON array"
fi

# ---------------------------------------------------------------------------
# 6. didio warroom show
# ---------------------------------------------------------------------------

show_output="$(bash "$BIN/didio-warroom.sh" show "WR-${today}-001" 2>&1)"
if echo "$show_output" | grep -q "Test smoke card"; then
  tap "ok" "warroom show displays card title"
else
  tap "not ok" "warroom show displays card title"
fi

# Non-existent card
if ! bash "$BIN/didio-warroom.sh" show "WR-NONEXISTENT" >/dev/null 2>&1; then
  tap "ok" "warroom show exits non-zero for missing card"
else
  tap "not ok" "warroom show exits non-zero for missing card"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "1..$TOTAL"
echo "# pass $PASS / $TOTAL"

if [[ $FAIL -gt 0 ]]; then
  echo "# FAIL $FAIL test(s) failed"
  exit 1
fi

echo "# All tests passed"
exit 0
