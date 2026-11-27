#!/usr/bin/env bash
# lib/alert-engine.sh — Alert engine for the Black Hawk autonomous loop
#
# This library is sourced by bin/didio-blackhawk-auto.sh (F45-T04).
# It provides: alert_create, alert_list_pending, alert_approve,
#              alert_reject, alert_approve_all, alert_expire_stale.
#
# Dependencies:
#   - python3 (for JSON manipulation)
#   - DIDIO_PROJECT_ROOT must be set before sourcing
#
# Usage:
#   source "$PROJECT_ROOT/lib/alert-engine.sh"

# Guard: only source once
[[ -n "${_ALERT_ENGINE_LOADED:-}" ]] && return 0
_ALERT_ENGINE_LOADED=1

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

_AE_PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$PWD}"
_AE_ALERTS_DIR="$_AE_PROJECT_ROOT/logs/warroom/alerts"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_ae_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_ae_today() {
  date -u +"%Y%m%d"
}

# Ensure alerts directory exists
_ae_ensure_dir() {
  mkdir -p "$_AE_ALERTS_DIR" 2>/dev/null || true
}

# Generate next alert ID: ALT-YYYYMMDD-NNN
_ae_next_id() {
  _ae_ensure_dir
  local today
  today="$(_ae_today)"
  local max_seq=0

  for f in "$_AE_ALERTS_DIR"/ALT-"${today}"-*.json; do
    [[ -f "$f" ]] || continue
    local bname
    bname="$(basename "$f" .json)"
    # Extract NNN from ALT-YYYYMMDD-NNN
    local snum="${bname##*-}"
    if [[ "$snum" =~ ^[0-9]+$ ]]; then
      local n=$((10#$snum))
      if [[ $n -gt $max_seq ]]; then max_seq=$n; fi
    fi
  done

  local next_seq=$((max_seq + 1))
  printf 'ALT-%s-%03d' "$today" "$next_seq"
}

# ---------------------------------------------------------------------------
# alert_create(type, card_id, title, description, suggestion, confidence)
#
# Creates a new alert JSON file in logs/warroom/alerts/.
# Returns the alert_id on stdout.
#
# type: needs_approval|failed_pipeline|low_confidence|escalation
# confidence: float 0.0-1.0
# ---------------------------------------------------------------------------
alert_create() {
  local type="${1:?alert type required (needs_approval|failed_pipeline|low_confidence|escalation)}"
  local card_id="${2:-}"
  local title="${3:?alert title required}"
  local description="${4:-}"
  local suggestion="${5:-}"
  local confidence="${6:-0.5}"

  _ae_ensure_dir

  local alert_id
  alert_id="$(_ae_next_id)"
  local now
  now="$(_ae_now_iso)"
  local alert_file="$_AE_ALERTS_DIR/${alert_id}.json"

  python3 -c "
import json, sys

alert = {
    'alert_id': sys.argv[1],
    'type': sys.argv[2],
    'card_id': sys.argv[3],
    'title': sys.argv[4],
    'description': sys.argv[5],
    'suggestion': sys.argv[6],
    'confidence': float(sys.argv[7]),
    'created_at': sys.argv[8],
    'status': 'pending'
}

with open(sys.argv[9], 'w', encoding='utf-8') as f:
    json.dump(alert, f, indent=2)
    f.write('\n')
" "$alert_id" "$type" "$card_id" "$title" "$description" "$suggestion" "$confidence" "$now" "$alert_file"

  echo "$alert_id"
}

# ---------------------------------------------------------------------------
# alert_list_pending()
#
# Lists all pending alerts as a JSON array on stdout.
# ---------------------------------------------------------------------------
alert_list_pending() {
  _ae_ensure_dir

  python3 -c "
import json, os, glob, sys

alerts_dir = sys.argv[1]
pattern = os.path.join(alerts_dir, 'ALT-*.json')
pending = []

for fpath in sorted(glob.glob(pattern)):
    try:
        with open(fpath, 'r', encoding='utf-8') as f:
            alert = json.load(f)
        if alert.get('status') == 'pending':
            pending.append(alert)
    except (json.JSONDecodeError, IOError):
        continue

print(json.dumps(pending, indent=2))
" "$_AE_ALERTS_DIR"
}

# ---------------------------------------------------------------------------
# alert_approve(alert_id)
#
# Approves an alert by ID:
# 1. Reads the alert JSON
# 2. Executes the suggestion command (only if it starts with 'didio ')
# 3. Updates alert status to 'approved'
# 4. Writes updated JSON back
#
# Returns 0 on success, 1 on error.
# ---------------------------------------------------------------------------
alert_approve() {
  local alert_id="${1:?alert_id required}"
  local alert_file="$_AE_ALERTS_DIR/${alert_id}.json"

  if [[ ! -f "$alert_file" ]]; then
    echo "[alert-engine] ERROR: alert '$alert_id' not found at $alert_file" >&2
    return 1
  fi

  # Read alert data
  local status suggestion
  status="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('status', ''))
" "$alert_file" 2>/dev/null)"

  if [[ "$status" != "pending" ]]; then
    echo "[alert-engine] WARN: alert '$alert_id' is not pending (status=$status), skipping" >&2
    return 1
  fi

  suggestion="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('suggestion', ''))
" "$alert_file" 2>/dev/null)"

  # Safety: only execute suggestions that start with 'didio '
  local exec_result=0
  if [[ -n "$suggestion" ]]; then
    if [[ "$suggestion" == didio\ * ]]; then
      echo "[alert-engine] Executing suggestion: $suggestion" >&2
      set +e
      eval "$suggestion" 2>&1
      exec_result=$?
      set -e
      if [[ $exec_result -ne 0 ]]; then
        echo "[alert-engine] WARN: suggestion command exited with code $exec_result" >&2
      fi
    else
      echo "[alert-engine] SAFETY: refusing to execute suggestion that does not start with 'didio ': $suggestion" >&2
      exec_result=2
    fi
  fi

  # Update alert status to approved
  local now
  now="$(_ae_now_iso)"

  python3 -c "
import json, sys

alert_file = sys.argv[1]
now = sys.argv[2]
exec_result = int(sys.argv[3])

with open(alert_file, 'r', encoding='utf-8') as f:
    d = json.load(f)

d['status'] = 'approved'
d['approved_at'] = now
d['exec_exit_code'] = exec_result

with open(alert_file, 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$alert_file" "$now" "$exec_result"

  echo "[alert-engine] Alert $alert_id approved" >&2
  return 0
}

# ---------------------------------------------------------------------------
# alert_reject(alert_id)
#
# Rejects an alert by ID: marks status as 'rejected'.
# ---------------------------------------------------------------------------
alert_reject() {
  local alert_id="${1:?alert_id required}"
  local alert_file="$_AE_ALERTS_DIR/${alert_id}.json"

  if [[ ! -f "$alert_file" ]]; then
    echo "[alert-engine] ERROR: alert '$alert_id' not found at $alert_file" >&2
    return 1
  fi

  local now
  now="$(_ae_now_iso)"

  python3 -c "
import json, sys

alert_file = sys.argv[1]
now = sys.argv[2]

with open(alert_file, 'r', encoding='utf-8') as f:
    d = json.load(f)

d['status'] = 'rejected'
d['rejected_at'] = now

with open(alert_file, 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$alert_file" "$now"

  echo "[alert-engine] Alert $alert_id rejected" >&2
  return 0
}

# ---------------------------------------------------------------------------
# alert_approve_all()
#
# Approves ALL pending alerts. Returns count of approved alerts on stdout.
# ---------------------------------------------------------------------------
alert_approve_all() {
  _ae_ensure_dir

  local count=0
  for alert_file in "$_AE_ALERTS_DIR"/ALT-*.json; do
    [[ -f "$alert_file" ]] || continue

    local status
    status="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('status', ''))
" "$alert_file" 2>/dev/null)"

    if [[ "$status" == "pending" ]]; then
      local alert_id
      alert_id="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('alert_id', ''))
" "$alert_file" 2>/dev/null)"

      if [[ -n "$alert_id" ]]; then
        alert_approve "$alert_id" || true
        count=$((count + 1))
      fi
    fi
  done

  echo "$count"
}

# ---------------------------------------------------------------------------
# alert_expire_stale(max_age_hours)
#
# Expires pending alerts older than max_age_hours.
# Returns count of expired alerts on stdout.
# ---------------------------------------------------------------------------
alert_expire_stale() {
  local max_age_hours="${1:-24}"

  _ae_ensure_dir

  local now
  now="$(_ae_now_iso)"
  local count=0

  python3 -c "
import json, os, glob, sys
from datetime import datetime, timedelta, timezone

alerts_dir = sys.argv[1]
max_hours = float(sys.argv[2])
now_str = sys.argv[3]

now = datetime.fromisoformat(now_str.replace('Z', '+00:00'))
cutoff = now - timedelta(hours=max_hours)

pattern = os.path.join(alerts_dir, 'ALT-*.json')
expired_count = 0

for fpath in sorted(glob.glob(pattern)):
    try:
        with open(fpath, 'r', encoding='utf-8') as f:
            alert = json.load(f)
    except (json.JSONDecodeError, IOError):
        continue

    if alert.get('status') != 'pending':
        continue

    created_str = alert.get('created_at', '')
    if not created_str:
        continue

    try:
        created = datetime.fromisoformat(created_str.replace('Z', '+00:00'))
    except ValueError:
        continue

    if created < cutoff:
        alert['status'] = 'expired'
        alert['expired_at'] = now_str
        with open(fpath, 'w', encoding='utf-8') as f:
            json.dump(alert, f, indent=2)
            f.write('\n')
        expired_count += 1

print(expired_count)
" "$_AE_ALERTS_DIR" "$max_age_hours" "$now"
}
