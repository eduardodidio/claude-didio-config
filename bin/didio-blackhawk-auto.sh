#!/usr/bin/env bash
# didio-blackhawk-auto.sh — Black Hawk autonomous card advancement loop
#
# Usage:
#   didio blackhawk auto              # start autonomous loop
#   didio blackhawk auto --dry-run    # preview what would happen
#   didio blackhawk auto --once       # run one cycle then exit (for testing)
#
# Flags:
#   --dry-run      Preview what would happen without executing actions
#   --once         Run a single cycle and exit (useful for testing)
#   --help, -h     Show this help and exit
#
# Signal control:
#   logs/agents/signals/blackhawk.stop    → graceful shutdown
#   logs/agents/signals/blackhawk.pause   → pause (remove to resume)
#   logs/agents/signals/blackhawk.resume  → resume from pause
#
# Exit codes:
#   0 = success (or clean shutdown)
#   1 = runtime error
#   2 = config / preflight issue

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$(pwd)}"
CARDS_DIR="$PROJECT_ROOT/logs/warroom/cards"
SIGNALS_DIR="$PROJECT_ROOT/logs/agents/signals"
PIPELINES_DIR="$PROJECT_ROOT/logs/agents"
LOG_PREFIX="[blackhawk-auto]"

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
  echo "$LOG_PREFIX ERROR: didio-config-lib.sh not found" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Source alert engine
# ---------------------------------------------------------------------------

ALERT_LIB="$PROJECT_ROOT/lib/alert-engine.sh"
if [[ -f "$ALERT_LIB" ]]; then
  # shellcheck disable=SC1090
  source "$ALERT_LIB"
else
  echo "$LOG_PREFIX ERROR: lib/alert-engine.sh not found" >&2
  echo "  Expected at: $ALERT_LIB" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

