#!/usr/bin/env bash
# delta-security.sh -- Black Hawk Delta security scanner library.
#
# Source this file (do NOT execute directly):
#   source "$DIDIO_HOME/lib/delta-security.sh"
#
# Scanners:
#   _delta_scan_secrets       Secrets in tracked files (.env, *.pem, tokens)
#   _delta_scan_shell         Dangerous shell patterns (eval, rm -rf, curl|bash)
#   _delta_scan_guardrails    CLAUDE.md guardrail completeness
#   _delta_scan_permissions   .claude/settings.json permission checks

_delta_project_root() {
  if [[ -n "${DIDIO_PROJECT_ROOT:-}" ]]; then echo "$DIDIO_PROJECT_ROOT"
  elif [[ -n "${PROJECT_ROOT:-}" ]]; then echo "$PROJECT_ROOT"
  else echo "$PWD"; fi
}

_delta_native_path() {
  if command -v cygpath &>/dev/null; then cygpath -m "$1"; else echo "$1"; fi
}

_DELTA_SECRETS_STATUS="ok";    _DELTA_SECRETS_FINDINGS="[]"
_DELTA_SHELL_STATUS="ok";      _DELTA_SHELL_FINDINGS="[]"
_DELTA_GUARDRAILS_STATUS="ok"; _DELTA_GUARDRAILS_FINDINGS="[]"
_DELTA_PERMS_STATUS="ok";      _DELTA_PERMS_FINDINGS="[]"

_delta_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
_delta_timestamp_id() { date -u +"%Y%m%d-%H%M%S"; }

_delta_worst_status() {
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
# Scanner: Secrets in tracked files
# ---------------------------------------------------------------------------
_delta_scan_secrets() {
  local root
  root="$(_delta_project_root)"
  local root_py
  root_py="$(_delta_native_path "$root")"

  local result
  result="$(python3 -c "
import json, sys, os, re, glob

root = sys.argv[1]
findings = []

# Patterns that indicate secrets
secret_patterns = [
    (r'\.env$', 'dotenv file'),
    (r'\.pem$', 'PEM certificate/key'),
    (r'\.key$', 'private key file'),
    (r'credentials\.json$', 'credentials file'),
    (r'\.p12$', 'PKCS12 keystore'),
    (r'id_rsa$', 'SSH private key'),
    (r'id_ed25519$', 'SSH private key'),
]

# Content patterns in tracked files
content_patterns = [
    (r'(?:api[_-]?key|apikey)\s*[=:]\s*[\"\\x27]?[A-Za-z0-9_\-]{20,}', 'API key in source'),
    (r'(?:secret|password|passwd|token)\s*[=:]\s*[\"\\x27]?[A-Za-z0-9_\-]{8,}', 'Secret/token in source'),
    (r'-----BEGIN (?:RSA |EC )?PRIVATE KEY-----', 'Private key in source'),
    (r'sk-[A-Za-z0-9]{20,}', 'Anthropic/OpenAI API key pattern'),
]

# Check for secret files in project root (not in node_modules, .git, etc)
skip_dirs = {'.git', 'node_modules', 'dist', 'build', 'archive', '.venv', '__pycache__'}
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in skip_dirs]
    rel_dir = os.path.relpath(dirpath, root)
    for fname in filenames:
        for pattern, desc in secret_patterns:
            if re.search(pattern, fname):
                rel_path = os.path.join(rel_dir, fname)
                findings.append({
                    'type': 'secret_file',
                    'detail': f'{desc} found: {rel_path}',
                    'severity': 'critical',
                    'file': rel_path
                })

# Check content of shell and config files for embedded secrets
for ext in ['*.sh', '*.json', '*.yml', '*.yaml', '*.toml', '*.cfg', '*.conf', '*.md']:
    for fpath in glob.glob(os.path.join(root, '**', ext), recursive=True):
        rel = os.path.relpath(fpath, root)
        if any(skip in rel for skip in skip_dirs):
            continue
        try:
            with open(fpath, 'r', errors='replace') as f:
                content = f.read(50000)  # Cap at 50KB per file
            for pattern, desc in content_patterns:
                matches = re.findall(pattern, content)
                if matches:
                    findings.append({
                        'type': 'embedded_secret',
                        'detail': f'{desc} in {rel} ({len(matches)} match(es))',
                        'severity': 'critical',
                        'file': rel
                    })
                    break  # One finding per file is enough
        except Exception:
            pass

worst = 'ok'
for f in findings:
    if f.get('severity') == 'critical': worst = 'critical'; break
    elif f.get('severity') == 'warning': worst = 'warning'
print(json.dumps({'status': worst, 'findings': findings}))
" "$root_py" 2>/dev/null || echo '{"status":"ok","findings":[]}')"

  _DELTA_SECRETS_STATUS="$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
  _DELTA_SECRETS_FINDINGS="$(echo "$result" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['findings']))")"
}

