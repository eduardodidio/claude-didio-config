#!/usr/bin/env bash
# charlie-monitoring.sh -- Black Hawk Charlie framework health scanner library.
#
# Source this file (do NOT execute directly):
#   source "$DIDIO_HOME/lib/charlie-monitoring.sh"
#
# Functions:
#   charlie_scan_all [--dry-run]      Main entry: runs all scanners, writes report, creates cards
#   _charlie_scan_agents              Agent spawn stats (success rate, duration)
#   _charlie_scan_velocity            Feature velocity (shipped per window)
#   _charlie_scan_learnings           Learnings growth metrics
#   _charlie_scan_watcher             Watcher/state.json liveness
#
# Requires: didio-config-lib.sh sourced before this file.

_charlie_project_root() {
  if [[ -n "${DIDIO_PROJECT_ROOT:-}" ]]; then
    echo "$DIDIO_PROJECT_ROOT"
  elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    echo "$PROJECT_ROOT"
  else
    echo "$PWD"
  fi
}

_charlie_native_path() {
  if command -v cygpath &>/dev/null; then
    cygpath -m "$1"
  else
    echo "$1"
  fi
}

# Scanner result variables
_CHARLIE_AGENTS_STATUS="ok"
_CHARLIE_AGENTS_FINDINGS="[]"
_CHARLIE_VELOCITY_STATUS="ok"
_CHARLIE_VELOCITY_FINDINGS="[]"
_CHARLIE_LEARNINGS_STATUS="ok"
_CHARLIE_LEARNINGS_FINDINGS="[]"
_CHARLIE_WATCHER_STATUS="ok"
_CHARLIE_WATCHER_FINDINGS="[]"

# Thresholds
_CHARLIE_LOW_SUCCESS_RATE="0.7"
_CHARLIE_HIGH_AVG_DURATION_SECS=600
_CHARLIE_LOW_VELOCITY_FEATURES=0
_CHARLIE_VELOCITY_WINDOW_DAYS=30
_CHARLIE_STATE_STALE_SECS=300

_charlie_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
_charlie_timestamp_id() { date -u +"%Y%m%d-%H%M%S"; }

_charlie_worst_status() {
  local worst="ok"
  for s in "$@"; do
    case "$s" in
      critical) echo "critical"; return 0 ;;
      warning)  worst="warning" ;;
    esac
  done
  echo "$worst"
}

# ---------------------------------------------------------------------------
# Scanner: Agent stats (from .meta.json files)
# ---------------------------------------------------------------------------
_charlie_scan_agents() {
  local root
  root="$(_charlie_project_root)"
  local log_dir="$root/logs/agents"
  local log_dir_py
  log_dir_py="$(_charlie_native_path "$log_dir")"

  local result
  result="$(python3 -c "
import json, glob, sys, os

log_dir = sys.argv[1]
low_success = float(sys.argv[2])
high_duration = int(sys.argv[3])

findings = []
total = 0
success = 0
durations = []

for f in glob.glob(os.path.join(log_dir, '*.meta.json')):
    try:
        with open(f, 'r') as fh:
            d = json.load(fh)
    except Exception:
        continue

    total += 1
    exit_code = d.get('exit_code', d.get('exitCode', None))
    if exit_code == 0:
        success += 1

    duration = d.get('duration_secs', d.get('durationSecs', None))
    if duration is not None and isinstance(duration, (int, float)):
        durations.append(duration)

if total > 0:
    rate = success / total
    avg_dur = sum(durations) / len(durations) if durations else 0

    if rate < low_success:
        findings.append({
            'type': 'low_spawn_success',
            'detail': f'Agent spawn success rate {rate:.0%} ({success}/{total}) below threshold {low_success:.0%}',
            'severity': 'warning'
        })

    if avg_dur > high_duration and durations:
        findings.append({
            'type': 'high_avg_duration',
            'detail': f'Average agent duration {avg_dur:.0f}s exceeds threshold {high_duration}s',
            'severity': 'warning'
        })

    # Also report error-heavy roles
    role_errors = {}
    for f in glob.glob(os.path.join(log_dir, '*.meta.json')):
        try:
            with open(f, 'r') as fh:
                d = json.load(fh)
            ec = d.get('exit_code', d.get('exitCode', None))
            role = d.get('role', 'unknown')
            if ec and ec != 0:
                role_errors[role] = role_errors.get(role, 0) + 1
        except Exception:
            continue

    for role, count in role_errors.items():
        if count >= 3:
            findings.append({
                'type': 'role_error_spike',
                'detail': f'Role \"{role}\" has {count} failed spawns',
                'severity': 'warning'
            })

worst = 'ok'
for f in findings:
    if f.get('severity') == 'critical': worst = 'critical'; break
    elif f.get('severity') == 'warning': worst = 'warning'

print(json.dumps({'status': worst, 'findings': findings, 'metrics': {'total': total, 'success': success, 'avg_duration': round(sum(durations)/len(durations), 1) if durations else 0}}))
" "$log_dir_py" "$_CHARLIE_LOW_SUCCESS_RATE" "$_CHARLIE_HIGH_AVG_DURATION_SECS" 2>/dev/null || echo '{"status":"ok","findings":[],"metrics":{}}')"

  _CHARLIE_AGENTS_STATUS="$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
  _CHARLIE_AGENTS_FINDINGS="$(echo "$result" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['findings']))")"
}

