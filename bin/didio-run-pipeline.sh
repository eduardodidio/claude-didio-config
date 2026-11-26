#!/usr/bin/env bash
# didio-run-pipeline.sh -- Autonomous feature pipeline execution
#
# Usage:
#   didio run-pipeline <feature-id> <brief-or-file> [flags]
#
# Executes the complete pipeline for a feature:
#   Handler gate -> Architect -> Readiness -> TEA -> Waves -> TechLead -> QA -> Post-review
#
# Tracks state in logs/agents/pipeline-<FXX>.state.json and supports
# pause/resume/cancel via signal files in logs/agents/signals/.
#
# Flags:
#   --skip-handler       Skip the Handler strategic gate
#   --skip-readiness     Skip the readiness audit
#   --skip-tea           Skip the TEA test architect
#   --skip-post-review   Skip the post-work review gate
#
# Exit codes:
#   0 = success (all stages passed)
#   1 = failed (a stage failed)
#   2 = escalated (Handler/GateKeeper escalation)
#   3 = paused (token budget exhausted)
#   4 = cancelled (via signal file)

set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
PROJECT_ROOT="$(pwd)"

# ── Help ──────────────────────────────────────────────────────────────
if [[ "${1:-}" = "--help" || "${1:-}" = "-h" ]]; then
  cat <<'EOF'
USAGE:
  didio run-pipeline <feature-id> <brief-or-file> [flags]

Executes the full autonomous pipeline for a feature:
  1. Handler gate (if enabled)
  2. Architect (plan tasks + waves)
  3. Readiness check (pre-wave audit)
  4. TEA gate (test architect, opt-in)
  5. Waves 0..N (developer tasks)
  6. TechLead review
  7. QA validation
  8. Post-work review (Handler + GateKeeper)

FLAGS:
  --skip-handler       Skip the Handler strategic gate
  --skip-readiness     Skip the readiness audit
  --skip-tea           Skip the TEA test architect
  --skip-post-review   Skip the post-work review gate
  --help, -h           Show this help and exit

EXIT CODES:
  0 = success
  1 = failed (a stage failed)
  2 = escalated (Handler/GateKeeper escalation)
  3 = paused (token budget exhausted)
  4 = cancelled (via signal file)

SIGNAL FILES (in logs/agents/signals/):
  <FXX>.pause    Pipeline pauses after current stage completes
  <FXX>.resume   Removes pause; pipeline continues
  <FXX>.cancel   Pipeline stops with exit code 4

STATE FILE:
  logs/agents/pipeline-<FXX>.state.json
  Updated at every phase transition.
EOF
  exit 0
fi

# ── Source config lib ─────────────────────────────────────────────────
if [[ -f "$PROJECT_ROOT/bin/didio-config-lib.sh" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/bin/didio-config-lib.sh"
else
  # shellcheck disable=SC1090
  source "$DIDIO_HOME/bin/didio-config-lib.sh"
fi

# ── Parse arguments ──────────────────────────────────────────────────
FEATURE="${1:?feature-id required (e.g. F29B)}"
BRIEF="${2:?brief or file path required}"
shift 2

SKIP_HANDLER=0
SKIP_READINESS=0
SKIP_TEA=0
SKIP_POST_REVIEW=0

for arg in "$@"; do
  case "$arg" in
    --skip-handler)      SKIP_HANDLER=1 ;;
    --skip-readiness)    SKIP_READINESS=1 ;;
    --skip-tea)          SKIP_TEA=1 ;;
    --skip-post-review)  SKIP_POST_REVIEW=1 ;;
    *)
      echo "[didio-run-pipeline] unknown flag: $arg" >&2
      exit 1
      ;;
  esac
done

# Also honor environment variables for skip flags
[[ "${DIDIO_SKIP_HANDLER:-0}" == "1" ]] && SKIP_HANDLER=1
[[ "${DIDIO_SKIP_READINESS:-0}" == "1" ]] && SKIP_READINESS=1
[[ "${DIDIO_SKIP_TEA:-0}" == "1" ]] && SKIP_TEA=1