show_help() {
  cat <<'EOF'
USAGE:
  didio blackhawk auto              Start the autonomous loop
  didio blackhawk auto --dry-run    Preview what would happen
  didio blackhawk auto --once       Run one cycle then exit

FLAGS:
  --dry-run      Preview actions without executing them
  --once         Run a single cycle and exit (testing)
  --help, -h     Show this help and exit

SIGNAL CONTROL:
  Create these files to control the loop:
  logs/agents/signals/blackhawk.stop    Graceful shutdown
  logs/agents/signals/blackhawk.pause   Pause the loop
  logs/agents/signals/blackhawk.resume  Resume from pause

CONFIG:
  blackhawk.auto_advance                Kill switch (true/false, default true)
  blackhawk.auto_confidence_threshold   Min confidence for auto-action (default 0.8)
  blackhawk.auto_interval_minutes       Sleep between cycles (default 5)
  blackhawk.auto_max_promotions_per_cycle  Max auto-promotions per cycle (default 3)

EXIT CODES:
  0  Success / clean shutdown
  1  Runtime error
  2  Config / preflight issue
EOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log_info() {
  echo "$LOG_PREFIX $(_now_iso) $*"
}

log_warn() {
  echo "$LOG_PREFIX $(_now_iso) WARN: $*" >&2
}

log_error() {
  echo "$LOG_PREFIX $(_now_iso) ERROR: $*" >&2
}

# Read a JSON field from a card file
_card_field() {
  local file="$1" field="$2"
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
v = d.get(sys.argv[2])
if v is None:
    print('')
elif isinstance(v, list):
    print(', '.join(str(x) for x in v))
elif isinstance(v, dict):
    print(json.dumps(v))
else:
    print(str(v))
" "$file" "$field" 2>/dev/null || echo ""
}

# Read a nested field from overlord_assessment
_assessment_field() {
  local file="$1" field="$2"
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
a = d.get('overlord_assessment')
if a and isinstance(a, dict):
    v = a.get(sys.argv[2])
    if v is None:
        print('')
    elif isinstance(v, (dict, list)):
        print(json.dumps(v))
    elif isinstance(v, bool):
        print('true' if v else 'false')
    elif isinstance(v, float):
        print(str(v))
    else:
        print(str(v))
else:
    print('')
" "$file" "$field" 2>/dev/null || echo ""
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
    log_error "didio.config.json not found. Run /install-claude-didio-framework first."
    return 2
  fi

  local enabled
  enabled="$(didio_blackhawk_enabled)"
  if [[ "$enabled" != "true" ]]; then
    log_error "Black Hawk Alpha is disabled in config (blackhawk.enabled = false)."
    return 2
  fi

  # 2. Check kill switch
  local auto_advance
  auto_advance="$(didio_read_config_path 'blackhawk.auto_advance' 'true')"
  if [[ "$auto_advance" != "true" ]]; then
    log_error "Autonomous mode is disabled (blackhawk.auto_advance = false). Set to true to enable."
    return 2
  fi

  # 3. Cards directory
  if [[ ! -d "$CARDS_DIR" ]]; then
    mkdir -p "$CARDS_DIR" 2>/dev/null || {
      log_error "Cannot create cards directory: $CARDS_DIR"
      errors=$((errors + 1))
    }
  fi

  # 4. python3 available
  if ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 is required but not found in PATH."
    errors=$((errors + 1))
  fi

  # 5. Ensure signals directory
  mkdir -p "$SIGNALS_DIR" 2>/dev/null || true

  if [[ $errors -gt 0 ]]; then
    return 2
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Signal handling
# ---------------------------------------------------------------------------

check_stop_signal() {
  [[ -f "$SIGNALS_DIR/blackhawk.stop" ]]
}

check_pause_signal() {
  [[ -f "$SIGNALS_DIR/blackhawk.pause" ]]
}

check_resume_signal() {
  [[ -f "$SIGNALS_DIR/blackhawk.resume" ]]
}

clear_stop_signal() {
  rm -f "$SIGNALS_DIR/blackhawk.stop" 2>/dev/null || true
}

clear_resume_signal() {
  rm -f "$SIGNALS_DIR/blackhawk.resume" 2>/dev/null || true
}

# Wait in pause state until resume or stop signal
wait_for_resume() {
  log_info "PAUSED. Waiting for resume signal (create $SIGNALS_DIR/blackhawk.resume)"
  while check_pause_signal; do
    # Check for stop during pause
    if check_stop_signal; then
      return 1
    fi
    # Check for resume
    if check_resume_signal; then
      rm -f "$SIGNALS_DIR/blackhawk.pause" 2>/dev/null || true
      clear_resume_signal
      log_info "RESUMED."
      return 0
    fi
    sleep 2
  done
  # Pause file removed externally = resume
  log_info "RESUMED (pause signal removed)."
  clear_resume_signal
  return 0
}

# ---------------------------------------------------------------------------
# Core: scan and process incoming cards
# ---------------------------------------------------------------------------

scan_incoming_cards() {
  local threshold="$1"
  local max_promotions="$2"
  local promotions_this_cycle=0

  mkdir -p "$CARDS_DIR"

  for card_file in "$CARDS_DIR"/WR-*.json; do
    [[ -f "$card_file" ]] || continue

    local status
    status="$(_card_field "$card_file" "status")"
    [[ "$status" != "incoming" ]] && continue

    local card_id
    card_id="$(_card_field "$card_file" "card_id")"
    [[ -z "$card_id" ]] && continue

    # Check if card already has an assessment
    local recommendation
    recommendation="$(_assessment_field "$card_file" "recommendation")"

    if [[ -n "$recommendation" && "$recommendation" != "" ]]; then
      # Card has assessment — check confidence
      local confidence_str
      confidence_str="$(_assessment_field "$card_file" "confidence")"
      local confidence="${confidence_str:-0}"

      local above_threshold
      above_threshold="$(python3 -c "
import sys
conf = float(sys.argv[1])
thresh = float(sys.argv[2])
print('true' if conf >= thresh else 'false')
" "$confidence" "$threshold" 2>/dev/null || echo "false")"

      if [[ "$above_threshold" == "true" ]]; then
        # High confidence: auto-promote or auto-defer
        if [[ "$recommendation" == "promote" ]]; then
          if [[ $promotions_this_cycle -ge $max_promotions ]]; then
            log_info "Card $card_id: would promote but hit per-cycle limit ($max_promotions)"
            alert_create "needs_approval" "$card_id" \
              "Promotion limit reached for $card_id" \
              "Card $card_id recommended for promotion (confidence=$confidence) but per-cycle limit reached." \
              "didio blackhawk promote $card_id" \
              "$confidence" > /dev/null
            continue
          fi

          if [[ "$DRY_RUN" == "1" ]]; then
            log_info "[DRY_RUN] Would auto-promote $card_id (confidence=$confidence)"
          else
            log_info "Auto-promoting $card_id (confidence=$confidence, recommendation=$recommendation)"
            bash "$PROJECT_ROOT/bin/didio-blackhawk-promote.sh" "$card_id" 2>&1 || {
              log_warn "Promotion failed for $card_id"
              alert_create "failed_pipeline" "$card_id" \
                "Promotion failed for $card_id" \
                "Auto-promotion command failed with non-zero exit code." \
                "didio blackhawk promote $card_id" \
                "$confidence" > /dev/null
            }
          fi
          promotions_this_cycle=$((promotions_this_cycle + 1))

        elif [[ "$recommendation" == "defer" ]]; then
          if [[ "$DRY_RUN" == "1" ]]; then
            log_info "[DRY_RUN] Would auto-defer $card_id (confidence=$confidence)"
          else
            log_info "Auto-deferring $card_id (confidence=$confidence)"
            # Update card status to deferred
            python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
d['status'] = 'deferred'
d['updated_at'] = sys.argv[2]
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$card_file" "$(_now_iso)"
          fi

        elif [[ "$recommendation" == "archive" ]]; then
          if [[ "$DRY_RUN" == "1" ]]; then
            log_info "[DRY_RUN] Would auto-archive $card_id (confidence=$confidence)"
          else
            log_info "Auto-archiving $card_id (confidence=$confidence)"
            python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
d['status'] = 'archived'
d['updated_at'] = sys.argv[2]
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$card_file" "$(_now_iso)"
          fi

        else
          # needs_input or unknown recommendation with high confidence — alert
          log_info "Card $card_id has recommendation=$recommendation, creating alert"
          alert_create "escalation" "$card_id" \
            "Card $card_id needs operator input" \
            "Assessment recommendation=$recommendation with confidence=$confidence." \
            "" \
            "$confidence" > /dev/null
        fi
      else
        # Low confidence: create alert for operator
        log_info "Card $card_id: low confidence ($confidence < $threshold), creating alert"
        local suggestion_cmd=""
        if [[ "$recommendation" == "promote" ]]; then
          suggestion_cmd="didio blackhawk promote $card_id"
        fi
        alert_create "low_confidence" "$card_id" \
          "Low confidence assessment for $card_id ($confidence)" \
          "Recommendation=$recommendation but confidence=$confidence is below threshold=$threshold. Operator review needed." \
          "$suggestion_cmd" \
          "$confidence" > /dev/null
      fi
    else
      # No assessment yet — run triage
      if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY_RUN] Would run triage on $card_id (no assessment yet)"
      else
        log_info "Running triage on $card_id (no assessment yet)"
        set +e
        bash "$PROJECT_ROOT/bin/didio-blackhawk-triage.sh" --card "$card_id" 2>&1
        local triage_exit=$?
        set -e
        if [[ $triage_exit -ne 0 ]]; then
          log_warn "Triage failed for $card_id (exit=$triage_exit)"
        fi
      fi
    fi
  done

  log_info "Card scan complete: $promotions_this_cycle promotions this cycle"
}

# ---------------------------------------------------------------------------
# Core: scan pipelines for failures
# ---------------------------------------------------------------------------

scan_pipelines() {
  for state_file in "$PIPELINES_DIR"/pipeline-*.state.json; do
    [[ -f "$state_file" ]] || continue

    local status feature error
    status="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('status', ''))
" "$state_file" 2>/dev/null || echo "")"

    if [[ "$status" == "failed" || "$status" == "error" ]]; then
      feature="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('feature', ''))
" "$state_file" 2>/dev/null || echo "")"

      error="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('error', '') or d.get('stage_detail', '') or 'unknown error')
" "$state_file" 2>/dev/null || echo "unknown error")"

      # Check if we already have a pending alert for this pipeline
      local existing
      existing="$(python3 -c "
import json, os, glob, sys

alerts_dir = sys.argv[1]
feature = sys.argv[2]
pattern = os.path.join(alerts_dir, 'ALT-*.json')

for fpath in sorted(glob.glob(pattern)):
    try:
        with open(fpath, 'r', encoding='utf-8') as f:
            alert = json.load(f)
        if alert.get('status') == 'pending' and alert.get('type') == 'failed_pipeline' and feature in alert.get('title', ''):
            print('yes')
            break
    except (json.JSONDecodeError, IOError):
        continue
else:
    print('no')
" "$_AE_ALERTS_DIR" "$feature" 2>/dev/null || echo "no")"

      if [[ "$existing" != "yes" ]]; then
        log_info "Pipeline failure detected: $feature ($error)"
        if [[ "$DRY_RUN" == "1" ]]; then
          log_info "[DRY_RUN] Would create alert for failed pipeline $feature"
        else
          alert_create "failed_pipeline" "$feature" \
            "Pipeline failed: $feature" \
            "$error" \
            "" \
            "0.0" > /dev/null
        fi
      fi
    fi
  done
}

# ---------------------------------------------------------------------------
# Main cycle: one full autonomous cycle
# ---------------------------------------------------------------------------

run_cycle() {
  local threshold="$1"
  local max_promotions="$2"
  local max_alert_age="$3"

  log_info "--- Cycle start ---"

  # a. Scan incoming warroom cards
  scan_incoming_cards "$threshold" "$max_promotions"

  # b. Scan pipelines for failures
  scan_pipelines

  # c. Expire stale alerts
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY_RUN] Would expire alerts older than ${max_alert_age}h"
  else
    local expired_count
    expired_count="$(alert_expire_stale "$max_alert_age")"
    if [[ "$expired_count" -gt 0 ]]; then
      log_info "Expired $expired_count stale alerts (>${max_alert_age}h)"
    fi
  fi

  # d. Report pending alerts
  local pending_count
  pending_count="$(python3 -c "
import json, sys
alerts = json.loads(sys.stdin.read())
print(len(alerts))
" <<< "$(alert_list_pending)" 2>/dev/null || echo "0")"

  if [[ "$pending_count" -gt 0 ]]; then
    log_info "Pending alerts: $pending_count (operator action needed)"
  fi

  log_info "--- Cycle end ---"
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

DRY_RUN="0"
RUN_ONCE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_help
      exit 0
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    --once)
      RUN_ONCE="1"
      shift
      ;;
    *)
      echo "$LOG_PREFIX Unknown option: $1" >&2
      echo "  Try: didio blackhawk auto --help" >&2
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

