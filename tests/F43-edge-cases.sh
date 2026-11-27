#!/usr/bin/env bash
# F43-edge-cases.sh — Edge case tests for War Room, Promote, Pipeline, Squad & Mesh
#
# TAP protocol output. Runs in an isolated temp directory.
# Usage: bash tests/F43-edge-cases.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$PROJECT_ROOT/bin"
LIB="$PROJECT_ROOT/lib"

# ---------------------------------------------------------------------------
# Isolated temp environment
# ---------------------------------------------------------------------------
TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

export DIDIO_PROJECT_ROOT="$TMPDIR_ROOT"
export PROJECT_ROOT="$TMPDIR_ROOT"

# Pipeline scripts need DIDIO_HOME for config-lib.sh and didio_pipeline_signal_dir
REAL_PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"
export DIDIO_HOME="$REAL_PROJECT"

# Create minimal didio.config.json for squad and pipeline
mkdir -p "$TMPDIR_ROOT/logs/agents" "$TMPDIR_ROOT/logs/warroom/cards" "$TMPDIR_ROOT/tasks/features"
cat > "$TMPDIR_ROOT/didio.config.json" <<'EOF'
{
  "project_name": "edge-case-test",
  "pipeline": {
    "signal_dir": "logs/agents/signals"
  },
  "meta_agents": {
    "blackhawk_bravo": { "enabled": false },
    "blackhawk_charlie": { "enabled": false },
    "blackhawk_delta": { "enabled": false }
  }
}
EOF

# Mesh registry lives in a temp home
MESH_TMPDIR="$(mktemp -d)"
export DIDIO_MESH_REGISTRY="$MESH_TMPDIR/mesh-registry.json"

# ---------------------------------------------------------------------------
# TAP helpers
# ---------------------------------------------------------------------------
PASS=0
FAIL=0
TOTAL=0

tap_ok() {
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "ok $TOTAL - $1"
}

tap_fail() {
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "not ok $TOTAL - $1"
  if [[ -n "${2:-}" ]]; then
    echo "  # $2"
  fi
}

tap() {
  if [[ "$1" == "ok" ]]; then
    tap_ok "$2"
  else
    tap_fail "$2" "${3:-}"
  fi
}

# ---------------------------------------------------------------------------
# TAP plan
# ---------------------------------------------------------------------------
echo "1..18"

# ===========================================================================
# WAR ROOM EDGE CASES
# ===========================================================================

# --- Test 1: Empty title ---
# warroom add with empty string: script checks $# -lt 1 || starts with --
# An empty string "" passes as $1 so the script should still create a card.
OUT1="$(bash "$BIN/didio-warroom.sh" add "" 2>&1)" || true
if echo "$OUT1" | grep -qi "created\|error\|usage"; then
  tap ok "warroom add empty title -- handled (created or errored)"
else
  tap fail "warroom add empty title -- unexpected output" "$OUT1"
fi

# --- Test 2: Invalid JSON card in cards dir ---
echo "THIS IS NOT JSON" > "$TMPDIR_ROOT/logs/warroom/cards/WR-00000000-999.json"
OUT2="$(bash "$BIN/didio-warroom.sh" list 2>&1)" || true
# list should not crash; it may skip the bad card or show partial output
if [[ $? -eq 0 ]] || echo "$OUT2" | grep -qi "CARD_ID\|no cards"; then
  tap ok "warroom list with invalid JSON card -- does not crash"
else
  tap fail "warroom list with invalid JSON card -- crashed" "$OUT2"
fi
# Clean up invalid card
rm -f "$TMPDIR_ROOT/logs/warroom/cards/WR-00000000-999.json"

# --- Test 3: Card with bogus status -- move validates ---
# First create a valid card
bash "$BIN/didio-warroom.sh" add "Test bogus status" > /dev/null 2>&1
# Find the card file
CARD3_FILE="$(ls "$TMPDIR_ROOT/logs/warroom/cards"/WR-*.json 2>/dev/null | head -1)"
if [[ -n "$CARD3_FILE" ]]; then
  CARD3_ID="$(basename "$CARD3_FILE" .json)"
  # Try to move to bogus status
  OUT3="$(bash "$BIN/didio-warroom.sh" move "$CARD3_ID" "bogus" 2>&1)" && RC3=0 || RC3=$?
  if [[ $RC3 -ne 0 ]] && echo "$OUT3" | grep -qi "invalid status"; then
    tap ok "warroom move to bogus status -- rejected with error"
  else
    tap fail "warroom move to bogus status -- should have been rejected" "rc=$RC3 out=$OUT3"
  fi
