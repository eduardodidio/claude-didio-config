#!/usr/bin/env bash
# didio-dashboard.sh — start the monitoring dashboard.
#
# Phase 1: placeholder. Prints a tail of the most recent agent logs.
# Phase 2: will serve dashboard/dist/ via python3 -m http.server and open
#          the browser.

set -euo pipefail
PORT="${1:-7777}"
PROJECT_ROOT="$(pwd)"
LOG_DIR="$PROJECT_ROOT/logs/agents"
DASHBOARD_DIST="$DIDIO_HOME/dashboard/dist"

if [[ -d "$DASHBOARD_DIST" && -f "$DASHBOARD_DIST/index.html" ]]; then
  echo "[didio-dashboard] serving $DASHBOARD_DIST on http://localhost:$PORT"
  "$DIDIO_HOME/bin/didio-log-watcher.sh" &
  WATCHER_PID=$!
  trap "kill $WATCHER_PID 2>/dev/null || true" EXIT
  (cd "$DASHBOARD_DIST" && python3 -m http.server "$PORT") &
  SERVER_PID=$!
  sleep 1
  open "http://localhost:$PORT" 2>/dev/null || true
  wait "$SERVER_PID"
else
  echo "[didio-dashboard] dashboard not built yet (Phase 2). Showing recent logs:"
  if [[ ! -d "$LOG_DIR" ]]; then
    echo "[didio-dashboard] no logs yet at $LOG_DIR"
    exit 0
  fi
  ls -1t "$LOG_DIR"/*.meta.json 2>/dev/null | head -n10 | while read -r META; do
    echo "---"
    cat "$META"
  done
fi
