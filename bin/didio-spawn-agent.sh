#!/usr/bin/env bash
# didio-spawn-agent.sh — launch a single Claude agent in an isolated bash
# context via 'claude -p' (headless mode). Streams output as JSONL to
# logs/agents/ for the dashboard and for auditing.
#
# Usage:
#   didio-spawn-agent.sh <role> <feature-id> <task-file> [extra-prompt]
#
# Roles: architect | developer | techlead | qa | readiness | tea
#
# The agent prompt is composed as:
#   <role-prompt-from-agents/prompts/>  +  task context  +  optional extra
#
# The feature-id, task-file path and timestamp compose the log filename, so
# multiple agents from the same Wave can run in parallel without clobbering.

set -euo pipefail

ROLE="${1:?role required: architect|developer|techlead|qa|readiness|tea|meeting-parser}"
FEATURE="${2:?feature-id required (e.g. F01)}"
TASK_FILE="${3:?task-file required (absolute or relative path)}"
EXTRA="${4:-}"

# F22 — rate-limit handling defaults
if [[ -z "${DIDIO_ON_RATE_LIMIT:-}" ]]; then
  if [[ "${DIDIO_CI:-${CI:-0}}" = "1" ]]; then
    DIDIO_ON_RATE_LIMIT='fail-fast'
  else
    DIDIO_ON_RATE_LIMIT='wait'
  fi
fi
# Also accept --on-rate-limit=<mode> anywhere in argv (overrides env)
for _arg in "$@"; do
  case "$_arg" in
    --on-rate-limit=*) DIDIO_ON_RATE_LIMIT="${_arg#--on-rate-limit=}" ; break ;;
  esac
done
unset _arg
DIDIO_MAX_RETRIES="${DIDIO_MAX_RETRIES:-3}"
DIDIO_RETRIES_SO_FAR="${DIDIO_RETRIES_SO_FAR:-0}"

PROJECT_ROOT="$(pwd)"
AGENTS_DIR="$PROJECT_ROOT/agents"
PROMPT_FILE="$AGENTS_DIR/prompts/${ROLE}.md"
LOG_DIR="$PROJECT_ROOT/logs/agents"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "[didio-spawn-agent] role prompt not found: $PROMPT_FILE" >&2
  echo "[didio-spawn-agent] is this a claude-didio-config project? run /install-claude-didio-framework first" >&2
  exit 2
fi

if [[ ! -f "$TASK_FILE" ]]; then
  echo "[didio-spawn-agent] task file not found: $TASK_FILE" >&2
  exit 2
fi

mkdir -p "$LOG_DIR"

# F22 — source rate-limit lib (defines didio_rl_* helpers)
RL_LIB="${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-rate-limit-lib.sh"
if [[ -f "$RL_LIB" ]]; then
  # shellcheck disable=SC1090
  source "$RL_LIB"
else
  echo "[didio-spawn-agent] WARN: rate-limit-lib not found at $RL_LIB; falling back to fail-fast" >&2
  DIDIO_ON_RATE_LIMIT='fail-fast'
fi

TS="$(date +%Y%m%d-%H%M%S)"
TASK_ID="$(basename "$TASK_FILE" .md)"
LOG_FILE="$LOG_DIR/${FEATURE}-${ROLE}-${TASK_ID}-${TS}.jsonl"
META_FILE="${LOG_FILE%.jsonl}.meta.json"