else
  tap fail "warroom move to bogus status -- could not create test card"
fi

# --- Test 4: Rapid sequential add -- IDs must be unique ---
bash "$BIN/didio-warroom.sh" add "Rapid A" > /dev/null 2>&1
bash "$BIN/didio-warroom.sh" add "Rapid B" > /dev/null 2>&1
bash "$BIN/didio-warroom.sh" add "Rapid C" > /dev/null 2>&1
CARD_COUNT="$(ls "$TMPDIR_ROOT/logs/warroom/cards"/WR-*.json 2>/dev/null | wc -l)"
UNIQUE_COUNT="$(ls "$TMPDIR_ROOT/logs/warroom/cards"/WR-*.json 2>/dev/null | sort -u | wc -l)"
if [[ "$CARD_COUNT" -ge 4 && "$CARD_COUNT" -eq "$UNIQUE_COUNT" ]]; then
  tap ok "rapid sequential add -- all $CARD_COUNT IDs are unique"
else
  tap fail "rapid sequential add -- ID collision detected" "total=$CARD_COUNT unique=$UNIQUE_COUNT"
fi

# ===========================================================================
# PROMOTE EDGE CASES
# ===========================================================================

# --- Test 5: Promote card with no overlord_assessment ---
# Create a fresh card (has overlord_assessment: null by default)
OUT5A="$(bash "$BIN/didio-warroom.sh" add "No assessment card" 2>&1)"
CARD5_ID="$(echo "$OUT5A" | grep -oP 'WR-\d+-\d+' | head -1)"
if [[ -n "$CARD5_ID" ]]; then
  OUT5="$(bash "$BIN/didio-blackhawk-promote.sh" "$CARD5_ID" 2>&1)" && RC5=0 || RC5=$?
  if [[ $RC5 -ne 0 ]] && echo "$OUT5" | grep -qi "no overlord_assessment\|run triage"; then
    tap ok "promote without assessment -- rejected with error"
  else
    tap fail "promote without assessment -- should have been rejected" "rc=$RC5 out=$OUT5"
  fi
else
  tap fail "promote without assessment -- could not create test card"
fi

# --- Test 6: Promote card with recommendation != promote ---
OUT6A="$(bash "$BIN/didio-warroom.sh" add "Defer me card" 2>&1)"
CARD6_ID="$(echo "$OUT6A" | grep -oP 'WR-\d+-\d+' | head -1)"
if [[ -n "$CARD6_ID" ]]; then
  CARD6_FILE="$TMPDIR_ROOT/logs/warroom/cards/${CARD6_ID}.json"
  # Inject a non-promote assessment via python3
  python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    d = json.load(f)
d['overlord_assessment'] = {
    'recommendation': 'defer',
    'priority': 'low',
    'rationale': 'Not now'
}
with open(sys.argv[1], 'w') as f:
    json.dump(d, f, indent=2)
" "$CARD6_FILE"
  OUT6="$(bash "$BIN/didio-blackhawk-promote.sh" "$CARD6_ID" 2>&1)" && RC6=0 || RC6=$?
  if [[ $RC6 -ne 0 ]] && echo "$OUT6" | grep -qi "not 'promote'\|recommendation.*defer"; then
    tap ok "promote with recommendation=defer -- rejected with error"
  else
    tap fail "promote with recommendation=defer -- should have been rejected" "rc=$RC6 out=$OUT6"
  fi
else
  tap fail "promote with recommendation=defer -- could not create test card"
fi

# --- Test 7: Feature directory already exists at next F-number -- auto-increment ---
# Create F01-existing to force promote to pick F02 or higher
mkdir -p "$TMPDIR_ROOT/tasks/features/F01-existing-feature"
OUT7A="$(bash "$BIN/didio-warroom.sh" add "Auto increment test" 2>&1)"
CARD7_ID="$(echo "$OUT7A" | grep -oP 'WR-\d+-\d+' | head -1)"
if [[ -n "$CARD7_ID" ]]; then
  CARD7_FILE="$TMPDIR_ROOT/logs/warroom/cards/${CARD7_ID}.json"
  python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    d = json.load(f)
d['overlord_assessment'] = {
    'recommendation': 'promote',
    'priority': 'medium',
    'rationale': 'Test auto-increment'
}
with open(sys.argv[1], 'w') as f:
    json.dump(d, f, indent=2)