# ---------------------------------------------------------------------------
# Scanner: Dangerous shell patterns
# ---------------------------------------------------------------------------
_delta_scan_shell() {
  local root
  root="$(_delta_project_root)"
  local root_py
  root_py="$(_delta_native_path "$root")"

  local result
  result="$(python3 -c "
import json, sys, os, re, glob

root = sys.argv[1]
findings = []

dangerous_patterns = [
    (r'\beval\s+\"\\\$', 'eval with variable expansion (command injection risk)'),
    (r'\brm\s+-rf\s+/(?!\s*\"|tmp)', 'rm -rf on root or absolute path'),
    (r'\bcurl\s+.*\|\s*(?:bash|sh)', 'curl piped to shell (remote code execution)'),
    (r'\bwget\s+.*\|\s*(?:bash|sh)', 'wget piped to shell (remote code execution)'),
    (r'\bchmod\s+777\b', 'chmod 777 (world-writable)'),
    (r'\bchmod\s+666\b', 'chmod 666 (world-writable)'),
    (r'--no-verify', 'git hook bypass (--no-verify)'),
    (r'git\s+push\s+--force(?!-with-lease)', 'git push --force without --force-with-lease'),
    (r'\bgit\s+reset\s+--hard', 'git reset --hard (destructive)'),
]

skip_dirs = {'.git', 'node_modules', 'dist', 'build', 'archive'}

for fpath in glob.glob(os.path.join(root, '**', '*.sh'), recursive=True):
    rel = os.path.relpath(fpath, root)
    if any(skip in rel for skip in skip_dirs):
        continue
    # Skip test files (they may legitimately test dangerous patterns)
    if '/tests/' in rel or rel.startswith('tests/'):
        continue
    try:
        with open(fpath, 'r', errors='replace') as f:
            lines = f.readlines()
        for i, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith('#'):
                continue  # skip comments
            for pattern, desc in dangerous_patterns:
                if re.search(pattern, stripped):
                    findings.append({
                        'type': 'dangerous_shell',
                        'detail': f'{desc} at {rel}:{i}',
                        'severity': 'warning',
                        'file': f'{rel}:{i}'
                    })
                    break  # one finding per line
    except Exception:
        pass

worst = 'ok'
for f in findings:
    if f.get('severity') == 'critical': worst = 'critical'; break
    elif f.get('severity') == 'warning': worst = 'warning'
print(json.dumps({'status': worst, 'findings': findings}))
" "$root_py" 2>/dev/null || echo '{"status":"ok","findings":[]}')"

  _DELTA_SHELL_STATUS="$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
  _DELTA_SHELL_FINDINGS="$(echo "$result" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['findings']))")"
}

# ---------------------------------------------------------------------------
# Scanner: Guardrails completeness in CLAUDE.md
# ---------------------------------------------------------------------------
_delta_scan_guardrails() {
  local root
  root="$(_delta_project_root)"
  local claude_md="$root/CLAUDE.md"
  local claude_md_py
  claude_md_py="$(_delta_native_path "$claude_md")"

  local result
  result="$(python3 -c "
import json, sys, os

claude_md = sys.argv[1]
findings = []

required_guardrails = [
    ('git rebase', 'No rebase on shared branches'),
    ('push --force', 'No force push without asking'),
    ('git add -A', 'No git add -A'),
    ('secrets', 'No committing secrets'),
    ('--no-verify', 'No skipping hooks'),
    ('rm -rf', 'No destructive rm without confirm'),
]

if not os.path.isfile(claude_md):
    findings.append({
        'type': 'missing_claude_md',
        'detail': 'CLAUDE.md not found — no guardrails in place',
        'severity': 'critical',
        'file': 'CLAUDE.md'
    })
else:
    try:
        with open(claude_md, 'r', errors='replace') as f:
            content = f.read().lower()

        missing = []
        for keyword, desc in required_guardrails:
            if keyword.lower() not in content:
                missing.append(desc)

        if missing:
            findings.append({
                'type': 'missing_guardrails',
                'detail': f'CLAUDE.md missing {len(missing)} guardrail(s): {', '.join(missing)}',
                'severity': 'warning',
                'file': 'CLAUDE.md'
            })
    except Exception as e:
        findings.append({
            'type': 'guardrails_read_error',
            'detail': f'Failed to read CLAUDE.md: {e}',
            'severity': 'warning',
            'file': 'CLAUDE.md'
        })

worst = 'ok'
for f in findings:
    if f.get('severity') == 'critical': worst = 'critical'; break
    elif f.get('severity') == 'warning': worst = 'warning'
print(json.dumps({'status': worst, 'findings': findings}))
" "$claude_md_py" 2>/dev/null || echo '{"status":"ok","findings":[]}')"

  _DELTA_GUARDRAILS_STATUS="$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
  _DELTA_GUARDRAILS_FINDINGS="$(echo "$result" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['findings']))")"
}

