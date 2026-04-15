#!/usr/bin/env bash
# F03-integration-test.sh — end-to-end integration test for F03 changes:
#   - didio_find_feature_dir (didio-config-lib.sh)
#   - didio-progress.py --all (README cache, correct output)
#   - didio-log-watcher-loop.py no-op guard
# Usage: bash tests/F03-integration-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"

PASS=0
FAIL=0
FAILURES=()

_pass() { echo "  [PASS] $1"; (( PASS++ )) || true; }
_fail() { echo "  [FAIL] $1"; FAILURES+=("$1"); (( FAIL++ )) || true; }

# ─── Temp workspace ────────────────────────────────────────────────────────────
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

_make_feature() {
  local fid="$1" name="$2" ntasks="${3:-3}"
  local fdir="$TMP/tasks/features/${fid}-${name}"
  mkdir -p "$fdir"
  local readme="$fdir/${fid}-README.md"
  echo "# $fid — $name" > "$readme"
  echo "" >> "$readme"
  echo "## Wave manifest" >> "$readme"
  echo "" >> "$readme"
  echo "- **Wave 0**: $(seq -s ', ' -f "${fid}-T%02g" 1 "$ntasks")" >> "$readme"
}

_make_meta() {
  local fid="$1" tid="$2" status="${3:-completed}"
  local mdir="$TMP/logs/agents"
  mkdir -p "$mdir"
  cat > "$mdir/${fid}-${tid}.meta.json" <<EOF
{
  "feature": "$fid",
  "task": "${fid}-${tid}",
  "status": "$status",
  "started_at": "2026-04-14T10:00:00Z"
}
EOF
}

# Build fake workspace: 5+ features
_make_feature F01 alpha 3
_make_feature F02 beta  3
_make_feature F03 gamma 3
_make_feature F04 delta 3
_make_feature F05 epsilon 3
_make_feature F99 zeta  2

# Add some meta entries
_make_meta F01 T01 completed
_make_meta F01 T02 completed
_make_meta F01 T03 running
_make_meta F02 T01 completed
_make_meta F03 T01 failed

echo ""
echo "=== F03 Integration Tests ==="
echo ""

# ─── 1. didio_find_feature_dir ─────────────────────────────────────────────────
echo "--- 1. didio_find_feature_dir ---"

# Temporarily override PROJECT_ROOT
(
  export PROJECT_ROOT="$TMP"
  source "$BIN_DIR/didio-config-lib.sh"

  # Happy: known features resolve
  for fid in F01 F02 F03 F04 F05 F99; do
    result="$(didio_find_feature_dir "$fid" 2>/dev/null)"
    if [[ "$result" == "$TMP/tasks/features/${fid}-"* ]]; then
      _pass "didio_find_feature_dir $fid => $result"
    else
      _fail "didio_find_feature_dir $fid returned '$result' (expected path under $TMP/tasks/features/${fid}-*)"
    fi
  done

  # Edge: non-existent feature returns 1
  if ! didio_find_feature_dir F00 &>/dev/null; then
    _pass "didio_find_feature_dir F00 (unknown) returns non-zero"
  else
    _fail "didio_find_feature_dir F00 should fail but succeeded"
  fi
)

# ─── 2. didio-progress.py --all ────────────────────────────────────────────────
echo ""
echo "--- 2. didio-progress.py --all ---"

output="$(python3 "$BIN_DIR/didio-progress.py" --root "$TMP" --all)"
if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert isinstance(d,list), 'not a list'" 2>/dev/null; then
  _pass "--all returns a JSON array"
else
  _fail "--all did not return a JSON array"
fi

nfeatures="$(echo "$output" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")"
if [[ "$nfeatures" -ge 6 ]]; then
  _pass "--all found $nfeatures features (>= 6 expected)"
else
  _fail "--all found $nfeatures features (expected >= 6)"
fi

# Verify required fields present
if echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for d in data:
    for f in ('feature','total','completed','trail'):
        assert f in d, f'missing field {f} in {d.get(\"feature\")}'
print('ok')
" 2>/dev/null | grep -q ok; then
  _pass "--all output has required fields"
else
  _fail "--all output missing required fields"
fi

# Edge: workspace with 0 features
TMP_EMPTY=$(mktemp -d)
trap 'rm -rf "$TMP" "$TMP_EMPTY"' EXIT
mkdir -p "$TMP_EMPTY/logs/agents" "$TMP_EMPTY/tasks/features"
empty_out="$(python3 "$BIN_DIR/didio-progress.py" --root "$TMP_EMPTY" --all)"
if [[ "$empty_out" == "[]" ]]; then
  _pass "empty workspace returns []"
else
  _fail "empty workspace returned '$empty_out' (expected [])"
fi

