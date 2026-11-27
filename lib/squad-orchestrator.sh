#!/usr/bin/env bash
# squad-orchestrator.sh -- Coordinated Bravo+Charlie+Delta scanning.
#
# Source this file (do NOT execute directly):
#   source "$DIDIO_HOME/lib/squad-orchestrator.sh"
#
# Functions:
#   squad_scan_all [--dry-run]   Run all enabled squad scanners, correlate, report

_squad_project_root() {
  if [[ -n "${DIDIO_PROJECT_ROOT:-}" ]]; then echo "$DIDIO_PROJECT_ROOT"
  elif [[ -n "${PROJECT_ROOT:-}" ]]; then echo "$PROJECT_ROOT"
  else echo "$PWD"; fi
}

_squad_native_path() {
  if command -v cygpath &>/dev/null; then cygpath -m "$1"; else echo "$1"; fi
}

_squad_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
_squad_timestamp_id() { date -u +"%Y%m%d-%H%M%S"; }

_squad_worst_status() {
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
# Cross-scanner correlation
# ---------------------------------------------------------------------------
_squad_correlate() {
  # Reads all scanner findings and detects compound risk patterns
  local root; root="$(_squad_project_root)"
  local root_py; root_py="$(_squad_native_path "$root")"

  # Combine all findings per squad member
  local all_bravo="[]" all_charlie="[]" all_delta="[]"
  if type _bravo_scan_pipelines &>/dev/null 2>&1; then
    all_bravo="$(python3 -c "
import json,sys
a = json.loads(sys.argv[1]) + json.loads(sys.argv[2]) + json.loads(sys.argv[3]) + json.loads(sys.argv[4])
print(json.dumps(a))
" "${_BRAVO_PIPELINE_FINDINGS:-[]}" "${_BRAVO_FLAGS_FINDINGS:-[]}" "${_BRAVO_TOKEN_FINDINGS:-[]}" "${_BRAVO_DECISIONS_FINDINGS:-[]}" 2>/dev/null || echo "[]")"
  fi
  if type _charlie_scan_agents &>/dev/null 2>&1; then
    all_charlie="$(python3 -c "
import json,sys
a = json.loads(sys.argv[1]) + json.loads(sys.argv[2]) + json.loads(sys.argv[3]) + json.loads(sys.argv[4])
print(json.dumps(a))
" "${_CHARLIE_AGENTS_FINDINGS:-[]}" "${_CHARLIE_VELOCITY_FINDINGS:-[]}" "${_CHARLIE_LEARNINGS_FINDINGS:-[]}" "${_CHARLIE_WATCHER_FINDINGS:-[]}" 2>/dev/null || echo "[]")"
  fi
  if type _delta_scan_secrets &>/dev/null 2>&1; then
    all_delta="$(python3 -c "
import json,sys
a = json.loads(sys.argv[1]) + json.loads(sys.argv[2]) + json.loads(sys.argv[3]) + json.loads(sys.argv[4])
print(json.dumps(a))
" "${_DELTA_SECRETS_FINDINGS:-[]}" "${_DELTA_SHELL_FINDINGS:-[]}" "${_DELTA_GUARDRAILS_FINDINGS:-[]}" "${_DELTA_PERMS_FINDINGS:-[]}" 2>/dev/null || echo "[]")"
  fi

  python3 -c "
import json, sys

bravo_f = json.loads(sys.argv[1])
charlie_f = json.loads(sys.argv[2])
delta_f = json.loads(sys.argv[3])

correlations = []

# Extract finding types for fast lookup
bravo_types = {f.get('type','') for f in bravo_f}
charlie_types = {f.get('type','') for f in charlie_f}
delta_types = {f.get('type','') for f in delta_f}

# Pattern 1: Failed pipeline + dangerous shell = code quality risk
if ('failed_pipeline' in bravo_types or 'stuck_pipeline' in bravo_types) and 'dangerous_shell' in delta_types:
    correlations.append({
        'type': 'pipeline_security_compound',
        'detail': 'Failed/stuck pipeline combined with dangerous shell patterns — elevated code quality risk',
        'severity': 'critical',
        'scanners': ['bravo', 'delta']
    })

# Pattern 2: Low spawn success + stale state = framework degradation
if 'low_spawn_success' in charlie_types and ('stale_state' in charlie_types or 'missing_state' in charlie_types):
    correlations.append({
        'type': 'framework_degradation',
        'detail': 'Low agent success rate combined with stale/missing watcher — framework may be degraded',
        'severity': 'critical',
        'scanners': ['charlie']
    })

# Pattern 3: Secrets found + auto permissions = high exposure
if ('secret_file' in delta_types or 'embedded_secret' in delta_types) and 'auto_mode' in delta_types:
    correlations.append({
        'type': 'secret_exposure',
        'detail': 'Secrets in codebase combined with auto-approve permissions — high exposure risk',
        'severity': 'critical',
        'scanners': ['delta']
    })

# Pattern 4: Token critical + multiple scanners warning = operational stress
if 'token_critical' in bravo_types and (charlie_types or delta_types):
    correlations.append({
        'type': 'operational_stress',
        'detail': 'Token budget critical while other scanners report issues — system under stress',
        'severity': 'critical',
        'scanners': ['bravo', 'charlie', 'delta']
    })

# Pattern 5: Missing guardrails + dangerous shell = unprotected
if 'missing_claude_md' in delta_types or 'missing_guardrails' in delta_types:
    if 'dangerous_shell' in delta_types:
        correlations.append({
            'type': 'unprotected_operations',
            'detail': 'Missing guardrails combined with dangerous shell patterns — no safety net',
            'severity': 'critical',
            'scanners': ['delta']
        })

print(json.dumps(correlations))
" "$all_bravo" "$all_charlie" "$all_delta"
}

# ---------------------------------------------------------------------------
# Report writer
# ---------------------------------------------------------------------------
_squad_write_report() {
  local root; root="$(_squad_project_root)"
  local report_dir="$root/logs/agents"
  local report_dir_py; report_dir_py="$(_squad_native_path "$report_dir")"
  local ts; ts="$(_squad_timestamp_id)"
  local report_file="$report_dir/squad-report-${ts}.json"
  local report_file_py; report_file_py="$(_squad_native_path "$report_file")"

  local overall="$1"
  local correlations="$2"
  local bravo_status="$3"
  local charlie_status="$4"
  local delta_status="$5"

  mkdir -p "$report_dir"

  python3 -c "
import json, sys, glob, os
from datetime import datetime, timezone

report_file = sys.argv[1]; report_dir = sys.argv[2]
overall = sys.argv[3]; correlations = json.loads(sys.argv[4])
bravo_s = sys.argv[5]; charlie_s = sys.argv[6]; delta_s = sys.argv[7]

now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

report = {
    'report_id': 'SQ-' + os.path.basename(report_file).replace('squad-report-','').replace('.json',''),
    'timestamp': now,
    'squad_status': {
        'bravo': bravo_s,
        'charlie': charlie_s,
        'delta': delta_s
    },
    'correlations': correlations,
    'overall_status': overall,
    'cards_created': []
}

with open(report_file, 'w') as f:
    json.dump(report, f, indent=2); f.write('\n')

reports = sorted(glob.glob(os.path.join(report_dir, 'squad-report-*.json')))
while len(reports) > 50: os.remove(reports.pop(0))

print(report_file)
" "$report_file_py" "$report_dir_py" "$overall" "$correlations" \
  "$bravo_status" "$charlie_status" "$delta_status"
}

# ---------------------------------------------------------------------------
# Card creator for correlations
# ---------------------------------------------------------------------------
_squad_create_cards() {
  local root; root="$(_squad_project_root)"
  local cards_dir="$root/logs/warroom/cards"
  local cards_dir_py; cards_dir_py="$(_squad_native_path "$cards_dir")"
  local correlations="$1"

  python3 -c "
import json, sys, glob, os
from datetime import datetime, timezone

cards_dir = sys.argv[1]
correlations = json.loads(sys.argv[2])
now = datetime.now(timezone.utc)

actionable = [c for c in correlations if c.get('severity') in ('warning','critical')]
if not actionable: sys.exit(0)

existing_titles = set()
if os.path.isdir(cards_dir):
    for cf in glob.glob(os.path.join(cards_dir, '*.json')):
        try:
            with open(cf, 'r') as fh:
                card = json.load(fh)
            if card.get('status') in ('incoming','triaging'):
                existing_titles.add(card.get('title',''))
        except Exception: pass

created = []
for c in actionable:
    title = f'[Squad] {c[\"type\"].replace(\"_\",\" \").title()}'
    if title in existing_titles: continue

    priority = 'high' if c.get('severity') == 'critical' else 'medium'
    body = f'Squad correlation detected:\\n\\n- **{c.get(\"severity\",\"?\").upper()}**: {c.get(\"detail\",\"\")}\\n- Scanners involved: {', '.join(c.get(\"scanners\",[]))}'

    date_str = now.strftime('%Y%m%d')
    existing_today = [os.path.basename(cf) for cf in glob.glob(os.path.join(cards_dir, f'WR-{date_str}-*.json'))]
    next_num = len(existing_today) + 1
    card_id = f'WR-{date_str}-{next_num:03d}'
    while os.path.exists(os.path.join(cards_dir, f'{card_id}.json')):
        next_num += 1; card_id = f'WR-{date_str}-{next_num:03d}'

    card = {
        'card_id': card_id, 'title': title, 'body': body,
        'source': 'agent', 'created_at': now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'updated_at': None, 'status': 'incoming', 'priority_suggestion': priority,
        'overlord_assessment': None, 'promoted_to': None,
        'tags': ['squad','correlation',c['type']], 'source_agent': 'blackhawk-squad',
        'source_feature': None
    }
    os.makedirs(cards_dir, exist_ok=True)
    with open(os.path.join(cards_dir, f'{card_id}.json'), 'w') as fh:
        json.dump(card, fh, indent=2); fh.write('\n')
    created.append(card_id)

if created: print(f'[squad] Created {len(created)} correlation card(s): {\" \".join(created)}')
else: print('[squad] No new correlation cards')
" "$cards_dir_py" "$correlations"
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
squad_scan_all() {
  local dry_run=0
  [[ "${1:-}" == "--dry-run" || "${1:-}" == "1" ]] && dry_run=1

  local root; root="$(_squad_project_root)"
  local config_file="$root/didio.config.json"

  # Check which scanners are enabled
  local bravo_enabled charlie_enabled delta_enabled
  bravo_enabled="$(python3 -c "
import json,sys
try:
    with open(sys.argv[1],'r') as f: d=json.load(f)
    print(str(d.get('meta_agents',{}).get('blackhawk_bravo',{}).get('enabled',False)).lower())
except: print('false')
" "$(_squad_native_path "$config_file")" 2>/dev/null || echo "false")"

  charlie_enabled="$(python3 -c "
import json,sys
try:
    with open(sys.argv[1],'r') as f: d=json.load(f)
    print(str(d.get('meta_agents',{}).get('blackhawk_charlie',{}).get('enabled',False)).lower())
except: print('false')
" "$(_squad_native_path "$config_file")" 2>/dev/null || echo "false")"

  delta_enabled="$(python3 -c "
import json,sys
try:
    with open(sys.argv[1],'r') as f: d=json.load(f)
    print(str(d.get('meta_agents',{}).get('blackhawk_delta',{}).get('enabled',False)).lower())
except: print('false')
" "$(_squad_native_path "$config_file")" 2>/dev/null || echo "false")"

  local bravo_status="disabled" charlie_status="disabled" delta_status="disabled"

  # Run enabled scanners
  if [[ "$bravo_enabled" == "true" ]] && type _bravo_scan_pipelines &>/dev/null; then
    _bravo_scan_pipelines
    _bravo_scan_flags
    _bravo_scan_token
    _bravo_scan_decisions
    bravo_status="$(_squad_worst_status "$_BRAVO_PIPELINE_STATUS" "$_BRAVO_FLAGS_STATUS" "$_BRAVO_TOKEN_STATUS" "$_BRAVO_DECISIONS_STATUS")"
    echo "[squad] Bravo: $bravo_status"
  else
    echo "[squad] Bravo: disabled/unavailable"
  fi

  if [[ "$charlie_enabled" == "true" ]] && type _charlie_scan_agents &>/dev/null; then
    _charlie_scan_agents
    _charlie_scan_velocity
    _charlie_scan_learnings
    _charlie_scan_watcher
    charlie_status="$(_squad_worst_status "$_CHARLIE_AGENTS_STATUS" "$_CHARLIE_VELOCITY_STATUS" "$_CHARLIE_LEARNINGS_STATUS" "$_CHARLIE_WATCHER_STATUS")"
    echo "[squad] Charlie: $charlie_status"
  else
    echo "[squad] Charlie: disabled/unavailable"
  fi

  if [[ "$delta_enabled" == "true" ]] && type _delta_scan_secrets &>/dev/null; then
    _delta_scan_secrets
    _delta_scan_shell
    _delta_scan_guardrails
    _delta_scan_permissions
    delta_status="$(_squad_worst_status "$_DELTA_SECRETS_STATUS" "$_DELTA_SHELL_STATUS" "$_DELTA_GUARDRAILS_STATUS" "$_DELTA_PERMS_STATUS")"
    echo "[squad] Delta: $delta_status"
  else
    echo "[squad] Delta: disabled/unavailable"
  fi

  # Correlate across scanners
  local correlations="[]"
  if [[ "$bravo_status" != "disabled" || "$charlie_status" != "disabled" || "$delta_status" != "disabled" ]]; then
    correlations="$(_squad_correlate)"
  fi

  local correlation_status="ok"
  if echo "$correlations" | python3 -c "import json,sys; c=json.load(sys.stdin); sys.exit(0 if any(x.get('severity')=='critical' for x in c) else 1)" 2>/dev/null; then
    correlation_status="critical"
  elif echo "$correlations" | python3 -c "import json,sys; c=json.load(sys.stdin); sys.exit(0 if len(c)>0 else 1)" 2>/dev/null; then
    correlation_status="warning"
  fi

  # Overall = worst of all statuses + correlations
  local overall
  overall="$(_squad_worst_status "$bravo_status" "$charlie_status" "$delta_status" "$correlation_status")"

  # Write report
  local report_file
  report_file="$(_squad_write_report "$overall" "$correlations" "$bravo_status" "$charlie_status" "$delta_status")"

  # Create correlation cards (unless dry-run)
  local correlation_count
  correlation_count="$(echo "$correlations" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")"

  if [[ $dry_run -eq 0 && "$correlation_count" -gt 0 ]]; then
    _squad_create_cards "$correlations"
  fi

  local mode="Scan"
  [[ $dry_run -eq 1 ]] && mode="DRY RUN"
  echo "[squad] ${mode} complete: bravo=${bravo_status} charlie=${charlie_status} delta=${delta_status} correlations=${correlation_count} overall=${overall}"
  if [[ -n "${report_file:-}" ]]; then
    echo "[squad] Report: ${report_file}"
  fi
}
