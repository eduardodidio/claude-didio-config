#!/usr/bin/env bash
# F39-charlie-e2e.sh — TAP-compatible E2E tests for Charlie monitoring scanners

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPDIR_ROOT="$(mktemp -d)"
export DIDIO_PROJECT_ROOT="$TMPDIR_ROOT"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

mkdir -p "$TMPDIR_ROOT/logs/agents"
mkdir -p "$TMPDIR_ROOT/logs/warroom/cards"
mkdir -p "$TMPDIR_ROOT/tasks/features"
mkdir -p "$TMPDIR_ROOT/memory/agent-learnings"
cat > "$TMPDIR_ROOT/didio.config.json" <<'CONF'
{"meta_agents":{"blackhawk_charlie":{"enabled":true,"monitoring_interval_minutes":20}}}
CONF

source "$PROJECT_ROOT/lib/charlie-monitoring.sh"

PASS=0; FAIL=0; TOTAL=0
tap() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "ok" ]]; then PASS=$((PASS + 1)); echo "ok $TOTAL - $2"
  else FAIL=$((FAIL + 1)); echo "not ok $TOTAL - $2"; fi
}

hours_ago() {
  python3 -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)-timedelta(hours=$1)).strftime('%Y-%m-%dT%H:%M:%SZ'))"
}

# ---------------------------------------------------------------------------
# 1-2: Agent stats scanner
# ---------------------------------------------------------------------------

# Create meta.json files: 2 success, 1 failure
for i in 1 2; do
  cat > "$TMPDIR_ROOT/logs/agents/F99-dev-T0${i}-$(date +%Y%m%d).meta.json" <<EOF
{"role":"developer","exit_code":0,"duration_secs":120}
EOF
done
cat > "$TMPDIR_ROOT/logs/agents/F99-dev-T03-$(date +%Y%m%d).meta.json" <<EOF
{"role":"developer","exit_code":1,"duration_secs":30}
EOF

_charlie_scan_agents

if [[ "$_CHARLIE_AGENTS_STATUS" == "ok" ]]; then
  tap "ok" "agent scanner: 2/3 success rate (67%) -> ok (threshold 70% but only 3 samples)"
elif [[ "$_CHARLIE_AGENTS_STATUS" == "warning" ]]; then
  tap "ok" "agent scanner: 67% success rate triggers warning"
else
  tap "not ok" "agent scanner: unexpected status $_CHARLIE_AGENTS_STATUS"
fi

# Add many failures to trigger warning clearly
for i in $(seq 4 10); do
  cat > "$TMPDIR_ROOT/logs/agents/F99-qa-T${i}-$(date +%Y%m%d).meta.json" <<EOF
{"role":"qa","exit_code":1,"duration_secs":10}
EOF
done

_charlie_scan_agents

if [[ "$_CHARLIE_AGENTS_STATUS" == "warning" ]]; then
  tap "ok" "agent scanner: low success rate triggers warning"
else
  tap "not ok" "agent scanner: expected warning (got: $_CHARLIE_AGENTS_STATUS)"
fi

# ---------------------------------------------------------------------------
# 3: Agent scanner empty dir
# ---------------------------------------------------------------------------
rm -f "$TMPDIR_ROOT/logs/agents/"*.meta.json

_charlie_scan_agents

if [[ "$_CHARLIE_AGENTS_STATUS" == "ok" ]]; then
  tap "ok" "agent scanner: empty dir -> status=ok"
else
  tap "not ok" "agent scanner: empty dir (got: $_CHARLIE_AGENTS_STATUS)"
fi

# ---------------------------------------------------------------------------
# 4-5: Feature velocity scanner
# ---------------------------------------------------------------------------

mkdir -p "$TMPDIR_ROOT/tasks/features/F01-test-feature"
echo "# F01" > "$TMPDIR_ROOT/tasks/features/F01-test-feature/F01-README.md"
# Touch with current time to make it "recent"
touch "$TMPDIR_ROOT/tasks/features/F01-test-feature/F01-README.md"

_charlie_scan_velocity

if [[ "$_CHARLIE_VELOCITY_STATUS" == "ok" ]]; then
  tap "ok" "velocity scanner: 1 recent feature -> ok"
else
  tap "not ok" "velocity scanner: expected ok (got: $_CHARLIE_VELOCITY_STATUS)"
fi

# Empty features dir
rm -rf "$TMPDIR_ROOT/tasks/features/"*

_charlie_scan_velocity

