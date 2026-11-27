#!/usr/bin/env bash
# F36-bravo-e2e.sh — TAP-compatible E2E tests for Bravo intelligence scanners
#
# Tests all 4 scanners, report aggregator, card creation, dry-run, and dedup.
# Uses synthetic fixtures in a temp directory — no real data touched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use a temp directory as project root
TMPDIR_ROOT="$(mktemp -d)"
export DIDIO_PROJECT_ROOT="$TMPDIR_ROOT"

trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Create directory structure
mkdir -p "$TMPDIR_ROOT/logs/agents/flags"
mkdir -p "$TMPDIR_ROOT/logs/decisions"
mkdir -p "$TMPDIR_ROOT/logs/governance"
mkdir -p "$TMPDIR_ROOT/logs/warroom/cards"
# Create a minimal didio.config.json
cat > "$TMPDIR_ROOT/didio.config.json" <<'CONF'
{
  "meta_agents": {
    "blackhawk_bravo": { "enabled": true, "monitoring_interval_minutes": 15 }
  }
}
CONF

# Source the library
source "$PROJECT_ROOT/lib/bravo-intelligence.sh"

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

# Helper: generate ISO timestamp N hours ago
hours_ago() {
  python3 -c "
from datetime import datetime, timezone, timedelta
print((datetime.now(timezone.utc) - timedelta(hours=$1)).strftime('%Y-%m-%dT%H:%M:%SZ'))
"
}

# ---------------------------------------------------------------------------
# 1-3: Pipeline scanner
# ---------------------------------------------------------------------------

# Create a stuck pipeline (running, updated 3h ago)
cat > "$TMPDIR_ROOT/logs/agents/pipeline-F99.state.json" <<EOF
{
  "feature": "F99",
  "started_at": "$(hours_ago 5)",
  "updated_at": "$(hours_ago 3)",
  "stage": "waves",
  "status": "running",
  "exit_code": null,
  "error": null,
  "paused_at": null,
  "resume_from": null
}
EOF

# Create a failed pipeline
cat > "$TMPDIR_ROOT/logs/agents/pipeline-F98.state.json" <<EOF
{
  "feature": "F98",
  "started_at": "$(hours_ago 2)",
  "updated_at": "$(hours_ago 1)",
  "stage": "waves",
  "status": "failed",
  "exit_code": 1,
  "error": "Wave 2 failed",
  "paused_at": null,
  "resume_from": null
}
EOF

# Create an OK pipeline
cat > "$TMPDIR_ROOT/logs/agents/pipeline-F97.state.json" <<EOF
{
  "feature": "F97",
  "started_at": "$(hours_ago 10)",
  "updated_at": "$(hours_ago 1)",
  "stage": "done",
  "status": "done",
  "exit_code": 0,
  "error": null,
  "paused_at": null,
  "resume_from": null
}
EOF

_bravo_scan_pipelines

if [[ "$_BRAVO_PIPELINE_STATUS" == "critical" ]]; then
  tap "ok" "pipeline scanner: status=critical when failed pipeline exists"
else
  tap "not ok" "pipeline scanner: status=critical (got: $_BRAVO_PIPELINE_STATUS)"
fi

# Check stuck pipeline detected
if echo "$_BRAVO_PIPELINE_FINDINGS" | python3 -c "import json,sys; fs=json.load(sys.stdin); sys.exit(0 if any(f['type']=='stuck_pipeline' for f in fs) else 1)"; then
  tap "ok" "pipeline scanner: stuck pipeline detected"
else
  tap "not ok" "pipeline scanner: stuck pipeline detected"
fi

# Check failed pipeline detected
if echo "$_BRAVO_PIPELINE_FINDINGS" | python3 -c "import json,sys; fs=json.load(sys.stdin); sys.exit(0 if any(f['type']=='failed_pipeline' for f in fs) else 1)"; then
  tap "ok" "pipeline scanner: failed pipeline detected"
else
  tap "not ok" "pipeline scanner: failed pipeline detected"
fi

# ---------------------------------------------------------------------------
# 4: Pipeline scanner empty dir
# ---------------------------------------------------------------------------
rm "$TMPDIR_ROOT/logs/agents/pipeline-"*.state.json

_bravo_scan_pipelines

if [[ "$_BRAVO_PIPELINE_STATUS" == "ok" ]]; then
  tap "ok" "pipeline scanner: empty directory -> status=ok"
else
  tap "not ok" "pipeline scanner: empty directory -> status=ok (got: $_BRAVO_PIPELINE_STATUS)"
fi

# ---------------------------------------------------------------------------
# 5-7: Flag scanner
# ---------------------------------------------------------------------------

