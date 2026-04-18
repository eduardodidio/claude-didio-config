#!/usr/bin/env bash
# didio-second-brain-smoke.sh — preflight check for the second-brain MCP tool.
#
# Exit codes:
#   0  → proceed (MCP available, or opt-out, or degraded with fallback)
#   2  → hard fail (MCP unavailable AND fallback disabled)
#
# Heuristic: we don't spawn a Claude process just to prove the tool works
# (expensive). We only verify the MCP server is wired up via `claude mcp list`
# (or a simple grep in ~/.claude/mcp.json as a cheaper fallback). When the
# real tool fails mid-run, the agent prompts already have a graceful fallback
# path (they re-read the local file), so this preflight is cheap-and-best-effort
# by design.

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
# Prefer project-local lib (newer helpers) over the global install fallback.
if [[ -f "$PROJECT_ROOT/bin/didio-config-lib.sh" ]]; then
  LIB="$PROJECT_ROOT/bin/didio-config-lib.sh"
else
  LIB="${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-config-lib.sh"
fi
# shellcheck disable=SC1090
source "$LIB"

ENABLED="$(didio_second_brain_enabled)"
FALLBACK="$(didio_second_brain_fallback)"

if [[ "$ENABLED" != "true" ]]; then
  echo "[smoke] second-brain disabled (opt-out)" >&2
  exit 0
fi

mcp_available=false
if command -v claude >/dev/null 2>&1 && claude mcp list 2>/dev/null | grep -qi 'second-brain'; then
  mcp_available=true
elif [[ -f "$HOME/.claude/mcp.json" ]] && grep -q '"second-brain"' "$HOME/.claude/mcp.json" 2>/dev/null; then
  mcp_available=true
elif [[ -f "$PROJECT_ROOT/.claude/mcp.json" ]] && grep -q '"second-brain"' "$PROJECT_ROOT/.claude/mcp.json" 2>/dev/null; then
  mcp_available=true
fi

if $mcp_available; then
  echo "[smoke] second-brain available" >&2
  exit 0
fi

if [[ "$FALLBACK" == "true" ]]; then
  echo "[smoke] WARN: second-brain MCP not detected. Using local files (memory/agent-learnings/)." >&2
  echo "[smoke]       To install MCP: https://github.com/eduardodidio/didio-second-brain-claude" >&2
  echo "[smoke]       To silence this warning: set \"second_brain.enabled\": false in didio.config.json" >&2
  exit 0
fi

echo "[smoke] ERROR: second-brain MCP not detected and fallback_to_local=false — aborting" >&2
exit 2