# Read config values
CONFIDENCE_THRESHOLD="$(didio_read_config_path 'blackhawk.auto_confidence_threshold' '0.8')"
INTERVAL_MINUTES="$(didio_read_config_path 'blackhawk.auto_interval_minutes' '5')"
MAX_PROMOTIONS="$(didio_read_config_path 'blackhawk.auto_max_promotions_per_cycle' '3')"
MAX_ALERT_AGE_HOURS="24"
INTERVAL_SECONDS=$((INTERVAL_MINUTES * 60))

log_info "Black Hawk autonomous loop starting"
log_info "  Confidence threshold: $CONFIDENCE_THRESHOLD"
log_info "  Interval: ${INTERVAL_MINUTES}m"
log_info "  Max promotions/cycle: $MAX_PROMOTIONS"
log_info "  Dry run: $DRY_RUN"
log_info "  Run once: $RUN_ONCE"

if [[ "$DRY_RUN" == "1" ]]; then
  log_info "[DRY_RUN] No actions will be executed"
fi

# Clear any leftover stop signal from previous run
clear_stop_signal

# Graceful shutdown on SIGINT / SIGTERM
RUNNING=1
_shutdown() {
  echo ""
  log_info "Received signal, shutting down gracefully..."
  RUNNING=0
}
trap _shutdown INT TERM

