#!/usr/bin/env bash
# didio-charlie-monitor.sh -- Black Hawk Charlie framework health scanner CLI.
#
# Usage:
#   didio charlie monitor              Scan once and exit (default)
#   didio charlie monitor --once       Same as above (explicit)
#   didio charlie monitor --continuous Loop every N minutes
#   didio charlie monitor --dry-run    Scan but do NOT create War Room cards
#
# Exit codes:
#   0 = success
#   1 = runtime error
#   2 = config / preflight issue

set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"

_resolve_lib() {
  local name="$1"
  if [[ -f "$PWD/$name" ]]; then echo "$PWD/$name"
  elif [[ -f "$DIDIO_HOME/$name" ]]; then echo "$DIDIO_HOME/$name"
  else echo ""; fi
}

CONFIG_LIB="$(_resolve_lib bin/didio-config-lib.sh)"
MONITOR_LIB="$(_resolve_lib lib/charlie-monitoring.sh)"

if [[ -z "$CONFIG_LIB" ]]; then
  echo "[charlie] config library not found" >&2; exit 2
fi
if [[ -z "$MONITOR_LIB" ]]; then
  echo "[charlie] monitoring library not found" >&2; exit 2
fi

# shellcheck disable=SC1090
source "$CONFIG_LIB"
# shellcheck disable=SC1090
source "$MONITOR_LIB"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
USAGE:
  didio charlie monitor [OPTIONS]

OPTIONS:
  --once         Scan once and exit (default)
  --continuous   Loop every N minutes
  --dry-run      Scan and report but do NOT create War Room cards

SCANNERS:
  1. Agent stats       Spawn success rate, avg duration, role error spikes
  2. Feature velocity  Features shipped per 30-day window
  3. Learnings growth  Total entries, roles with learnings
  4. Watcher liveness  state.json freshness (is the watcher running?)

CONFIGURATION (didio.config.json):
  meta_agents.blackhawk_charlie.enabled
  meta_agents.blackhawk_charlie.monitoring_interval_minutes (default: 20)
EOF
  exit 0
fi

PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$PWD}"
CONFIG_FILE="$PROJECT_ROOT/didio.config.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[charlie] didio.config.json not found" >&2; exit 2
fi

charlie_enabled="$(python3 -c "
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        d = json.load(f)
    print(str(d.get('meta_agents', {}).get('blackhawk_charlie', {}).get('enabled', False)).lower())
except Exception:
    print('false')
" "$CONFIG_FILE" 2>/dev/null || echo "false")"

if [[ "$charlie_enabled" != "true" ]]; then
  echo "[charlie] Charlie is disabled in config" >&2; exit 2
fi

if ! command -v python3 &>/dev/null; then
  echo "[charlie] python3 not found" >&2; exit 2
fi

DRY_RUN=0
CONTINUOUS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=1 ;;
    --continuous) CONTINUOUS=1 ;;
    --once)       CONTINUOUS=0 ;;
  esac
done

INTERVAL_MINUTES="$(python3 -c "
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        d = json.load(f)
    print(d.get('meta_agents', {}).get('blackhawk_charlie', {}).get('monitoring_interval_minutes', 20))
except Exception:
    print(20)
" "$CONFIG_FILE" 2>/dev/null || echo "20")"

_run_once() {
  if [[ $DRY_RUN -eq 1 ]]; then
    charlie_scan_all --dry-run
  else
    charlie_scan_all
  fi
}

if [[ $CONTINUOUS -eq 1 ]]; then
  echo "[charlie] Starting continuous monitoring (interval: ${INTERVAL_MINUTES}m)"
  while true; do _run_once; sleep "$((INTERVAL_MINUTES * 60))"; done
else
  _run_once
fi
