#!/usr/bin/env bash
# didio-checkpoint-write.sh — scaffold a per-run checkpoint JSON for the
# session guard. Called by PostToolUse hook (throttled 60s).
#
# The shell does not know the agent's semantic progress — it only persists
# recent log context + preserves any richer fields the agent itself wrote
# into the checkpoint earlier (via Write tool, guided by Wave 4 prompts).
#
# Required env:
#   DIDIO_RUN_ID        — set by didio-spawn-agent.sh
# Optional env:
#   DIDIO_FEATURE, DIDIO_TASK, DIDIO_ROLE
#   DIDIO_CHECKPOINT_THROTTLE_SECS (default 60)

set -u

RUN_ID="${DIDIO_RUN_ID:-}"
[[ -z "$RUN_ID" ]] && exit 0

PROJECT="${DIDIO_PROJECT_ROOT:-$(pwd)}"
LOG_DIR="$PROJECT/logs/agents"
[[ -d "$LOG_DIR" ]] || exit 0

THROTTLE="${DIDIO_CHECKPOINT_THROTTLE_SECS:-60}"
STAMP_FILE="$LOG_DIR/.${RUN_ID}.ckpt.at"
NOW=$(date +%s)
LAST=0
[[ -f "$STAMP_FILE" ]] && LAST=$(cat "$STAMP_FILE" 2>/dev/null || echo 0)
if (( NOW - LAST < THROTTLE )); then
  exit 0
fi
echo "$NOW" > "$STAMP_FILE" 2>/dev/null || true

CKPT="$LOG_DIR/${RUN_ID}.checkpoint.json"
LOG="$LOG_DIR/${RUN_ID}.jsonl"

# Capture up to 30 tail lines of the run log (may be empty pre-first-tool).
TAIL_B64=""
if [[ -f "$LOG" ]]; then
  TAIL_B64="$(tail -n 30 "$LOG" 2>/dev/null | base64 | tr -d '\n' || true)"
fi

python3 - "$CKPT" "$RUN_ID" "${DIDIO_FEATURE:-}" "${DIDIO_TASK:-}" "${DIDIO_ROLE:-}" "$TAIL_B64" <<'PY' 2>/dev/null || true
import json, sys, base64, os
from datetime import datetime, timezone
path, run_id, feat, task, role, tail_b64 = sys.argv[1:7]
try:
    tail = base64.b64decode(tail_b64).decode('utf-8', errors='ignore') if tail_b64 else ''
except Exception:
    tail = ''
payload = {
    "run_id": run_id,
    "feature": feat,
    "task": task,
    "role": role,
    "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "task_progress": "unknown",
    "last_tool_result": tail[-2000:],
    "todo_state": [],
    "context_summary": "",
    "next_action_hint": "",
}
# Preserve richer fields the agent wrote directly into this file.
try:
    with open(path) as f:
        prev = json.load(f)
    for k in ("task_progress", "todo_state", "context_summary", "next_action_hint"):
        v = prev.get(k)
        if v:
            payload[k] = v
except Exception:
    pass
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
exit 0
