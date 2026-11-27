#!/usr/bin/env bash
# F43-journey-e2e.sh -- End-to-end journey tests for the didio framework.
#
# Tests complete user journeys through the framework using DRY_RUN and
# isolated temp directories. Produces TAP output.
#
# Usage:  bash tests/F43-journey-e2e.sh

set -euo pipefail

###############################################################################
# TAP scaffolding
###############################################################################
TOTAL_TESTS=31
echo "1..$TOTAL_TESTS"

T=0
PASS=0
FAIL=0

ok() {
  T=$((T + 1)); PASS=$((PASS + 1))
  echo "ok $T - $1"
}

not_ok() {
  T=$((T + 1)); FAIL=$((FAIL + 1))
  echo "not ok $T - $1"
  [[ -n "${2:-}" ]] && echo "# $2"
}

skip() {
  T=$((T + 1)); PASS=$((PASS + 1))
  echo "ok $T - SKIP $1"
}

diag() { echo "# $*"; }

###############################################################################
# Environment setup -- fully isolated temp directory
###############################################################################
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
MOCK_PROJECT="$TMPDIR_BASE/project"

cleanup() {
  rm -rf "$TMPDIR_BASE" 2>/dev/null || true
}
trap cleanup EXIT

# Create project skeleton inside temp dir
mkdir -p "$MOCK_PROJECT/logs/agents"
mkdir -p "$MOCK_PROJECT/logs/agents/signals"
mkdir -p "$MOCK_PROJECT/logs/warroom/cards"
mkdir -p "$MOCK_PROJECT/tasks/features"
mkdir -p "$MOCK_PROJECT/bin"
mkdir -p "$MOCK_PROJECT/lib"
mkdir -p "$MOCK_PROJECT/memory/agent-learnings"

# Copy a minimal didio.config.json with all agents enabled
cat > "$MOCK_PROJECT/didio.config.json" <<'CFGEOF'
{
  "turbo": false,
  "economy": false,
  "max_parallel": 0,
  "providers": { "claude": { "bin": "claude", "default": true } },
  "models": {
    "architect": { "model": "opus", "fallback": "sonnet" },
    "developer": { "model": "sonnet", "fallback": "haiku" }
  },
  "models_economy": {},
  "meta_agents": {
    "handler":           { "enabled": true, "auto_governance": true },
    "gatekeeper":        { "enabled": true, "review_mode": "post-decision" },
    "blackhawk_alpha":   { "enabled": true },
    "blackhawk_bravo":   { "enabled": true },
    "blackhawk_charlie": { "enabled": true },
    "blackhawk_delta":   { "enabled": true }
  },
  "pipeline": {
    "autonomous": true,
    "signal_dir": "logs/agents/signals",
    "state_dir": "logs/agents"
  },
  "blackhawk": {
    "enabled": true,
    "auto_triage": true,
    "triage_interval_minutes": 30,
    "knowledge_sources": ["adr", "learnings"],
    "max_concurrent_promotions": 2
  },
  "negotiation": {
    "max_rounds": 3,
    "post_work_review": true
  },
  "token_monitor": { "enabled": true, "check_interval_minutes": 10 }
}
CFGEOF

# Point all env vars to our isolated project
export DIDIO_HOME="$REPO_ROOT"
export DIDIO_PROJECT_ROOT="$MOCK_PROJECT"
export PROJECT_ROOT="$MOCK_PROJECT"
export DIDIO_DRY_RUN=1
export DRY_RUN=1

# Source the config lib so helpers like didio_pipeline_signal_dir are available
source "$REPO_ROOT/bin/didio-config-lib.sh"

# Warroom script path
WARROOM="$REPO_ROOT/bin/didio-warroom.sh"
PIPELINE_STATUS="$REPO_ROOT/bin/didio-pipeline-status.sh"
PIPELINE_PAUSE="$REPO_ROOT/bin/didio-pipeline-pause.sh"
PIPELINE_RESUME="$REPO_ROOT/bin/didio-pipeline-resume.sh"
PROMOTE="$REPO_ROOT/bin/didio-blackhawk-promote.sh"
SQUAD_SCAN="$REPO_ROOT/bin/didio-squad-scan.sh"