# Create a blocked flag (48h ago)
cat > "$TMPDIR_ROOT/logs/agents/flags/F99_blocked_001.json" <<EOF
{
  "flag_id": "F99_blocked_001",
  "feature": "F99",
  "type": "blocked",
  "task": "F99-T01",
  "message": "Test blocked",
  "raised_at": "$(hours_ago 48)",
  "resolved_at": null
}
EOF

# Create a stale warning flag (48h ago)
cat > "$TMPDIR_ROOT/logs/agents/flags/F99_warning_002.json" <<EOF
{
  "flag_id": "F99_warning_002",
  "feature": "F99",
  "type": "warning",
  "task": null,
  "message": "Test stale",
  "raised_at": "$(hours_ago 48)",
  "resolved_at": null
}
EOF

# Create a resolved flag (should be ignored)
cat > "$TMPDIR_ROOT/logs/agents/flags/F98_blocked_001.json" <<EOF
{
  "flag_id": "F98_blocked_001",
  "feature": "F98",
  "type": "blocked",
  "task": null,
  "message": "Resolved",
  "raised_at": "$(hours_ago 72)",
  "resolved_at": "$(hours_ago 24)"
}
EOF

_bravo_scan_flags

if echo "$_BRAVO_FLAGS_FINDINGS" | python3 -c "import json,sys; fs=json.load(sys.stdin); sys.exit(0 if any(f['type']=='blocked_feature' for f in fs) else 1)"; then
  tap "ok" "flag scanner: blocked feature detected"
else
  tap "not ok" "flag scanner: blocked feature detected"
fi

if echo "$_BRAVO_FLAGS_FINDINGS" | python3 -c "import json,sys; fs=json.load(sys.stdin); sys.exit(0 if any(f['type']=='stale_flag' for f in fs) else 1)"; then
  tap "ok" "flag scanner: stale flag detected"
else
  tap "not ok" "flag scanner: stale flag detected"
fi

# Resolved flag should NOT appear
resolved_count="$(echo "$_BRAVO_FLAGS_FINDINGS" | python3 -c "import json,sys; fs=json.load(sys.stdin); print(sum(1 for f in fs if f.get('feature')=='F98'))")"
if [[ "$resolved_count" == "0" ]]; then
  tap "ok" "flag scanner: resolved flag ignored"
else
  tap "not ok" "flag scanner: resolved flag ignored (found $resolved_count findings for F98)"
fi

# ---------------------------------------------------------------------------
# 8: Flag scanner empty dir
# ---------------------------------------------------------------------------
rm "$TMPDIR_ROOT/logs/agents/flags/"*.json

_bravo_scan_flags

if [[ "$_BRAVO_FLAGS_STATUS" == "ok" ]]; then
  tap "ok" "flag scanner: empty directory -> status=ok"
else
  tap "not ok" "flag scanner: empty directory -> status=ok (got: $_BRAVO_FLAGS_STATUS)"
fi

# ---------------------------------------------------------------------------
# 9-10: Token scanner
# ---------------------------------------------------------------------------

# Create a critical token schedule
cat > "$TMPDIR_ROOT/logs/agents/token-schedule-suggestion.json" <<EOF
{
  "status": "critical",
  "pct_used": 0.95,
  "minutes_to_depletion": 10,
  "stale": false
}
EOF

_bravo_scan_token

if [[ "$_BRAVO_TOKEN_STATUS" == "critical" ]]; then
  tap "ok" "token scanner: critical status detected"
else
  tap "not ok" "token scanner: critical status detected (got: $_BRAVO_TOKEN_STATUS)"
fi

# Replace with OK token schedule
cat > "$TMPDIR_ROOT/logs/agents/token-schedule-suggestion.json" <<EOF
{
  "status": "ok",
  "pct_used": 0.20,
  "minutes_to_depletion": 500,
  "stale": false
}
EOF
rm -f "$TMPDIR_ROOT/logs/session-budget.json"

_bravo_scan_token

if [[ "$_BRAVO_TOKEN_STATUS" == "ok" ]]; then
  tap "ok" "token scanner: OK status -> no findings"
else
  tap "not ok" "token scanner: OK status -> no findings (got: $_BRAVO_TOKEN_STATUS)"
fi

# ---------------------------------------------------------------------------
# 11: Token scanner missing files
# ---------------------------------------------------------------------------
rm -f "$TMPDIR_ROOT/logs/agents/token-schedule-suggestion.json"
rm -f "$TMPDIR_ROOT/logs/session-budget.json"

_bravo_scan_token

if [[ "$_BRAVO_TOKEN_STATUS" == "ok" ]]; then
  tap "ok" "token scanner: missing files -> status=ok"