# ── Constants ─────────────────────────────────────────────────────────
LOG_DIR="$PROJECT_ROOT/logs/agents"
STATE_FILE="$LOG_DIR/pipeline-${FEATURE}.state.json"
SIGNAL_DIR="$PROJECT_ROOT/$(didio_pipeline_signal_dir)"
POLL_INTERVAL=5

mkdir -p "$LOG_DIR" "$SIGNAL_DIR"

# All pipeline stages in order
ALL_STAGES=("handler_gate" "architect" "readiness" "tea" "waves" "techlead" "qa" "post_review")

# ── State management ─────────────────────────────────────────────────

# Write or update the state JSON file.
# Usage: update_state <status> [error_message]
update_state() {
  local status="$1"
  local error_msg="${2:-}"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Build stages_completed and stages_remaining as JSON arrays
  local completed_json remaining_json
  completed_json="$(printf '%s\n' "${STAGES_COMPLETED[@]+"${STAGES_COMPLETED[@]}"}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))" 2>/dev/null || echo "[]")"
  remaining_json="$(printf '%s\n' "${STAGES_REMAINING[@]+"${STAGES_REMAINING[@]}"}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))" 2>/dev/null || echo "[]")"

  local paused_at_val="null"
  if [[ "$status" == "paused" ]]; then
    paused_at_val="\"$now\""
  fi

  local resume_from_val="null"
  if [[ "$status" == "paused" && -n "${CURRENT_STAGE:-}" ]]; then
    resume_from_val="\"$CURRENT_STAGE\""
  fi

  local exit_code_val="null"
  if [[ "$status" == "completed" ]]; then
    exit_code_val="0"
  elif [[ "$status" == "failed" ]]; then
    exit_code_val="1"
  elif [[ "$status" == "escalated" ]]; then
    exit_code_val="2"
  elif [[ "$status" == "paused" && "$error_msg" == "token_budget_exhausted" ]]; then
    exit_code_val="3"
  elif [[ "$status" == "cancelled" ]]; then
    exit_code_val="4"
  fi

  local error_val="null"
  if [[ -n "$error_msg" ]]; then
    error_val="\"$error_msg\""
  fi

  cat > "$STATE_FILE" <<STATEJSON
{
  "feature": "$FEATURE",
  "started_at": "$STARTED_AT",
  "updated_at": "$now",
  "stage": "${CURRENT_STAGE:-}",
  "stage_detail": "${STAGE_DETAIL:-}",
  "status": "$status",
  "stages_completed": $completed_json,
  "stages_remaining": $remaining_json,
  "current_wave": ${CURRENT_WAVE:-null},
  "total_waves": ${TOTAL_WAVES:-null},
  "exit_code": $exit_code_val,
  "error": $error_val,
  "paused_at": $paused_at_val,
  "resume_from": $resume_from_val
}
STATEJSON
}

# ── Signal checking ──────────────────────────────────────────────────

# Returns 0 to continue, 1 to cancel.
# If paused, blocks until resume signal appears.
check_signals() {
  # Cancel signal
  if [[ -f "$SIGNAL_DIR/${FEATURE}.cancel" ]]; then
    rm -f "$SIGNAL_DIR/${FEATURE}.cancel"
    update_state "cancelled"
    echo "[didio-run-pipeline] CANCELLED via signal file" >&2
    return 1
  fi

  # Pause signal
  if [[ -f "$SIGNAL_DIR/${FEATURE}.pause" ]]; then
    echo "[didio-run-pipeline] PAUSED via signal file. Waiting for resume..." >&2
    update_state "paused"
    while [[ -f "$SIGNAL_DIR/${FEATURE}.pause" && ! -f "$SIGNAL_DIR/${FEATURE}.resume" ]]; do
      # Also check for cancel during pause
      if [[ -f "$SIGNAL_DIR/${FEATURE}.cancel" ]]; then
        rm -f "$SIGNAL_DIR/${FEATURE}.cancel" "$SIGNAL_DIR/${FEATURE}.pause"
        update_state "cancelled"
        echo "[didio-run-pipeline] CANCELLED while paused" >&2
        return 1
      fi
      sleep "$POLL_INTERVAL"
    done
    rm -f "$SIGNAL_DIR/${FEATURE}.pause" "$SIGNAL_DIR/${FEATURE}.resume"
    echo "[didio-run-pipeline] RESUMED" >&2
    update_state "running"
  fi

  return 0
}

