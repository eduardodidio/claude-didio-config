#!/usr/bin/env bash
# didio-post-tool.sh — PostToolUse hook for the didio session guard.
#
# Reads the harness JSON from stdin, forwards `transcript_path` to the
# budget probe (via DIDIO_TRANSCRIPT_PATH env), then triggers the
# per-agent checkpoint write if we are inside a didio-spawned run.
#
# Must never break the session: all failures exit 0.

set -u

STDIN="$(cat 2>/dev/null || true)"

# Self-locate so this hook works from any downstream project.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIDIO_HOME="${DIDIO_HOME:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PROJECT="${DIDIO_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
export DIDIO_PROJECT_ROOT="$PROJECT"

# Extract transcript_path from stdin JSON (if present).
TRANSCRIPT="$(
  printf '%s' "$STDIN" | python3 -c 'import sys,json
try:
  d=json.load(sys.stdin)
  print(d.get("transcript_path","") or "")
except Exception:
  pass' 2>/dev/null || true
)"
export DIDIO_TRANSCRIPT_PATH="${TRANSCRIPT:-${DIDIO_TRANSCRIPT_PATH:-}}"

# 1. Refresh budget snapshot (throttled internally). Runs from $DIDIO_HOME
#    but writes into $PROJECT/logs/ via DIDIO_PROJECT_ROOT.
if [[ -x "$DIDIO_HOME/bin/didio-budget-probe.sh" ]]; then
  "$DIDIO_HOME/bin/didio-budget-probe.sh" >/dev/null 2>&1 || true
fi

# 2. Write a scaffolded checkpoint only if inside a didio-spawned run.
if [[ -n "${DIDIO_RUN_ID:-}" ]] && [[ -x "$DIDIO_HOME/bin/didio-checkpoint-write.sh" ]]; then
  "$DIDIO_HOME/bin/didio-checkpoint-write.sh" >/dev/null 2>&1 || true
fi

exit 0
