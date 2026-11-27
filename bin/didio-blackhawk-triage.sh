#!/usr/bin/env bash
# didio-blackhawk-triage.sh — Black Hawk Alpha triage CLI (single / batch / auto modes)
#
# Usage:
#   didio blackhawk triage --card WR-XXXXXXXX-NNN   # triage single card
#   didio blackhawk triage                           # triage ALL incoming cards (batch)
#   didio blackhawk triage --auto                    # continuous loop
#
# Flags:
#   --card <id>    Triage a single card by ID
#   --auto         Run batch triage in a continuous loop
#   --dry-run      Show what would happen without spawning agents or writing files
#   --help, -h     Show this help and exit
#
# Exit codes:
#   0 = success
#   1 = runtime error
#   2 = config / preflight issue
#
# All triage logic (assess, promote, defer, gather_knowledge, etc.) lives in
# lib/blackhawk-triage.sh. This script is a thin CLI that sources the lib
# and dispatches based on arguments.

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$(pwd)}"
CARDS_DIR="$PROJECT_ROOT/logs/warroom/cards"

# ---------------------------------------------------------------------------
# Source config lib
# ---------------------------------------------------------------------------

if [[ -f "$PROJECT_ROOT/bin/didio-config-lib.sh" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/bin/didio-config-lib.sh"
elif [[ -f "$DIDIO_HOME/bin/didio-config-lib.sh" ]]; then
  # shellcheck disable=SC1090
  source "$DIDIO_HOME/bin/didio-config-lib.sh"
else
  echo "[blackhawk-triage] ERROR: didio-config-lib.sh not found" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Source triage library (single source of truth for all triage functions)
# ---------------------------------------------------------------------------

TRIAGE_LIB="$PROJECT_ROOT/lib/blackhawk-triage.sh"
if [[ -f "$TRIAGE_LIB" ]]; then
  # shellcheck disable=SC1090
  source "$TRIAGE_LIB"
else
  echo "[blackhawk-triage] ERROR: lib/blackhawk-triage.sh not found" >&2
  echo "  Expected at: $TRIAGE_LIB" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

show_help() {
  cat <<'EOF'
USAGE:
  didio blackhawk triage --card <card-id>   Triage a single War Room card
  didio blackhawk triage                    Batch triage ALL incoming cards
  didio blackhawk triage --auto             Continuous loop (runs every interval)

FLAGS:
  --card <id>    Card ID to triage (e.g. WR-20261126-001)
  --auto         Run batch triage in a periodic loop
  --dry-run      Preview what would happen without writing files or spawning
  --help, -h     Show this help and exit

EXIT CODES:
  0  Success
  1  Runtime error
  2  Config / preflight issue

EXAMPLES:
  didio blackhawk triage --card WR-20261126-001
  didio blackhawk triage --dry-run
  didio blackhawk triage --auto
EOF
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

preflight() {
  local errors=0

  # 1. Config exists and blackhawk is enabled
  local config
  config="$(didio_find_config)"
  if [[ -z "$config" ]]; then
    echo "[blackhawk-triage] ERROR: didio.config.json not found." >&2
    echo "  Run /install-claude-didio-framework first." >&2
    return 2
  fi

  local enabled
  enabled="$(didio_blackhawk_enabled)"
  if [[ "$enabled" != "true" ]]; then
    echo "[blackhawk-triage] ERROR: Black Hawk Alpha is disabled in config." >&2
    echo "  Set blackhawk.enabled = true in didio.config.json to enable." >&2
    return 2
  fi

  # 2. Cards directory exists (or can be created)
  if [[ ! -d "$CARDS_DIR" ]]; then
    mkdir -p "$CARDS_DIR" 2>/dev/null || {
      echo "[blackhawk-triage] ERROR: Cannot create cards directory: $CARDS_DIR" >&2
      errors=$((errors + 1))
    }
  fi

  # 3. python3 available (used for JSON parsing)
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[blackhawk-triage] ERROR: python3 is required but not found in PATH." >&2
    errors=$((errors + 1))
  fi

  # 4. spawn-agent script exists
  local spawn_script="$PROJECT_ROOT/bin/didio-spawn-agent.sh"
  if [[ ! -f "$spawn_script" ]]; then
    spawn_script="$DIDIO_HOME/bin/didio-spawn-agent.sh"
  fi
  if [[ ! -f "$spawn_script" ]]; then
    echo "[blackhawk-triage] ERROR: didio-spawn-agent.sh not found." >&2
    errors=$((errors + 1))
  fi

  if [[ $errors -gt 0 ]]; then
    return 2
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Single-card triage (thin wrapper around lib functions)
# ---------------------------------------------------------------------------

triage_single() {
  local card_id="$1"

  echo "Triaging card ${card_id}..."

  # Gather knowledge
  printf '  Gathering knowledge sources... '
  gather_knowledge > /dev/null
  echo "done"

  # Run assessment (lib sets status + writes overlord_assessment)
  printf '  Running Black Hawk Alpha assessment... '
  local recommendation
  recommendation="$(assess_card "$card_id")"
  local exit_code=$?
  echo "done"

  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # If promoted, run the promotion flow to create feature directory
  local card_file="$CARDS_DIR/${card_id}.json"
  if [[ "$recommendation" == "promote" ]]; then
    promote_card "$card_id"
  fi

  # Print result
  local rec priority rationale
  rec="$(_assessment_field "$card_file" "recommendation")"
  priority="$(_assessment_field "$card_file" "priority")"
  rationale="$(_assessment_field "$card_file" "rationale")"

  if [[ -n "$rec" ]]; then
    echo "  Recommendation: ${rec} (priority: ${priority})"
    echo "  Rationale: ${rationale}"

    if [[ "$rec" == "promote" ]]; then
      local promoted_to promoted_as
      promoted_to="$(_card_field "$card_file" "promoted_to")"
      promoted_as="$(_assessment_field "$card_file" "promoted_as")"
      echo "  Promoted as: ${promoted_to} -- ${promoted_as}"
    fi
  else
    echo "  (no assessment produced)"
  fi
}

# ---------------------------------------------------------------------------
# Auto (continuous) triage
# ---------------------------------------------------------------------------

triage_auto() {
  local auto_enabled
  auto_enabled="$(didio_blackhawk_auto_triage)"

  if [[ "$auto_enabled" != "true" ]]; then
    echo "[blackhawk-triage] Auto-triage is disabled in config (blackhawk.auto_triage = false)." >&2
    echo "  Set blackhawk.auto_triage = true in didio.config.json to enable." >&2
    exit 2
  fi

  local interval_minutes
  interval_minutes="$(didio_blackhawk_triage_interval)"
  local interval_seconds=$((interval_minutes * 60))

  echo "Black Hawk Alpha auto-triage starting (interval: ${interval_minutes}m)..."
  echo "  Press Ctrl+C to stop."
  echo ""

  # Graceful shutdown on SIGINT / SIGTERM
  local running=1
  _shutdown() {
    echo ""
    echo "[blackhawk-triage] Received signal, shutting down gracefully..."
    running=0
  }
  trap _shutdown INT TERM

  while [[ $running -eq 1 ]]; do
    echo "--- Triage cycle at $(_now_iso) ---"
    echo ""

    triage_batch || true

    echo ""

    if [[ $running -eq 0 ]]; then
      break
    fi

    echo "Next cycle in ${interval_minutes} minutes ($(date -u -d "+${interval_minutes} minutes" +%H:%M 2>/dev/null || echo "~"))..."

    # Sleep in small increments so we can respond to signals
    local slept=0
    while [[ $slept -lt $interval_seconds && $running -eq 1 ]]; do
      sleep 1
      slept=$((slept + 1))
    done
  done

  echo "[blackhawk-triage] Auto-triage stopped."
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

MODE="batch"       # default
CARD_ID=""
DRY_RUN="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_help
      exit 0
      ;;
    --card)
      MODE="single"
      CARD_ID="${2:?--card requires a card ID}"
      shift 2
      ;;
    --card=*)
      MODE="single"
      CARD_ID="${1#--card=}"
      shift
      ;;
    --auto)
      MODE="auto"
      shift
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    *)
      echo "[blackhawk-triage] Unknown option: $1" >&2
      echo "  Try: didio blackhawk triage --help" >&2
      exit 1
      ;;
  esac
done

export DRY_RUN
export DIDIO_DRY_RUN="$DRY_RUN"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Preflight
preflight || exit $?

if [[ "$DRY_RUN" == "1" ]]; then
  echo "[DRY_RUN] Mode: ${MODE}"
  if [[ "$MODE" == "single" ]]; then
    echo "[DRY_RUN] Card: ${CARD_ID}"
  fi
  echo ""
fi

case "$MODE" in
  single)
    if [[ -z "$CARD_ID" ]]; then
      echo "[blackhawk-triage] ERROR: --card requires a card ID" >&2
      exit 1
    fi
    triage_single "$CARD_ID"
    ;;
  batch)
    triage_batch
    ;;
  auto)
    triage_auto
    ;;
esac