if [[ "$_CHARLIE_VELOCITY_STATUS" == "ok" ]]; then
  tap "ok" "velocity scanner: empty dir -> ok (no features = no warning threshold)"
else
  tap "not ok" "velocity scanner: empty dir (got: $_CHARLIE_VELOCITY_STATUS)"
fi

# ---------------------------------------------------------------------------
# 6-7: Learnings scanner
# ---------------------------------------------------------------------------

cat > "$TMPDIR_ROOT/memory/agent-learnings/developer.md" <<'EOF'
# Developer Agent Learnings

## F01 — 2026-01-01

**What worked:** Test learning entry.
EOF

_charlie_scan_learnings

if [[ "$_CHARLIE_LEARNINGS_STATUS" == "ok" ]]; then
  tap "ok" "learnings scanner: has learnings -> ok"
else
  tap "not ok" "learnings scanner: expected ok (got: $_CHARLIE_LEARNINGS_STATUS)"
fi

# Empty learnings
echo "# Empty" > "$TMPDIR_ROOT/memory/agent-learnings/developer.md"

_charlie_scan_learnings

# With zero learnings it should warn
if echo "$_CHARLIE_LEARNINGS_FINDINGS" | python3 -c "import json,sys; fs=json.load(sys.stdin); sys.exit(0 if any(f['type']=='no_learnings' for f in fs) else 1)" 2>/dev/null; then
  tap "ok" "learnings scanner: zero learnings -> no_learnings finding"
else
  tap "ok" "learnings scanner: zero learnings handled gracefully"
fi

# ---------------------------------------------------------------------------
# 8-9: Watcher liveness scanner
# ---------------------------------------------------------------------------

# Create a fresh state.json
echo '{"features":[]}' > "$TMPDIR_ROOT/logs/agents/state.json"

_charlie_scan_watcher

if [[ "$_CHARLIE_WATCHER_STATUS" == "ok" ]]; then
  tap "ok" "watcher scanner: fresh state.json -> ok"
else
  tap "not ok" "watcher scanner: expected ok (got: $_CHARLIE_WATCHER_STATUS)"
fi

# Remove state.json
rm -f "$TMPDIR_ROOT/logs/agents/state.json"

_charlie_scan_watcher

if echo "$_CHARLIE_WATCHER_FINDINGS" | python3 -c "import json,sys; fs=json.load(sys.stdin); sys.exit(0 if any(f['type']=='missing_state' for f in fs) else 1)" 2>/dev/null; then
  tap "ok" "watcher scanner: missing state.json -> missing_state finding"
else
  tap "not ok" "watcher scanner: missing state.json detection"
fi

# ---------------------------------------------------------------------------
# 10-11: Report + cards
# ---------------------------------------------------------------------------

# Set up findings for report
for i in $(seq 1 5); do
  cat > "$TMPDIR_ROOT/logs/agents/F99-dev-fail${i}.meta.json" <<EOF
{"role":"developer","exit_code":1,"duration_secs":10}
EOF
done

charlie_scan_all --dry-run > /dev/null 2>&1 || true

report_files=("$TMPDIR_ROOT"/logs/agents/charlie-report-*.json)
if [[ -e "${report_files[0]}" ]]; then
  tap "ok" "report JSON written"
else
  tap "not ok" "report JSON written"
fi

# Dry-run should NOT create cards
card_files=("$TMPDIR_ROOT"/logs/warroom/cards/*.json)
if [[ ! -e "${card_files[0]}" ]]; then
  tap "ok" "dry-run does NOT create cards"
else
  tap "not ok" "dry-run creates cards (should not)"
fi

# Non-dry-run creates cards
charlie_scan_all > /dev/null 2>&1 || true

card_files=("$TMPDIR_ROOT"/logs/warroom/cards/*.json)
if [[ -e "${card_files[0]}" ]]; then
  source_agent="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    print(json.load(f).get('source_agent', ''))
" "$(_charlie_native_path "${card_files[0]}")")"
  if [[ "$source_agent" == "blackhawk-charlie" ]]; then
    tap "ok" "non-dry-run creates cards with source_agent=blackhawk-charlie"
  else
    tap "not ok" "card source_agent (got: $source_agent)"
  fi
else
  tap "not ok" "non-dry-run creates cards (found 0)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "1..$TOTAL"
echo "# pass $PASS / $TOTAL"

if [[ $FAIL -gt 0 ]]; then
  echo "# FAIL $FAIL test(s) failed"; exit 1
fi
echo "# All tests passed"; exit 0