# Main loop
while [[ $RUNNING -eq 1 ]]; do
  # a. Check for stop signal
  if check_stop_signal; then
    log_info "Stop signal detected, shutting down..."
    clear_stop_signal
    break
  fi

  # b. Check for pause signal
  if check_pause_signal; then
    wait_for_resume || {
      log_info "Stop signal during pause, shutting down..."
      clear_stop_signal
      break
    }
  fi

  # c. Re-check kill switch each cycle (config may have changed)
  auto_advance="$(didio_read_config_path 'blackhawk.auto_advance' 'true')"
  if [[ "$auto_advance" != "true" ]]; then
    log_info "Kill switch activated (blackhawk.auto_advance=false), shutting down..."
    break
  fi

  # d. Run one cycle
  run_cycle "$CONFIDENCE_THRESHOLD" "$MAX_PROMOTIONS" "$MAX_ALERT_AGE_HOURS"

  # e. If --once, exit after first cycle
  if [[ "$RUN_ONCE" == "1" ]]; then
    log_info "Single cycle complete (--once). Exiting."
    break
  fi

  # f. Sleep interval (in small increments for signal responsiveness)
  log_info "Next cycle in ${INTERVAL_MINUTES}m..."
  slept=0
  while [[ $slept -lt $INTERVAL_SECONDS && $RUNNING -eq 1 ]]; do
    # Check signals during sleep
    if check_stop_signal; then
      log_info "Stop signal detected during sleep, shutting down..."
      clear_stop_signal
      RUNNING=0
      break
    fi
    if check_pause_signal; then
      wait_for_resume || {
        RUNNING=0
        break
      }
    fi
    sleep 1
    slept=$((slept + 1))
  done
done

log_info "Black Hawk autonomous loop stopped."
exit 0