# ---------------------------------------------------------------------------
# Scanner: Feature velocity
# ---------------------------------------------------------------------------
_charlie_scan_velocity() {
  local root
  root="$(_charlie_project_root)"
  local features_dir="$root/tasks/features"
  local features_dir_py
  features_dir_py="$(_charlie_native_path "$features_dir")"

  local result
  result="$(python3 -c "
import json, glob, sys, os, re
from datetime import datetime, timezone, timedelta

features_dir = sys.argv[1]
window_days = int(sys.argv[2])
low_threshold = int(sys.argv[3])

findings = []
now = datetime.now(timezone.utc)
window = now - timedelta(days=window_days)

total_features = 0
recent_features = 0

if os.path.isdir(features_dir):
    for d in sorted(os.listdir(features_dir)):
        full = os.path.join(features_dir, d)
        if os.path.isdir(full) and re.match(r'F\d+-', d):
            total_features += 1
            # Check mtime of README as proxy for completion
            readme = None
            for f in os.listdir(full):
                if f.endswith('-README.md'):
                    readme = os.path.join(full, f)
                    break
            if readme and os.path.isfile(readme):
                mtime = datetime.fromtimestamp(os.path.getmtime(readme), tz=timezone.utc)
                if mtime >= window:
                    recent_features += 1

if total_features > 0 and recent_features <= low_threshold:
    findings.append({
        'type': 'low_velocity',
        'detail': f'Only {recent_features} features shipped in last {window_days} days ({total_features} total)',
        'severity': 'warning'
    })

worst = 'ok'
for f in findings:
    if f.get('severity') == 'critical': worst = 'critical'; break
    elif f.get('severity') == 'warning': worst = 'warning'

print(json.dumps({'status': worst, 'findings': findings, 'metrics': {'total': total_features, 'recent': recent_features, 'window_days': window_days}}))
" "$features_dir_py" "$_CHARLIE_VELOCITY_WINDOW_DAYS" "$_CHARLIE_LOW_VELOCITY_FEATURES" 2>/dev/null || echo '{"status":"ok","findings":[],"metrics":{}}')"

  _CHARLIE_VELOCITY_STATUS="$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
  _CHARLIE_VELOCITY_FINDINGS="$(echo "$result" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['findings']))")"
}

# ---------------------------------------------------------------------------
# Scanner: Learnings growth
# ---------------------------------------------------------------------------
_charlie_scan_learnings() {
  local root
  root="$(_charlie_project_root)"
  local learnings_dir="$root/memory/agent-learnings"
  local learnings_dir_py
  learnings_dir_py="$(_charlie_native_path "$learnings_dir")"

  local result
  result="$(python3 -c "
import json, glob, sys, os

learnings_dir = sys.argv[1]
findings = []

total_entries = 0
roles_with_learnings = 0
empty_roles = []

if os.path.isdir(learnings_dir):
    for md in sorted(glob.glob(os.path.join(learnings_dir, '*.md'))):
        role = os.path.basename(md).replace('.md', '')
        try:
            with open(md, 'r', errors='replace') as f:
                content = f.read()
            count = content.count('## F')
            if count > 0:
                roles_with_learnings += 1
                total_entries += count
            else:
                empty_roles.append(role)
        except Exception:
            empty_roles.append(role)

# No findings for empty roles — it's informational
# Only warn if zero learnings across all roles (framework not being used)
if total_entries == 0 and os.path.isdir(learnings_dir):
    findings.append({
        'type': 'no_learnings',
        'detail': 'No agent learnings found across any role. Framework may not be in active use.',
        'severity': 'warning'
    })

worst = 'ok'
for f in findings:
    if f.get('severity') == 'critical': worst = 'critical'; break
    elif f.get('severity') == 'warning': worst = 'warning'

print(json.dumps({'status': worst, 'findings': findings, 'metrics': {'total_entries': total_entries, 'roles_with_learnings': roles_with_learnings, 'empty_roles': empty_roles}}))
" "$learnings_dir_py" 2>/dev/null || echo '{"status":"ok","findings":[],"metrics":{}}')"

  _CHARLIE_LEARNINGS_STATUS="$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
  _CHARLIE_LEARNINGS_FINDINGS="$(echo "$result" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['findings']))")"
}

