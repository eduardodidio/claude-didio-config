#!/usr/bin/env bash
# didio-bravo-monitor.sh -- Black Hawk Bravo intelligence scanner CLI.
#
# Usage:
#   didio bravo monitor              Scan once and exit (default)
#   didio bravo monitor --once       Same as above (explicit)
#   didio bravo monitor --continuous Loop every N minutes
#   didio bravo monitor --dry-run    Scan but do NOT create War Room cards
#
# Exit codes:
#   0 = success
#   1 = runtime error
#   2 = config / preflight issue

set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"

# -- Resolve libraries --
_resolve_lib() {
  local name="$1"
  if [[ -f "$PWD/$name" ]]; then
    echo "$PWD/$name"
  elif [[ -f "$DIDIO_HOME/$name" ]]; then
    echo "$DIDIO_HOME/$name"
  else
    echo ""
  fi
}

CONFIG_LIB="$(_resolve_lib bin/didio-config-lib.sh)"
INTEL_LIB="$(_resolve_lib lib/bravo-intelligence.sh)"

if [[ -z "$CONFIG_LIB" ]]; then
  echo "[bravo] config library not found" >&2
  exit 2
fi
if [[ -z "$INTEL_LIB" ]]; then
  echo "[bravo] intelligence library not found" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "$CONFIG_LIB"
# shellcheck disable=SC1090
source "$INTEL_LIB"

# -- Help --
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
USAGE:
  didio bravo monitor [OPTIONS]

OPTIONS:
  --once         Scan once and exit (default)
  --continuous   Loop every N minutes (from config: meta_agents.blackhawk_bravo.monitoring_interval_minutes)
  --dry-run      Scan and report but do NOT create War Room cards
  --help, -h     Show this help

EXIT CODES:
  0 = success
  1 = runtime error
  2 = config / preflight issue

SCANNERS:
  1. Pipeline health    Stuck, failed, paused, escalated pipelines
  2. Flag health        Stale flags, blocked features, flag storms
  3. Token budget       Critical/warning status, burn rate, stale data
  4. Decision drift     Repeated challenges, low confidence, escalation spikes

CONFIGURATION (didio.config.json):
  meta_agents.blackhawk_bravo.enabled                  Enable/disable Bravo
  meta_agents.blackhawk_bravo.monitoring_interval_minutes  Loop interval (default: 15)
EOF
  exit 0
fi

# -- Preflight --
PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$PWD}"
CONFIG_FILE="$PROJECT_ROOT/didio.config.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[bravo] didio.config.json not found at $CONFIG_FILE" >&2
  exit 2
fi

# Check if Bravo is enabled
bravo_enabled="$(python3 -c "
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        d = json.load(f)
    print(str(d.get('meta_agents', {}).get('blackhawk_bravo', {}).get('enabled', False)).lower())
except Exception:
    print('false')
" "$CONFIG_FILE" 2>/dev/null || echo "false")"

if [[ "$bravo_enabled" != "true" ]]; then
  echo "[bravo] Bravo is disabled in config (meta_agents.blackhawk_bravo.enabled)" >&2
  exit 2
fi

# Check python3
if ! command -v python3 &>/dev/null; then
  echo "[bravo] python3 not found in PATH" >&2
  exit 2
fi

# -- Parse flags --
DRY_RUN=0
CONTINUOUS=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=1 ;;
    --continuous) CONTINUOUS=1 ;;
    --once)       CONTINUOUS=0 ;;
  esac
done

# Read monitoring interval from config
INTERVAL_MINUTES="$(python3 -c "
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        d = json.load(f)
    print(d.get('meta_agents', {}).get('blackhawk_bravo', {}).get('monitoring_interval_minutes', 15))
except Exception:
    print(15)
" "$CONFIG_FILE" 2>/dev/null || echo "15")"

# -- Run --
_run_once() {
  if [[ $DRY_RUN -eq 1 ]]; then
    bravo_scan_all --dry-run
  else
    bravo_scan_all
  fi
}

if [[ $CONTINUOUS -eq 1 ]]; then
  echo "[bravo] Starting continuous monitoring (interval: ${INTERVAL_MINUTES}m)"
  while true; do
    _run_once
    sleep "$((INTERVAL_MINUTES * 60))"
  done
else
  _run_once
fi
