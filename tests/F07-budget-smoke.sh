#!/usr/bin/env bash
# F07-budget-smoke.sh — smoke test for session-guard primitives.
#
# Covers:
#   1. didio_read_config_path (4 scenarios)
#   2. didio-budget-probe.sh ccusage + transcript paths + schema sanity
#   3. didio-pre-tool.sh at allow/warn/deny thresholds
#   4. didio-post-tool.sh safe on empty stdin
#
# Usage: bash tests/F07-budget-smoke.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"
export DIDIO_PROJECT_ROOT="$PROJECT"

PASS=0
FAIL=0
FAILURES=()
_pass() { echo "  [PASS] $1"; (( PASS++ )) || true; }
_fail() { echo "  [FAIL] $1"; FAILURES+=("$1"); (( FAIL++ )) || true; }

TMP="$(mktemp -d)"
# Always clear the real budget.json on exit so a leftover fixture cannot
# brick the parent session via the PreToolUse hook.
trap 'rm -rf "$TMP"; rm -f "$PROJECT/logs/session-budget.json" "$PROJECT/logs/.budget-probe.lock"' EXIT

echo "=== F07 smoke tests ==="
echo ""

# ─── 1. didio_read_config_path ──────────────────────────────────────────────
echo "--- 1. didio_read_config_path ---"
source "$PROJECT/bin/didio-config-lib.sh"

v="$(didio_read_config_path session_guard.hard_pct)"
[[ "$v" == "0.98" ]] && _pass "hard_pct=0.98" || _fail "hard_pct got '$v'"

v="$(didio_read_config_path session_guard.enabled)"
[[ "$v" == "true" ]] && _pass "enabled=true" || _fail "enabled got '$v'"

v="$(didio_read_config_path session_guard.missing_key 42)"
[[ "$v" == "42" ]] && _pass "missing returns default" || _fail "missing got '$v'"

# Empty config path
(
  export PROJECT_ROOT="$TMP"
  v="$(didio_read_config_path session_guard.enabled fallback_val)"
  [[ "$v" == "fallback_val" ]] && echo "PASS_EMPTY" || echo "FAIL_EMPTY got '$v'"
) > "$TMP/r1" 2>&1
grep -q PASS_EMPTY "$TMP/r1" && _pass "empty config path returns default" || _fail "empty config got $(cat "$TMP/r1")"

# ─── 2. Budget probe: ccusage path ──────────────────────────────────────────
echo ""
echo "--- 2. Budget probe ---"

rm -f "$PROJECT/logs/session-budget.json" "$PROJECT/logs/.budget-probe.lock"
FAKE_CCUSAGE_JSON='{"sessions":[{"inputTokens":1000,"outputTokens":500,"windowLimit":200000,"windowResetsAt":"2026-04-20T18:00:00Z","sessionId":"test"}]}' \
  bash "$PROJECT/bin/didio-budget-probe.sh"
if [[ -f "$PROJECT/logs/session-budget.json" ]]; then
  _pass "probe wrote session-budget.json"
else
  _fail "probe did not write session-budget.json"
fi

# Schema sanity (required fields)
python3 - "$PROJECT/logs/session-budget.json" <<'PY' > "$TMP/r2" 2>&1 || true
import json, sys
d = json.load(open(sys.argv[1]))
for k in ("source","tokens_used","limit","pct","updated_at"):
    assert k in d, f"missing {k}"
assert d["source"] == "ccusage", f"expected ccusage, got {d['source']}"
assert d["tokens_used"] == 1500, f"expected 1500, got {d['tokens_used']}"
print("OK")
PY
grep -q "^OK$" "$TMP/r2" && _pass "ccusage JSON parsed correctly" || _fail "ccusage parse: $(cat "$TMP/r2")"

# Throttle: second call within throttle window should NOT rewrite (mtime stable)
m1=$(stat -f '%m' "$PROJECT/logs/session-budget.json" 2>/dev/null || stat -c '%Y' "$PROJECT/logs/session-budget.json")
sleep 1
FAKE_CCUSAGE_JSON='{"sessions":[{"inputTokens":9999,"outputTokens":0,"windowLimit":200000,"windowResetsAt":"2026-04-20T18:00:00Z"}]}' \
  bash "$PROJECT/bin/didio-budget-probe.sh"
m2=$(stat -f '%m' "$PROJECT/logs/session-budget.json" 2>/dev/null || stat -c '%Y' "$PROJECT/logs/session-budget.json")
[[ "$m1" == "$m2" ]] && _pass "probe throttled within window" || _fail "probe not throttled (mtimes $m1 vs $m2)"