# ---------------------------------------------------------------------------
# Scanner: Watcher/state.json liveness
# ---------------------------------------------------------------------------
_charlie_scan_watcher() {
  local root
  root="$(_charlie_project_root)"
  local state_file="$root/logs/agents/state.json"
  local state_file_py
  state_file_py="$(_charlie_native_path "$state_file")"

  local result
  result="$(python3 -c "
import json, sys, os
from datetime import datetime, timezone

state_file = sys.argv[1]
stale_secs = int(sys.argv[2])

findings = []

if os.path.isfile(state_file):
    mtime = os.path.getmtime(state_file)
    now = datetime.now(timezone.utc).timestamp()
    age_secs = now - mtime

    if age_secs > stale_secs:
        findings.append({
            'type': 'stale_state',
            'detail': f'state.json is {age_secs:.0f}s old (threshold: {stale_secs}s). Watcher may not be running.',
            'severity': 'warning',
            'file': 'logs/agents/state.json'
        })
else:
    findings.append({
        'type': 'missing_state',
        'detail': 'state.json not found. Watcher has never run or logs/agents/ is missing.',
        'severity': 'warning',
        'file': 'logs/agents/state.json'
    })

worst = 'ok'
for f in findings:
    if f.get('severity') == 'critical': worst = 'critical'; break
    elif f.get('severity') == 'warning': worst = 'warning'

print(json.dumps({'status': worst, 'findings': findings}))
" "$state_file_py" "$_CHARLIE_STATE_STALE_SECS" 2>/dev/null || echo '{"status":"ok","findings":[]}')"

  _CHARLIE_WATCHER_STATUS="$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
  _CHARLIE_WATCHER_FINDINGS="$(echo "$result" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['findings']))")"
}

# ---------------------------------------------------------------------------
# Report writer
# ---------------------------------------------------------------------------
_charlie_write_report() {
  local root
  root="$(_charlie_project_root)"
  local report_dir="$root/logs/agents"
  local report_dir_py
  report_dir_py="$(_charlie_native_path "$report_dir")"
  local ts
  ts="$(_charlie_timestamp_id)"
  local report_file="$report_dir/charlie-report-${ts}.json"
  local report_file_py
  report_file_py="$(_charlie_native_path "$report_file")"
  local overall="$1"

  mkdir -p "$report_dir"

  python3 -c "
import json, sys, glob, os
from datetime import datetime, timezone

report_file = sys.argv[1]
report_dir = sys.argv[2]
overall = sys.argv[3]
agents_s = sys.argv[4]; agents_f = sys.argv[5]
velocity_s = sys.argv[6]; velocity_f = sys.argv[7]
learnings_s = sys.argv[8]; learnings_f = sys.argv[9]
watcher_s = sys.argv[10]; watcher_f = sys.argv[11]

now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
all_findings = json.loads(agents_f) + json.loads(velocity_f) + json.loads(learnings_f) + json.loads(watcher_f)

report = {
    'report_id': 'CH-' + os.path.basename(report_file).replace('charlie-report-','').replace('.json',''),
    'timestamp': now,
    'scanners': {
        'agents': {'status': agents_s, 'findings': json.loads(agents_f)},
        'velocity': {'status': velocity_s, 'findings': json.loads(velocity_f)},
        'learnings': {'status': learnings_s, 'findings': json.loads(learnings_f)},
        'watcher': {'status': watcher_s, 'findings': json.loads(watcher_f)}
    },
    'overall_status': overall,
    'total_findings': len(all_findings),
    'cards_created': []
}

with open(report_file, 'w') as f:
    json.dump(report, f, indent=2)
    f.write('\n')

reports = sorted(glob.glob(os.path.join(report_dir, 'charlie-report-*.json')))
while len(reports) > 50:
    os.remove(reports.pop(0))

print(report_file)
" "$report_file_py" "$report_dir_py" "$overall" \
  "$_CHARLIE_AGENTS_STATUS" "$_CHARLIE_AGENTS_FINDINGS" \
  "$_CHARLIE_VELOCITY_STATUS" "$_CHARLIE_VELOCITY_FINDINGS" \
  "$_CHARLIE_LEARNINGS_STATUS" "$_CHARLIE_LEARNINGS_FINDINGS" \
  "$_CHARLIE_WATCHER_STATUS" "$_CHARLIE_WATCHER_FINDINGS"
}

