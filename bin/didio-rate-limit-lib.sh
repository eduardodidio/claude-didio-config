#!/usr/bin/env bash
# didio-rate-limit-lib.sh — F22 — single source of truth for
# rate-limit detection, reset-time parsing, and pending-job persistence.
# Sourced by didio-spawn-agent.sh and didio-resume-pending.sh.
# See: tasks/features/F22-rate-limit-auto-resume/F22-T02.md
#      docs/adr/0014-rate-limit-auto-resume.md

set -euo pipefail

DIDIO_RL_MARGIN_SEC="${DIDIO_RATE_LIMIT_MARGIN_SEC:-60}"
DIDIO_RL_MAX_RETRIES="${DIDIO_MAX_RETRIES:-3}"
DIDIO_RL_ENV_WHITELIST_REGEX='^(DIDIO_|ANTHROPIC_|DISCORD_|PATH$|HOME$|TZ$|LANG$|LC_)'

# ── 1. didio_rl_classify_jsonl ────────────────────────────────────────────────
# Purpose: Read last result event from a JSONL log; return rate_limit|real_error|success|unknown.
# Returns: Classification string on stdout; always exits 0.
didio_rl_classify_jsonl() {
  local log_file="${1:-}"

  if [[ -z "$log_file" || ! -f "$log_file" ]]; then
    echo "unknown"
    return 0
  fi

  local last_result=""
  last_result="$(tail -n 50 "$log_file" | grep '"type":"result"' 2>/dev/null | tail -n 1)" || true

  if [[ -z "$last_result" ]]; then
    echo "unknown"
    return 0
  fi

  local class=""
  class="$(RL_LINE="$last_result" python3 - <<'PYEOF' 2>/dev/null
import json, os, sys
try:
    data = json.loads(os.environ.get("RL_LINE", ""))
except Exception:
    print("unknown")
    sys.exit(0)
is_error = data.get("is_error", False)
result_text = str(data.get("result", ""))
api_status = str(data.get("api_error_status", ""))
if not is_error:
    print("success")
elif "hit your limit" in result_text or "rate_limit" in result_text or api_status == "429":
    print("rate_limit")
else:
    print("real_error")
PYEOF
  )" || class="unknown"

  echo "${class:-unknown}"
  return 0
}

# ── 2. didio_rl_parse_reset_to_unix ──────────────────────────────────────────
# Purpose: Parse a rate-limit reset time string (or JSONL log) to a UTC Unix epoch.
# Returns: Epoch seconds on stdout; always exits 0 (falls back to now+5h on failure).
didio_rl_parse_reset_to_unix() {
  local input="${1:-}"
  local text=""

  if [[ -n "$input" && -f "$input" ]]; then
    local last_result=""
    last_result="$(tail -n 50 "$input" | grep '"type":"result"' 2>/dev/null | tail -n 1)" || true

    if [[ -z "$last_result" ]]; then
      echo "$(( $(date +%s) + 5*3600 ))"
      echo "[didio-rl] WARN: no result event in \"$input\", falling back to +5h" >&2
      return 0
    fi

    local extract_exit=0
    text="$(RL_LINE="$last_result" python3 -c \
      'import json,os; data=json.loads(os.environ.get("RL_LINE","{}")); print(data.get("result",""))' \
      2>/dev/null)" || extract_exit=$?

    if [[ $extract_exit -ne 0 || -z "$text" ]]; then
      echo "$(( $(date +%s) + 5*3600 ))"
      echo "[didio-rl] WARN: could not extract result text from \"$input\", falling back to +5h" >&2
      return 0
    fi
  else
    text="$input"
  fi

  local epoch=""
  local py_exit=0
  epoch="$(RL_TEXT="$text" python3 - <<'PYEOF' 2>/dev/null
import os, re, sys
from datetime import datetime, timedelta

text = os.environ.get("RL_TEXT", "")
m = re.search(r'resets\s+(\d{1,2}:\d{2})(am|pm)?\s*\(([^)]+)\)', text, re.IGNORECASE)
if not m:
    sys.exit(1)

time_str = m.group(1)
ampm = (m.group(2) or "").lower()
tz_name = m.group(3).strip()

hour, minute = map(int, time_str.split(":"))
if ampm == "pm" and hour != 12:
    hour += 12
elif ampm == "am" and hour == 12:
    hour = 0

try:
    from zoneinfo import ZoneInfo
    tz = ZoneInfo(tz_name)
except Exception:
    sys.exit(2)

now_in_tz = datetime.now(tz)
candidate = now_in_tz.replace(hour=hour, minute=minute, second=0, microsecond=0)
if candidate <= now_in_tz:
    candidate += timedelta(days=1)

print(int(candidate.timestamp()))
PYEOF
  )" || py_exit=$?

  if [[ $py_exit -ne 0 || -z "$epoch" ]]; then
    echo "$(( $(date +%s) + 5*3600 ))"
    echo "[didio-rl] WARN: parse failed for \"$text\", falling back to +5h" >&2
    return 0
  fi

  echo "$epoch"
  return 0
}