# ── Token budget check ───────────────────────────────────────────────

check_token_budget() {
  if [[ "$(didio_token_monitor_enabled)" == "true" ]]; then
    local budget_check
    budget_check="$("$DIDIO_HOME/bin/didio-token-monitor.sh" --check-only 2>/dev/null || true)"
    if [[ "$budget_check" == "DEPLETED" ]]; then
      echo "[didio-run-pipeline] Token budget exhausted -- pausing pipeline" >&2
      update_state "paused" "token_budget_exhausted"
      return 1
    fi
  fi
  return 0
}

# ── Stage transition helper ──────────────────────────────────────────

# Move current stage to completed, set next stage.
# Usage: advance_stage <next_stage>
advance_stage() {
  local next="$1"
  if [[ -n "${CURRENT_STAGE:-}" ]]; then
    STAGES_COMPLETED+=("$CURRENT_STAGE")
  fi
  # Remove the next stage from remaining (rebuild remaining list)
  local new_remaining=()
  local found=0
  for s in "${STAGES_REMAINING[@]+"${STAGES_REMAINING[@]}"}"; do
    if [[ "$s" == "$next" && "$found" -eq 0 ]]; then
      found=1
      continue
    fi
    new_remaining+=("$s")
  done
  STAGES_REMAINING=("${new_remaining[@]+"${new_remaining[@]}"}")
  CURRENT_STAGE="$next"
  STAGE_DETAIL=""
}

# Mark current stage as skipped (move to completed without running)
skip_stage() {
  local stage="$1"
  local reason="$2"
  advance_stage "$stage"
  echo "[didio-run-pipeline] SKIP $stage: $reason" >&2
  STAGES_COMPLETED+=("$CURRENT_STAGE")
  CURRENT_STAGE=""
}

# ── Resume support ───────────────────────────────────────────────────

RESUME_MODE=0
RESUME_FROM=""

if [[ -f "$STATE_FILE" ]]; then
  PREV_STATUS="$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('status',''))" 2>/dev/null || echo "")"
  if [[ "$PREV_STATUS" == "paused" ]]; then
    RESUME_FROM="$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('resume_from','') or '')" 2>/dev/null || echo "")"
    if [[ -n "$RESUME_FROM" ]]; then
      RESUME_MODE=1
      # Restore completed stages from previous state
      STAGES_COMPLETED=()
      while IFS= read -r line; do
        [[ -n "$line" ]] && STAGES_COMPLETED+=("$line")
      done < <(python3 -c "
import json
with open('$STATE_FILE') as f:
    s = json.load(f)
for stage in s.get('stages_completed', []):
    print(stage)
" 2>/dev/null || true)
      echo "[didio-run-pipeline] RESUMING from stage '$RESUME_FROM' (${#STAGES_COMPLETED[@]} stages already completed)" >&2
    fi
  fi
fi

# ── Initialize state ─────────────────────────────────────────────────

STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CURRENT_STAGE=""
STAGE_DETAIL=""
CURRENT_WAVE=null
TOTAL_WAVES=null

if [[ "$RESUME_MODE" -eq 0 ]]; then
  STAGES_COMPLETED=()
  STAGES_REMAINING=("${ALL_STAGES[@]}")
else
  # Build remaining stages from resume point forward
  STAGES_REMAINING=()
  local_found=0
  for s in "${ALL_STAGES[@]}"; do
    if [[ "$s" == "$RESUME_FROM" ]]; then
      local_found=1
    fi
    if [[ "$local_found" -eq 1 ]]; then
      # Only add if not already completed
      local_already=0
      for c in "${STAGES_COMPLETED[@]+"${STAGES_COMPLETED[@]}"}"; do
        [[ "$c" == "$s" ]] && local_already=1 && break
      done
      [[ "$local_already" -eq 0 ]] && STAGES_REMAINING+=("$s")
    fi
  done
  # Restore started_at from previous run
  STARTED_AT="$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('started_at',''))" 2>/dev/null || echo "$STARTED_AT")"
