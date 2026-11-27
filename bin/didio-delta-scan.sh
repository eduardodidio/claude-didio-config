#!/usr/bin/env bash
# didio-delta-scan.sh -- Black Hawk Delta security scanner CLI.
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"

_resolve_lib() {
  local name="$1"
  if [[ -f "$PWD/$name" ]]; then echo "$PWD/$name"
  elif [[ -f "$DIDIO_HOME/$name" ]]; then echo "$DIDIO_HOME/$name"
  else echo ""; fi
}

CONFIG_LIB="$(_resolve_lib bin/didio-config-lib.sh)"
SEC_LIB="$(_resolve_lib lib/delta-security.sh)"

if [[ -z "$CONFIG_LIB" ]]; then echo "[delta] config library not found" >&2; exit 2; fi
if [[ -z "$SEC_LIB" ]]; then echo "[delta] security library not found" >&2; exit 2; fi

# shellcheck disable=SC1090
source "$CONFIG_LIB"
# shellcheck disable=SC1090
source "$SEC_LIB"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
USAGE:
  didio delta scan [OPTIONS]

OPTIONS:
  --once         Scan once and exit (default)
  --continuous   Loop every N minutes
  --dry-run      Scan and report but do NOT create War Room cards

SCANNERS:
  1. Secrets         .env, *.pem, *.key, tokens, API keys in source
  2. Shell patterns  eval, rm -rf, curl|bash, chmod 777, --no-verify
  3. Guardrails      CLAUDE.md completeness (required guardrail sections)
  4. Permissions     .claude/settings.json auto mode, broad allow patterns
EOF
  exit 0
fi

PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$PWD}"
CONFIG_FILE="$PROJECT_ROOT/didio.config.json"

if [[ ! -f "$CONFIG_FILE" ]]; then echo "[delta] didio.config.json not found" >&2; exit 2; fi

delta_enabled="$(python3 -c "
import json, sys
try:
    with open(sys.argv[1], 'r') as f: d = json.load(f)
    print(str(d.get('meta_agents',{}).get('blackhawk_delta',{}).get('enabled',False)).lower())
except: print('false')
" "$CONFIG_FILE" 2>/dev/null || echo "false")"

if [[ "$delta_enabled" != "true" ]]; then echo "[delta] Delta is disabled" >&2; exit 2; fi
if ! command -v python3 &>/dev/null; then echo "[delta] python3 not found" >&2; exit 2; fi

DRY_RUN=0; CONTINUOUS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;; --continuous) CONTINUOUS=1 ;; --once) CONTINUOUS=0 ;;
  esac
done

INTERVAL="$(python3 -c "
import json, sys
try:
    with open(sys.argv[1], 'r') as f: d = json.load(f)
    print(d.get('meta_agents',{}).get('blackhawk_delta',{}).get('scan_interval_minutes',30))
except: print(30)
" "$CONFIG_FILE" 2>/dev/null || echo "30")"

_run_once() {
  if [[ $DRY_RUN -eq 1 ]]; then delta_scan_all --dry-run
  else delta_scan_all; fi
}

if [[ $CONTINUOUS -eq 1 ]]; then
  echo "[delta] Starting continuous scanning (interval: ${INTERVAL}m)"
  while true; do _run_once; sleep "$((INTERVAL * 60))"; done
else _run_once; fi