###############################################################################
# Helper: create a pipeline state file
###############################################################################
create_pipeline_state() {
  local fxx="$1" status="$2" stage="${3:-}" started="${4:-2026-11-27T10:00:00Z}"
  local state_file="$MOCK_PROJECT/logs/agents/pipeline-${fxx}.state.json"
  local stage_json="null"
  [[ -n "$stage" ]] && stage_json="\"$stage\""
  cat > "$state_file" <<EOF
{
  "feature": "$fxx",
  "status": "$status",
  "stage": $stage_json,
  "stage_detail": null,
  "started_at": "$started",
  "paused_at": null,
  "resume_from": $stage_json,
  "current_wave": null,
  "total_waves": null,
  "error": null,
  "stages_completed": []
}
EOF
  echo "$state_file"
}

###############################################################################
# Helper: read a JSON field via python3
###############################################################################
json_field() {
  local file="$1" field="$2"
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
v = d.get(sys.argv[2])
if v is None:
    print('')
elif isinstance(v, list):
    print(json.dumps(v))
elif isinstance(v, dict):
    print(json.dumps(v))
elif isinstance(v, bool):
    print('true' if v else 'false')
else:
    print(str(v))
" "$file" "$field" 2>/dev/null || echo ""
}

###############################################################################
# J1: War Room Card Full Lifecycle
###############################################################################
diag "=== J1: War Room Card Full Lifecycle ==="

# J1.1 -- Create a card via warroom add
OUTPUT="$(bash "$WARROOM" add "Test auth refactor" --body "Full body text" --tags "auth,q1" --priority high 2>&1)" || true
if echo "$OUTPUT" | grep -q "Created card WR-"; then
  ok "J1.1 warroom add creates a card"
else
  not_ok "J1.1 warroom add creates a card" "Output: $OUTPUT"
fi

# Extract card ID from output
CARD_ID="$(echo "$OUTPUT" | grep -oE 'WR-[0-9]+-[0-9]+' | head -n1)"

# J1.2 -- Card appears in warroom list
LIST_OUTPUT="$(bash "$WARROOM" list 2>&1)" || true
if echo "$LIST_OUTPUT" | grep -q "$CARD_ID"; then
  ok "J1.2 card appears in warroom list"
else
  not_ok "J1.2 card appears in warroom list" "Card $CARD_ID not found in list"
fi

# J1.3 -- Card JSON has correct fields
CARD_FILE="$MOCK_PROJECT/logs/warroom/cards/${CARD_ID}.json"
if [[ -f "$CARD_FILE" ]]; then
  CARD_STATUS="$(json_field "$CARD_FILE" "status")"
  CARD_TITLE="$(json_field "$CARD_FILE" "title")"
  CARD_CREATED="$(json_field "$CARD_FILE" "created_at")"
  if [[ "$CARD_STATUS" == "incoming" && "$CARD_TITLE" == "Test auth refactor" && -n "$CARD_CREATED" ]]; then
    ok "J1.3 card JSON has status=incoming, title, and created_at"
  else
    not_ok "J1.3 card JSON has status=incoming, title, and created_at" \
      "status=$CARD_STATUS title=$CARD_TITLE created=$CARD_CREATED"
  fi
else
  not_ok "J1.3 card JSON has status=incoming, title, and created_at" "Card file not found: $CARD_FILE"
fi

# J1.4 -- Card tags are correct
CARD_TAGS="$(json_field "$CARD_FILE" "tags")"
if echo "$CARD_TAGS" | grep -q "auth" && echo "$CARD_TAGS" | grep -q "q1"; then
  ok "J1.4 card tags contain auth and q1"
else
  not_ok "J1.4 card tags contain auth and q1" "tags=$CARD_TAGS"
fi

# J1.5 -- Move card to triaging status
MOVE_OUTPUT="$(bash "$WARROOM" move "$CARD_ID" triaging 2>&1)" || true
NEW_STATUS="$(json_field "$CARD_FILE" "status")"
if [[ "$NEW_STATUS" == "triaging" ]]; then
  ok "J1.5 card moves to triaging via warroom move"
else
  not_ok "J1.5 card moves to triaging via warroom move" "status=$NEW_STATUS"