else
  tap "not ok" "token scanner: missing files -> status=ok (got: $_BRAVO_TOKEN_STATUS)"
fi

# ---------------------------------------------------------------------------
# 12: Decision scanner — low confidence
# ---------------------------------------------------------------------------

for i in 1 2 3 4 5; do
  cat > "$TMPDIR_ROOT/logs/governance/G-D-TEST-00${i}.json" <<EOF
{
  "decision_id": "D-TEST-00${i}",
  "reviewed_at": "$(hours_ago $((i * 2)))",
  "verdict": "agree",
  "confidence": 0.4
}
EOF
done

_bravo_scan_decisions

if echo "$_BRAVO_DECISIONS_FINDINGS" | python3 -c "import json,sys; fs=json.load(sys.stdin); sys.exit(0 if any(f['type']=='low_confidence' for f in fs) else 1)"; then
  tap "ok" "decision scanner: low confidence detected"
else
  tap "not ok" "decision scanner: low confidence detected"
fi

# ---------------------------------------------------------------------------
# 13: Decision scanner empty dirs
# ---------------------------------------------------------------------------
rm -f "$TMPDIR_ROOT/logs/governance/"*.json
rm -f "$TMPDIR_ROOT/logs/decisions/"*.json

_bravo_scan_decisions

if [[ "$_BRAVO_DECISIONS_STATUS" == "ok" ]]; then
  tap "ok" "decision scanner: empty directories -> status=ok"
else
  tap "not ok" "decision scanner: empty directories -> status=ok (got: $_BRAVO_DECISIONS_STATUS)"
fi

# ---------------------------------------------------------------------------
# 14-15: Report aggregator
# ---------------------------------------------------------------------------

# Set up mixed findings for report test
cat > "$TMPDIR_ROOT/logs/agents/pipeline-F99.state.json" <<EOF
{
  "feature": "F99",
  "started_at": "$(hours_ago 5)",
  "updated_at": "$(hours_ago 3)",
  "stage": "waves",
  "status": "running",
  "exit_code": null,
  "error": null,
  "paused_at": null,
  "resume_from": null
}
EOF
cat > "$TMPDIR_ROOT/logs/agents/token-schedule-suggestion.json" <<EOF
{ "status": "warning", "pct_used": 0.75, "stale": false }
EOF

_bravo_scan_pipelines
_bravo_scan_flags
_bravo_scan_token
_bravo_scan_decisions

overall="$(_bravo_worst_status "$_BRAVO_PIPELINE_STATUS" "$_BRAVO_FLAGS_STATUS" "$_BRAVO_TOKEN_STATUS" "$_BRAVO_DECISIONS_STATUS")"

if [[ "$overall" == "warning" ]]; then
  tap "ok" "report: overall status is worst of all scanners (warning)"
else
  tap "not ok" "report: overall status is worst of all scanners (expected warning, got: $overall)"
fi

report_file="$(_bravo_write_report "$overall")"

if [[ -f "$report_file" ]]; then
  tap "ok" "report: JSON file written to expected path"
else
  tap "not ok" "report: JSON file written to expected path (file not found)"
fi

# ---------------------------------------------------------------------------
# 16: Dry-run does NOT create cards
# ---------------------------------------------------------------------------
bravo_scan_all --dry-run > /dev/null 2>&1 || true

card_files=("$TMPDIR_ROOT"/logs/warroom/cards/*.json)
if [[ ! -e "${card_files[0]}" ]]; then
  tap "ok" "dry-run does NOT create War Room cards"
else
  tap "not ok" "dry-run does NOT create War Room cards (found ${#card_files[@]})"
fi

# ---------------------------------------------------------------------------
# 17: Non-dry-run creates cards
# ---------------------------------------------------------------------------
bravo_scan_all > /dev/null 2>&1 || true

card_files=("$TMPDIR_ROOT"/logs/warroom/cards/*.json)
if [[ -e "${card_files[0]}" ]]; then
  tap "ok" "non-dry-run creates War Room cards (${#card_files[@]} card(s))"
else
  tap "not ok" "non-dry-run creates War Room cards (found 0)"
fi

# Check source_agent on created card
if [[ -e "${card_files[0]}" ]]; then
  source_agent="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    print(json.load(f).get('source_agent', ''))
" "${card_files[0]}")"
  if [[ "$source_agent" == "blackhawk-bravo" ]]; then
    tap "ok" "card source_agent is blackhawk-bravo"
  else
    tap "not ok" "card source_agent is blackhawk-bravo (got: $source_agent)"
  fi
else
  tap "not ok" "card source_agent check (no card file found)"
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
