#!/usr/bin/env bash
# didio-run-wave.sh — run all tasks of a given Wave in parallel.
#
# Usage:
#   didio-run-wave.sh <feature-id> <wave-number> [role]
#
# Reads tasks/features/<feature>-*/<feature>-README.md and finds the line:
#   Wave <N>: <task-id>, <task-id>, ...
# Then for each task-id spawns a didio-spawn-agent in background. Waits for
# all to finish, exits non-zero if any failed.
#
# Role defaults to 'developer' (the typical case for Waves). For Wave 0
# (setup/permissions) the orchestrator usually calls this with role=architect
# or skips and runs a single architect pass beforehand.

set -euo pipefail

FEATURE="${1:?feature-id required (e.g. F01)}"
WAVE="${2:?wave-number required (e.g. 1)}"
ROLE="${3:-developer}"

PROJECT_ROOT="$(pwd)"

# Load config lib early so didio_find_feature_dir is available
source "${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-config-lib.sh"

FEATURE_DIR=$(didio_find_feature_dir "$FEATURE") || {
  echo "[didio-run-wave] feature directory not found: tasks/features/${FEATURE}-*" >&2
  exit 2
}

README="$FEATURE_DIR/${FEATURE}-README.md"
if [[ ! -f "$README" ]]; then
  echo "[didio-run-wave] feature README not found: $README" >&2
  exit 2
fi

# Extract tasks for the given wave. Expected lines in the README:
#   - **Wave 0**: F01-T01, F01-T02
#   - **Wave 1**: F01-T03, F01-T04, F01-T05
WAVE_LINE=$(grep -iE "wave[[:space:]]*${WAVE}[^0-9]" "$README" | head -n1 || true)
if [[ -z "$WAVE_LINE" ]]; then
  echo "[didio-run-wave] no tasks found for Wave $WAVE in $README" >&2
  exit 2
fi

# Pull out FXX-TYY tokens from the line
TASK_IDS=$(echo "$WAVE_LINE" | grep -oE "${FEATURE}-T[0-9]+" | sort -u)
if [[ -z "$TASK_IDS" ]]; then
  echo "[didio-run-wave] Wave $WAVE line parsed but no task ids matched pattern ${FEATURE}-TYY" >&2
  echo "[didio-run-wave] line was: $WAVE_LINE" >&2
  exit 2
fi

# Load config lib for parallelism and turbo/highlander settings (already sourced above)
MAX_PARALLEL=$(didio_max_parallel)
MAX_PARALLEL_LABEL=$([[ "$MAX_PARALLEL" -eq 0 ]] && echo "ilimitado" || echo "$MAX_PARALLEL")

# Turbo + Highlander: activate Claude Code Auto Mode for unattended Waves
if [[ "$(didio_is_turbo)" == "true" && "$(didio_is_highlander)" == "true" ]]; then
  HIGHLANDER_SRC="$PROJECT_ROOT/.claude/settings.highlander.json"
  SETTINGS_DST="$PROJECT_ROOT/.claude/settings.json"
  if [[ -f "$HIGHLANDER_SRC" ]]; then
    cp "$HIGHLANDER_SRC" "$SETTINGS_DST"
    echo "[didio-run-wave] TURBO+HIGHLANDER: Auto Mode activated via defaultMode=auto" >&2
  fi
fi

echo "[didio-run-wave] feature=$FEATURE wave=$WAVE role=$ROLE max_parallel=$MAX_PARALLEL_LABEL tasks=$(echo $TASK_IDS | tr '\n' ' ')" >&2

PROGRESS_LIB="${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-progress-lib.sh"
if [[ -f "$PROGRESS_LIB" ]]; then
  # shellcheck disable=SC1090
  source "$PROGRESS_LIB"
  didio_feature_progress "$FEATURE" >&2 || true
fi

PIDS=()
FAILED=()

for TID in $TASK_IDS; do
  TASK_FILE="$FEATURE_DIR/${TID}.md"
  if [[ ! -f "$TASK_FILE" ]]; then
    echo "[didio-run-wave] task file missing, skipping: $TASK_FILE" >&2
    FAILED+=("$TID:missing")
    continue
  fi

  # Semaphore: if at max, wait for a slot to free up
  if [[ "$MAX_PARALLEL" -gt 0 ]]; then
    while [[ $(jobs -rp | wc -l) -ge $MAX_PARALLEL ]]; do
      sleep 1
    done
  fi

  (
    "$DIDIO_HOME/bin/didio-spawn-agent.sh" "$ROLE" "$FEATURE" "$TASK_FILE" \
      "This task is part of Wave $WAVE. Other tasks in this Wave run concurrently — do not touch their files."
  ) &
  PIDS+=($!)
done

# Wait for all, collect failures
for PID in "${PIDS[@]}"; do
  if ! wait "$PID"; then
    FAILED+=("pid:$PID")
  fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "[didio-run-wave] Wave $WAVE failed: ${FAILED[*]}" >&2
  exit 1
fi

echo "[didio-run-wave] Wave $WAVE completed: $(echo $TASK_IDS | wc -w | tr -d ' ') tasks" >&2

# Post-Wave summary (F12) — opt-in via sharding.wave_summary, default true.
# Failure to write the summary is non-blocking — Wave N+1 simply lacks
# carry-forward. Log a warning and continue.
WAVE_SUMMARY_ENABLED="$(didio_read_config_path sharding.wave_summary true 2>/dev/null || echo "true")"
if [[ "$WAVE_SUMMARY_ENABLED" == "true" ]]; then
  SUMMARY_OUT="$FEATURE_DIR/${FEATURE}-wave-${WAVE}-summary.md"
  # Use the feature README as the "task file" pointer — TechLead in
  # wave-summary mode reads README + task files of the wave + git diff,
  # not this file's body. Path just needs to exist + be readable.
  if [[ -x "$DIDIO_HOME/bin/didio-spawn-agent.sh" ]]; then
    echo "[didio-run-wave] post-Wave summary: spawning techlead for Wave $WAVE" >&2
    set +e
    "$DIDIO_HOME/bin/didio-spawn-agent.sh" techlead "$FEATURE" "$README" \
      "MODE=wave-summary FEATURE=$FEATURE WAVE=$WAVE"
    SUMMARY_EXIT=$?
    set -e
    if [[ $SUMMARY_EXIT -ne 0 ]]; then
      echo "[didio-run-wave] WARN: wave-summary spawn exited $SUMMARY_EXIT (non-blocking)" >&2
    elif [[ ! -f "$SUMMARY_OUT" ]]; then
      echo "[didio-run-wave] WARN: techlead returned 0 but summary file absent: $SUMMARY_OUT" >&2
    else
      echo "[didio-run-wave] wave-summary written: $SUMMARY_OUT" >&2
    fi
  else
    echo "[didio-run-wave] WARN: spawn-agent.sh not found, skipping wave-summary" >&2
  fi
fi

if declare -f didio_feature_progress >/dev/null 2>&1; then
  didio_feature_progress "$FEATURE" >&2 || true
fi
