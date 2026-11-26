#!/usr/bin/env bash
# didio-pipeline-status.sh — Show status of active pipelines
#
# Usage:
#   didio pipeline-status              List all active pipelines
#   didio pipeline-status <feature-id> Show detailed status for one pipeline
#
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
source "$DIDIO_HOME/bin/didio-config-lib.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
STATE_DIR="$PROJECT_ROOT/logs/agents"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Portable elapsed-time calculation.
elapsed_human() {
  local started="$1"
  python3 - "$started" <<'PY' 2>/dev/null || echo "?"
import datetime, sys
try:
    raw = sys.argv[1]
    s = raw.replace('Z','+00:00')
    try:
        start = datetime.datetime.fromisoformat(s)
    except Exception:
        start = datetime.datetime.strptime(raw, '%Y-%m-%dT%H:%M:%S')
        start = start.replace(tzinfo=datetime.timezone.utc)
    now = datetime.datetime.now(datetime.timezone.utc)
    delta = now - start
    total_min = int(delta.total_seconds() / 60)
    if total_min < 60:
        print(f'{total_min}m')
    else:
        h = total_min // 60
        m = total_min % 60
        print(f'{h}h {m}m')
except Exception:
    print('?')
PY
}

# Read a key from a JSON file via python3.
json_get() {
  local file="$1" key="$2" default="${3:-}"
  python3 - "$file" "$key" "$default" <<'PY' 2>/dev/null || echo "$default"
import json, sys, os
fpath, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
# Resolve MSYS/cygwin paths for python on Windows
if not os.path.exists(fpath) and fpath.startswith('/'):
    # Try converting /c/... to C:/...
    import re
    m = re.match(r'^/([a-zA-Z])/(.*)', fpath)
    if m:
        fpath = m.group(1).upper() + ':/' + m.group(2)
try:
    with open(fpath) as f:
        d = json.load(f)
    v = d.get(key)
    if v is None:
        print(default)
    elif isinstance(v, list):
        print(json.dumps(v))
    elif isinstance(v, bool):
        print('true' if v else 'false')
    else:
        print(v)
except Exception:
    print(default)
PY
}

json_get_array() {
  local file="$1" key="$2"
  python3 - "$file" "$key" <<'PY' 2>/dev/null || true
import json, sys, os, re
fpath, key = sys.argv[1], sys.argv[2]
if not os.path.exists(fpath) and fpath.startswith('/'):
    m = re.match(r'^/([a-zA-Z])/(.*)', fpath)
    if m:
        fpath = m.group(1).upper() + ':/' + m.group(2)
with open(fpath) as f:
    d = json.load(f)
for item in d.get(key, []):
    print(item)
PY
}

# Check whether a pause signal exists for a feature.
has_pause_signal() {
  local fxx="$1"
  local signal_dir
  signal_dir="$(didio_pipeline_signal_dir)"
  [[ -f "$PROJECT_ROOT/$signal_dir/${fxx}.pause" ]]
}

