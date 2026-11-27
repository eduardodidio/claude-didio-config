#!/usr/bin/env bash
# bravo-intelligence.sh -- Black Hawk Bravo intelligence scanner library.
#
# Source this file (do NOT execute directly):
#   source "$DIDIO_HOME/lib/bravo-intelligence.sh"
#
# Functions:
#   bravo_scan_all [--dry-run]        Main entry: runs all scanners, writes report, creates cards
#   _bravo_scan_pipelines             Pipeline health scanner
#   _bravo_scan_flags                 Flag health scanner
#   _bravo_scan_token                 Token budget scanner
#   _bravo_scan_decisions             Decision/governance drift scanner
#   _bravo_write_report               Write JSON report to logs/agents/
#   _bravo_create_cards               Create War Room cards for findings
#
# Requires: didio-config-lib.sh sourced before this file.

# -- Resolve project root --
_bravo_project_root() {
  if [[ -n "${DIDIO_PROJECT_ROOT:-}" ]]; then
    echo "$DIDIO_PROJECT_ROOT"
  elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    echo "$PROJECT_ROOT"
  else
    echo "$PWD"
  fi
}

# Scanner result variables (set by each scanner)
_BRAVO_PIPELINE_STATUS="ok"
_BRAVO_PIPELINE_FINDINGS="[]"
_BRAVO_FLAGS_STATUS="ok"
_BRAVO_FLAGS_FINDINGS="[]"
_BRAVO_TOKEN_STATUS="ok"
_BRAVO_TOKEN_FINDINGS="[]"
_BRAVO_DECISIONS_STATUS="ok"
_BRAVO_DECISIONS_FINDINGS="[]"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_bravo_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_bravo_timestamp_id() {
  date -u +"%Y%m%d-%H%M%S"
}

# Determine worst status from a list of statuses
_bravo_worst_status() {
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
# Thresholds (constants)
# ---------------------------------------------------------------------------
_BRAVO_STUCK_HOURS=2
_BRAVO_STALE_FLAG_HOURS=24
_BRAVO_FLAG_STORM_THRESHOLD=5
_BRAVO_LOW_BURN_MINUTES=30
_BRAVO_BUDGET_STALE_HOURS=1
_BRAVO_CHALLENGE_WINDOW_DAYS=7
_BRAVO_CHALLENGE_THRESHOLD=3
_BRAVO_LOW_CONFIDENCE_THRESHOLD="0.6"
_BRAVO_ESCALATION_THRESHOLD=2
_BRAVO_RECENT_DECISIONS=10
_BRAVO_RECENT_REVIEWS=5

# ---------------------------------------------------------------------------
# Scanner: Pipelines (T04)
# ---------------------------------------------------------------------------
_bravo_scan_pipelines() {
  local root
  root="$(_bravo_project_root)"
  local state_dir="$root/logs/agents"

  local result
  result="$(python3 -c "
import json, glob, sys, os
from datetime import datetime, timezone, timedelta

state_dir = sys.argv[1]
stuck_hours = int(sys.argv[2])

findings = []
now = datetime.now(timezone.utc)

for f in sorted(glob.glob(os.path.join(state_dir, 'pipeline-*.state.json'))):
    try:
        with open(f, 'r') as fh:
            d = json.load(fh)
    except Exception:
        continue

    feature = d.get('feature', os.path.basename(f))
    status = d.get('status', '')
    exit_code = d.get('exit_code')
    error = d.get('error')
    updated_at = d.get('updated_at', '')
    paused_at = d.get('paused_at')
    resume_from = d.get('resume_from')
    rel = os.path.relpath(f, os.path.dirname(state_dir))

    # Parse updated_at
    try:
        up = datetime.fromisoformat(updated_at.replace('Z', '+00:00'))
    except Exception:
        up = now

    hours_since = (now - up).total_seconds() / 3600

    # failed_pipeline
    if exit_code is not None and exit_code != 0 and exit_code != 2:
        findings.append({
            'type': 'failed_pipeline',
            'feature': feature,
            'detail': f'Pipeline {feature} failed with exit_code={exit_code}' + (f': {error}' if error else ''),
            'severity': 'critical',
            'file': rel
        })
    # escalated_pipeline
    elif exit_code == 2:
        findings.append({
            'type': 'escalated_pipeline',
            'feature': feature,
            'detail': f'Pipeline {feature} escalated (exit_code=2)',
            'severity': 'warning',
            'file': rel
        })
    # error_pipeline
    elif error and status != 'done':
        findings.append({
            'type': 'error_pipeline',
            'feature': feature,
            'detail': f'Pipeline {feature} has error: {error}',
            'severity': 'critical',
            'file': rel
        })
    # stuck_pipeline
    elif status == 'running' and hours_since > stuck_hours:
        findings.append({
            'type': 'stuck_pipeline',
            'feature': feature,
            'detail': f'Pipeline {feature} running since {updated_at}, last update {hours_since:.1f}h ago',
            'severity': 'warning',
            'file': rel
        })
    # paused_pipeline > 24h
    if paused_at and not resume_from:
        try:
            pa = datetime.fromisoformat(paused_at.replace('Z', '+00:00'))
            paused_hours = (now - pa).total_seconds() / 3600
            if paused_hours > 24:
                findings.append({
                    'type': 'paused_pipeline',
                    'feature': feature,
                    'detail': f'Pipeline {feature} paused for {paused_hours:.1f}h without resume',
                    'severity': 'warning',
                    'file': rel
                })
        except Exception:
            pass

worst = 'ok'
for f in findings:
    if f['severity'] == 'critical':
        worst = 'critical'
        break
    elif f['severity'] == 'warning':
        worst = 'warning'

print(json.dumps({'status': worst, 'findings': findings}))
" "$state_dir" "$_BRAVO_STUCK_HOURS" 2>/dev/null || echo '{"status":"ok","findings":[]}')"

  _BRAVO_PIPELINE_STATUS="$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
  _BRAVO_PIPELINE_FINDINGS="$(echo "$result" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['findings']))")"
}