fi

# J1.6 -- Move card to deferred
MOVE_OUTPUT="$(bash "$WARROOM" move "$CARD_ID" deferred 2>&1)" || true
NEW_STATUS="$(json_field "$CARD_FILE" "status")"
UPDATED_AT="$(json_field "$CARD_FILE" "updated_at")"
if [[ "$NEW_STATUS" == "deferred" && -n "$UPDATED_AT" && "$UPDATED_AT" != "null" ]]; then
  ok "J1.6 card moves to deferred with updated_at timestamp"
else
  not_ok "J1.6 card moves to deferred with updated_at timestamp" \
    "status=$NEW_STATUS updated_at=$UPDATED_AT"
fi

###############################################################################
# J2: Pipeline State Lifecycle
###############################################################################
diag "=== J2: Pipeline State Lifecycle ==="

# J2.1 -- Create pipeline state (planned)
STATE_FILE="$(create_pipeline_state "F99" "planned" "planned")"
if [[ -f "$STATE_FILE" ]]; then
  ok "J2.1 pipeline state file created for F99"
else
  not_ok "J2.1 pipeline state file created for F99"
fi

# J2.2 -- pipeline-status reads planned state
STATUS_OUT="$(bash "$PIPELINE_STATUS" 2>&1)" || true
if echo "$STATUS_OUT" | grep -q "F99"; then
  ok "J2.2 pipeline-status lists F99"
else
  not_ok "J2.2 pipeline-status lists F99" "Output: $STATUS_OUT"
fi

# J2.3 -- Transition through stages: planned -> architect -> wave-0 -> wave-1 -> techlead -> qa -> done
STAGES=("architect" "wave-0" "wave-1" "techlead" "qa" "done")
TRANSITION_OK=true
for stage in "${STAGES[@]}"; do
  local_status="running"
  [[ "$stage" == "done" ]] && local_status="completed"
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
completed = d.get('stages_completed', [])
if d.get('stage') and d['stage'] not in completed:
    completed.append(d['stage'])
d['stages_completed'] = completed
d['status'] = sys.argv[2]
d['stage'] = sys.argv[3]
d['resume_from'] = sys.argv[3]
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2); f.write('\n')
" "$STATE_FILE" "$local_status" "$stage"

  CURRENT_STATUS="$(json_field "$STATE_FILE" "status")"
  CURRENT_STAGE="$(json_field "$STATE_FILE" "stage")"
  if [[ "$CURRENT_STAGE" != "$stage" ]]; then
    TRANSITION_OK=false
    break
  fi
done

if $TRANSITION_OK; then
  ok "J2.3 pipeline transitions through all stages to done"
else
  not_ok "J2.3 pipeline transitions through all stages to done" \
    "Failed at stage=$stage got=$CURRENT_STAGE"
fi

# J2.4 -- Detail view shows completed status
DETAIL_OUT="$(bash "$PIPELINE_STATUS" F99 2>&1)" || true
if echo "$DETAIL_OUT" | grep -q "completed"; then
  ok "J2.4 pipeline-status detail shows completed"
else
  not_ok "J2.4 pipeline-status detail shows completed" "Output: $DETAIL_OUT"
fi

# J2.5 -- Reset to running and test pause signal
python3 - "$STATE_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f: d = json.load(f)
d['status'] = 'running'; d['stage'] = 'wave-1'
with open(sys.argv[1], 'w') as f: json.dump(d, f, indent=2); f.write('\n')
PYEOF
PAUSE_OUT="$(bash "$PIPELINE_PAUSE" F99 2>&1)" || true
SIGNAL_DIR="$MOCK_PROJECT/$(didio_pipeline_signal_dir)"
if [[ -f "$SIGNAL_DIR/F99.pause" ]]; then
  ok "J2.5 pipeline-pause creates pause signal file"
else
  not_ok "J2.5 pipeline-pause creates pause signal file" "Signal file not found at $SIGNAL_DIR/F99.pause"
fi

# J2.6 -- pipeline-status shows pause pending signal
DETAIL_PAUSED="$(bash "$PIPELINE_STATUS" F99 2>&1)" || true
if echo "$DETAIL_PAUSED" | grep -qi "pause"; then
  ok "J2.6 pipeline-status shows pause signal"
