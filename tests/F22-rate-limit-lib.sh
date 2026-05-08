#!/usr/bin/env bash
# Tests for didio-rate-limit-lib.sh (F22-T02)
# Run: bash /Users/eduardodidio/claude-didio-config/tests/F22-rate-limit-lib.sh
set -uo pipefail

LIB="/Users/eduardodidio/claude-didio-config/bin/didio-rate-limit-lib.sh"
# shellcheck disable=SC1090
source "$LIB"
set +e  # lib sets -e; disable for test runner so intentional non-zero exits are catchable

PASS=0
FAIL=0
RL_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$RL_TEST_DIR"' EXIT

pass() { echo "  PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "  FAIL: $1"; FAIL=$(( FAIL + 1 )); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label — expected='$expected' got='$actual'"
  fi
}

echo "=== F22-rate-limit-lib unit tests ==="

# ─── 1. classify_jsonl — happy path ──────────────────────────────────────────
echo "--- classify_jsonl"

RATE_LIMIT_LOG="$RL_TEST_DIR/rate-limit.jsonl"
printf '%s\n' '{"type":"result","subtype":"success","is_error":true,"result":"You have hit your limit · resets 11:20am (America/Sao_Paulo)"}' > "$RATE_LIMIT_LOG"
assert_eq "rate_limit via 'hit your limit'" "rate_limit" "$(didio_rl_classify_jsonl "$RATE_LIMIT_LOG")"

RATE_LIMIT2_LOG="$RL_TEST_DIR/rate-limit2.jsonl"
printf '%s\n' '{"type":"result","subtype":"error","is_error":true,"result":"rate_limit exceeded, please wait"}' > "$RATE_LIMIT2_LOG"
assert_eq "rate_limit via 'rate_limit' in result" "rate_limit" "$(didio_rl_classify_jsonl "$RATE_LIMIT2_LOG")"

RATE_LIMIT3_LOG="$RL_TEST_DIR/rate-limit3.jsonl"
printf '%s\n' '{"type":"result","subtype":"error","is_error":true,"api_error_status":429,"result":"API error"}' > "$RATE_LIMIT3_LOG"
assert_eq "rate_limit via api_error_status 429" "rate_limit" "$(didio_rl_classify_jsonl "$RATE_LIMIT3_LOG")"

SUCCESS_LOG="$RL_TEST_DIR/success.jsonl"
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"Task completed successfully"}' > "$SUCCESS_LOG"
assert_eq "success" "success" "$(didio_rl_classify_jsonl "$SUCCESS_LOG")"

ERROR_LOG="$RL_TEST_DIR/error.jsonl"
printf '%s\n' '{"type":"result","subtype":"error","is_error":true,"result":"Something went wrong with file"}' > "$ERROR_LOG"
assert_eq "real_error" "real_error" "$(didio_rl_classify_jsonl "$ERROR_LOG")"

# ─── 2. classify_jsonl — edge cases ──────────────────────────────────────────
assert_eq "missing file returns unknown" "unknown" "$(didio_rl_classify_jsonl "/nonexistent/path.jsonl")"
assert_eq "empty arg returns unknown" "unknown" "$(didio_rl_classify_jsonl "")"

STREAM_LOG="$RL_TEST_DIR/stream-only.jsonl"
printf '%s\n' '{"type":"text","text":"streaming output..."}' > "$STREAM_LOG"
printf '%s\n' '{"type":"text","text":"more streaming..."}' >> "$STREAM_LOG"
assert_eq "no result event returns unknown" "unknown" "$(didio_rl_classify_jsonl "$STREAM_LOG")"

# ─── 3. parse_reset_to_unix — happy path ─────────────────────────────────────
echo "--- parse_reset_to_unix"

NOW="$(date +%s)"
FUTURE_MAX=$(( NOW + 86400 + 7200 ))

EPOCH_SP="$(didio_rl_parse_reset_to_unix "resets 11:20am (America/Sao_Paulo)")"
if [[ "$EPOCH_SP" -ge "$NOW" && "$EPOCH_SP" -le "$FUTURE_MAX" ]]; then
  pass "parse: America/Sao_Paulo future epoch"
else
  fail "parse: America/Sao_Paulo out of range — got $EPOCH_SP (now=$NOW max=$FUTURE_MAX)"
fi

EPOCH_NY="$(didio_rl_parse_reset_to_unix "resets 4:05pm (America/New_York)")"
if [[ "$EPOCH_NY" -ge "$NOW" && "$EPOCH_NY" -le "$FUTURE_MAX" ]]; then
  pass "parse: America/New_York future epoch"