# ---------------------------------------------------------------------------
# Detail mode — single pipeline
# ---------------------------------------------------------------------------
show_detail() {
  local fxx="$1"
  local state_file="$STATE_DIR/pipeline-${fxx}.state.json"

  if [[ ! -f "$state_file" ]]; then
    echo "No pipeline state found for $fxx" >&2
    exit 1
  fi

  local feature status stage stage_detail started paused_at resume_from
  local current_wave total_waves error_msg

  feature="$(json_get "$state_file" feature "$fxx")"
  status="$(json_get "$state_file" status "unknown")"
  stage="$(json_get "$state_file" stage "")"
  stage_detail="$(json_get "$state_file" stage_detail "")"
  started="$(json_get "$state_file" started_at "")"
  paused_at="$(json_get "$state_file" paused_at "")"
  resume_from="$(json_get "$state_file" resume_from "")"
  current_wave="$(json_get "$state_file" current_wave "")"
  total_waves="$(json_get "$state_file" total_waves "")"
  error_msg="$(json_get "$state_file" error "")"

  local elapsed=""
  if [[ -n "$started" && "$started" != "null" ]]; then
    elapsed="$(elapsed_human "$started")"
  fi

  # Header
  echo "Pipeline: $feature"
  echo "Status: $status"
  if [[ -n "$stage" && "$stage" != "null" ]]; then
    if [[ -n "$stage_detail" && "$stage_detail" != "null" ]]; then
      echo "Stage: $stage ($stage_detail)"
    else
      echo "Stage: $stage"
    fi
  fi
  if [[ -n "$started" && "$started" != "null" ]]; then
    echo "Started: $started ($elapsed ago)"
  fi
  if [[ -n "$paused_at" && "$paused_at" != "null" ]]; then
    echo "Paused at: $paused_at"
  fi
  if [[ -n "$resume_from" && "$resume_from" != "null" ]]; then
    echo "Resume from: $resume_from"
  fi
  if [[ -n "$error_msg" && "$error_msg" != "null" ]]; then
    echo "Error: $error_msg"
  fi

  # Signal state
  if has_pause_signal "$fxx"; then
    echo "Signal: PAUSE pending"
  fi
  local signal_dir
  signal_dir="$(didio_pipeline_signal_dir)"
  if [[ -f "$PROJECT_ROOT/$signal_dir/${fxx}.cancel" ]]; then
    echo "Signal: CANCEL pending"
  fi

  echo ""

  # Stage list
  local all_stages=(handler_gate architect readiness tea waves techlead qa post_review)
  local completed_stages
  completed_stages="$(json_get_array "$state_file" stages_completed)"

  echo "Completed stages:"
  for s in "${all_stages[@]}"; do
    local marker="  "
    local suffix=""

    # Check if completed
    if echo "$completed_stages" | grep -qx "$s"; then
      marker="OK"
      printf "  [%s] %s\n" "$marker" "$s"
      continue
    fi

    # Check if currently running
    if [[ "$s" == "$stage" && "$status" == "running" ]]; then
      marker=".."
      if [[ -n "$stage_detail" && "$stage_detail" != "null" ]]; then
        suffix=" (running, $stage_detail)"
      else
        suffix=" (running)"
      fi
      printf "  [%s] %s%s\n" "$marker" "$s" "$suffix"
      continue
    fi

    # Check if this is the paused stage
    if [[ "$s" == "$stage" && "$status" == "paused" ]]; then
      marker="||"
      suffix=" (paused)"
      printf "  [%s] %s%s\n" "$marker" "$s" "$suffix"
      continue
    fi

    # Check if this is the failed stage
    if [[ "$s" == "$stage" && "$status" == "failed" ]]; then
      marker="!!"
      suffix=" (failed)"
      printf "  [%s] %s%s\n" "$marker" "$s" "$suffix"
      continue
    fi

    # Pending
    printf "  [%s] %s\n" "$marker" "$s"
  done
}

# ---------------------------------------------------------------------------
# List mode — all pipelines
# ---------------------------------------------------------------------------
show_list() {
  local state_files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && state_files+=("$f")
  done < <(find "$STATE_DIR" -maxdepth 1 -name "pipeline-*.state.json" 2>/dev/null | sort)

  if [[ ${#state_files[@]} -eq 0 ]]; then
    echo "No active pipelines"
    return 0
  fi

  # Print header
  printf "%-10s %-18s %-12s %-22s %s\n" "Feature" "Stage" "Status" "Started" "Duration"
  printf "%-10s %-18s %-12s %-22s %s\n" "-------" "-----" "------" "-------" "--------"

  for state_file in "${state_files[@]}"; do
    local feature status stage stage_detail started elapsed signal_note=""

    feature="$(json_get "$state_file" feature "?")"
    status="$(json_get "$state_file" status "?")"
    stage="$(json_get "$state_file" stage "?")"
    stage_detail="$(json_get "$state_file" stage_detail "")"
    started="$(json_get "$state_file" started_at "")"

    # Build stage display
    local stage_display="$stage"
    if [[ -n "$stage_detail" && "$stage_detail" != "null" ]]; then
      stage_display="$stage ($stage_detail)"
    fi

    # Elapsed time
    elapsed="?"
    if [[ -n "$started" && "$started" != "null" ]]; then
      elapsed="$(elapsed_human "$started")"
    fi

    # Check for pending signals
    if has_pause_signal "$feature"; then
      signal_note=" [pause pending]"
    fi
    local signal_dir
    signal_dir="$(didio_pipeline_signal_dir)"
    if [[ -f "$PROJECT_ROOT/$signal_dir/${feature}.cancel" ]]; then
      signal_note=" [cancel pending]"
    fi

    # Trim started to date+time for display
    local started_display="$started"
    if [[ -n "$started" && "$started" != "null" ]]; then
      started_display="${started%%T*} ${started#*T}"
      started_display="${started_display%%Z*}"
      started_display="${started_display%%+*}"
      # Truncate to seconds
      started_display="${started_display:0:19}"
    fi

    printf "%-10s %-18s %-12s %-22s %s%s\n" \
      "$feature" "$stage_display" "$status" "$started_display" "$elapsed" "$signal_note"
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
FXX="${1:-}"

if [[ -n "$FXX" ]]; then
  show_detail "$FXX"
else
  show_list
fi