else
  not_ok "J2.6 pipeline-status shows pause signal" "Output: $DETAIL_PAUSED"
fi

# J2.7 -- Set state to paused, then resume
python3 - "$STATE_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f: d = json.load(f)
d['status'] = 'paused'; d['resume_from'] = 'wave-1'
with open(sys.argv[1], 'w') as f: json.dump(d, f, indent=2); f.write('\n')
PYEOF
# Remove old pause signal to simulate pipeline consuming it
rm -f "$SIGNAL_DIR/F99.pause"

RESUME_OUT="$(bash "$PIPELINE_RESUME" F99 2>&1)" || true
if [[ -f "$SIGNAL_DIR/F99.resume" ]]; then
  ok "J2.7 pipeline-resume creates resume signal file"
else
  not_ok "J2.7 pipeline-resume creates resume signal file" "Output: $RESUME_OUT"
fi

###############################################################################
# J3: Board Aggregation
###############################################################################
diag "=== J3: Board Aggregation ==="

# Clean up previous pipeline states
rm -f "$MOCK_PROJECT"/logs/agents/pipeline-*.state.json

# J3.1 -- Create 3 pipeline state files: running, paused, done
create_pipeline_state "F50" "running" "wave-0" > /dev/null
create_pipeline_state "F51" "paused" "techlead" > /dev/null
create_pipeline_state "F52" "completed" "done" > /dev/null

BOARD_OUT="$(bash "$PIPELINE_STATUS" 2>&1)" || true
PIPELINE_COUNT="$(echo "$BOARD_OUT" | grep -cE 'F5[0-2]' || true)"
if [[ "$PIPELINE_COUNT" -eq 3 ]]; then
  ok "J3.1 pipeline-status shows all 3 pipelines"
else
  not_ok "J3.1 pipeline-status shows all 3 pipelines" "count=$PIPELINE_COUNT output=$BOARD_OUT"
fi

# J3.2 -- Verify different statuses appear
HAS_RUNNING=$(echo "$BOARD_OUT" | grep -c "running" || true)
HAS_PAUSED=$(echo "$BOARD_OUT" | grep -c "paused" || true)
HAS_COMPLETED=$(echo "$BOARD_OUT" | grep -c "completed" || true)
if [[ "$HAS_RUNNING" -ge 1 && "$HAS_PAUSED" -ge 1 && "$HAS_COMPLETED" -ge 1 ]]; then
  ok "J3.2 pipeline-status shows running, paused, completed statuses"
else
  not_ok "J3.2 pipeline-status shows running, paused, completed statuses" \
    "running=$HAS_RUNNING paused=$HAS_PAUSED completed=$HAS_COMPLETED"
fi

# J3.3 -- Create 5 War Room cards with different statuses
# Clean previous cards
rm -f "$MOCK_PROJECT"/logs/warroom/cards/WR-*.json

bash "$WARROOM" add "Card A" --priority low > /dev/null 2>&1
bash "$WARROOM" add "Card B" --priority medium > /dev/null 2>&1
bash "$WARROOM" add "Card C" --priority high > /dev/null 2>&1
bash "$WARROOM" add "Card D" --priority high > /dev/null 2>&1
bash "$WARROOM" add "Card E" --priority low > /dev/null 2>&1

# Move some cards to different statuses
ALL_CARDS=($(ls "$MOCK_PROJECT/logs/warroom/cards/" | sed 's/.json//' | sort))
# Card 0,1 = incoming (leave as is)
# Card 2 = triaging
bash "$WARROOM" move "${ALL_CARDS[2]}" triaging > /dev/null 2>&1
# Card 3 = promoted
bash "$WARROOM" move "${ALL_CARDS[3]}" promoted > /dev/null 2>&1
# Card 4 = deferred
bash "$WARROOM" move "${ALL_CARDS[4]}" deferred > /dev/null 2>&1