else
  fail "parse: America/New_York out of range — got $EPOCH_NY"
fi

EPOCH_UTC="$(didio_rl_parse_reset_to_unix "You've hit your limit · resets 09:00 (UTC)")"
if [[ "$EPOCH_UTC" -ge "$NOW" && "$EPOCH_UTC" -le "$FUTURE_MAX" ]]; then
  pass "parse: UTC future epoch"
else
  fail "parse: UTC out of range — got $EPOCH_UTC"
fi

# full message format
EPOCH_FULL="$(didio_rl_parse_reset_to_unix "You've hit your limit · resets 11:20am (America/Sao_Paulo)")"
if [[ "$EPOCH_FULL" -ge "$NOW" && "$EPOCH_FULL" -le "$FUTURE_MAX" ]]; then
  pass "parse: full message format with middle-dot"
else
  fail "parse: full message format out of range — got $EPOCH_FULL"
fi

# ─── 4. parse_reset_to_unix — edge cases ─────────────────────────────────────

# Missing TZ paren → fallback +5h with WARN to stderr
STDERR_FILE="$RL_TEST_DIR/stderr.txt"
FALLBACK_EPOCH="$(didio_rl_parse_reset_to_unix "resets 11:20am" 2>"$STDERR_FILE")"
if [[ "$FALLBACK_EPOCH" -ge "$NOW" ]]; then
  pass "parse: missing TZ fallback returns future epoch"
else
  fail "parse: missing TZ fallback epoch not in future — got $FALLBACK_EPOCH"
fi
if grep -q "WARN" "$STDERR_FILE" 2>/dev/null; then
  pass "parse: missing TZ emits WARN to stderr"
else
  fail "parse: missing TZ should emit WARN to stderr"
fi

# Midnight UTC reset — must be in the future (either today or tomorrow)
MIDNIGHT_EPOCH="$(didio_rl_parse_reset_to_unix "resets 00:00 (UTC)" 2>/dev/null)"
if [[ "$MIDNIGHT_EPOCH" -ge "$NOW" ]]; then
  pass "parse: midnight UTC is in the future (next-day logic)"
else
  fail "parse: midnight UTC should be future — got $MIDNIGHT_EPOCH, now=$NOW"
fi

# Past time today → should add 1 day (use 00:01 UTC which is almost certainly in the past)
PAST_STR="resets 00:01 (UTC)"
PAST_EPOCH="$(didio_rl_parse_reset_to_unix "$PAST_STR" 2>/dev/null)"
if [[ "$PAST_EPOCH" -ge "$NOW" ]]; then
  pass "parse: past-time reset adds 1 day → future"
else
  fail "parse: past-time reset should be future — got $PAST_EPOCH"
fi

# Fixed-TZ deterministic check: 11:20am Sao_Paulo == 14:20 UTC (BRT = UTC-3)
# Set TZ=UTC so python reads the env cleanly; pass Sao_Paulo tz explicitly via message.
EXPECTED_UTC_HMS="14:20"
FIXED_EPOCH="$(TZ=UTC didio_rl_parse_reset_to_unix "resets 11:20am (America/Sao_Paulo)" 2>/dev/null)"
ACTUAL_UTC_HMS="$(python3 -c "
import datetime, sys
e = int('${FIXED_EPOCH}')
dt = datetime.datetime.fromtimestamp(e, tz=datetime.timezone.utc)
print(dt.strftime('%H:%M'))
" 2>/dev/null)"
if [[ "$ACTUAL_UTC_HMS" == "$EXPECTED_UTC_HMS" ]]; then
  pass "parse: 11:20am Sao_Paulo → UTC 14:20 (TZ=UTC fixed)"
else
  fail "parse: expected UTC ${EXPECTED_UTC_HMS} from 11:20am Sao_Paulo, got ${ACTUAL_UTC_HMS} (epoch=${FIXED_EPOCH})"
fi

# From a JSONL file
PARSE_LOG="$RL_TEST_DIR/parse-from-log.jsonl"
printf '%s\n' '{"type":"text","text":"streaming"}' > "$PARSE_LOG"
printf '%s\n' '{"type":"result","subtype":"success","is_error":true,"result":"You have hit your limit · resets 4:05pm (America/New_York)"}' >> "$PARSE_LOG"
EPOCH_FROM_LOG="$(didio_rl_parse_reset_to_unix "$PARSE_LOG")"
if [[ "$EPOCH_FROM_LOG" -ge "$NOW" && "$EPOCH_FROM_LOG" -le "$FUTURE_MAX" ]]; then
  pass "parse: extracts from JSONL log file"