# Resolve model for this role from didio.config.json.
# Prefer project-local lib (newer helpers) over the global install fallback.
if [[ -f "$PROJECT_ROOT/bin/didio-config-lib.sh" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/bin/didio-config-lib.sh"
else
  # shellcheck disable=SC1090
  source "${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-config-lib.sh"
fi
AGENT_MODEL=$(didio_model_for_role "$ROLE")
AGENT_FALLBACK=$(didio_fallback_for_role "$ROLE")
AGENT_EFFORT=""
if declare -F didio_effort_for_role >/dev/null 2>&1; then
  AGENT_EFFORT="$(didio_effort_for_role "$ROLE" 2>/dev/null || echo "")"
fi

# Meta header for dashboard consumption
cat > "$META_FILE" <<EOF
{
  "feature": "$FEATURE",
  "role": "$ROLE",
  "task": "$TASK_ID",
  "task_file": "$TASK_FILE",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "log": "$LOG_FILE",
  "status": "running",
  "pid": $$,
  "model": "${AGENT_MODEL:-default}",
  "fallback_model": "${AGENT_FALLBACK:-none}",
  "effort": "${AGENT_EFFORT:-none}"
}
EOF

# Compose the prompt: role instructions + task body + optional extra
ROLE_PROMPT="$(cat "$PROMPT_FILE")"
TASK_BODY="$(cat "$TASK_FILE")"

# Substitute the {{USE_SECOND_BRAIN}} sentinel based on second_brain.enabled.
# Helpers return "true"/"false"; if unavailable (older config-lib installed),
# default to "false" so the prompt falls back to the local learnings file.
SB_ENABLED="false"
if declare -F didio_second_brain_enabled >/dev/null 2>&1; then
  SB_ENABLED="$(didio_second_brain_enabled 2>/dev/null || echo "false")"
fi
ROLE_PROMPT="${ROLE_PROMPT//\{\{USE_SECOND_BRAIN\}\}/$SB_ENABLED}"

# Substitute {{DIDIO_CHECKPOINT}} with the shared checkpointing block when
# session_guard is enabled; otherwise strip the sentinel.
CKPT_BLOCK=""
if declare -F didio_read_config_path >/dev/null 2>&1; then
  SG_ENABLED="$(didio_read_config_path session_guard.enabled false 2>/dev/null || echo "false")"
  if [[ "$SG_ENABLED" == "true" ]]; then
    CKPT_PATH="$PROJECT_ROOT/templates/agents/prompts/_checkpoint-block.md"
    [[ -f "$CKPT_PATH" ]] && CKPT_BLOCK="$(cat "$CKPT_PATH")"
  fi
fi
ROLE_PROMPT="${ROLE_PROMPT//\{\{DIDIO_CHECKPOINT\}\}/$CKPT_BLOCK}"

FULL_PROMPT=$(cat <<PROMPT
$ROLE_PROMPT

---

You are working on feature **$FEATURE**, task **$TASK_ID**.

Task details:

$TASK_BODY

---

$EXTRA

Constraints:
- You are running in a clean, isolated context. You do not share memory with
  other agents. All facts you need must come from the task file, the project
  files, or the role prompt above.
- Write your work directly to files in the project.
- When done, print a one-line summary starting with "DIDIO_DONE:".
PROMPT
)

RUN_ID="$(basename "$LOG_FILE" .jsonl)"
export DIDIO_RUN_ID="$RUN_ID"
export DIDIO_FEATURE="$FEATURE"
export DIDIO_ROLE="$ROLE"
export DIDIO_TASK="$TASK_ID"
export DIDIO_META_FILE="$META_FILE"
export DIDIO_LOG_FILE="$LOG_FILE"
export DIDIO_PROJECT_ROOT="$PROJECT_ROOT"
export DIDIO_AGENT=1

echo "[didio-spawn-agent] role=$ROLE feature=$FEATURE task=$TASK_ID model=$AGENT_MODEL log=$LOG_FILE" >&2

# Launch claude in headless streaming mode, new process, clean env. We
# inherit PATH so the user's claude CLI is findable, but we deliberately do
# not pass any other state — the agent's context is ONLY the prompt.
if [[ "${DIDIO_DRY_RUN:-0}" == "1" ]]; then
  printf '[DRY_RUN] claude -p <prompt_omitted>\n'
  printf '[DRY_RUN]   --output-format stream-json\n'
  printf '[DRY_RUN]   --verbose\n'
  [[ -n "$AGENT_MODEL" ]]    && printf '[DRY_RUN]   --model %s\n' "$AGENT_MODEL"
  [[ -n "$AGENT_FALLBACK" ]] && printf '[DRY_RUN]   --fallback-model %s\n' "$AGENT_FALLBACK"
  [[ -n "$AGENT_EFFORT" ]]   && printf '[DRY_RUN]   --effort %s\n' "$AGENT_EFFORT"
  printf '[DRY_RUN]   --dangerously-skip-permissions\n'
  printf '[DRY_RUN]   --allowedTools "Edit Write MultiEdit Read Bash Glob Grep"\n'
  [[ -n "$EXTRA" ]] && printf '[DRY_RUN]   EXTRA: %s\n' "$EXTRA"
  exit 0
fi
set +e
claude \
  -p "$FULL_PROMPT" \
  --output-format stream-json \
  --verbose \
  ${AGENT_MODEL:+--model "$AGENT_MODEL"} \
  ${AGENT_FALLBACK:+--fallback-model "$AGENT_FALLBACK"} \
  ${AGENT_EFFORT:+--effort "$AGENT_EFFORT"} \
  --dangerously-skip-permissions \
  --allowedTools "Edit Write MultiEdit Read Bash Glob Grep" \
  > "$LOG_FILE" 2>&1
EXIT_CODE=$?
set -e

# F15: trust JSONL ground truth, not CLI exit code. Any tool_result with
# is_error=true means the agent's actions failed even if the conversation
# ended cleanly. Use exit code 2 (distinct from 1 = CLI usage error).
# Set DIDIO_TOLERATE_TOOL_ERRORS=1 to skip this check for workflows that
# intentionally permit benign tool errors (e.g. file-not-found the agent handles).
if [[ "${DIDIO_TOLERATE_TOOL_ERRORS:-0}" != "1" ]]; then
  TOOL_ERRORS=$(python3 "$PROJECT_ROOT/bin/didio-jsonl-errors.py" "$LOG_FILE" 2>/dev/null || echo 0)
  TOOL_ERRORS="${TOOL_ERRORS:-0}"
  if [[ "$TOOL_ERRORS" -gt 0 && "$EXIT_CODE" -eq 0 ]]; then
    echo "[didio-spawn-agent] $TOOL_ERRORS tool_result error(s) detected — overriding exit code 0 → 2" >&2
    EXIT_CODE=2
  fi
fi

# F22 — rate-limit classification and branching
RL_CLASS="success"
if [[ $EXIT_CODE -ne 0 ]] && declare -F didio_rl_classify_jsonl >/dev/null 2>&1; then
  RL_CLASS=$(didio_rl_classify_jsonl "$LOG_FILE")
fi

if [[ "$RL_CLASS" = "rate_limit" ]]; then
  PENDING_DIR="$PROJECT_ROOT/logs/agents/_pending"
  mkdir -p "$PENDING_DIR"
  PENDING_ID="${FEATURE}-${ROLE}-${TASK_ID}-${TS}"
  RESET_AT=$(didio_rl_parse_reset_to_unix "$LOG_FILE")
  _TS_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  didio_rl_append_telemetry "$PENDING_DIR" \
    "$(printf '{"event":"rate_limit","role":"%s","feature":"%s","task":"%s","reset_at_unix":%s,"retries":%s,"mode":"%s","ts":"%s"}' \
      "$ROLE" "$FEATURE" "$TASK_ID" "$RESET_AT" "$DIDIO_RETRIES_SO_FAR" "$DIDIO_ON_RATE_LIMIT" "$_TS_NOW")"

  if (( DIDIO_RETRIES_SO_FAR >= DIDIO_MAX_RETRIES )); then
    echo "[didio-spawn-agent] max-retries exhausted ($DIDIO_RETRIES_SO_FAR/$DIDIO_MAX_RETRIES) — failing" >&2
    didio_rl_append_telemetry "$PENDING_DIR" \
      "$(printf '{"event":"failed_max_retries","role":"%s","feature":"%s","task":"%s","retries":%s,"ts":"%s"}' \
        "$ROLE" "$FEATURE" "$TASK_ID" "$DIDIO_RETRIES_SO_FAR" "$_TS_NOW")"
    NOTIFY="${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-notify.sh"
    [[ -x "$NOTIFY" ]] && "$NOTIFY" "rate-limit max-retries: $PENDING_ID" >/dev/null 2>&1 || true
    EXIT_CODE=3
  else
    case "$DIDIO_ON_RATE_LIMIT" in
      wait)
        NOW=$(date +%s)
        SLEEP_FOR=$(( RESET_AT - NOW + ${DIDIO_RL_MARGIN_SEC:-60} ))
        (( SLEEP_FOR < 0 )) && SLEEP_FOR=0
        RESET_AT_HUMAN="$(date -r "$RESET_AT" 2>/dev/null || date -u -d "@$RESET_AT" 2>/dev/null || echo "unix:$RESET_AT")"
        echo "[didio-spawn-agent] rate-limited; sleeping ${SLEEP_FOR}s until $RESET_AT_HUMAN" >&2
        sleep "$SLEEP_FOR"
        export DIDIO_RETRIES_SO_FAR=$(( DIDIO_RETRIES_SO_FAR + 1 ))
        export DIDIO_ON_RATE_LIMIT DIDIO_MAX_RETRIES
        didio_rl_append_telemetry "$PENDING_DIR" \
          "$(printf '{"event":"resume","role":"%s","feature":"%s","task":"%s","retries":%s,"ts":"%s"}' \
            "$ROLE" "$FEATURE" "$TASK_ID" "$DIDIO_RETRIES_SO_FAR" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
        exec "$0" "$ROLE" "$FEATURE" "$TASK_FILE" "$EXTRA"
        ;;
      schedule)
        # Convert epoch to ISO-8601 for reset_at (required by resume-pending parser).
        # Pass epoch as reset_at_unix so resume-pending can fall back if ISO parse fails.
        RESET_AT_ISO=$(python3 -c \
          "from datetime import datetime,timezone; print(datetime.fromtimestamp($RESET_AT, tz=timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" \
          2>/dev/null || echo "")
        PENDING_JSON=$(didio_rl_build_pending_json \
          --id="$PENDING_ID" \
          --role="$ROLE" --feature="$FEATURE" --task="$TASK_ID" \
          --task-file="$TASK_FILE" --extra-prompt="$EXTRA" \
          --cwd="$PROJECT_ROOT" \
          --model="$AGENT_MODEL" --fallback-model="$AGENT_FALLBACK" \
          --reset-at="${RESET_AT_ISO:-$RESET_AT}" --reset-at-unix="$RESET_AT" \
          --retries="$DIDIO_RETRIES_SO_FAR" \
          --max-retries="$DIDIO_MAX_RETRIES" \
          --original-log="$LOG_FILE")
        didio_rl_persist_pending "$PENDING_DIR" "$PENDING_ID" "$PENDING_JSON"
        RESET_AT_HUMAN="$(date -r "$RESET_AT" 2>/dev/null || date -u -d "@$RESET_AT" 2>/dev/null || echo "unix:$RESET_AT")"
        echo "[didio-spawn-agent] rate-limited; scheduled pending: $PENDING_DIR/$PENDING_ID.json (reset at $RESET_AT_HUMAN)" >&2
        EXIT_CODE=2
        ;;
      fail-fast|*)
        echo "[didio-spawn-agent] rate-limited; fail-fast mode (set DIDIO_ON_RATE_LIMIT=wait or =schedule to recover)" >&2
        EXIT_CODE=1
        ;;
    esac
  fi