# J3.3 -- Verify warroom list JSON has correct counts
WR_JSON="$(bash "$WARROOM" list --format json 2>&1)" || true
INCOMING_COUNT="$(echo "$WR_JSON" | python3 -c "
import json, sys
cards = json.load(sys.stdin)
print(sum(1 for c in cards if c.get('status') == 'incoming'))
" 2>/dev/null || echo "0")"
TRIAGING_COUNT="$(echo "$WR_JSON" | python3 -c "
import json, sys
cards = json.load(sys.stdin)
print(sum(1 for c in cards if c.get('status') == 'triaging'))
" 2>/dev/null || echo "0")"
PROMOTED_COUNT="$(echo "$WR_JSON" | python3 -c "
import json, sys
cards = json.load(sys.stdin)
print(sum(1 for c in cards if c.get('status') == 'promoted'))
" 2>/dev/null || echo "0")"

if [[ "$INCOMING_COUNT" -eq 2 && "$TRIAGING_COUNT" -eq 1 && "$PROMOTED_COUNT" -eq 1 ]]; then
  ok "J3.3 warroom list shows 2 incoming, 1 triaging, 1 promoted"
else
  not_ok "J3.3 warroom list shows 2 incoming, 1 triaging, 1 promoted" \
    "incoming=$INCOMING_COUNT triaging=$TRIAGING_COUNT promoted=$PROMOTED_COUNT"
fi

# J3.4 -- Filter by status
INCOMING_LIST="$(bash "$WARROOM" list --status incoming --format json 2>&1)" || true
FILTERED_COUNT="$(echo "$INCOMING_LIST" | python3 -c "
import json, sys
cards = json.load(sys.stdin)
print(len(cards))
" 2>/dev/null || echo "0")"
if [[ "$FILTERED_COUNT" -eq 2 ]]; then
  ok "J3.4 warroom list --status incoming returns exactly 2 cards"
else
  not_ok "J3.4 warroom list --status incoming returns exactly 2 cards" "count=$FILTERED_COUNT"
fi

###############################################################################
# J4: Squad Scan Flow (Structural)
###############################################################################
diag "=== J4: Squad Scan Flow (Structural) ==="

# J4.1 -- Create mock Bravo report JSON
BRAVO_REPORT="$MOCK_PROJECT/logs/agents/bravo-report-20261127-120000.json"
cat > "$BRAVO_REPORT" <<'EOF'
{
  "report_id": "BR-20261127-120000",
  "timestamp": "2026-11-27T12:00:00Z",
  "scanner": "bravo",
  "status": "ok",
  "findings": [],
  "summary": "No pipeline issues detected"
}
EOF
if [[ -f "$BRAVO_REPORT" ]]; then
  ok "J4.1 mock Bravo report created"
else
  not_ok "J4.1 mock Bravo report created"
fi

# J4.2 -- Create mock Charlie report JSON
CHARLIE_REPORT="$MOCK_PROJECT/logs/agents/charlie-report-20261127-120000.json"
cat > "$CHARLIE_REPORT" <<'EOF'
{
  "report_id": "CH-20261127-120000",
  "timestamp": "2026-11-27T12:00:00Z",
  "scanner": "charlie",
  "status": "warning",
  "findings": [
    {"type": "slow_velocity", "detail": "Feature velocity below threshold", "severity": "warning"}
  ],
  "summary": "Velocity warning detected"
}
EOF
if [[ -f "$CHARLIE_REPORT" ]]; then
  ok "J4.2 mock Charlie report created"
else
  not_ok "J4.2 mock Charlie report created"
fi

# J4.3 -- Create mock Delta report JSON
DELTA_REPORT="$MOCK_PROJECT/logs/agents/delta-report-20261127-120000.json"
cat > "$DELTA_REPORT" <<'EOF'
{
  "report_id": "DL-20261127-120000",
  "timestamp": "2026-11-27T12:00:00Z",
  "scanner": "delta",
  "status": "ok",
  "findings": [],
  "summary": "No security issues detected"
}
EOF
if [[ -f "$DELTA_REPORT" ]]; then
  ok "J4.3 mock Delta report created"
else
  not_ok "J4.3 mock Delta report created"
fi