fi

update_state "running"
echo "[didio-run-pipeline] Starting pipeline for $FEATURE" >&2

# ── Resolve feature directory helper ─────────────────────────────────

resolve_feature_dir() {
  FEATURE_DIR="$(didio_find_feature_dir "$FEATURE" 2>/dev/null || true)"
  if [[ -z "$FEATURE_DIR" ]]; then
    FEATURE_DIR=""
  fi
}

resolve_readme() {
  resolve_feature_dir
  if [[ -n "$FEATURE_DIR" ]]; then
    FEATURE_README="$FEATURE_DIR/${FEATURE}-README.md"
  else
    FEATURE_README=""
  fi
}

# ── Helper: should we skip to resume point? ──────────────────────────

should_skip_for_resume() {
  local stage="$1"
  if [[ "$RESUME_MODE" -eq 1 ]]; then
    for c in "${STAGES_COMPLETED[@]+"${STAGES_COMPLETED[@]}"}"; do
      if [[ "$c" == "$stage" ]]; then
        return 0  # yes, skip
      fi
    done
  fi
  return 1  # no, run it
}

# ══════════════════════════════════════════════════════════════════════
# PIPELINE STAGES
# ══════════════════════════════════════════════════════════════════════

# ── Stage 1: Handler gate ─────────────────────────────────────────────

run_handler_gate() {
  if should_skip_for_resume "handler_gate"; then
    echo "[didio-run-pipeline] handler_gate: already completed (resume)" >&2
    return 0
  fi

  advance_stage "handler_gate"

  # Check if Handler is enabled
  local handler_enabled
  handler_enabled="$(didio_handler_enabled)"

  if [[ "$handler_enabled" != "true" ]]; then
    echo "[didio-run-pipeline] handler_gate: Handler disabled, skipping" >&2
    update_state "running"
    return 0
  fi

  if [[ "$SKIP_HANDLER" -eq 1 ]]; then
    echo "[didio-run-pipeline] WARNING: Handler gate bypassed via --skip-handler" >&2
    update_state "running"
    return 0
  fi

  STAGE_DETAIL="spawning Handler"
  update_state "running"

  # Prepare brief file
  local brief_file="$BRIEF"
  if [[ ! -f "$brief_file" ]]; then
    # Brief is a string, write to temp file
    local tmp_brief="$PROJECT_ROOT/tasks/features/${FEATURE}-_tmp-pipeline-brief.md"
    echo "$BRIEF" > "$tmp_brief"
    brief_file="$tmp_brief"
  fi

  set +e
  "$DIDIO_HOME/bin/didio-handler.sh" "$FEATURE" "$brief_file"
  local handler_exit=$?
  set -e

  # Clean up temp brief if we created it
  [[ -f "$PROJECT_ROOT/tasks/features/${FEATURE}-_tmp-pipeline-brief.md" ]] && \
    rm -f "$PROJECT_ROOT/tasks/features/${FEATURE}-_tmp-pipeline-brief.md"

  if [[ $handler_exit -eq 3 ]]; then
    echo "[didio-run-pipeline] handler_gate: ESCALATED" >&2
    update_state "escalated" "Handler/GateKeeper escalated this decision"
    return 2
  elif [[ $handler_exit -ne 0 ]]; then
    echo "[didio-run-pipeline] handler_gate: FAILED (exit=$handler_exit)" >&2
    update_state "failed" "Handler gate failed with exit $handler_exit"
    return 1
  fi

  echo "[didio-run-pipeline] handler_gate: PASSED" >&2
  return 0
}

# ── Stage 2: Architect ───────────────────────────────────────────────

