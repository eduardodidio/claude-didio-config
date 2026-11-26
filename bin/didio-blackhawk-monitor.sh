#!/usr/bin/env bash
# didio-blackhawk-monitor.sh — Black Hawk Alpha governance pattern detection + strategic cards.
#
# Usage:
#   didio blackhawk monitor               Run once
#   didio blackhawk monitor --continuous   Loop every N minutes
#   didio blackhawk monitor --dry-run      Show detections without creating cards
#   didio blackhawk monitor --since YYYY-MM-DD  Only analyze after this date
#
# Scans governance data and raises strategic War Room cards when patterns
# are detected (repeated challenges, persistent blocks, low confidence,
# token budget pressure, etc.).

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
GOV_LIB="$(_resolve_lib lib/blackhawk-governance.sh)"

if [[ -z "$CONFIG_LIB" ]]; then
  echo "[blackhawk-monitor] config library not found" >&2
  exit 2
fi
if [[ -z "$GOV_LIB" ]]; then
  echo "[blackhawk-monitor] governance library not found" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "$CONFIG_LIB"
# shellcheck disable=SC1090
source "$GOV_LIB"

# -- Help --
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
USAGE:
  didio blackhawk monitor [OPTIONS]

OPTIONS:
  --since YYYY-MM-DD   Only analyze decisions/reviews after this date
  --dry-run            Detect patterns but do not create War Room cards
  --continuous         Loop every N minutes (uses blackhawk.triage_interval_minutes)
  --interval MINUTES   Override loop interval (default: from config or 30)

PATTERN DETECTORS:
  1. Repeated challenges     3+ GateKeeper challenges in 7 days on similar topics
  2. Blocked pipelines       2+ decisions blocked with similar reason
  3. Low confidence          Average confidence < 0.6 in last 5 reviews
  4. Escalation frequency    2+ escalations in last 10 decisions
  5. Persistent blocked flags  Any flag unresolved for >24h
  6. Token budget pressure   token-schedule-suggestion.json shows status=critical

Each detected pattern creates a War Room card (source=agent, source_agent=blackhawk-alpha)
unless a similar active card already exists.

EXAMPLES:
  didio blackhawk monitor
  didio blackhawk monitor --dry-run
  didio blackhawk monitor --since 2026-11-25
  didio blackhawk monitor --continuous --interval 15
EOF
  exit 0
fi

# -- Parse args --
SINCE=""
DRY_RUN=0
CONTINUOUS=0
INTERVAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)       SINCE="${2:?--since requires YYYY-MM-DD}"; shift 2 ;;
    --since=*)     SINCE="${1#--since=}"; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --continuous)  CONTINUOUS=1; shift ;;
    --interval)    INTERVAL="${2:?--interval requires minutes}"; shift 2 ;;
    --interval=*)  INTERVAL="${1#--interval=}"; shift ;;
    *)
      echo "[blackhawk-monitor] Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# -- Check if blackhawk is enabled --
enabled="$(didio_blackhawk_enabled 2>/dev/null || echo "true")"
if [[ "$enabled" == "false" ]]; then
  echo "[blackhawk-monitor] Black Hawk Alpha is disabled in config (blackhawk.enabled=false)"
  exit 0
fi

# -- Build analysis args --
ANALYZE_ARGS=()
if [[ -n "$SINCE" ]]; then
  ANALYZE_ARGS+=(--since "$SINCE")
fi
if [[ $DRY_RUN -eq 1 ]]; then
  ANALYZE_ARGS+=(--dry-run)
fi

# -- Run once or continuous --
_run_once() {
  analyze_decision_patterns "${ANALYZE_ARGS[@]}"
}

if [[ $CONTINUOUS -eq 0 ]]; then
  _run_once
else
  # Continuous mode: loop every N minutes
  if [[ -z "$INTERVAL" ]]; then
    INTERVAL="$(didio_blackhawk_triage_interval 2>/dev/null || echo "30")"
  fi
  echo "[blackhawk-monitor] Continuous mode: checking every ${INTERVAL} minutes"
  echo "[blackhawk-monitor] Press Ctrl+C to stop"
  echo ""

  while true; do
    _run_once
    echo ""
    echo "[blackhawk-monitor] Next check in ${INTERVAL} minutes..."
    sleep "$((INTERVAL * 60))"
  done
fi
