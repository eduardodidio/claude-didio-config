#!/usr/bin/env bash
# didio-squad-scan.sh -- Squad Orchestrator: coordinated Bravo+Charlie+Delta scanning.
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"

_resolve_lib() {
  local name="$1"
  if [[ -f "$PWD/$name" ]]; then echo "$PWD/$name"
  elif [[ -f "$DIDIO_HOME/$name" ]]; then echo "$DIDIO_HOME/$name"
  else echo ""; fi
}

CONFIG_LIB="$(_resolve_lib bin/didio-config-lib.sh)"
BRAVO_LIB="$(_resolve_lib lib/bravo-intelligence.sh)"
CHARLIE_LIB="$(_resolve_lib lib/charlie-monitoring.sh)"
DELTA_LIB="$(_resolve_lib lib/delta-security.sh)"
SQUAD_LIB="$(_resolve_lib lib/squad-orchestrator.sh)"

if [[ -z "$CONFIG_LIB" ]]; then echo "[squad] config library not found" >&2; exit 2; fi
if [[ -z "$SQUAD_LIB" ]]; then echo "[squad] squad library not found" >&2; exit 2; fi

# shellcheck disable=SC1090
source "$CONFIG_LIB"
[[ -n "$BRAVO_LIB" ]] && source "$BRAVO_LIB"
[[ -n "$CHARLIE_LIB" ]] && source "$CHARLIE_LIB"
[[ -n "$DELTA_LIB" ]] && source "$DELTA_LIB"
source "$SQUAD_LIB"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
USAGE:
  didio squad scan [OPTIONS]

OPTIONS:
  --once         Scan once and exit (default)
  --continuous   Loop every N minutes
  --dry-run      Scan and report but do NOT create War Room cards

Runs all enabled squad scanners (Bravo, Charlie, Delta) in a coordinated pass.
Produces a combined report with cross-scanner correlation analysis.

Enable/disable per scanner in didio.config.json:
  meta_agents.blackhawk_bravo.enabled
  meta_agents.blackhawk_charlie.enabled
  meta_agents.blackhawk_delta.enabled
EOF
  exit 0
fi

if ! command -v python3 &>/dev/null; then echo "[squad] python3 not found" >&2; exit 2; fi

DRY_RUN=0; CONTINUOUS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;; --continuous) CONTINUOUS=1 ;; --once) CONTINUOUS=0 ;;
  esac
done

_run_once() {
  if [[ $DRY_RUN -eq 1 ]]; then squad_scan_all --dry-run
  else squad_scan_all; fi
}

if [[ $CONTINUOUS -eq 1 ]]; then
  echo "[squad] Starting continuous scanning (interval: 30m)"
  while true; do _run_once; sleep 1800; done
else _run_once; fi
