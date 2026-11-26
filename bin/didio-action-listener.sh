#!/usr/bin/env bash
# didio-action-listener.sh — polls logs/agents/actions/ for operator actions
# Usage: didio-action-listener.sh [--interval SECS] [--once]
#   --interval SECS  polling interval (default: 5)
#   --once           process pending actions and exit (no loop)

set -euo pipefail

# --- Dependency check ---
# We use python3 for JSON parsing instead of jq — python3 is already
# a framework requirement so this avoids adding an extra dependency.
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required but not found. The didio framework requires Python 3." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ACTIONS_DIR="$PROJECT_ROOT/logs/agents/actions"
ARCHIVE_DIR="$ACTIONS_DIR/archive"
FLAGS_DIR="$PROJECT_ROOT/logs/agents/flags"
POLL_INTERVAL=5
RUN_ONCE=false

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval) POLL_INTERVAL="$2"; shift 2 ;;
    --once)     RUN_ONCE=true; shift ;;
    *)          echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Ensure directories
mkdir -p "$ACTIONS_DIR" "$ARCHIVE_DIR" "$FLAGS_DIR"

# --- JSON helpers (python3-based) ---

# Read a field from a JSON file. Usage: _json_get <file> <field> [default]
_json_get() {
  local file="$1" field="$2" default="${3:-}"
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
val = d.get(sys.argv[2])
if val is None:
    print(sys.argv[3] if len(sys.argv) > 3 else '')
else:
    print(val)
" "$file" "$field" "$default" 2>/dev/null || echo "$default"
}

# Add fields to a JSON file and write to a new path.
# Usage: _json_add_fields <input> <output> key1=val1 key2=val2 ...
_json_add_fields() {
  local input="$1" output="$2"
  shift 2
  local pairs=""
  for kv in "$@"; do
    local k="${kv%%=*}"
    local v="${kv#*=}"
    pairs="${pairs}, \"$k\": \"$v\""
  done
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
pairs_raw = sys.argv[3]
if pairs_raw:
    import ast
    # Parse the extra k/v from args
    for i in range(3, len(sys.argv), 2):
        d[sys.argv[i]] = sys.argv[i+1]
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
" "$input" "$output" "${@}"
}

# Simpler: add processed_status and processed_at to a JSON file
_json_archive() {
  local input="$1" output="$2" status="$3" processed_at="$4"
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
d['processed_status'] = sys.argv[3]
d['processed_at'] = sys.argv[4]
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
" "$input" "$output" "$status" "$processed_at"
}

# Set resolved_at on a flag JSON file
_json_set_resolved() {
  local flag_file="$1" now="$2"
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
d['resolved_at'] = sys.argv[2]
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
" "$flag_file" "$now"
}

# --- Action handlers ---

_resolve_flags() {
  local feature="$1" task="$2" flag_type="$3"
  if [[ ! -d "$FLAGS_DIR" ]]; then return 0; fi

  for flag_file in "$FLAGS_DIR"/*.json; do
    [[ -f "$flag_file" ]] || continue
    local f_feature f_type f_task f_resolved
    f_feature=$(_json_get "$flag_file" "feature")
    f_type=$(_json_get "$flag_file" "type")
    f_task=$(_json_get "$flag_file" "task")
    f_resolved=$(_json_get "$flag_file" "resolved_at")

    # Skip already-resolved flags
    if [[ -n "$f_resolved" ]]; then continue; fi

    if [[ "$f_feature" == "$feature" && "$f_type" == "$flag_type" ]]; then
      if [[ -z "$task" || "$f_task" == "$task" ]]; then
        local now
        now="$(date -u +%FT%TZ)"
        _json_set_resolved "$flag_file" "$now"
        echo "  Resolved flag: $(basename "$flag_file")"
      fi
    fi
  done
}

_write_skip_marker() {
  local feature="$1" task="$2"
  local now
  now="$(date -u +%FT%TZ)"
  local marker_file="$ARCHIVE_DIR/skip_${feature}_${task}_$(date -u +%Y%m%d%H%M%S).marker"
  python3 -c "
import json, sys
d = {'type': 'skip', 'feature': sys.argv[1], 'task': sys.argv[2], 'at': sys.argv[3]}
with open(sys.argv[4], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
" "$feature" "$task" "$now" "$marker_file"
  echo "  Skip marker written for $feature/$task"
}

_write_pipeline_control() {
  local feature="$1" desired_state="$2"
  local now
  now="$(date -u +%FT%TZ)"
  local control_file="$PROJECT_ROOT/logs/agents/pipeline-${feature}.control.json"
  python3 -c "
import json, sys
d = {'feature': sys.argv[1], 'desired_state': sys.argv[2], 'at': sys.argv[3]}
with open(sys.argv[4], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
" "$feature" "$desired_state" "$now" "$control_file"
  echo "  Pipeline control: $feature -> $desired_state"
}

process_action() {
  local file="$1"
  local action_id action feature task

  # Parse JSON fields
  action_id=$(_json_get "$file" "action_id")
  action=$(_json_get "$file" "action")
  feature=$(_json_get "$file" "feature")
  task=$(_json_get "$file" "task")

  echo "[$(date -u +%FT%TZ)] Processing action=$action feature=$feature task=$task id=$action_id"

  local exit_code=0
  case "$action" in
    unblock)
      # Remove the blocked flag for this feature/task
      _resolve_flags "$feature" "$task" "blocked"
      ;;
    approve)
      # Mark needs_review flags as resolved
      _resolve_flags "$feature" "$task" "needs_review"
      ;;
    skip)
      # Write a skip marker for the task
      _write_skip_marker "$feature" "$task"
      ;;
    pause)
      # Write a pause marker for the pipeline
      _write_pipeline_control "$feature" "paused"
      ;;
    resume)
      # Remove pause marker
      _write_pipeline_control "$feature" "running"
      ;;
    cancel)
      # Write cancel marker
      _write_pipeline_control "$feature" "cancelled"
      ;;
    *)
      echo "  WARNING: unknown action '$action' -- archiving without processing" >&2
      exit_code=1
      ;;
  esac

  # Archive the action file
  local archive_name="${action_id}_$(date -u +%Y%m%d%H%M%S).json"
  local status
  if [ $exit_code -eq 0 ]; then status="completed"; else status="failed"; fi
  local processed_at
  processed_at="$(date -u +%FT%TZ)"

  _json_archive "$file" "$ARCHIVE_DIR/$archive_name" "$status" "$processed_at"
  rm -f "$file"

  echo "  Archived to $archive_name (status=$status)"
  return $exit_code
}

# --- Main loop ---

poll_cycle() {
  local found=0
  for action_file in "$ACTIONS_DIR"/*.json; do
    [[ -f "$action_file" ]] || continue
    process_action "$action_file" || true
    found=$((found + 1))
  done
  return 0
}

echo "=== Didio Action Listener ==="
echo "  Actions dir: $ACTIONS_DIR"
echo "  Poll interval: ${POLL_INTERVAL}s"
echo "  Mode: $([ "$RUN_ONCE" = true ] && echo 'single-pass' || echo 'continuous')"

if [ "$RUN_ONCE" = true ]; then
  poll_cycle
else
  while true; do
    poll_cycle
    sleep "$POLL_INTERVAL"
  done
fi