# ---------------------------------------------------------------------------
# Scanner: Flags (T05)
# ---------------------------------------------------------------------------
_bravo_scan_flags() {
  local root
  root="$(_bravo_project_root)"
  local flags_dir="$root/logs/agents/flags"

  local result
  result="$(python3 -c "
import json, glob, sys, os
from datetime import datetime, timezone

flags_dir = sys.argv[1]
stale_hours = int(sys.argv[2])
storm_threshold = int(sys.argv[3])

findings = []
now = datetime.now(timezone.utc)

# Collect unresolved flags per feature
unresolved_by_feature = {}

for f in sorted(glob.glob(os.path.join(flags_dir, '*.json'))):
    try:
        with open(f, 'r') as fh:
            d = json.load(fh)
    except Exception:
        continue

    resolved = d.get('resolved_at')
    if resolved:
        continue  # skip resolved flags

    feature = d.get('feature', 'unknown')
    flag_type = d.get('type', 'unknown')
    raised_at = d.get('raised_at', '')
    task = d.get('task', '')
    rel = os.path.relpath(f, os.path.dirname(os.path.dirname(flags_dir)))

    # Track for storm detection
    unresolved_by_feature.setdefault(feature, []).append(d)

    # Parse raised_at
    try:
        ra = datetime.fromisoformat(raised_at.replace('Z', '+00:00'))
        hours_since = (now - ra).total_seconds() / 3600
    except Exception:
        hours_since = 0

    # blocked_feature
    if flag_type == 'blocked':
        detail = f'Feature {feature} blocked'
        if task:
            detail += f' (task {task})'
        detail += f' since {raised_at}'
        findings.append({
            'type': 'blocked_feature',
            'feature': feature,
            'detail': detail,
            'severity': 'critical',
            'file': rel
        })
    # stale_flag
    elif hours_since > stale_hours:
        findings.append({
            'type': 'stale_flag',
            'feature': feature,
            'detail': f'Flag type={flag_type} for {feature} unresolved for {hours_since:.1f}h',
            'severity': 'warning',
            'file': rel
        })

# flag_storm
for feat, flags in unresolved_by_feature.items():
    if len(flags) >= storm_threshold:
        findings.append({
            'type': 'flag_storm',
            'feature': feat,
            'detail': f'{len(flags)} unresolved flags for {feat}',
            'severity': 'warning',
            'file': flags_dir
        })

worst = 'ok'
for f in findings:
    if f['severity'] == 'critical':
        worst = 'critical'
        break
    elif f['severity'] == 'warning':
        worst = 'warning'

print(json.dumps({'status': worst, 'findings': findings}))
" "$flags_dir" "$_BRAVO_STALE_FLAG_HOURS" "$_BRAVO_FLAG_STORM_THRESHOLD" 2>/dev/null || echo '{"status":"ok","findings":[]}')"

  _BRAVO_FLAGS_STATUS="$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
  _BRAVO_FLAGS_FINDINGS="$(echo "$result" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['findings']))")"
}