fi

# Update meta with final status
if [[ "$RL_CLASS" = "rate_limit" ]]; then
  case "$EXIT_CODE" in
    2) FINAL_STATUS="rate_limited_scheduled" ;;
    3) FINAL_STATUS="failed_max_retries" ;;
    *) FINAL_STATUS="failed" ;;
  esac
else
  FINAL_STATUS="completed"
  [[ $EXIT_CODE -ne 0 ]] && FINAL_STATUS="failed"
fi

# Pick a thematic phrase for this role+outcome (may be empty if disabled)
PHRASE=""
if [[ -x "${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-easter-egg.sh" ]]; then
  PHRASE="$("${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-easter-egg.sh" "$ROLE" "$EXIT_CODE" || true)"
fi

# Rewrite meta atomically with final status, timestamp, and phrase
python3 - "$META_FILE" "$FINAL_STATUS" "$EXIT_CODE" "$PHRASE" <<'PY' || true
import json, sys
from datetime import datetime, timezone
path, status, code, phrase = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
with open(path) as f:
    m = json.load(f)
m["status"] = status
m["exit_code"] = code
m["finished_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
if phrase:
    m["phrase"] = phrase
with open(path, "w") as f:
    json.dump(m, f, indent=2)
PY

[[ -n "$PHRASE" ]] && echo "$PHRASE" >&2
echo "[didio-spawn-agent] $ROLE/$TASK_ID -> $FINAL_STATUS (exit=$EXIT_CODE)" >&2

PROGRESS_LIB="${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-progress-lib.sh"
if [[ -f "$PROGRESS_LIB" ]]; then
  # shellcheck disable=SC1090
  source "$PROGRESS_LIB"
  didio_feature_progress "$FEATURE" >&2 || true
fi

exit $EXIT_CODE
