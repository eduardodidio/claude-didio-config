#!/usr/bin/env bash
# didio-pre-tool.sh — PreToolUse hook for the didio session guard.
#
# Reads logs/session-budget.json (last written by the PostToolUse probe) and
# decides allow/warn/deny based on session_guard.soft_pct / .hard_pct.
#
# Three tiers of safety valve (in order of precedence):
#
#   1. DIDIO_BYPASS_GUARD=1 env var                        → always allow
#   2. File kill-switch: $PROJECT/logs/.guard-bypass       → always allow
#   3. Read-only tool whitelist (Read, Grep, Glob, LS,
#      TodoWrite, Task*)                                   → always allow
#
# These let a blocked session self-diagnose and self-heal without turning
# off the entire guard.
#
# Decision flow (after safety valves):
#   pct >= hard_pct  → emit deny JSON to stderr, exit 2, fire pause in bg
#   pct >= soft_pct  → emit systemMessage warning to stdout, exit 0
#   else             → exit 0 silently
#
# Any failure along the path degrades to "allow silent" (exit 0) — this
# hook must never false-deny a tool call.

set -u

# ── Safety valve #1: explicit bypass ──────────────────────────────────────────
if [[ "${DIDIO_BYPASS_GUARD:-0}" == "1" ]]; then
  exit 0
fi

# Self-locate so this hook can be referenced by absolute path from any
# downstream project's .claude/settings.json.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIDIO_HOME="${DIDIO_HOME:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PROJECT="${DIDIO_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
export DIDIO_PROJECT_ROOT="$PROJECT"
export PROJECT_ROOT="$PROJECT"

# ── Safety valve #2: file-based kill-switch ───────────────────────────────────
# If $PROJECT/logs/.guard-bypass exists, skip the guard. Useful when the
# guard itself is misbehaving and the user needs to work RIGHT NOW.
# Create with: touch $PROJECT/logs/.guard-bypass
if [[ -f "$PROJECT/logs/.guard-bypass" ]]; then
  exit 0
fi

# ── Safety valve #3: read-only tool whitelist ─────────────────────────────────
# The hook receives the tool name via stdin JSON. If it's a read-only tool,
# allow it regardless of budget — a stuck session must always be able to
# read files and list tasks to recover.
#
# Whitelist rationale:
#   Read/Grep/Glob/LS  — file inspection (diagnostic)
#   TodoWrite          — task-list bookkeeping (no external effect)
#   TaskGet/List/Output — subagent status (read-only)
STDIN_BUF="$(cat 2>/dev/null || true)"
TOOL_NAME="$(printf '%s' "$STDIN_BUF" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get("tool_name", "") or d.get("tool", "") or "")
except Exception:
    print("")
' 2>/dev/null || echo "")"
case "$TOOL_NAME" in
  Read|Grep|Glob|LS|TodoWrite|TaskGet|TaskList|TaskOutput|ToolSearch)
    exit 0
    ;;
esac

# shellcheck disable=SC1090
source "$DIDIO_HOME/bin/didio-config-lib.sh" 2>/dev/null || exit 0

ENABLED="$(didio_read_config_path session_guard.enabled true 2>/dev/null || echo true)"
[[ "$ENABLED" != "true" ]] && exit 0

BUDGET="$PROJECT/logs/session-budget.json"
[[ -f "$BUDGET" ]] || exit 0

# Staleness guard: ignore the snapshot if it's older than the configured
# max age (default 300s / 5min). This prevents a stale or orphan budget
# file — e.g. from a crashed test fixture — from bricking a live session.
STALE_MAX="$(didio_read_config_path session_guard.max_snapshot_age_secs 300 2>/dev/null || echo 300)"
SNAP_MTIME=$(stat -f '%m' "$BUDGET" 2>/dev/null || stat -c '%Y' "$BUDGET" 2>/dev/null || echo 0)
NOW_TS=$(date +%s)
if (( NOW_TS - SNAP_MTIME > STALE_MAX )); then
  exit 0
fi

SOFT="$(didio_read_config_path session_guard.soft_pct 0.90 2>/dev/null || echo 0.90)"
HARD="$(didio_read_config_path session_guard.hard_pct 0.98 2>/dev/null || echo 0.98)"

read -r PCT RESUME_AT <<<"$(python3 -c "
import json, sys
try:
  d = json.load(open('$BUDGET'))
  print(d.get('pct',0), d.get('window_resets_at',''))
except Exception:
  print(0, '')
" 2>/dev/null)"
PCT="${PCT:-0}"
RESUME_AT="${RESUME_AT:-}"

# Compare pct >= hard
if awk -v p="$PCT" -v h="$HARD" 'BEGIN { exit !(p+0 >= h+0) }'; then
  PCT_INT="$(awk -v p="$PCT" 'BEGIN { printf "%d", p*100 }')"
  # Fire pause in background so the deny returns fast.
  # Skip if a recent paused.json already exists (pause script also dedupes,
  # but starting a subprocess just to have it exit is wasteful).
  PAUSE_SNAP="$PROJECT/logs/session-paused.json"
  SKIP_PAUSE=0
  if [[ -f "$PAUSE_SNAP" ]]; then
    SNAP_AGE=$(( NOW_TS - $(stat -f '%m' "$PAUSE_SNAP" 2>/dev/null || stat -c '%Y' "$PAUSE_SNAP" 2>/dev/null || echo 0) ))
    if (( SNAP_AGE < 60 )); then
      SKIP_PAUSE=1
    fi
  fi
  if (( SKIP_PAUSE == 0 )) && [[ -x "$DIDIO_HOME/bin/didio-budget-pause.sh" ]]; then
    nohup "$DIDIO_HOME/bin/didio-budget-pause.sh" "$RESUME_AT" >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Session budget at %s%% >= hard threshold. Graceful stop. Resume scheduled at %s. Override: export DIDIO_BYPASS_GUARD=1 or touch %s/logs/.guard-bypass"}}\n' \
    "$PCT_INT" "${RESUME_AT:-unknown}" "$PROJECT" >&2
  exit 2
fi

# Compare pct >= soft
if awk -v p="$PCT" -v s="$SOFT" 'BEGIN { exit !(p+0 >= s+0) }'; then
  PCT_INT="$(awk -v p="$PCT" 'BEGIN { printf "%d", p*100 }')"
  printf '{"systemMessage":"⚠️ Session budget at %s%% — if this task is long, synthesize your progress as a checkpoint (logs/agents/%s.checkpoint.json) before continuing."}\n' \
    "$PCT_INT" "${DIDIO_RUN_ID:-session}"
  exit 0
fi

exit 0