# ---------------------------------------------------------------------------
# Scanner: Token budget (T06)
# ---------------------------------------------------------------------------
_bravo_scan_token() {
  local root
  root="$(_bravo_project_root)"
  local token_file="$root/logs/agents/token-schedule-suggestion.json"
  local budget_file="$root/logs/session-budget.json"

  local result
  result="$(python3 -c "
import json, sys, os
from datetime import datetime, timezone

token_file = sys.argv[1]
budget_file = sys.argv[2]
low_burn_minutes = int(sys.argv[3])
stale_hours = int(sys.argv[4])

findings = []
now = datetime.now(timezone.utc)

# Token schedule
if os.path.isfile(token_file):
    try:
        with open(token_file, 'r') as f:
            d = json.load(f)
        status = d.get('status', 'ok')
        pct = d.get('pct_used', 0)
        remaining = d.get('minutes_to_depletion', 999)
        stale = d.get('stale', False)
        rel = os.path.relpath(token_file, os.path.dirname(os.path.dirname(token_file)))

        if status == 'critical':
            findings.append({
                'type': 'token_critical',
                'detail': f'Token budget critical: {pct*100:.1f}% used',
                'severity': 'critical',
                'file': rel
            })
        elif status == 'warning':
            findings.append({
                'type': 'token_warning',
                'detail': f'Token budget warning: {pct*100:.1f}% used',
                'severity': 'warning',
                'file': rel
            })

        if stale:
            findings.append({
                'type': 'budget_stale',
                'detail': 'Token schedule data marked as stale',
                'severity': 'warning',
                'file': rel
            })
    except Exception:
        pass

# Session budget
if os.path.isfile(budget_file):
    try:
        with open(budget_file, 'r') as f:
            d = json.load(f)
        remaining_min = d.get('remaining_minutes', 999)
        updated_at = d.get('updated_at', '')
        rel = os.path.relpath(budget_file, os.path.dirname(budget_file))

        if remaining_min < low_burn_minutes:
            findings.append({
                'type': 'high_burn_rate',
                'detail': f'Only {remaining_min} minutes of token budget remaining',
                'severity': 'warning',
                'file': rel
            })

        # Check staleness
        if updated_at:
            try:
                up = datetime.fromisoformat(updated_at.replace('Z', '+00:00'))
                hours_since = (now - up).total_seconds() / 3600
                if hours_since > stale_hours:
                    findings.append({
                        'type': 'budget_stale',
                        'detail': f'Session budget data is {hours_since:.1f}h old',
                        'severity': 'warning',
                        'file': rel
                    })
            except Exception:
                pass
    except Exception:
        pass

worst = 'ok'
for f in findings:
    if f['severity'] == 'critical':
        worst = 'critical'
        break
    elif f['severity'] == 'warning':
        worst = 'warning'

print(json.dumps({'status': worst, 'findings': findings}))
" "$token_file" "$budget_file" "$_BRAVO_LOW_BURN_MINUTES" "$_BRAVO_BUDGET_STALE_HOURS" 2>/dev/null || echo '{"status":"ok","findings":[]}')"

  _BRAVO_TOKEN_STATUS="$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
  _BRAVO_TOKEN_FINDINGS="$(echo "$result" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['findings']))")"
}