# ── 3. didio_rl_persist_pending ───────────────────────────────────────────────
# Purpose: Atomically write a pending-job JSON file to <pending_dir>/<id>.json.
# Returns: 0 on success; non-zero if JSON is invalid or write fails.
didio_rl_persist_pending() {
  local pending_dir="${1:?pending_dir required}"
  local id="${2:?id required}"
  local json_blob="${3:?json_blob required}"

  if ! printf '%s' "$json_blob" | python3 -m json.tool > /dev/null 2>&1; then
    echo "[didio-rl] ERROR: invalid JSON for persist_pending id=$id" >&2
    return 1
  fi

  mkdir -p "$pending_dir"
  local tmp=""
  tmp="$(mktemp "${pending_dir}/.tmp-XXXXXX")" || {
    echo "[didio-rl] ERROR: mktemp failed in persist_pending" >&2
    return 1
  }
  printf '%s\n' "$json_blob" > "$tmp"
  mv -f "$tmp" "${pending_dir}/${id}.json"
  return 0
}

# ── 4. didio_rl_consume_pending ───────────────────────────────────────────────
# Purpose: Atomically rename a pending file to .consumed (race protection).
# Returns: 0 on success; non-zero if rename fails (already consumed by another process).
didio_rl_consume_pending() {
  local pending_file="${1:?pending_file required}"

  mv "$pending_file" "${pending_file}.consumed" 2>/dev/null || return 1
  return 0
}

# ── 5. didio_rl_acquire_lock ──────────────────────────────────────────────────
# Purpose: Acquire exclusive lock on a pending file via atomic mkdir (POSIX).
# Returns: 0 if lock acquired; 1 if already held. Caller must call release_lock after.
# Note: Uses mkdir atomicity — flock is not available on macOS by default.
didio_rl_acquire_lock() {
  local pending_file="${1:?pending_file required}"

  mkdir "${pending_file}.lock" 2>/dev/null || return 1
  return 0
}

# ── 6. didio_rl_release_lock ──────────────────────────────────────────────────
# Purpose: Release the lock directory for a pending file.
# Returns: 0 always (errors ignored — lock cleanup is best-effort).
didio_rl_release_lock() {
  local pending_file="${1:?pending_file required}"

  rmdir "${pending_file}.lock" 2>/dev/null || true
  return 0
}

# ── 7. didio_rl_append_telemetry ──────────────────────────────────────────────
# Purpose: Append a JSON event line to <pending_dir>/index.jsonl.
# Returns: 0 always (best-effort — warns on failure, never crashes).
didio_rl_append_telemetry() {
  local pending_dir="${1:-}"
  local event_json="${2:-}"

  if [[ -z "$pending_dir" || -z "$event_json" ]]; then
    echo "[didio-rl] WARN: append_telemetry called with missing args" >&2
    return 0
  fi

  if ! printf '%s' "$event_json" | python3 -m json.tool > /dev/null 2>&1; then
    echo "[didio-rl] WARN: invalid event JSON, skipping telemetry append" >&2
    return 0
  fi

  mkdir -p "$pending_dir"
  printf '%s\n' "$event_json" >> "${pending_dir}/index.jsonl" || {
    echo "[didio-rl] WARN: failed to append telemetry to ${pending_dir}/index.jsonl" >&2
  }
  return 0
}

# ── 8. didio_rl_bump_retries ──────────────────────────────────────────────────
# Purpose: Increment retries counter in pending JSON; write back atomically.
# Returns: New retries value on stdout; exit 1 if retries > max_retries after increment.
didio_rl_bump_retries() {
  local pending_file="${1:?pending_file required}"

  if [[ ! -f "$pending_file" ]]; then
    echo "[didio-rl] ERROR: pending file not found: $pending_file" >&2
    return 1
  fi

  local new_retries=""
  local py_exit=0
  new_retries="$(RL_PENDING_FILE="$pending_file" python3 - <<'PYEOF' 2>/dev/null
import json, os, sys

path = os.environ["RL_PENDING_FILE"]
with open(path) as f:
    data = json.load(f)

retries = data.get("retries", 0) + 1
max_retries = data.get("max_retries", 3)
data["retries"] = retries
if retries > max_retries:
    data["state"] = "failed-max-retries"

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, path)

print(retries)
if retries > max_retries:
    sys.exit(1)
PYEOF
  )" || py_exit=$?

  echo "${new_retries:-0}"
  return $py_exit
}