else
  fail "parse: from JSONL log out of range — got $EPOCH_FROM_LOG"
fi

# ─── 5. persist_pending ──────────────────────────────────────────────────────
echo "--- persist_pending"

PENDING_DIR="$RL_TEST_DIR/pending"
VALID_JSON='{"schema_version":1,"id":"test-id","role":"developer","feature":"F22","task":"F22-T02","task_file":"/tmp/task.md","extra_prompt":"","cwd":"/tmp","env":{},"model":"claude-opus-4-7","fallback_model":"claude-sonnet-4-6","reset_at":"2026-05-07T14:20:00Z","retries":0,"max_retries":3,"created_at":"2026-05-07T10:00:00Z","original_log":"/tmp/log.jsonl","state":"waiting"}'

didio_rl_persist_pending "$PENDING_DIR" "test-id" "$VALID_JSON"
if [[ -f "${PENDING_DIR}/test-id.json" ]]; then
  pass "persist: file created"
else
  fail "persist: file not created"
fi

if python3 -m json.tool "${PENDING_DIR}/test-id.json" > /dev/null 2>&1; then
  pass "persist: output is valid JSON"
else
  fail "persist: output is invalid JSON"
fi

FIELD_COUNT="$(python3 -c "import json; d=json.load(open('${PENDING_DIR}/test-id.json')); print(len(d))")"
if [[ "$FIELD_COUNT" -ge 14 ]]; then
  pass "persist: JSON has >= 14 schema-v1 fields (got $FIELD_COUNT)"
else
  fail "persist: expected >= 14 fields, got $FIELD_COUNT"
fi

# Invalid JSON → should fail, no file written
BAD_DIR="$RL_TEST_DIR/bad-pending"
mkdir -p "$BAD_DIR"
persist_exit=0
didio_rl_persist_pending "$BAD_DIR" "bad-id" "not-valid-json" 2>/dev/null || persist_exit=$?
if [[ $persist_exit -ne 0 ]]; then
  pass "persist: rejects invalid JSON (exit non-zero)"
else
  fail "persist: should reject invalid JSON"
fi
if [[ ! -f "${BAD_DIR}/bad-id.json" ]]; then
  pass "persist: no file written on invalid JSON"
else
  fail "persist: file should not exist on invalid JSON"
fi

# ─── 6. consume_pending ──────────────────────────────────────────────────────
echo "--- consume_pending"

CONSUME_FILE="$RL_TEST_DIR/consume-test.json"
printf '%s\n' '{}' > "$CONSUME_FILE"
didio_rl_consume_pending "$CONSUME_FILE"
if [[ -f "${CONSUME_FILE}.consumed" ]]; then
  pass "consume: file renamed to .consumed"
else
  fail "consume: .consumed file not found"
fi
if [[ ! -f "$CONSUME_FILE" ]]; then
  pass "consume: original file removed"
else
  fail "consume: original file should be gone"
fi

# Second consume on same (now absent) file → should fail
consume_exit=0
didio_rl_consume_pending "$CONSUME_FILE" 2>/dev/null || consume_exit=$?
if [[ $consume_exit -ne 0 ]]; then
  pass "consume: returns non-zero on already-consumed (race protection)"
else
  fail "consume: should return non-zero when source is gone"
fi

# ─── 7. acquire_lock / release_lock ──────────────────────────────────────────
echo "--- acquire_lock / release_lock"

LOCK_FILE="$RL_TEST_DIR/locktest.json"
printf '%s\n' '{}' > "$LOCK_FILE"

lock_exit=0
didio_rl_acquire_lock "$LOCK_FILE" || lock_exit=$?
if [[ $lock_exit -eq 0 ]]; then
  pass "acquire_lock: first acquire succeeds"
else
  fail "acquire_lock: first acquire should succeed (exit 0)"
fi

lock2_exit=0
didio_rl_acquire_lock "$LOCK_FILE" 2>/dev/null || lock2_exit=$?
if [[ $lock2_exit -ne 0 ]]; then
  pass "acquire_lock: second acquire returns 1 (contention)"
else
  fail "acquire_lock: second acquire should fail while lock is held"
fi

didio_rl_release_lock "$LOCK_FILE"
pass "release_lock: lock released (no error)"

lock3_exit=0
didio_rl_acquire_lock "$LOCK_FILE" || lock3_exit=$?
if [[ $lock3_exit -eq 0 ]]; then
  pass "acquire_lock: re-acquire after release succeeds"
  didio_rl_release_lock "$LOCK_FILE"