# ---------------------------------------------------------------------------
# Scanner: Decisions/governance (T07)
# ---------------------------------------------------------------------------
_bravo_scan_decisions() {
  local root
  root="$(_bravo_project_root)"
  local decisions_dir="$root/logs/decisions"
  local governance_dir="$root/logs/governance"

  local result
  result="$(python3 -c "
import json, glob, sys, os
from datetime import datetime, timezone, timedelta

decisions_dir = sys.argv[1]
governance_dir = sys.argv[2]
challenge_days = int(sys.argv[3])
challenge_threshold = int(sys.argv[4])
confidence_threshold = float(sys.argv[5])
escalation_threshold = int(sys.argv[6])
recent_decisions = int(sys.argv[7])
recent_reviews = int(sys.argv[8])

findings = []
now = datetime.now(timezone.utc)
window = now - timedelta(days=challenge_days)

# --- Governance reviews ---
reviews = []
for f in sorted(glob.glob(os.path.join(governance_dir, 'G-*.json')), reverse=True):
    # Skip round and summary files
    base = os.path.basename(f)
    if '-round-' in base or '-summary' in base:
        continue
    try:
        with open(f, 'r') as fh:
            d = json.load(fh)
        reviews.append((f, d))
    except Exception:
        continue

# Check low confidence in last N reviews
recent = reviews[:recent_reviews]
if recent:
    confidences = [d.get('confidence', 1.0) for _, d in recent if d.get('confidence') is not None]
    if confidences:
        avg_conf = sum(confidences) / len(confidences)
        if avg_conf < confidence_threshold:
            files = [os.path.relpath(f, os.path.dirname(governance_dir)) for f, _ in recent]
            findings.append({
                'type': 'low_confidence',
                'detail': f'Average GateKeeper confidence {avg_conf:.2f} across last {len(confidences)} reviews (threshold: {confidence_threshold})',
                'severity': 'warning',
                'files': files
            })

# Check repeated challenges in window
challenges = []
for f, d in reviews:
    verdict = d.get('verdict', '')
    reviewed_at = d.get('reviewed_at', '')
    if verdict == 'challenge':
        try:
            ra = datetime.fromisoformat(reviewed_at.replace('Z', '+00:00'))
            if ra >= window:
                challenges.append((f, d))
        except Exception:
            pass

if len(challenges) >= challenge_threshold:
    files = [os.path.relpath(f, os.path.dirname(governance_dir)) for f, _ in challenges]
    findings.append({
        'type': 'repeated_challenges',
        'detail': f'{len(challenges)} GateKeeper challenges in last {challenge_days} days (threshold: {challenge_threshold})',
        'severity': 'warning',
        'files': files
    })

# --- Decisions ---
decisions = []
for f in sorted(glob.glob(os.path.join(decisions_dir, 'D-*.json')), reverse=True):
    try:
        with open(f, 'r') as fh:
            d = json.load(fh)
        decisions.append((f, d))
    except Exception:
        continue

# Check escalation frequency in last N decisions
recent_dec = decisions[:recent_decisions]
escalations = [(f, d) for f, d in recent_dec if d.get('status') == 'escalated']
if len(escalations) >= escalation_threshold:
    files = [os.path.relpath(f, os.path.dirname(decisions_dir)) for f, _ in escalations]
    findings.append({
        'type': 'escalation_spike',
        'detail': f'{len(escalations)} escalations in last {len(recent_dec)} decisions (threshold: {escalation_threshold})',
        'severity': 'warning',
        'files': files
    })

worst = 'ok'
for f in findings:
    if f.get('severity') == 'critical':
        worst = 'critical'
        break
    elif f.get('severity') == 'warning':
        worst = 'warning'

print(json.dumps({'status': worst, 'findings': findings}))
" "$decisions_dir" "$governance_dir" "$_BRAVO_CHALLENGE_WINDOW_DAYS" "$_BRAVO_CHALLENGE_THRESHOLD" "$_BRAVO_LOW_CONFIDENCE_THRESHOLD" "$_BRAVO_ESCALATION_THRESHOLD" "$_BRAVO_RECENT_DECISIONS" "$_BRAVO_RECENT_REVIEWS" 2>/dev/null || echo '{"status":"ok","findings":[]}')"

  _BRAVO_DECISIONS_STATUS="$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
  _BRAVO_DECISIONS_FINDINGS="$(echo "$result" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['findings']))")"
}

