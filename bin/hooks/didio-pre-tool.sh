#!/usr/bin/env bash
# didio-pre-tool.sh — PreToolUse hook for the didio session guard.
#
# Reads logs/session-budget.json (last written by the PostToolUse probe) and
# decides allow/warn/deny based on session_guard.soft_pct / .hard_pct:
#
#   pct >= hard_pct  → emit deny JSON to stderr, exit 2, fire pause in bg
#   pct >= soft_pct  → emit systemMessage warning to stdout, exit 0
#   else             → exit 0 silently
#
# Any failure along the path degrades to "allow silent" (exit 0) — this
# hook must never false-deny a tool call.

set -u

# Self-locate so this hook can be referenced by absolute path from any
# downstream project's .claude/settings.json. The framework lives at
# $DIDIO_HOME (2 dirs up from this script); per-project state lives at
# $PROJECT (derived from CLAUDE_PROJECT_DIR).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIDIO_HOME="${DIDIO_HOME:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PROJECT="${DIDIO_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
export DIDIO_PROJECT_ROOT="$PROJECT"
export PROJECT_ROOT="$PROJECT"

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
  if [[ -x "$DIDIO_HOME/bin/didio-budget-pause.sh" ]]; then
    nohup "$DIDIO_HOME/bin/didio-budget-pause.sh" "$RESUME_AT" >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Session budget at %s%% >= hard threshold. Graceful stop. Resume scheduled at %s"}}\n' \
    "$PCT_INT" "${RESUME_AT:-unknown}" >&2
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