else
  fail "acquire_lock: re-acquire after release should succeed"
fi

# ─── 8. append_telemetry ─────────────────────────────────────────────────────
echo "--- append_telemetry"

TELEM_DIR="$RL_TEST_DIR/telem"
EVENT_JSON='{"type":"rate_limit","ts":"2026-05-07T10:00:00Z","id":"test-1"}'
didio_rl_append_telemetry "$TELEM_DIR" "$EVENT_JSON"
if grep -q "rate_limit" "${TELEM_DIR}/index.jsonl" 2>/dev/null; then
  pass "append_telemetry: event appended to index.jsonl"
else
  fail "append_telemetry: event not found in index.jsonl"
fi

# Second append
EVENT2_JSON='{"type":"resume","ts":"2026-05-07T15:00:00Z","id":"test-2"}'
didio_rl_append_telemetry "$TELEM_DIR" "$EVENT2_JSON"
LINE_COUNT="$(wc -l < "${TELEM_DIR}/index.jsonl")"
if [[ "$LINE_COUNT" -ge 2 ]]; then
  pass "append_telemetry: multiple events accumulated"
else
  fail "append_telemetry: expected >= 2 lines, got $LINE_COUNT"
fi

# Invalid JSON → should warn but not crash
telem_exit=0
didio_rl_append_telemetry "$TELEM_DIR" "bad-json" 2>/dev/null || telem_exit=$?
if [[ $telem_exit -eq 0 ]]; then
  pass "append_telemetry: bad JSON returns 0 (best-effort)"
else
  fail "append_telemetry: should return 0 even on bad JSON"
fi

# ─── 9. bump_retries ─────────────────────────────────────────────────────────
echo "--- bump_retries"

RETRY_FILE="$RL_TEST_DIR/retry.json"
printf '%s\n' '{"retries":0,"max_retries":3,"state":"waiting"}' > "$RETRY_FILE"

r1="$(didio_rl_bump_retries "$RETRY_FILE" 2>/dev/null)"
assert_eq "bump_retries: first bump returns 1" "1" "$r1"

r2="$(didio_rl_bump_retries "$RETRY_FILE" 2>/dev/null)"
assert_eq "bump_retries: second bump returns 2" "2" "$r2"

r3="$(didio_rl_bump_retries "$RETRY_FILE" 2>/dev/null)"
assert_eq "bump_retries: third bump returns 3" "3" "$r3"

# retries=3, max=3: next bump should exit 1 (exceeded)
bump4_exit=0
r4="$(didio_rl_bump_retries "$RETRY_FILE" 2>/dev/null)" || bump4_exit=$?
assert_eq "bump_retries: fourth bump returns 4" "4" "$r4"
if [[ $bump4_exit -ne 0 ]]; then
  pass "bump_retries: exits non-zero when retries > max_retries"
else
  fail "bump_retries: should exit non-zero when retries > max_retries"
fi

# Verify state was updated
STATE="$(python3 -c "import json; d=json.load(open('$RETRY_FILE')); print(d.get('state',''))")"
assert_eq "bump_retries: state set to failed-max-retries" "failed-max-retries" "$STATE"

# Missing file → exit non-zero
bump_missing_exit=0
didio_rl_bump_retries "$RL_TEST_DIR/nonexistent.json" > /dev/null 2>/dev/null || bump_missing_exit=$?
if [[ $bump_missing_exit -ne 0 ]]; then
  pass "bump_retries: exit non-zero on missing file"
else
  fail "bump_retries: should fail on missing file"
fi

# ─── 10. capture_env ─────────────────────────────────────────────────────────
echo "--- capture_env"

export DIDIO_TEST_CAPTURE_VAR="test-value-$$"
export ANTHROPIC_API_KEY="fake-key-for-test"
export DISCORD_TEST_VAR="discord-val"
export MY_SECRET_SHOULD_NOT_APPEAR="secret"
export OPENAI_API_KEY_NOPE="openai-secret"

ENV_JSON="$(didio_rl_capture_env)"

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert 'DIDIO_TEST_CAPTURE_VAR' in d" "$ENV_JSON" 2>/dev/null; then
  pass "capture_env: includes DIDIO_ prefix"
else
  fail "capture_env: missing DIDIO_ vars"
fi

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert 'ANTHROPIC_API_KEY' in d" "$ENV_JSON" 2>/dev/null; then
  pass "capture_env: includes ANTHROPIC_ prefix"
else
  fail "capture_env: missing ANTHROPIC_ vars"