# ---------------------------------------------------------------------------
# Report writer (T08)
# ---------------------------------------------------------------------------
_bravo_write_report() {
  local root
  root="$(_bravo_project_root)"
  local report_dir="$root/logs/agents"
  local ts
  ts="$(_bravo_timestamp_id)"
  local report_id="BR-${ts}"
  local report_file="$report_dir/bravo-report-${ts}.json"
  local overall="$1"

  mkdir -p "$report_dir"

  python3 -c "
import json, sys, glob, os

report_id = sys.argv[1]
overall = sys.argv[2]
report_file = sys.argv[3]
report_dir = sys.argv[4]
pipeline_s = sys.argv[5]
pipeline_f = sys.argv[6]
flags_s = sys.argv[7]
flags_f = sys.argv[8]
token_s = sys.argv[9]
token_f = sys.argv[10]
decisions_s = sys.argv[11]
decisions_f = sys.argv[12]

from datetime import datetime, timezone
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

# Count total findings
all_findings = json.loads(pipeline_f) + json.loads(flags_f) + json.loads(token_f) + json.loads(decisions_f)

report = {
    'report_id': report_id,
    'timestamp': now,
    'scanners': {
        'pipeline': { 'status': pipeline_s, 'findings': json.loads(pipeline_f) },
        'flags': { 'status': flags_s, 'findings': json.loads(flags_f) },
        'token': { 'status': token_s, 'findings': json.loads(token_f) },
        'decisions': { 'status': decisions_s, 'findings': json.loads(decisions_f) }
    },
    'overall_status': overall,
    'total_findings': len(all_findings),
    'cards_created': []
}

with open(report_file, 'w') as f:
    json.dump(report, f, indent=2)
    f.write('\n')

# Retention: keep max 50 reports
reports = sorted(glob.glob(os.path.join(report_dir, 'bravo-report-*.json')))
while len(reports) > 50:
    os.remove(reports.pop(0))

print(report_file)
" "$report_id" "$overall" "$report_file" "$report_dir" \
  "$_BRAVO_PIPELINE_STATUS" "$_BRAVO_PIPELINE_FINDINGS" \
  "$_BRAVO_FLAGS_STATUS" "$_BRAVO_FLAGS_FINDINGS" \
  "$_BRAVO_TOKEN_STATUS" "$_BRAVO_TOKEN_FINDINGS" \
  "$_BRAVO_DECISIONS_STATUS" "$_BRAVO_DECISIONS_FINDINGS"
}