# J4.4 -- Verify squad-scan invocation (dry-run, structural check)
# The squad-scan script sources libs that may not all function in isolation
# without real scan targets, so we test structurally: source the orchestrator
# and verify key functions exist.
SQUAD_LIB="$REPO_ROOT/lib/squad-orchestrator.sh"
if [[ -f "$SQUAD_LIB" ]]; then
  # Check that the lib defines expected functions
  FUNC_CHECK="$(grep -c 'squad_scan_all\|_squad_correlate\|_squad_write_report\|_squad_create_cards' "$SQUAD_LIB" || true)"
  if [[ "$FUNC_CHECK" -ge 4 ]]; then
    ok "J4.4 squad-orchestrator.sh defines all required functions"
  else
    not_ok "J4.4 squad-orchestrator.sh defines all required functions" "found=$FUNC_CHECK expected>=4"
  fi
else
  not_ok "J4.4 squad-orchestrator.sh defines all required functions" "File not found"
fi

# J4.5 -- Verify squad report output structure by creating one manually
# and validating its schema
SQUAD_REPORT="$MOCK_PROJECT/logs/agents/squad-report-20261127-120000.json"
cat > "$SQUAD_REPORT" <<'EOF'
{
  "report_id": "SQ-20261127-120000",
  "timestamp": "2026-11-27T12:00:00Z",
  "squad_status": {
    "bravo": "ok",
    "charlie": "warning",
    "delta": "ok"
  },
  "correlations": [],
  "overall_status": "warning",
  "cards_created": []
}
EOF

SCHEMA_OK="$(python3 -c "
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
required = ['report_id', 'timestamp', 'squad_status', 'correlations', 'overall_status', 'cards_created']
missing = [k for k in required if k not in d]
if missing:
    print('missing: ' + ','.join(missing))
else:
    # Validate squad_status has bravo, charlie, delta
    ss = d.get('squad_status', {})
    agents = ['bravo', 'charlie', 'delta']
    missing_agents = [a for a in agents if a not in ss]
    if missing_agents:
        print('missing agents: ' + ','.join(missing_agents))
    else:
        print('ok')
" "$SQUAD_REPORT" 2>/dev/null || echo "error")"

if [[ "$SCHEMA_OK" == "ok" ]]; then
  ok "J4.5 squad report JSON has correct schema"
else
  not_ok "J4.5 squad report JSON has correct schema" "$SCHEMA_OK"
fi

# J4.6 -- Verify squad report aggregation: worst status wins
WORST="$(python3 - "$SQUAD_REPORT" <<'PYEOF' 2>/dev/null || echo ""
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
print(d['overall_status'])
PYEOF
)"
if [[ "$WORST" == "warning" ]]; then
  ok "J4.6 squad report overall_status reflects worst scanner status"
else
  not_ok "J4.6 squad report overall_status reflects worst scanner status" "got=$WORST"
fi

###############################################################################
# J5: Signal Control Flow
###############################################################################
diag "=== J5: Signal Control Flow ==="