run_architect() {
  if should_skip_for_resume "architect"; then
    echo "[didio-run-pipeline] architect: already completed (resume)" >&2
    return 0
  fi

  advance_stage "architect"
  STAGE_DETAIL="planning tasks and waves"
  update_state "running"

  # Prepare brief file
  local brief_file="$BRIEF"
  if [[ ! -f "$brief_file" ]]; then
    local tmp_brief="$PROJECT_ROOT/tasks/features/${FEATURE}-_tmp-brief.md"
    mkdir -p "$PROJECT_ROOT/tasks/features"
    echo "$BRIEF" > "$tmp_brief"
    brief_file="$tmp_brief"
  fi

  set +e
  "$DIDIO_HOME/bin/didio-spawn-agent.sh" architect "$FEATURE" "$brief_file"
  local arch_exit=$?
  set -e

  # Clean up temp brief
  [[ -f "$PROJECT_ROOT/tasks/features/${FEATURE}-_tmp-brief.md" ]] && \
    rm -f "$PROJECT_ROOT/tasks/features/${FEATURE}-_tmp-brief.md"

  if [[ $arch_exit -ne 0 ]]; then
    echo "[didio-run-pipeline] architect: FAILED (exit=$arch_exit)" >&2
    update_state "failed" "Architect failed with exit $arch_exit"
    return 1
  fi

  # Verify README was created
  resolve_readme
  if [[ -z "$FEATURE_README" || ! -f "$FEATURE_README" ]]; then
    echo "[didio-run-pipeline] architect: FAILED -- no README produced" >&2
    update_state "failed" "Architect did not produce $FEATURE-README.md"
    return 1
  fi

  echo "[didio-run-pipeline] architect: DONE" >&2
  return 0
}

# ── Stage 3: Readiness check ────────────────────────────────────────

run_readiness() {
  if should_skip_for_resume "readiness"; then
    echo "[didio-run-pipeline] readiness: already completed (resume)" >&2
    return 0
  fi

  advance_stage "readiness"

  if [[ "$SKIP_READINESS" -eq 1 ]]; then
    echo "[didio-run-pipeline] WARNING: Readiness gate bypassed via --skip-readiness" >&2
    update_state "running"
    return 0
  fi

  STAGE_DETAIL="pre-wave audit"
  update_state "running"

  resolve_readme

  set +e
  "$DIDIO_HOME/bin/didio-spawn-agent.sh" readiness "$FEATURE" "$FEATURE_README"
  local ready_exit=$?
  set -e

  if [[ $ready_exit -ne 0 ]]; then
    # Check if BLOCKED
    resolve_feature_dir
    local report="$FEATURE_DIR/readiness-report.md"
    if [[ -f "$report" ]] && grep -qE '^\*\*Verdict:\*\* BLOCKED' "$report" 2>/dev/null; then
      echo "[didio-run-pipeline] readiness: BLOCKED -- see $report" >&2
      update_state "failed" "Readiness audit verdict: BLOCKED"
      return 1
    fi
    echo "[didio-run-pipeline] readiness: FAILED (exit=$ready_exit)" >&2
    update_state "failed" "Readiness check failed with exit $ready_exit"
    return 1
  fi

  echo "[didio-run-pipeline] readiness: PASSED" >&2
  return 0
}

# ── Stage 4: TEA gate ────────────────────────────────────────────────