# ---------------------------------------------------------------------------
# Card creator (T08)
# ---------------------------------------------------------------------------
_bravo_create_cards() {
  local root
  root="$(_bravo_project_root)"
  local cards_dir="$root/logs/warroom/cards"

  python3 -c "
import json, sys, glob, os
from datetime import datetime, timezone

cards_dir = sys.argv[1]
pipeline_f = json.loads(sys.argv[2])
flags_f = json.loads(sys.argv[3])
token_f = json.loads(sys.argv[4])
decisions_f = json.loads(sys.argv[5])

now = datetime.now(timezone.utc)

# Collect all findings with severity warning or critical
all_findings = pipeline_f + flags_f + token_f + decisions_f
actionable = [f for f in all_findings if f.get('severity') in ('warning', 'critical')]

if not actionable:
    sys.exit(0)

# Group findings by type
by_type = {}
for f in actionable:
    t = f.get('type', 'unknown')
    by_type.setdefault(t, []).append(f)

# Check for existing non-resolved cards with same title prefix (dedup)
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
    # Build card title
    title = f'[Bravo] {finding_type.replace(\"_\", \" \").title()}'

    # Dedup: skip if card with same title exists in incoming/triaging
    if title in existing_titles:
        continue

    # Determine priority from worst severity
    worst_sev = 'warning'
    for f in findings:
        if f.get('severity') == 'critical':
            worst_sev = 'critical'
            break
    priority = 'high' if worst_sev == 'critical' else 'medium'

    # Build body
    lines = [f'Bravo intelligence scanner detected {len(findings)} finding(s):', '']
    for f in findings:
        feature = f.get('feature', '')
        detail = f.get('detail', '')
        line = f'- **{f.get(\"severity\", \"?\").upper()}**'
        if feature:
            line += f' [{feature}]'
        line += f': {detail}'
        lines.append(line)

    body = chr(10).join(lines)

    # Create card JSON
    date_str = now.strftime('%Y%m%d')
    # Find next card number for today
    existing_today = [os.path.basename(cf) for cf in glob.glob(os.path.join(cards_dir, f'WR-{date_str}-*.json'))]
    next_num = len(existing_today) + 1
    card_id = f'WR-{date_str}-{next_num:03d}'

    # Avoid collision
    while os.path.exists(os.path.join(cards_dir, f'{card_id}.json')):
        next_num += 1
        card_id = f'WR-{date_str}-{next_num:03d}'

    tags = ['bravo', 'intelligence', finding_type]

    card = {
        'card_id': card_id,
        'title': title,
        'body': body,
        'source': 'agent',
        'created_at': now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'updated_at': None,
        'status': 'incoming',
        'priority_suggestion': priority,
        'overlord_assessment': None,
        'promoted_to': None,
        'tags': tags,
        'source_agent': 'blackhawk-bravo',
        'source_feature': None
    }

    os.makedirs(cards_dir, exist_ok=True)
    card_file = os.path.join(cards_dir, f'{card_id}.json')
    with open(card_file, 'w') as fh:
        json.dump(card, fh, indent=2)
        fh.write('\n')

    created.append(card_id)

if created:
    print(f'[bravo] Created {len(created)} War Room card(s): {\" \".join(created)}')
else:
    print('[bravo] No new cards created (all findings already have existing cards)')
" "$cards_dir" \
  "$_BRAVO_PIPELINE_FINDINGS" \
  "$_BRAVO_FLAGS_FINDINGS" \
  "$_BRAVO_TOKEN_FINDINGS" \
  "$_BRAVO_DECISIONS_FINDINGS"
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
bravo_scan_all() {
  local dry_run=0
  [[ "${1:-}" == "--dry-run" || "${1:-}" == "1" ]] && dry_run=1

  # Run all scanners
  _bravo_scan_pipelines
  _bravo_scan_flags
  _bravo_scan_token
  _bravo_scan_decisions

  # Determine overall status
  local overall
  overall="$(_bravo_worst_status "$_BRAVO_PIPELINE_STATUS" "$_BRAVO_FLAGS_STATUS" "$_BRAVO_TOKEN_STATUS" "$_BRAVO_DECISIONS_STATUS")"

  # Write report
  local report_file
  report_file="$(_bravo_write_report "$overall")"

  # Create cards (unless dry-run)
  if [[ $dry_run -eq 0 ]]; then
    _bravo_create_cards
  fi

  # Summary line
  local mode="Scan"
  [[ $dry_run -eq 1 ]] && mode="DRY RUN"
  echo "[bravo] ${mode} complete: pipeline=${_BRAVO_PIPELINE_STATUS} flags=${_BRAVO_FLAGS_STATUS} token=${_BRAVO_TOKEN_STATUS} decisions=${_BRAVO_DECISIONS_STATUS} overall=${overall}"
  if [[ -n "${report_file:-}" ]]; then
    echo "[bravo] Report: ${report_file}"
  fi
}