# Edge: feature with 0 tasks (README has no task IDs)
TMP_NOTASKS=$(mktemp -d)
trap 'rm -rf "$TMP" "$TMP_EMPTY" "$TMP_NOTASKS"' EXIT
mkdir -p "$TMP_NOTASKS/logs/agents" "$TMP_NOTASKS/tasks/features/F10-empty"
echo "# F10 — empty feature" > "$TMP_NOTASKS/tasks/features/F10-empty/F10-README.md"
notasks_out="$(python3 "$BIN_DIR/didio-progress.py" --root "$TMP_NOTASKS" --all)"
if echo "$notasks_out" | python3 -c "
import json, sys
data = json.load(sys.stdin)
f10 = next((d for d in data if d['feature']=='F10'), None)
assert f10 is not None, 'F10 not found'
assert f10['trail'] == [], 'expected empty trail'
" 2>/dev/null; then
  _pass "feature with 0 tasks returns empty trail"
else
  _fail "feature with 0 tasks did not return empty trail (got: $notasks_out)"
fi

# ─── 3. Output stability (except generated_at) ──────────────────────────────────
echo ""
echo "--- 3. Output stability ---"

out1="$(python3 "$BIN_DIR/didio-progress.py" --root "$TMP" --all)"
out2="$(python3 "$BIN_DIR/didio-progress.py" --root "$TMP" --all)"
# Strip generated_at (not present in --all output; present in state.json, but let's check equality anyway)
if [[ "$out1" == "$out2" ]]; then
  _pass "Repeated --all calls produce identical output"
else
  _fail "Repeated --all calls differ"
fi

# ─── 4. No-op guard via didio-log-watcher-loop.py ─────────────────────────────
echo ""
echo "--- 4. No-op guard (watcher) ---"

STATE="$TMP/logs/agents/state.json"
LOOP_PY="$BIN_DIR/didio-log-watcher-loop.py"

# Start watcher in background
python3 "$LOOP_PY" "$STATE" "$TMP" "$BIN_DIR/didio-progress.py" &
WATCHER_PID=$!
trap 'kill "$WATCHER_PID" 2>/dev/null; rm -rf "$TMP" "$TMP_EMPTY" "$TMP_NOTASKS"' EXIT

# Wait for first write
timeout_s=5
for i in $(seq 1 $((timeout_s * 10))); do
  [[ -f "$STATE" ]] && break
  sleep 0.1
done

if [[ ! -f "$STATE" ]]; then
  _fail "watcher never wrote state.json within ${timeout_s}s"
else
  _pass "watcher created state.json"

  # Capture mtime after initial write
  sleep 2
  mtime1="$(stat -f '%m' "$STATE" 2>/dev/null || stat -c '%Y' "$STATE" 2>/dev/null)"
  sleep 3
  mtime2="$(stat -f '%m' "$STATE" 2>/dev/null || stat -c '%Y' "$STATE" 2>/dev/null)"

  if [[ "$mtime1" == "$mtime2" ]]; then
    _pass "No-op guard: state.json mtime stable during idle ticks"
  else
    _fail "No-op guard: state.json mtime changed during idle (mtime1=$mtime1 mtime2=$mtime2)"
  fi

  # Write a NEW .meta.json with different content → watcher must update state.json.
  # (Just touching a file doesn't change the JSON payload, so no-op guard stays.)
  cat > "$TMP/logs/agents/F01-T99.meta.json" <<'METAEOF'
{
  "feature": "F01",
  "task": "F01-T99",
  "status": "completed",
  "started_at": "2026-04-14T12:00:00Z"
}
METAEOF
  sleep 2
  mtime3="$(stat -f '%m' "$STATE" 2>/dev/null || stat -c '%Y' "$STATE" 2>/dev/null)"

  if [[ "$mtime3" != "$mtime2" ]]; then
    _pass "No-op guard: state.json mtime updated after new .meta.json added"
  else
    _fail "No-op guard: state.json mtime unchanged after new .meta.json (mtime2=$mtime2 mtime3=$mtime3)"
  fi
fi

# ─── 5. Error handling — watcher on non-existent directory ─────────────────────
echo ""
echo "--- 5. Error handling ---"

kill "$WATCHER_PID" 2>/dev/null || true
WATCHER_PID=""
trap 'rm -rf "$TMP" "$TMP_EMPTY" "$TMP_NOTASKS"' EXIT

TMP_STATE_BAD=$(mktemp)
python3 "$LOOP_PY" "$TMP_STATE_BAD" "/nonexistent/path/$$" "$BIN_DIR/didio-progress.py" &
BAD_PID=$!
sleep 2
if kill -0 "$BAD_PID" 2>/dev/null; then
  _pass "Watcher on non-existent dir keeps running (graceful)"
  kill "$BAD_PID" 2>/dev/null || true
else
  _fail "Watcher on non-existent dir crashed (should survive)"
fi
rm -f "$TMP_STATE_BAD"

# ─── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
if [[ "${#FAILURES[@]}" -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  echo ""
  exit 1
fi
echo ""
echo "All tests passed."