run_tea() {
  if should_skip_for_resume "tea"; then
    echo "[didio-run-pipeline] tea: already completed (resume)" >&2
    return 0
  fi

  advance_stage "tea"

  # Check if TEA is enabled in config
  local tea_enabled
  tea_enabled="$(didio_read_config_path 'tea.enabled' 'false')"

  if [[ "$tea_enabled" != "true" ]]; then
    echo "[didio-run-pipeline] tea: disabled in config, skipping" >&2
    update_state "running"
    return 0
  fi

  if [[ "$SKIP_TEA" -eq 1 ]]; then
    echo "[didio-run-pipeline] WARNING: TEA gate bypassed via --skip-tea" >&2
    update_state "running"
    return 0
  fi

  STAGE_DETAIL="test architect"
  update_state "running"

  resolve_readme

  set +e
  "$DIDIO_HOME/bin/didio-spawn-agent.sh" tea "$FEATURE" "$FEATURE_README"
  local tea_exit=$?
  set -e

  if [[ $tea_exit -ne 0 ]]; then
    echo "[didio-run-pipeline] tea: FAILED (exit=$tea_exit)" >&2
    update_state "failed" "TEA failed with exit $tea_exit"
    return 1
  fi

  echo "[didio-run-pipeline] tea: DONE" >&2
  return 0
}

# ── Stage 5: Waves ───────────────────────────────────────────────────

run_waves() {
  if should_skip_for_resume "waves"; then
    echo "[didio-run-pipeline] waves: already completed (resume)" >&2
    return 0
  fi

  advance_stage "waves"
  update_state "running"

  resolve_readme

  # Parse total waves from README
  local max_wave=0
  while IFS= read -r line; do
    local wn
    wn="$(echo "$line" | grep -oE '[Ww]ave[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1 || true)"
    if [[ -n "$wn" && "$wn" -gt "$max_wave" ]]; then
      max_wave="$wn"
    fi
  done < <(grep -iE 'wave[[:space:]]*[0-9]+' "$FEATURE_README" 2>/dev/null || true)

  TOTAL_WAVES=$((max_wave + 1))
  echo "[didio-run-pipeline] waves: $TOTAL_WAVES waves detected (0..$max_wave)" >&2

  local wave_num=0
  while [[ $wave_num -le $max_wave ]]; do
    CURRENT_WAVE=$wave_num
    STAGE_DETAIL="wave $wave_num of $((max_wave + 1))"
    update_state "running"

    echo "[didio-run-pipeline] waves: starting Wave $wave_num" >&2

    set +e
    "$DIDIO_HOME/bin/didio-run-wave.sh" "$FEATURE" "$wave_num" developer
    local wave_exit=$?
    set -e

    if [[ $wave_exit -ne 0 ]]; then
      echo "[didio-run-pipeline] waves: Wave $wave_num FAILED (exit=$wave_exit)" >&2
      update_state "failed" "Wave $wave_num failed with exit $wave_exit"
      return 1
    fi

    echo "[didio-run-pipeline] waves: Wave $wave_num completed" >&2

    # Check signals between waves
    if ! check_signals; then
      return 4
    fi

    # Check token budget between waves
    if ! check_token_budget; then
      return 3
    fi

    wave_num=$((wave_num + 1))
  done

  CURRENT_WAVE=null
  echo "[didio-run-pipeline] waves: ALL $TOTAL_WAVES waves completed" >&2
  return 0
}

# ── Stage 6: TechLead review ────────────────────────────────────────

run_techlead() {
  if should_skip_for_resume "techlead"; then
    echo "[didio-run-pipeline] techlead: already completed (resume)" >&2
    return 0
  fi

  advance_stage "techlead"
  STAGE_DETAIL="architecture review"
  update_state "running"

  resolve_readme

  set +e
  "$DIDIO_HOME/bin/didio-spawn-agent.sh" techlead "$FEATURE" "$FEATURE_README"
  local tl_exit=$?
  set -e

  if [[ $tl_exit -ne 0 ]]; then
    echo "[didio-run-pipeline] techlead: FAILED (exit=$tl_exit)" >&2
    update_state "failed" "TechLead review failed with exit $tl_exit"
    return 1
  fi

  echo "[didio-run-pipeline] techlead: PASSED" >&2
  return 0
}

# ── Stage 7: QA validation ──────────────────────────────────────────