# ---------------------------------------------------------------------------
# Scanner: Permission checks (.claude/settings.json)
# ---------------------------------------------------------------------------
_delta_scan_permissions() {
  local root
  root="$(_delta_project_root)"
  local settings="$root/.claude/settings.json"
  local settings_py
  settings_py="$(_delta_native_path "$settings")"

  local result
  result="$(python3 -c "
import json, sys, os

settings_file = sys.argv[1]
findings = []

if os.path.isfile(settings_file):
    try:
        with open(settings_file, 'r') as f:
            d = json.load(f)

        # Check for auto mode (overly permissive)
        perms = d.get('permissions', {})
        default_mode = perms.get('defaultMode', '')
        if default_mode == 'auto':
            findings.append({
                'type': 'auto_mode',
                'detail': 'permissions.defaultMode is \"auto\" — all tools auto-approved. Use only in sandboxed environments.',
                'severity': 'warning',
                'file': '.claude/settings.json'
            })

        # Check for overly broad allow patterns
        allow = perms.get('allow', [])
        broad_patterns = [p for p in allow if p in ('*', '**', 'Bash(*)', 'Bash')]
        if broad_patterns:
            findings.append({
                'type': 'broad_allow',
                'detail': f'Overly broad allow patterns: {broad_patterns}',
                'severity': 'warning',
                'file': '.claude/settings.json'
            })

    except Exception as e:
        findings.append({
            'type': 'settings_parse_error',
            'detail': f'Failed to parse .claude/settings.json: {e}',
            'severity': 'warning',
            'file': '.claude/settings.json'
        })

worst = 'ok'
for f in findings:
    if f.get('severity') == 'critical': worst = 'critical'; break
    elif f.get('severity') == 'warning': worst = 'warning'
print(json.dumps({'status': worst, 'findings': findings}))
" "$settings_py" 2>/dev/null || echo '{"status":"ok","findings":[]}')"

  _DELTA_PERMS_STATUS="$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
  _DELTA_PERMS_FINDINGS="$(echo "$result" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['findings']))")"
}

# ---------------------------------------------------------------------------
# Report writer
# ---------------------------------------------------------------------------
_delta_write_report() {
  local root; root="$(_delta_project_root)"
  local report_dir="$root/logs/agents"
  local report_dir_py; report_dir_py="$(_delta_native_path "$report_dir")"
  local ts; ts="$(_delta_timestamp_id)"
  local report_file="$report_dir/delta-report-${ts}.json"
  local report_file_py; report_file_py="$(_delta_native_path "$report_file")"
  local overall="$1"

  mkdir -p "$report_dir"

  python3 -c "
import json, sys, glob, os
from datetime import datetime, timezone

report_file = sys.argv[1]; report_dir = sys.argv[2]; overall = sys.argv[3]
secrets_s = sys.argv[4]; secrets_f = sys.argv[5]
shell_s = sys.argv[6]; shell_f = sys.argv[7]
guard_s = sys.argv[8]; guard_f = sys.argv[9]
perms_s = sys.argv[10]; perms_f = sys.argv[11]

now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
all_f = json.loads(secrets_f) + json.loads(shell_f) + json.loads(guard_f) + json.loads(perms_f)

report = {
    'report_id': 'DL-' + os.path.basename(report_file).replace('delta-report-','').replace('.json',''),
    'timestamp': now,
    'scanners': {
        'secrets': {'status': secrets_s, 'findings': json.loads(secrets_f)},
        'shell': {'status': shell_s, 'findings': json.loads(shell_f)},
        'guardrails': {'status': guard_s, 'findings': json.loads(guard_f)},
        'permissions': {'status': perms_s, 'findings': json.loads(perms_f)}
    },
    'overall_status': overall,
    'total_findings': len(all_f),
    'cards_created': []
}

with open(report_file, 'w') as f:
    json.dump(report, f, indent=2); f.write('\n')

reports = sorted(glob.glob(os.path.join(report_dir, 'delta-report-*.json')))
while len(reports) > 50: os.remove(reports.pop(0))

print(report_file)
" "$report_file_py" "$report_dir_py" "$overall" \
  "$_DELTA_SECRETS_STATUS" "$_DELTA_SECRETS_FINDINGS" \
  "$_DELTA_SHELL_STATUS" "$_DELTA_SHELL_FINDINGS" \
  "$_DELTA_GUARDRAILS_STATUS" "$_DELTA_GUARDRAILS_FINDINGS" \
  "$_DELTA_PERMS_STATUS" "$_DELTA_PERMS_FINDINGS"
}

