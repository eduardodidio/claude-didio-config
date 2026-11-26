#!/usr/bin/env bash
# didio-flags-lib.sh — helper library for agents to raise/resolve flags.
# Source this file:  source "$DIDIO_HOME/bin/didio-flags-lib.sh"
#
# Functions:
#   didio_flag_raise  <feature> <type> [task] [message]
#   didio_flag_resolve <feature> <type> [task]
#   didio_flag_is_blocked <feature> [task]
#
# Flag types: blocked, needs_review, warning, info
# Flags are stored as JSON in logs/agents/flags/

_didio_flags_project_root() {
  if [[ -n "${DIDIO_PROJECT_ROOT:-}" ]]; then
    echo "$DIDIO_PROJECT_ROOT"
  elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    echo "$PROJECT_ROOT"
  else
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$script_dir/.." && pwd
  fi
}

_didio_flags_dir() {
  echo "$(_didio_flags_project_root)/logs/agents/flags"
}

# didio_flag_raise <feature> <type> [task] [message]
# Creates a flag JSON file in logs/agents/flags/
# Returns: the flag filename (without path)
didio_flag_raise() {
  local feature="${1:?feature-id required (e.g. F30)}"
  local flag_type="${2:?flag type required (blocked|needs_review|warning|info)}"
  local task="${3:-}"
  local message="${4:-}"

  local flags_dir
  flags_dir="$(_didio_flags_dir)"
  mkdir -p "$flags_dir"

  local now
  now="$(date -u +%FT%TZ)"
  local flag_id="${feature}_${flag_type}_$(date -u +%Y%m%d%H%M%S)_$$"
  local filename="${flag_id}.json"

  python3 -c "
import json, sys
d = {
    'flag_id': sys.argv[1],
    'feature': sys.argv[2],
    'type': sys.argv[3],
    'task': sys.argv[4] if sys.argv[4] else None,
    'message': sys.argv[5] if sys.argv[5] else None,
    'raised_at': sys.argv[6],
    'resolved_at': None
}
with open(sys.argv[7], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
" "$flag_id" "$feature" "$flag_type" "$task" "$message" "$now" "$flags_dir/$filename"

  echo "$filename"
}

# didio_flag_resolve <feature> <type> [task]
# Sets resolved_at on matching unresolved flags.
# Returns: number of flags resolved
didio_flag_resolve() {
  local feature="${1:?feature-id required}"
  local flag_type="${2:?flag type required}"
  local task="${3:-}"

  local flags_dir
  flags_dir="$(_didio_flags_dir)"
  if [[ ! -d "$flags_dir" ]]; then
    echo "0"
    return 0
  fi

  local count=0
  local now
  now="$(date -u +%FT%TZ)"

  for flag_file in "$flags_dir"/*.json; do
    [[ -f "$flag_file" ]] || continue

    local resolved
    resolved=$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
match = (d.get('feature') == sys.argv[2]
         and d.get('type') == sys.argv[3]
         and d.get('resolved_at') is None)
if sys.argv[4]:
    match = match and d.get('task') == sys.argv[4]
if match:
    d['resolved_at'] = sys.argv[5]
    with open(sys.argv[1], 'w', encoding='utf-8') as f:
        json.dump(d, f, indent=2)
    print('1')
else:
    print('0')
" "$flag_file" "$feature" "$flag_type" "$task" "$now" 2>/dev/null || echo "0")

    if [[ "$resolved" == "1" ]]; then
      count=$((count + 1))
    fi
  done

  echo "$count"
}

# didio_flag_is_blocked <feature> [task]
# Checks if there is an unresolved "blocked" flag for the given feature/task.
# Returns: exit code 0 if blocked, 1 if not blocked.
# Stdout: "true" or "false"
didio_flag_is_blocked() {
  local feature="${1:?feature-id required}"
  local task="${2:-}"

  local flags_dir
  flags_dir="$(_didio_flags_dir)"
  if [[ ! -d "$flags_dir" ]]; then
    echo "false"
    return 1
  fi

  for flag_file in "$flags_dir"/*.json; do
    [[ -f "$flag_file" ]] || continue

    local is_blocked
    is_blocked=$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
match = (d.get('feature') == sys.argv[2]
         and d.get('type') == 'blocked'
         and d.get('resolved_at') is None)
if sys.argv[3]:
    match = match and d.get('task') == sys.argv[3]
print('true' if match else 'false')
" "$flag_file" "$feature" "$task" 2>/dev/null || echo "false")

    if [[ "$is_blocked" == "true" ]]; then
      echo "true"
      return 0
    fi
  done

  echo "false"
  return 1
}

# If run directly (not sourced), expose a simple CLI
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    raise)    shift; didio_flag_raise "$@" ;;
    resolve)  shift; didio_flag_resolve "$@" ;;
    is-blocked) shift; didio_flag_is_blocked "$@" ;;
    *)
      echo "Usage: didio-flags-lib.sh <raise|resolve|is-blocked> [args...]" >&2
      echo "  raise    <feature> <type> [task] [message]" >&2
      echo "  resolve  <feature> <type> [task]" >&2
      echo "  is-blocked <feature> [task]" >&2
      exit 1
      ;;
  esac
fi
