#!/usr/bin/env bash
# didio-spawn-agent.sh — launch a single Claude agent in an isolated bash
# context via 'claude -p' (headless mode). Streams output as JSONL to
# logs/agents/ for the dashboard and for auditing.
#
# Usage:
#   didio-spawn-agent.sh <role> <feature-id> <task-file> [extra-prompt]
#
# Roles: architect | developer | techlead | qa
#
# The agent prompt is composed as:
#   <role-prompt-from-agents/prompts/>  +  task context  +  optional extra
#
# The feature-id, task-file path and timestamp compose the log filename, so
# multiple agents from the same Wave can run in parallel without clobbering.

set -euo pipefail

ROLE="${1:?role required: architect|developer|techlead|qa}"
FEATURE="${2:?feature-id required (e.g. F01)}"
TASK_FILE="${3:?task-file required (absolute or relative path)}"
EXTRA="${4:-}"

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

TS="$(date +%Y%m%d-%H%M%S)"
TASK_ID="$(basename "$TASK_FILE" .md)"
LOG_FILE="$LOG_DIR/${FEATURE}-${ROLE}-${TASK_ID}-${TS}.jsonl"
META_FILE="${LOG_FILE%.jsonl}.meta.json"

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
  "pid": $$
}
EOF

# Compose the prompt: role instructions + task body + optional extra
ROLE_PROMPT="$(cat "$PROMPT_FILE")"
TASK_BODY="$(cat "$TASK_FILE")"

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

echo "[didio-spawn-agent] role=$ROLE feature=$FEATURE task=$TASK_ID log=$LOG_FILE" >&2

# Launch claude in headless streaming mode, new process, clean env. We
# inherit PATH so the user's claude CLI is findable, but we deliberately do
# not pass any other state — the agent's context is ONLY the prompt.
set +e
claude \
  -p "$FULL_PROMPT" \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  > "$LOG_FILE" 2>&1
EXIT_CODE=$?
set -e

# Update meta with final status
FINAL_STATUS="completed"
[[ $EXIT_CODE -ne 0 ]] && FINAL_STATUS="failed"

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
exit $EXIT_CODE
