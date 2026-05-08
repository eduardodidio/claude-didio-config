#!/usr/bin/env bash
# F22 hook — auto-resume pending rate-limited jobs on session start.
# Opt-in. Safe: errors swallowed, never blocks the session.
set -u
PROJECT_ROOT="$(pwd)"
PENDING_DIR="$PROJECT_ROOT/logs/agents/_pending"
[[ -d "$PENDING_DIR" ]] || exit 0
# Quick check: any non-empty pending json?
ls "$PENDING_DIR"/*.json >/dev/null 2>&1 || exit 0
if command -v didio >/dev/null 2>&1; then
  didio resume-pending 2>/dev/null || echo "[F22 hook] resume-pending failed (non-fatal)" >&2
else
  echo "[F22 hook] didio CLI not on PATH; skipping resume-pending" >&2
fi
exit 0
