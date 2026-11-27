#!/usr/bin/env bash
# F44-board-e2e.sh -- E2E tests for the Live Kanban Board server
# TAP protocol output
set -uo pipefail

echo "1..8"

PASS=0
FAIL=0
TOTAL=8

ok()   { PASS=$((PASS+1)); echo "ok $1 - $2"; }
fail() { FAIL=$((FAIL+1)); echo "not ok $1 - $2"; }

# --- Setup ---
TMPDIR_ROOT=$(mktemp -d)
SERVER_PID=""
PORT=$((10000 + RANDOM % 50000))

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

# Create mock project structure
MOCK_ROOT="$TMPDIR_ROOT/project"
mkdir -p "$MOCK_ROOT/logs/warroom/cards"
mkdir -p "$MOCK_ROOT/logs/agents"
mkdir -p "$MOCK_ROOT/tasks/features/F01-test-feature"

# Create 3 mock warroom cards
printf '{"card_id":"WR-TEST-001","title":"Test Card Alpha","body":"First test card","status":"incoming","source":"operator","tags":["test"],"priority_suggestion":"medium","created_at":"2026-01-01T00:00:00Z"}\n' > "$MOCK_ROOT/logs/warroom/cards/WR-TEST-001.json"
printf '{"card_id":"WR-TEST-002","title":"Test Card Bravo","body":"Second test card","status":"promoted","source":"agent","tags":["ci"],"priority_suggestion":"high","created_at":"2026-01-01T01:00:00Z"}\n' > "$MOCK_ROOT/logs/warroom/cards/WR-TEST-002.json"
printf '{"card_id":"WR-TEST-003","title":"Test Card Charlie","body":"Third test card","status":"deferred","source":"operator","tags":[],"priority_suggestion":"low","created_at":"2026-01-01T02:00:00Z"}\n' > "$MOCK_ROOT/logs/warroom/cards/WR-TEST-003.json"

# Create 2 mock pipeline states
printf '{"feature":"F01","status":"done","stage":"done","stages_completed":["architect","waves","techlead","qa"],"stages_remaining":[],"exit_code":0,"started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T01:00:00Z"}\n' > "$MOCK_ROOT/logs/agents/pipeline-F01.state.json"
printf '{"feature":"F02","status":"failed","stage":"handler_gate","stages_completed":[],"stages_remaining":["architect","waves"],"exit_code":1,"error":"Handler failed","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T01:00:00Z"}\n' > "$MOCK_ROOT/logs/agents/pipeline-F02.state.json"

# Locate the server script
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_SCRIPT="$SCRIPT_DIR/bin/didio-board-server.py"

if [ ! -f "$SERVER_SCRIPT" ]; then
  echo "Bail out! Server script not found: $SERVER_SCRIPT"
  exit 1
fi

# --- Test 1: Server starts on a random port ---
DIDIO_PROJECT_ROOT="$MOCK_ROOT" python3 "$SERVER_SCRIPT" --port "$PORT" --no-open 2>/dev/null &
SERVER_PID=$!

# Wait for server ready (retry curl up to 5 seconds)
READY=0
for i in $(seq 1 25); do
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/" 2>/dev/null | grep -q "200"; then
    READY=1
    break
  fi
  sleep 0.2
done

if [ "$READY" = "1" ]; then
  ok 1 "Server starts on port $PORT"
else
  fail 1 "Server did not start on port $PORT within 5s"
  echo "# Bailing out early - server not reachable"
  exit 1
fi

# --- Test 2: GET / returns HTTP 200 with text/html ---
CT=$(curl -s -o /dev/null -w "%{content_type}" "http://localhost:$PORT/")
if echo "$CT" | grep -qi "text/html"; then
  ok 2 "GET / returns text/html content-type"
else
  fail 2 "GET / content-type is $CT, expected text/html"
fi

# --- Test 3: GET /api/warroom returns valid JSON with cards and counts ---
WR_BODY=$(curl -s "http://localhost:$PORT/api/warroom")
WR_CARDS=$(echo "$WR_BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['cards']),len(d['counts']))" 2>/dev/null)
if [ "$WR_CARDS" = "3 6" ]; then
  ok 3 "GET /api/warroom returns 3 cards and 6 count keys"
else
  fail 3 "GET /api/warroom unexpected: $WR_CARDS"
fi

# --- Test 4: GET /api/pipelines returns valid JSON with pipelines and counts ---
PL_BODY=$(curl -s "http://localhost:$PORT/api/pipelines")
PL_CHECK=$(echo "$PL_BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['pipelines']),len(d['counts']))" 2>/dev/null)
if [ "$PL_CHECK" = "2 5" ]; then
  ok 4 "GET /api/pipelines returns 2 pipelines and 5 count keys"
else
  fail 4 "GET /api/pipelines unexpected: $PL_CHECK"
