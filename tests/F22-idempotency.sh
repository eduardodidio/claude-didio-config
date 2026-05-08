#!/usr/bin/env bash
# F22 idempotency / race / max-retries tests.
# Hermetic: runs entirely inside a mktemp sandbox, no real filesystem mutations.
#
# Run:
#   bash /Users/eduardodidio/claude-didio-config/tests/F22-idempotency.sh
#
# Stress (optional, flush flakes locally — CI runs once):
#   for i in {1..50}; do bash F22-idempotency.sh || break; done
set -euo pipefail

# Derive DIDIO_ROOT from this script's location (tests/ lives one level below root).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIDIO_ROOT="${DIDIO_HOME:-$(cd "$SCRIPT_DIR/.." && pwd)}"
export DIDIO_HOME="$DIDIO_ROOT"
FIX_DIR="$DIDIO_ROOT/tests/F22-fixtures"
SANDBOX=$(mktemp -d -t f22-idem-XXXX)
trap 'rm -rf "$SANDBOX"' EXIT

mkdir -p \
  "$SANDBOX/logs/agents/_pending" \
  "$SANDBOX/agents/prompts" \
  "$SANDBOX/tasks/features/F22I" \
  "$SANDBOX/bin"
echo "# dev" > "$SANDBOX/agents/prompts/developer.md"
echo "# t"   > "$SANDBOX/tasks/features/F22I/F22I-T01.md"

# Create a sandbox-local claude wrapper that resolves fixtures via an absolute
# MOCK_CLAUDE_FIX_DIR path — avoids BASH_SOURCE[0] symlink resolution issues in
# the upstream mock-claude.sh when invoked through $FIX_DIR/bin/claude.
cat > "$SANDBOX/bin/claude" << 'MOCKEOF'
#!/usr/bin/env bash
cat "${MOCK_CLAUDE_FIX_DIR:?}/${MOCK_CLAUDE_FIXTURE:?MOCK_CLAUDE_FIXTURE not set}"
exit "${MOCK_CLAUDE_EXIT:-0}"
MOCKEOF
chmod +x "$SANDBOX/bin/claude"

cd "$SANDBOX"
export MOCK_CLAUDE_FIX_DIR="$FIX_DIR"
export MOCK_CLAUDE_FIXTURE=success.jsonl
export PATH="$SANDBOX/bin:$PATH"
export DIDIO_RATE_LIMIT_MARGIN_SEC=1

pass=0; fail=0
assert() {
  if eval "$2"; then
    echo "PASS: $1"
    pass=$((pass+1))
  else
    echo "FAIL: $1"
    fail=$((fail+1))
  fi
}

# Count files matching a glob pattern in the _pending dir (robust under set -o pipefail).
count_pending() {
  find logs/agents/_pending -maxdepth 1 -name "$1" 2>/dev/null | wc -l | tr -d ' '
}

# Clean the _pending dir (also removes any stale .lock dirs from previous scenario).
clean_pending() {
  rm -rf logs/agents/_pending
  mkdir -p logs/agents/_pending
}

