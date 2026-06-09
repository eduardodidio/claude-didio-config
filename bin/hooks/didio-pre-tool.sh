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

# ── Read the hook payload once, up front ──────────────────────────────────────
# Every decision below keys off the tool name and (for writes) the target path.
# Read stdin exactly once here and reuse it; downstream branches must NOT
# re-read stdin (it is already consumed). Bash-regex extraction keeps the
# common path subprocess-free.
STDIN_BUF="$(cat 2>/dev/null || true)"
TOOL_NAME=""
if [[ "$STDIN_BUF" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  TOOL_NAME="${BASH_REMATCH[1]}"
elif [[ "$STDIN_BUF" =~ \"tool\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  TOOL_NAME="${BASH_REMATCH[1]}"
fi

# ── Sensitive-file lock for spawned agents (F15 AC8) — evaluated FIRST ─────────
# Claude Code's built-in sensitive-file guard used to block any write under
# .claude/ even with --dangerously-skip-permissions (confirmed by the F15-T01
# spike, 2026-04-27). That CLI behavior has since changed: a spawned agent can
# now freely Edit/Write .claude/settings.json, which controls hooks and
# permissions — a privilege-escalation / persistence vector. Re-enforce the lock
# here, where a PreToolUse deny IS honored under skip-permissions (same path the
# session_guard budget-deny uses). This runs BEFORE the bypass valves on
# purpose: the budget escape-hatches must never also unlock settings.json for an
# agent. Scoped to DIDIO_AGENT=1 so the human's own interactive session can
# still edit its settings (e.g. via /update-config).
if [[ "${DIDIO_AGENT:-0}" == "1" ]]; then
  case "$TOOL_NAME" in
    Edit|Write|MultiEdit)
      _TGT=""
      if [[ "$STDIN_BUF" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
        _TGT="${BASH_REMATCH[1]}"
      elif [[ "$STDIN_BUF" =~ \"path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
        _TGT="${BASH_REMATCH[1]}"
      fi
      case "$_TGT" in
        */.claude/settings.json|.claude/settings.json|\
        */.claude/settings.local.json|.claude/settings.local.json)
          printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"SENSITIVE-FILE LOCK (didio): spawned agents may not edit .claude/settings*.json — it controls hooks and permissions and is operator-owned. Treat it as read-only; do NOT retry."}}\n' >&2
          exit 2
          ;;
      esac
      ;;
  esac
fi

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
# Fast path: TOOL_NAME was already parsed from STDIN_BUF at the top of the
# hook. If the regex couldn't find a tool name (odd formatting, escaped chars),
# TOOL_NAME is empty, the case below doesn't match, and we fall through to the
# full evaluation — same observable behavior, just no whitelist shortcut.
case "$TOOL_NAME" in
  Read|Grep|Glob|LS|TodoWrite|TaskGet|TaskList|TaskOutput|ToolSearch)
    exit 0
    ;;
esac

# requires python3 for stdin parse on the non-whitelisted path; absent → allow-silent
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
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"AUTO-PAUSE (session_guard): budget at %s%% >= hard threshold. Auto-resume already scheduled for %s. STOP working immediately — do NOT ask the user whether to resume, do NOT attempt any bypass, do NOT continue with other tools. Just acknowledge the pause briefly and end your turn. The resume will happen automatically without user intervention."}}\n' \
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