fi

# --- Test 5: GET /api/features returns valid JSON with features array ---
FT_BODY=$(curl -s "http://localhost:$PORT/api/features")
FT_CHECK=$(echo "$FT_BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print('ok' if isinstance(d.get('features'), list) else 'fail')" 2>/dev/null)
if [ "$FT_CHECK" = "ok" ]; then
  ok 5 "GET /api/features returns valid JSON with features array"
else
  fail 5 "GET /api/features unexpected response"
fi

# --- Test 6: API handles empty state gracefully ---
kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

EMPTY_ROOT="$TMPDIR_ROOT/empty"
mkdir -p "$EMPTY_ROOT/logs/warroom/cards"
mkdir -p "$EMPTY_ROOT/logs/agents"
mkdir -p "$EMPTY_ROOT/tasks/features"

PORT2=$((10000 + RANDOM % 50000))
DIDIO_PROJECT_ROOT="$EMPTY_ROOT" python3 "$SERVER_SCRIPT" --port "$PORT2" --no-open 2>/dev/null &
SERVER_PID=$!

READY2=0
for i in $(seq 1 25); do
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT2/api/warroom" 2>/dev/null | grep -q "200"; then
    READY2=1
    break
  fi
  sleep 0.2
done

if [ "$READY2" = "1" ]; then
  EMPTY_WR=$(curl -s "http://localhost:$PORT2/api/warroom")
  EMPTY_PL=$(curl -s "http://localhost:$PORT2/api/pipelines")
  EMPTY_WR_OK=$(echo "$EMPTY_WR" | python3 -c "import json,sys; d=json.load(sys.stdin); print('ok' if d['cards']==[] and d['total']==0 else 'fail')" 2>/dev/null)
  EMPTY_PL_OK=$(echo "$EMPTY_PL" | python3 -c "import json,sys; d=json.load(sys.stdin); print('ok' if d['pipelines']==[] else 'fail')" 2>/dev/null)
  if [ "$EMPTY_WR_OK" = "ok" ] && [ "$EMPTY_PL_OK" = "ok" ]; then
    ok 6 "API handles empty state: empty arrays, no error"
  else
    fail 6 "API empty state: warroom=$EMPTY_WR_OK pipelines=$EMPTY_PL_OK"
  fi
else
  fail 6 "Server for empty state did not start on port $PORT2"
fi

# --- Test 7: API handles malformed JSON file gracefully ---
kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

MAL_ROOT="$TMPDIR_ROOT/malformed"
mkdir -p "$MAL_ROOT/logs/warroom/cards"
mkdir -p "$MAL_ROOT/logs/agents"
mkdir -p "$MAL_ROOT/tasks/features"

# One good card, one malformed
printf '{"card_id":"WR-GOOD","title":"Good Card","body":"Valid","status":"incoming","source":"operator","tags":[],"created_at":"2026-01-01T00:00:00Z"}\n' > "$MAL_ROOT/logs/warroom/cards/WR-GOOD.json"
echo "THIS IS NOT JSON {{{" > "$MAL_ROOT/logs/warroom/cards/WR-BAD.json"

PORT3=$((10000 + RANDOM % 50000))
DIDIO_PROJECT_ROOT="$MAL_ROOT" python3 "$SERVER_SCRIPT" --port "$PORT3" --no-open 2>/dev/null &
SERVER_PID=$!

READY3=0
for i in $(seq 1 25); do
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT3/api/warroom" 2>/dev/null | grep -q "200"; then
    READY3=1
    break
  fi
  sleep 0.2
done

if [ "$READY3" = "1" ]; then
  MAL_WR=$(curl -s "http://localhost:$PORT3/api/warroom")
  MAL_COUNT=$(echo "$MAL_WR" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['cards']))" 2>/dev/null)
  if [ "$MAL_COUNT" = "1" ]; then
    ok 7 "API handles malformed JSON: skips bad file, returns 1 valid card"
  else
    fail 7 "API malformed JSON: expected 1 card, got $MAL_COUNT"
  fi
else
  fail 7 "Server for malformed test did not start on port $PORT3"
fi

# --- Test 8: Server shuts down cleanly on SIGTERM ---
if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
  kill -TERM "$SERVER_PID" 2>/dev/null
  WAITED=0
  while kill -0 "$SERVER_PID" 2>/dev/null && [ "$WAITED" -lt 10 ]; do
    sleep 0.5
    WAITED=$((WAITED+1))
  done
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    ok 8 "Server shuts down cleanly on SIGTERM"
  else
    fail 8 "Server did not shut down within 5s after SIGTERM"
    kill -9 "$SERVER_PID" 2>/dev/null || true
  fi
  SERVER_PID=""
else
  fail 8 "Server was not running to test SIGTERM shutdown"
fi

# --- Summary ---
echo "# Tests: $TOTAL  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