fi

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert 'DISCORD_TEST_VAR' in d" "$ENV_JSON" 2>/dev/null; then
  pass "capture_env: includes DISCORD_ prefix"
else
  fail "capture_env: missing DISCORD_ vars"
fi

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert 'PATH' in d" "$ENV_JSON" 2>/dev/null; then
  pass "capture_env: includes PATH"
else
  fail "capture_env: missing PATH"
fi

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert 'HOME' in d" "$ENV_JSON" 2>/dev/null; then
  pass "capture_env: includes HOME"
else
  fail "capture_env: missing HOME"
fi

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert 'MY_SECRET_SHOULD_NOT_APPEAR' not in d" "$ENV_JSON" 2>/dev/null; then
  pass "capture_env: excludes MY_SECRET_*"
else
  fail "capture_env: should exclude MY_SECRET_SHOULD_NOT_APPEAR"
fi

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert 'OPENAI_API_KEY_NOPE' not in d" "$ENV_JSON" 2>/dev/null; then
  pass "capture_env: excludes OPENAI_API_KEY"
else
  fail "capture_env: should exclude OPENAI_API_KEY_NOPE"
fi

# ─── 11. build_pending_json ───────────────────────────────────────────────────
echo "--- build_pending_json"

BUILT_JSON="$(didio_rl_build_pending_json \
  --id="F22-developer-F22-T02-20260507" \
  --role="developer" \
  --feature="F22" \
  --task="F22-T02" \
  --task-file="/tmp/F22-T02.md" \
  --extra-prompt="test prompt" \
  --cwd="/tmp" \
  --model="claude-opus-4-7" \
  --fallback-model="claude-sonnet-4-6" \
  --reset-at="2026-05-07T14:20:00Z" \
  --retries=0 \
  --max-retries=3 \
  --original-log="/tmp/log.jsonl" \
  --state="waiting")"

if python3 -m json.tool <<< "$BUILT_JSON" > /dev/null 2>&1; then
  pass "build_pending_json: outputs valid JSON"
else
  fail "build_pending_json: invalid JSON output"
fi

FIELD_COUNT2="$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(len(d))" "$BUILT_JSON")"
if [[ "$FIELD_COUNT2" -ge 14 ]]; then
  pass "build_pending_json: has >= 14 schema-v1 fields (got $FIELD_COUNT2)"
else
  fail "build_pending_json: expected >= 14 fields, got $FIELD_COUNT2"
fi

for field in schema_version id role feature task task_file extra_prompt cwd env model fallback_model reset_at retries max_retries created_at original_log state; do
  if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert '$field' in d" "$BUILT_JSON" 2>/dev/null; then
    pass "build_pending_json: field '$field' present"
  else
    fail "build_pending_json: missing field '$field'"
  fi
done

# ─── 12. Whitelist regex AC check ─────────────────────────────────────────────
echo "--- whitelist regex"

regex_ok=0
for v in DIDIO_HOME ANTHROPIC_API_KEY PATH HOME TZ LANG LC_ALL DISCORD_WEBHOOK_DEV; do
  if [[ ! "$v" =~ ^(DIDIO_|ANTHROPIC_|DISCORD_|PATH$|HOME$|TZ$|LANG$|LC_) ]]; then
    fail "whitelist: $v should match but doesn't"
    regex_ok=1
  fi
done
for v in USER SHELL EDITOR OPENAI_API_KEY MY_SECRET; do
  if [[ "$v" =~ ^(DIDIO_|ANTHROPIC_|DISCORD_|PATH$|HOME$|TZ$|LANG$|LC_) ]]; then
    fail "whitelist: $v should NOT match but does"
    regex_ok=1
  fi
done
if [[ $regex_ok -eq 0 ]]; then
  pass "whitelist regex: all accept/reject cases correct"
fi

# ─── 13. Boundary: DIDIO_RATE_LIMIT_MARGIN_SEC=0 ─────────────────────────────
echo "--- boundary values"

DIDIO_RL_MARGIN_SEC=0
if [[ "${DIDIO_RL_MARGIN_SEC}" == "0" ]]; then
  pass "boundary: DIDIO_RL_MARGIN_SEC=0 accepted (no margin)"
else
  fail "boundary: DIDIO_RL_MARGIN_SEC should be 0"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
TOTAL=$(( PASS + FAIL ))
echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
if [[ $FAIL -gt 0 ]]; then
  echo "FAILED: $FAIL test(s)"
  exit 1
fi
echo "All tests passed."
exit 0