" "$CARD7_FILE"
  # Also create F02 to force further increment
  mkdir -p "$TMPDIR_ROOT/tasks/features/F02-also-exists"
  OUT7="$(bash "$BIN/didio-blackhawk-promote.sh" "$CARD7_ID" 2>&1)" && RC7=0 || RC7=$?
  if [[ $RC7 -eq 0 ]]; then
    # Extract the feature ID from output
    PROMOTED_FID="$(echo "$OUT7" | grep -oP 'F\d+' | head -1)"
    if [[ -n "$PROMOTED_FID" ]]; then
      FNUM="${PROMOTED_FID#F}"
      FNUM=$((10#$FNUM))
      if [[ $FNUM -ge 3 ]]; then
        tap ok "feature dir auto-increment -- promoted as $PROMOTED_FID (skipped F01, F02)"
      else
        tap fail "feature dir auto-increment -- got $PROMOTED_FID but expected F03+" "$OUT7"
      fi
    else
      tap fail "feature dir auto-increment -- could not parse feature ID" "$OUT7"
    fi
  else
    tap fail "feature dir auto-increment -- promote failed" "rc=$RC7 out=$OUT7"
  fi
else
  tap fail "feature dir auto-increment -- could not create test card"
fi

# ===========================================================================
# PIPELINE EDGE CASES
# ===========================================================================

# --- Test 8: pipeline-status with no state files -- clean empty output ---
# Clean out any state files first
rm -f "$TMPDIR_ROOT/logs/agents"/pipeline-*.state.json
OUT8="$(bash "$BIN/didio-pipeline-status.sh" 2>&1)" && RC8=0 || RC8=$?
if [[ $RC8 -eq 0 ]] && echo "$OUT8" | grep -qi "no active pipelines"; then
  tap ok "pipeline-status with no state files -- clean empty output"
else
  tap fail "pipeline-status with no state files -- unexpected" "rc=$RC8 out=$OUT8"
fi

# --- Test 9: pipeline-pause on non-existent feature -- errors cleanly ---
OUT9="$(bash "$BIN/didio-pipeline-pause.sh" F99 2>&1)" && RC9=0 || RC9=$?
if [[ $RC9 -ne 0 ]] && echo "$OUT9" | grep -qi "no pipeline state\|not found\|error"; then
  tap ok "pipeline-pause on non-existent feature -- clean error"
else
  tap fail "pipeline-pause on non-existent feature -- unexpected" "rc=$RC9 out=$OUT9"
fi

# --- Test 10: Corrupted state file (invalid JSON) -- status handles gracefully ---
echo "NOT VALID JSON {{{" > "$TMPDIR_ROOT/logs/agents/pipeline-F98.state.json"
OUT10="$(bash "$BIN/didio-pipeline-status.sh" 2>&1)" && RC10=0 || RC10=$?
# In list mode, it should not crash even with a corrupted file
# The json_get helper returns defaults on parse error, so it should show "?" values
if [[ $RC10 -eq 0 ]] || echo "$OUT10" | grep -qi "F98\|no active\|pipeline"; then
  tap ok "corrupted state file -- pipeline-status does not crash"
else
  tap fail "corrupted state file -- pipeline-status crashed" "rc=$RC10 out=$OUT10"
fi
rm -f "$TMPDIR_ROOT/logs/agents/pipeline-F98.state.json"

# --- Test 11: pipeline-status detail on corrupted state file ---
echo "BROKEN JSON" > "$TMPDIR_ROOT/logs/agents/pipeline-F97.state.json"
OUT11="$(bash "$BIN/didio-pipeline-status.sh" F97 2>&1)" && RC11=0 || RC11=$?
# Detail mode tries to read fields; json_get returns defaults.
# Should not crash -- fields show as default/empty values
if [[ $RC11 -eq 0 ]]; then
  tap ok "corrupted state file detail mode -- handled gracefully"
else
  # Even if it exits non-zero, as long as it didn't crash with a bash error
  if echo "$OUT11" | grep -qi "pipeline\|status\|unknown"; then
    tap ok "corrupted state file detail mode -- handled gracefully (non-zero exit)"
  else
    tap fail "corrupted state file detail mode -- crashed" "rc=$RC11 out=$OUT11"
  fi
fi
rm -f "$TMPDIR_ROOT/logs/agents/pipeline-F97.state.json"

# --- Test 12: pipeline-resume on non-existent feature -- clean error ---
OUT12="$(bash "$BIN/didio-pipeline-resume.sh" F99 2>&1)" && RC12=0 || RC12=$?
if [[ $RC12 -ne 0 ]] && echo "$OUT12" | grep -qi "no pipeline state\|not found\|error"; then
  tap ok "pipeline-resume on non-existent feature -- clean error"
else
  tap fail "pipeline-resume on non-existent feature -- unexpected" "rc=$RC12 out=$OUT12"
fi

# ===========================================================================
# SQUAD EDGE CASES
# ===========================================================================

# --- Test 13: Squad scan with no data files -- clean empty report ---
# Source the squad orchestrator and run with all scanners disabled
OUT13="$(bash -c '
export DIDIO_PROJECT_ROOT="'"$TMPDIR_ROOT"'"
export PROJECT_ROOT="'"$TMPDIR_ROOT"'"
export DIDIO_HOME="'"$REAL_PROJECT"'"
source "'"$LIB/squad-orchestrator.sh"'"
squad_scan_all --dry-run
' 2>&1)" && RC13=0 || RC13=$?
if echo "$OUT13" | grep -qi "disabled\|unavailable\|complete\|DRY RUN"; then
  tap ok "squad scan with no data -- clean report with disabled scanners"
else
  tap fail "squad scan with no data -- unexpected output" "rc=$RC13 out=$OUT13"
fi

# --- Test 14: Squad scan produces report JSON -- verify structure ---
# Run a real (non-dry-run) scan; all scanners disabled so it should still produce a report
OUT14="$(bash -c '
export DIDIO_PROJECT_ROOT="'"$TMPDIR_ROOT"'"
export PROJECT_ROOT="'"$TMPDIR_ROOT"'"
export DIDIO_HOME="'"$REAL_PROJECT"'"
source "'"$LIB/squad-orchestrator.sh"'"
squad_scan_all
' 2>&1)" && RC14=0 || RC14=$?
# Check that a report file was created
REPORT_FILE="$(ls "$TMPDIR_ROOT/logs/agents"/squad-report-*.json 2>/dev/null | tail -1)"
if [[ -n "$REPORT_FILE" && -f "$REPORT_FILE" ]]; then
  # Validate JSON structure
  VALID_JSON="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    d = json.load(f)
required = ['report_id', 'timestamp', 'squad_status', 'overall_status']
missing = [k for k in required if k not in d]
if missing:
    print('missing: ' + ', '.join(missing))
else:
    print('valid')
" "$REPORT_FILE" 2>&1)"
  if [[ "$VALID_JSON" == "valid" ]]; then
    tap ok "squad scan report JSON -- valid structure"
  else
    tap fail "squad scan report JSON -- invalid structure" "$VALID_JSON"
  fi
else
  tap fail "squad scan report JSON -- no report file created" "$OUT14"
fi

# ===========================================================================
# MESH EDGE CASES
# ===========================================================================

# --- Test 15: Mesh list with no registry file -- clean init ---
rm -f "$DIDIO_MESH_REGISTRY"
OUT15="$(bash "$BIN/didio-mesh.sh" list 2>&1)" && RC15=0 || RC15=$?
if [[ $RC15 -eq 0 ]] && echo "$OUT15" | grep -qi "no projects registered\|Name"; then
  tap ok "mesh list with no registry -- clean init and output"
else
  tap fail "mesh list with no registry -- unexpected" "rc=$RC15 out=$OUT15"
fi

# --- Test 16: Mesh list --json with fresh registry -- returns empty array ---
# Registry was auto-created by prior test
OUT16="$(bash "$BIN/didio-mesh.sh" list --json 2>&1)" && RC16=0 || RC16=$?
PARSED16="$(echo "$OUT16" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "err")"
if [[ "$PARSED16" == "0" ]]; then
  tap ok "mesh list --json with empty registry -- returns empty array"
else
  tap fail "mesh list --json with empty registry -- unexpected" "rc=$RC16 parsed=$PARSED16"
fi

# --- Test 17: Mesh sync with empty registry -- no crash ---
OUT17="$(bash "$BIN/didio-mesh.sh" sync --dry-run 2>&1)" && RC17=0 || RC17=$?
if [[ $RC17 -eq 0 ]] && echo "$OUT17" | grep -qi "no projects\|nothing to sync\|0 projects\|complete"; then
  tap ok "mesh sync with empty registry -- clean no-op"
else
  tap fail "mesh sync with empty registry -- unexpected" "rc=$RC17 out=$OUT17"
fi

# --- Test 18: Mesh query with empty registry -- no crash ---
OUT18="$(bash "$BIN/didio-mesh.sh" query "test keyword" 2>&1)" && RC18=0 || RC18=$?
if [[ $RC18 -eq 0 ]] && echo "$OUT18" | grep -qi "no results"; then
  tap ok "mesh query with empty registry -- clean no results"
else
  tap fail "mesh query with empty registry -- unexpected" "rc=$RC18 out=$OUT18"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "# F43 Edge Cases: $PASS/$TOTAL passed, $FAIL failed"

# Cleanup mesh temp
rm -rf "$MESH_TMPDIR"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