# Write a ready-to-resume pending file into logs/agents/_pending/<id>.json.
#
# rc_seconds:  positive  => reset was this many seconds in the past  (ready)
#              negative  => reset is this many seconds in the future (not ready)
#              0         => reset exactly at "now" (boundary: treated as ready)
make_pending() {
  local id="$1" rc_seconds="${2:-0}"
  local now; now=$(date +%s)
  local reset=$((now - rc_seconds))
  local reset_iso
  reset_iso=$(date -u -r "$reset" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$reset" +%Y-%m-%dT%H:%M:%SZ)
  cat > "logs/agents/_pending/$id.json" <<EOF
{"schema_version":1,"id":"$id","role":"developer","feature":"F22I","task":"F22I-T01","task_file":"$SANDBOX/tasks/features/F22I/F22I-T01.md","extra_prompt":"","cwd":"$SANDBOX","env":{"PATH":"$PATH","HOME":"$HOME"},"model":"","fallback_model":"","reset_at":"$reset_iso","reset_at_unix":$reset,"retries":0,"max_retries":3,"created_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","original_log":"","state":"waiting"}
EOF
}

echo "=== F22 idempotency / race / max-retries ==="

# ─── 1. Race scenario: two parallel resume-pending on same job ────────────────
# Exactly ONE invocation must win the mkdir-lock + atomic mv; the other skips.
echo "--- race"
make_pending "F22I-developer-F22I-T01-RACE" 60
( bash "$DIDIO_ROOT/bin/didio-resume-pending.sh" >>"$SANDBOX/race.log" 2>&1 ) &
P1=$!
( bash "$DIDIO_ROOT/bin/didio-resume-pending.sh" >>"$SANDBOX/race.log" 2>&1 ) &
P2=$!
wait $P1 || true
wait $P2 || true
CONSUMED=$(count_pending "*.consumed")
JSONS=$(count_pending "*.json")
assert "race: exactly 1 consumed file" "[[ $CONSUMED -eq 1 ]]"
assert "race: 0 unconsumed json"        "[[ $JSONS -eq 0 ]]"

# ─── 2. Future job not consumed ───────────────────────────────────────────────
echo "--- future"
clean_pending
make_pending "F22I-developer-F22I-T01-FUTURE" -3600   # reset_at 1h from now
bash "$DIDIO_ROOT/bin/didio-resume-pending.sh" >/dev/null
assert "future: still unconsumed" "[[ -f logs/agents/_pending/F22I-developer-F22I-T01-FUTURE.json ]]"

# ─── 3. Max-retries=0: exit 3 immediately on first rate-limit hit ─────────────
# DIDIO_RETRIES_SO_FAR=0 >= DIDIO_MAX_RETRIES=0 → failed_max_retries branch.
echo "--- max-retries=0"
clean_pending
rc=0
MOCK_CLAUDE_FIXTURE=rate-limit-brt-am.jsonl MOCK_CLAUDE_EXIT=1 \
  DIDIO_ON_RATE_LIMIT=schedule DIDIO_MAX_RETRIES=0 \
  DIDIO_RETRIES_SO_FAR=0 \
  bash "$DIDIO_ROOT/bin/didio-spawn-agent.sh" developer F22I tasks/features/F22I/F22I-T01.md "" || rc=$?
assert "max-retries=0 exits 3"         "[[ $rc -eq 3 ]]"
assert "max-retries telemetry written" "grep -q failed_max_retries logs/agents/_pending/index.jsonl"

# ─── 4. Dry-run: no consumption ───────────────────────────────────────────────
echo "--- dry-run"
clean_pending
make_pending "F22I-developer-F22I-T01-IDEM" 60
PRE=$(count_pending "*.json")
bash "$DIDIO_ROOT/bin/didio-resume-pending.sh" --dry-run >/dev/null
POST=$(count_pending "*.json")
assert "dry-run preserves pending count" "[[ $PRE -eq $POST ]]"

# ─── 5. Schema version mismatch: warn + skip + preserve ──────────────────────
echo "--- schema mismatch"
clean_pending
cat > logs/agents/_pending/F22I-bad-schema.json <<EOF
{"schema_version":99,"id":"F22I-bad-schema"}
EOF
out=$(bash "$DIDIO_ROOT/bin/didio-resume-pending.sh" 2>&1)
assert "schema mismatch logs warn"    "echo \"$out\" | grep -q 'schema_version=99'"
assert "schema mismatch not consumed" "[[ -f logs/agents/_pending/F22I-bad-schema.json ]]"

# ─── 6. Boundary: reset_at exactly == now is treated as ready ────────────────
# resume-pending uses `(( reset_at > NOW ))` — strict greater-than — so
# reset_at == NOW is NOT skipped and must be consumed.
echo "--- boundary: reset_at==now"
clean_pending
make_pending "F22I-developer-F22I-T01-NOW" 0
bash "$DIDIO_ROOT/bin/didio-resume-pending.sh" >/dev/null || true
assert "boundary: reset_at==now is consumed" "[[ -f logs/agents/_pending/F22I-developer-F22I-T01-NOW.json.consumed ]]"
assert "boundary: reset_at==now json gone"   "[[ ! -f logs/agents/_pending/F22I-developer-F22I-T01-NOW.json ]]"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo "------"
echo "F22 idempotency: pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