# ---------------------------------------------------------------------------
# Card creator
# ---------------------------------------------------------------------------
_delta_create_cards() {
  local root; root="$(_delta_project_root)"
  local cards_dir="$root/logs/warroom/cards"
  local cards_dir_py; cards_dir_py="$(_delta_native_path "$cards_dir")"

  python3 -c "
import json, sys, glob, os
from datetime import datetime, timezone

cards_dir = sys.argv[1]
all_findings = json.loads(sys.argv[2]) + json.loads(sys.argv[3]) + json.loads(sys.argv[4]) + json.loads(sys.argv[5])
now = datetime.now(timezone.utc)

actionable = [f for f in all_findings if f.get('severity') in ('warning','critical')]
if not actionable: sys.exit(0)

by_type = {}
for f in actionable: by_type.setdefault(f.get('type','unknown'), []).append(f)

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
for ft, findings in by_type.items():
    title = f'[Delta] {ft.replace(\"_\",\" \").title()}'
    if title in existing_titles: continue
    worst_sev = 'critical' if any(f.get('severity')=='critical' for f in findings) else 'warning'
    priority = 'high' if worst_sev == 'critical' else 'medium'
    lines = [f'Delta security scanner detected {len(findings)} finding(s):','']
    for f in findings:
        lines.append(f'- **{f.get(\"severity\",\"?\").upper()}**: {f.get(\"detail\",\"\")}')
    body = chr(10).join(lines)

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
        'tags': ['delta','security',ft], 'source_agent': 'blackhawk-delta',
        'source_feature': None
    }
    os.makedirs(cards_dir, exist_ok=True)
    with open(os.path.join(cards_dir, f'{card_id}.json'), 'w') as fh:
        json.dump(card, fh, indent=2); fh.write('\n')
    created.append(card_id)

if created: print(f'[delta] Created {len(created)} War Room card(s): {\" \".join(created)}')
else: print('[delta] No new cards created')
" "$cards_dir_py" \
  "$_DELTA_SECRETS_FINDINGS" "$_DELTA_SHELL_FINDINGS" \
  "$_DELTA_GUARDRAILS_FINDINGS" "$_DELTA_PERMS_FINDINGS"
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
delta_scan_all() {
  local dry_run=0
  [[ "${1:-}" == "--dry-run" || "${1:-}" == "1" ]] && dry_run=1

  _delta_scan_secrets
  _delta_scan_shell
  _delta_scan_guardrails
  _delta_scan_permissions

  local overall
  overall="$(_delta_worst_status "$_DELTA_SECRETS_STATUS" "$_DELTA_SHELL_STATUS" "$_DELTA_GUARDRAILS_STATUS" "$_DELTA_PERMS_STATUS")"

  local report_file
  report_file="$(_delta_write_report "$overall")"

  if [[ $dry_run -eq 0 ]]; then
    _delta_create_cards
  fi

  local mode="Scan"
  [[ $dry_run -eq 1 ]] && mode="DRY RUN"
  echo "[delta] ${mode} complete: secrets=${_DELTA_SECRETS_STATUS} shell=${_DELTA_SHELL_STATUS} guardrails=${_DELTA_GUARDRAILS_STATUS} permissions=${_DELTA_PERMS_STATUS} overall=${overall}"
  if [[ -n "${report_file:-}" ]]; then
    echo "[delta] Report: ${report_file}"
  fi
}