# ── 9. didio_rl_capture_env ───────────────────────────────────────────────────
# Purpose: Capture whitelisted env vars as a compact JSON object.
# Returns: {"VAR":"value",...} on stdout.
didio_rl_capture_env() {
  RL_WHITELIST_PATTERN="${DIDIO_RL_ENV_WHITELIST_REGEX}" python3 - <<'PYEOF'
import json, os, re

pattern = os.environ.get("RL_WHITELIST_PATTERN", "")
result = {}
for key, val in os.environ.items():
    if pattern and re.match(pattern, key) and key != "RL_WHITELIST_PATTERN":
        result[key] = val

print(json.dumps(result, separators=(',', ':')))
PYEOF
  return 0
}

# ── 10. didio_rl_build_pending_json ──────────────────────────────────────────
# Purpose: Build and print the canonical pending JSON (schema v1) from --key=value args.
# Returns: Indented JSON string on stdout.
didio_rl_build_pending_json() {
  local _schema_version="1"
  local _id="" _role="" _feature="" _task="" _task_file="" _extra_prompt=""
  local _cwd="" _model="" _fallback_model="" _reset_at="" _reset_at_unix="" _retries="0"
  local _max_retries="${DIDIO_RL_MAX_RETRIES}"
  local _created_at=""
  _created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local _original_log="" _state="waiting"

  for arg in "$@"; do
    case "$arg" in
      --id=*)             _id="${arg#--id=}" ;;
      --role=*)           _role="${arg#--role=}" ;;
      --feature=*)        _feature="${arg#--feature=}" ;;
      --task=*)           _task="${arg#--task=}" ;;
      --task-file=*)      _task_file="${arg#--task-file=}" ;;
      --extra-prompt=*)   _extra_prompt="${arg#--extra-prompt=}" ;;
      --cwd=*)            _cwd="${arg#--cwd=}" ;;
      --model=*)          _model="${arg#--model=}" ;;
      --fallback-model=*) _fallback_model="${arg#--fallback-model=}" ;;
      --reset-at=*)       _reset_at="${arg#--reset-at=}" ;;
      --reset-at-unix=*)  _reset_at_unix="${arg#--reset-at-unix=}" ;;
      --retries=*)        _retries="${arg#--retries=}" ;;
      --max-retries=*)    _max_retries="${arg#--max-retries=}" ;;
      --original-log=*)   _original_log="${arg#--original-log=}" ;;
      --state=*)          _state="${arg#--state=}" ;;
      --created-at=*)     _created_at="${arg#--created-at=}" ;;
    esac
  done

  local env_json=""
  env_json="$(didio_rl_capture_env)"

  BPJ_SCHEMA_VERSION="$_schema_version" \
  BPJ_ID="$_id" \
  BPJ_ROLE="$_role" \
  BPJ_FEATURE="$_feature" \
  BPJ_TASK="$_task" \
  BPJ_TASK_FILE="$_task_file" \
  BPJ_EXTRA_PROMPT="$_extra_prompt" \
  BPJ_CWD="$_cwd" \
  BPJ_ENV_JSON="$env_json" \
  BPJ_MODEL="$_model" \
  BPJ_FALLBACK_MODEL="$_fallback_model" \
  BPJ_RESET_AT="$_reset_at" \
  BPJ_RESET_AT_UNIX="$_reset_at_unix" \
  BPJ_RETRIES="$_retries" \
  BPJ_MAX_RETRIES="$_max_retries" \
  BPJ_CREATED_AT="$_created_at" \
  BPJ_ORIGINAL_LOG="$_original_log" \
  BPJ_STATE="$_state" \
  python3 - <<'PYEOF'
import json, os

def g(k, default=""):
    return os.environ.get(k, default)

reset_at_unix_raw = g("BPJ_RESET_AT_UNIX", "")
reset_at_unix = int(reset_at_unix_raw) if reset_at_unix_raw.strip().isdigit() else None

result = {
    "schema_version":  int(g("BPJ_SCHEMA_VERSION", "1")),
    "id":              g("BPJ_ID"),
    "role":            g("BPJ_ROLE"),
    "feature":         g("BPJ_FEATURE"),
    "task":            g("BPJ_TASK"),
    "task_file":       g("BPJ_TASK_FILE"),
    "extra_prompt":    g("BPJ_EXTRA_PROMPT"),
    "cwd":             g("BPJ_CWD"),
    "env":             json.loads(g("BPJ_ENV_JSON", "{}")),
    "model":           g("BPJ_MODEL"),
    "fallback_model":  g("BPJ_FALLBACK_MODEL"),
    "reset_at":        g("BPJ_RESET_AT"),
    "retries":         int(g("BPJ_RETRIES", "0")),
    "max_retries":     int(g("BPJ_MAX_RETRIES", "3")),
    "created_at":      g("BPJ_CREATED_AT"),
    "original_log":    g("BPJ_ORIGINAL_LOG"),
    "state":           g("BPJ_STATE", "waiting"),
}

if reset_at_unix is not None:
    result["reset_at_unix"] = reset_at_unix

print(json.dumps(result, indent=2))
PYEOF
  return 0
}