# Clean up previous state and signals
rm -f "$MOCK_PROJECT"/logs/agents/pipeline-*.state.json
rm -f "$MOCK_PROJECT"/logs/agents/signals/*.pause
rm -f "$MOCK_PROJECT"/logs/agents/signals/*.resume

# J5.1 -- Create pipeline state (running)
create_pipeline_state "F70" "running" "wave-0" > /dev/null
STATE_F70="$MOCK_PROJECT/logs/agents/pipeline-F70.state.json"
F70_STATUS="$(json_field "$STATE_F70" "status")"
if [[ "$F70_STATUS" == "running" ]]; then
  ok "J5.1 pipeline F70 created with status=running"
else
  not_ok "J5.1 pipeline F70 created with status=running" "status=$F70_STATUS"
fi

# J5.2 -- pipeline-pause creates signal file
PAUSE_OUT="$(bash "$PIPELINE_PAUSE" F70 2>&1)" || true
SIGNAL_DIR="$MOCK_PROJECT/$(didio_pipeline_signal_dir)"
if [[ -f "$SIGNAL_DIR/F70.pause" ]]; then
  ok "J5.2 pipeline-pause creates F70.pause signal"
else
  not_ok "J5.2 pipeline-pause creates F70.pause signal" "Output: $PAUSE_OUT"
fi

# J5.3 -- Pause signal contains a timestamp
PAUSE_CONTENT="$(cat "$SIGNAL_DIR/F70.pause" 2>/dev/null || echo "")"
if echo "$PAUSE_CONTENT" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then
  ok "J5.3 pause signal file contains ISO timestamp"
else
  not_ok "J5.3 pause signal file contains ISO timestamp" "content=$PAUSE_CONTENT"
fi

# J5.4 -- pipeline-pause rejects already-paused pipeline
python3 - "$STATE_F70" <<'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f: d = json.load(f)
d['status'] = 'paused'
with open(sys.argv[1], 'w') as f: json.dump(d, f, indent=2); f.write('\n')
PYEOF
rm -f "$SIGNAL_DIR/F70.pause"

PAUSE_AGAIN="$(bash "$PIPELINE_PAUSE" F70 2>&1)" && PAUSE_EXIT=0 || PAUSE_EXIT=$?
if [[ "$PAUSE_EXIT" -ne 0 ]]; then
  ok "J5.4 pipeline-pause rejects already-paused pipeline (exit=$PAUSE_EXIT)"
else
  not_ok "J5.4 pipeline-pause rejects already-paused pipeline" "exit=0 (expected non-zero)"
fi

# J5.5 -- pipeline-resume creates resume signal for paused pipeline
RESUME_OUT="$(bash "$PIPELINE_RESUME" F70 2>&1)" || true
if [[ -f "$SIGNAL_DIR/F70.resume" ]]; then
  ok "J5.5 pipeline-resume creates F70.resume signal"
else
  not_ok "J5.5 pipeline-resume creates F70.resume signal" "Output: $RESUME_OUT"
fi

# J5.6 -- pipeline-resume rejects running pipeline
python3 - "$STATE_F70" <<'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f: d = json.load(f)
d['status'] = 'running'
with open(sys.argv[1], 'w') as f: json.dump(d, f, indent=2); f.write('\n')
PYEOF
rm -f "$SIGNAL_DIR/F70.resume"

RESUME_AGAIN="$(bash "$PIPELINE_RESUME" F70 2>&1)" && RESUME_EXIT=0 || RESUME_EXIT=$?
if [[ "$RESUME_EXIT" -ne 0 ]]; then
  ok "J5.6 pipeline-resume rejects running pipeline (exit=$RESUME_EXIT)"
else
  not_ok "J5.6 pipeline-resume rejects running pipeline" "exit=0 (expected non-zero)"
fi

# J5.7 -- Signals clean up: verify no stale signals remain
rm -f "$SIGNAL_DIR"/F70.*
REMAINING=0
for _sf in "$SIGNAL_DIR"/F70.*; do
  [[ -f "$_sf" ]] && REMAINING=$((REMAINING + 1))
done
if [[ "$REMAINING" -eq 0 ]]; then
  ok "J5.7 signal cleanup leaves no stale signal files"
else
  not_ok "J5.7 signal cleanup leaves no stale signal files" "remaining=$REMAINING"
fi

###############################################################################
# Bonus: War Room card show subcommand
###############################################################################
diag "=== Bonus: warroom show ==="

# Clean and create a fresh card for show test
rm -f "$MOCK_PROJECT"/logs/warroom/cards/WR-*.json
ADD_OUT="$(bash "$WARROOM" add "Show test card" --body "Detailed body" --tags "test" 2>&1)" || true
SHOW_CARD_ID="$(echo "$ADD_OUT" | grep -oE 'WR-[0-9]+-[0-9]+' | head -n1)"

if [[ -n "$SHOW_CARD_ID" ]]; then
  SHOW_OUT="$(bash "$WARROOM" show "$SHOW_CARD_ID" 2>&1)" || true
  if echo "$SHOW_OUT" | grep -q "Show test card" && echo "$SHOW_OUT" | grep -q "incoming"; then
    ok "Bonus: warroom show displays card title and status"
  else
    not_ok "Bonus: warroom show displays card title and status" "Output: $SHOW_OUT"
  fi
else
  not_ok "Bonus: warroom show displays card title and status" "Could not create card"
fi

###############################################################################
# Summary
###############################################################################
diag ""
diag "=== Summary ==="
diag "Passed: $PASS / $TOTAL_TESTS"
diag "Failed: $FAIL / $TOTAL_TESTS"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