# ---------------------------------------------------------------------------
# Card creator (same pattern as Bravo)
# ---------------------------------------------------------------------------
_charlie_create_cards() {
  local root
  root="$(_charlie_project_root)"
  local cards_dir="$root/logs/warroom/cards"
  local cards_dir_py
  cards_dir_py="$(_charlie_native_path "$cards_dir")"

  python3 -c "
import json, sys, glob, os
from datetime import datetime, timezone

cards_dir = sys.argv[1]
all_findings = json.loads(sys.argv[2]) + json.loads(sys.argv[3]) + json.loads(sys.argv[4]) + json.loads(sys.argv[5])
now = datetime.now(timezone.utc)

actionable = [f for f in all_findings if f.get('severity') in ('warning', 'critical')]
if not actionable:
    sys.exit(0)

by_type = {}
for f in actionable:
    by_type.setdefault(f.get('type','unknown'), []).append(f)

existing_titles = set()
if os.path.isdir(cards_dir):
    for cf in glob.glob(os.path.join(cards_dir, '*.json')):
        try:
            with open(cf, 'r') as fh:
                card = json.load(fh)
            if card.get('status') in ('incoming', 'triaging'):
                existing_titles.add(card.get('title', ''))
        except Exception:
            pass

created = []
for finding_type, findings in by_type.items():
    title = f'[Charlie] {finding_type.replace(\"_\", \" \").title()}'
    if title in existing_titles:
        continue

    worst_sev = 'critical' if any(f.get('severity')=='critical' for f in findings) else 'warning'
    priority = 'high' if worst_sev == 'critical' else 'medium'

    lines = [f'Charlie monitoring scanner detected {len(findings)} finding(s):', '']
    for f in findings:
        lines.append(f'- **{f.get(\"severity\",\"?\").upper()}**: {f.get(\"detail\",\"\")}')
    body = chr(10).join(lines)

    date_str = now.strftime('%Y%m%d')
    existing_today = [os.path.basename(cf) for cf in glob.glob(os.path.join(cards_dir, f'WR-{date_str}-*.json'))]
    next_num = len(existing_today) + 1
    card_id = f'WR-{date_str}-{next_num:03d}'
    while os.path.exists(os.path.join(cards_dir, f'{card_id}.json')):
        next_num += 1
        card_id = f'WR-{date_str}-{next_num:03d}'

    card = {
        'card_id': card_id, 'title': title, 'body': body,
        'source': 'agent', 'created_at': now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'updated_at': None, 'status': 'incoming',
        'priority_suggestion': priority, 'overlord_assessment': None,
        'promoted_to': None, 'tags': ['charlie', 'monitoring', finding_type],
        'source_agent': 'blackhawk-charlie', 'source_feature': None
    }

    os.makedirs(cards_dir, exist_ok=True)
    with open(os.path.join(cards_dir, f'{card_id}.json'), 'w') as fh:
        json.dump(card, fh, indent=2)
        fh.write('\n')
    created.append(card_id)

if created:
    print(f'[charlie] Created {len(created)} War Room card(s): {\" \".join(created)}')
else:
    print('[charlie] No new cards created (all findings already have existing cards)')
" "$cards_dir_py" \
  "$_CHARLIE_AGENTS_FINDINGS" "$_CHARLIE_VELOCITY_FINDINGS" \
  "$_CHARLIE_LEARNINGS_FINDINGS" "$_CHARLIE_WATCHER_FINDINGS"
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
charlie_scan_all() {
  local dry_run=0
  [[ "${1:-}" == "--dry-run" || "${1:-}" == "1" ]] && dry_run=1

  _charlie_scan_agents
  _charlie_scan_velocity
  _charlie_scan_learnings
  _charlie_scan_watcher

  local overall
  overall="$(_charlie_worst_status "$_CHARLIE_AGENTS_STATUS" "$_CHARLIE_VELOCITY_STATUS" "$_CHARLIE_LEARNINGS_STATUS" "$_CHARLIE_WATCHER_STATUS")"

  local report_file
  report_file="$(_charlie_write_report "$overall")"

  if [[ $dry_run -eq 0 ]]; then
    _charlie_create_cards
  fi

  local mode="Scan"
  [[ $dry_run -eq 1 ]] && mode="DRY RUN"
  echo "[charlie] ${mode} complete: agents=${_CHARLIE_AGENTS_STATUS} velocity=${_CHARLIE_VELOCITY_STATUS} learnings=${_CHARLIE_LEARNINGS_STATUS} watcher=${_CHARLIE_WATCHER_STATUS} overall=${overall}"
  if [[ -n "${report_file:-}" ]]; then
    echo "[charlie] Report: ${report_file}"
  fi
}