# Transcript fallback
TSCRIPT="$TMP/fake-transcript.jsonl"
cat > "$TSCRIPT" <<'EOF'
{"session_id":"xyz","message":{"usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":2000,"cache_read_input_tokens":5000}}}
{"message":{"usage":{"input_tokens":800,"output_tokens":300}}}
EOF
rm -f "$PROJECT/logs/session-budget.json"
FAKE_CCUSAGE_FAIL=1 DIDIO_TRANSCRIPT_PATH="$TSCRIPT" \
  bash "$PROJECT/bin/didio-budget-probe.sh"
if [[ -f "$PROJECT/logs/session-budget.json" ]]; then
  src=$(python3 -c "import json; print(json.load(open('$PROJECT/logs/session-budget.json'))['source'])")
  [[ "$src" == "transcript" ]] && _pass "transcript fallback: source=transcript" || _fail "fallback source=$src"
  tokens=$(python3 -c "import json; print(json.load(open('$PROJECT/logs/session-budget.json'))['tokens_used'])")
  [[ "$tokens" == "9600" ]] && _pass "transcript token sum = 9600" || _fail "transcript tokens=$tokens"
else
  _fail "transcript fallback did not write snapshot"
fi

# ─── 3. PreToolUse hook at 3 thresholds ─────────────────────────────────────
echo ""
echo "--- 3. PreToolUse hook (allow/warn/deny) ---"

_fixture_budget() {
  local pct="$1"
  python3 -c "
import json
json.dump({
  'source':'ccusage','session_id':'test',
  'tokens_used': int($pct*200000), 'limit':200000, 'pct':$pct,
  'window_resets_at':'2026-04-20T22:00:00Z',
  'updated_at':'2026-04-20T18:00:00Z'
}, open('$PROJECT/logs/session-budget.json','w'), indent=2)
"
  # Keep mtime fresh so the staleness guard in the hook doesn't skip us.
  touch "$PROJECT/logs/session-budget.json"
}

# allow (pct=0.5)
_fixture_budget 0.5
stdout="$(bash "$PROJECT/bin/hooks/didio-pre-tool.sh" 2>/dev/null)"
ec=$?
[[ -z "$stdout" && $ec -eq 0 ]] && _pass "pct=0.5 → silent allow" || _fail "pct=0.5 out='$stdout' exit=$ec"

# warn (pct=0.92)
_fixture_budget 0.92
stdout="$(bash "$PROJECT/bin/hooks/didio-pre-tool.sh" 2>/dev/null)"
ec=$?
if [[ $ec -eq 0 ]] && echo "$stdout" | grep -q "systemMessage"; then
  _pass "pct=0.92 → warn with systemMessage"
else
  _fail "pct=0.92 warn path failed (exit=$ec out=$stdout)"
fi

# deny (pct=0.99) — pause script would be launched in bg, but we disable it
_fixture_budget 0.99
# Temporarily move the pause script aside so we don't actually fire it in smoke.
mv "$PROJECT/bin/didio-budget-pause.sh" "$PROJECT/bin/didio-budget-pause.sh.bak"
stderr="$(bash "$PROJECT/bin/hooks/didio-pre-tool.sh" 2>&1 1>/dev/null)"
ec=$?
mv "$PROJECT/bin/didio-budget-pause.sh.bak" "$PROJECT/bin/didio-budget-pause.sh"
if [[ $ec -eq 2 ]] && echo "$stderr" | grep -q '"permissionDecision":"deny"'; then
  _pass "pct=0.99 → deny with permissionDecision JSON + exit 2"
else
  _fail "pct=0.99 deny path failed (exit=$ec err=$stderr)"
fi

# Staleness guard: a stale fixture (mtime > max) must NOT trigger deny.
_fixture_budget 0.99
# Backdate mtime to 10 minutes ago (portable via Python; BSD vs GNU touch differs).
python3 -c "
import os, time
p = '$PROJECT/logs/session-budget.json'
t = time.time() - 600
os.utime(p, (t, t))
"
ec=$(bash "$PROJECT/bin/hooks/didio-pre-tool.sh" >/dev/null 2>&1; echo $?)
[[ "$ec" == "0" ]] && _pass "stale pct=0.99 fixture ignored (staleness guard)" || _fail "staleness guard failed: exit=$ec"

# ─── 4. PostToolUse hook safe on empty stdin ────────────────────────────────
echo ""
echo "--- 4. PostToolUse safe ---"
ec=$(echo "" | bash "$PROJECT/bin/hooks/didio-post-tool.sh" >/dev/null 2>&1; echo $?)
[[ "$ec" == "0" ]] && _pass "PostToolUse safe on empty stdin" || _fail "PostToolUse exit=$ec"

# ─── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf 'Failures:\n'
  for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
echo "All smoke tests passed."