run_qa() {
  if should_skip_for_resume "qa"; then
    echo "[didio-run-pipeline] qa: already completed (resume)" >&2
    return 0
  fi

  advance_stage "qa"
  STAGE_DETAIL="end-to-end validation"
  update_state "running"

  resolve_readme

  set +e
  "$DIDIO_HOME/bin/didio-spawn-agent.sh" qa "$FEATURE" "$FEATURE_README"
  local qa_exit=$?
  set -e

  if [[ $qa_exit -ne 0 ]]; then
    echo "[didio-run-pipeline] qa: FAILED (exit=$qa_exit)" >&2
    update_state "failed" "QA validation failed with exit $qa_exit"
    return 1
  fi

  echo "[didio-run-pipeline] qa: PASSED" >&2
  return 0
}

# ── Stage 8: Post-work review ───────────────────────────────────────

run_post_review() {
  if should_skip_for_resume "post_review"; then
    echo "[didio-run-pipeline] post_review: already completed (resume)" >&2
    return 0
  fi

  advance_stage "post_review"

  # Check config
  local post_review_enabled
  post_review_enabled="$(didio_read_config_path 'negotiation.post_work_review' 'true')"

  if [[ "$post_review_enabled" != "true" ]]; then
    echo "[didio-run-pipeline] post_review: disabled in config, skipping" >&2
    update_state "running"
    return 0
  fi

  if [[ "$SKIP_POST_REVIEW" -eq 1 ]]; then
    echo "[didio-run-pipeline] WARNING: Post-review gate bypassed via --skip-post-review" >&2
    update_state "running"
    return 0
  fi

  STAGE_DETAIL="post-work governance review"
  update_state "running"

  set +e
  "$DIDIO_HOME/bin/didio-post-review.sh" "$FEATURE"
  local pr_exit=$?
  set -e

  if [[ $pr_exit -eq 2 ]]; then
    echo "[didio-run-pipeline] post_review: ESCALATED" >&2
    update_state "escalated" "Post-work review escalated to human"
    return 2
  elif [[ $pr_exit -ne 0 ]]; then
    echo "[didio-run-pipeline] post_review: FAILED (exit=$pr_exit)" >&2
    update_state "failed" "Post-work review failed with exit $pr_exit"
    return 1
  fi

  echo "[didio-run-pipeline] post_review: APPROVED" >&2
  return 0
}

# ══════════════════════════════════════════════════════════════════════
# MAIN PIPELINE LOOP
# ══════════════════════════════════════════════════════════════════════

# Map stage names to functions
declare -A STAGE_FUNCTIONS=(
  [handler_gate]=run_handler_gate
  [architect]=run_architect
  [readiness]=run_readiness
  [tea]=run_tea
  [waves]=run_waves
  [techlead]=run_techlead
  [qa]=run_qa
  [post_review]=run_post_review
)

PIPELINE_EXIT=0

for stage in "${ALL_STAGES[@]}"; do
  # Check signals before each stage
  if ! check_signals; then
    PIPELINE_EXIT=4
    break
  fi

  # Check token budget before each stage
  if ! check_token_budget; then
    PIPELINE_EXIT=3
    break
  fi

  # Run the stage function
  stage_fn="${STAGE_FUNCTIONS[$stage]}"
  set +e
  "$stage_fn"
  stage_exit=$?
  set -e

  if [[ $stage_exit -ne 0 ]]; then
    PIPELINE_EXIT=$stage_exit
    break
  fi
done

# ── Finalize ─────────────────────────────────────────────────────────

if [[ $PIPELINE_EXIT -eq 0 ]]; then
  # Mark last stage as completed
  if [[ -n "${CURRENT_STAGE:-}" ]]; then
    STAGES_COMPLETED+=("$CURRENT_STAGE")
    CURRENT_STAGE=""
  fi
  STAGES_REMAINING=()
  update_state "completed"
  echo "[didio-run-pipeline] Pipeline COMPLETED successfully for $FEATURE" >&2
  echo "[didio-run-pipeline] State: $STATE_FILE" >&2
else
  echo "[didio-run-pipeline] Pipeline STOPPED for $FEATURE (exit=$PIPELINE_EXIT)" >&2
  echo "[didio-run-pipeline] State: $STATE_FILE" >&2
fi

exit $PIPELINE_EXIT
