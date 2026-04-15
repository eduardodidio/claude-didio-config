#!/usr/bin/env bash
# didio-log-watcher.sh — aggregate logs/agents/*.meta.json into a single
# logs/agents/state.json file, regenerated every 1s. The dashboard fetches
# state.json directly (no backend needed).
#
# Delegates to a persistent Python process so that the no-op guard
# (skip write when payload unchanged) and README mtime cache survive
# across ticks without touching the filesystem for bookkeeping.

set -euo pipefail
PROJECT_ROOT="$(pwd)"
LOG_DIR="$PROJECT_ROOT/logs/agents"
STATE_FILE="$LOG_DIR/state.json"

# Resolve bin dir relative to this script (works regardless of DIDIO_HOME).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$LOG_DIR"

exec python3 "$SCRIPT_DIR/didio-log-watcher-loop.py" \
    "$STATE_FILE" \
    "$PROJECT_ROOT" \
    "$SCRIPT_DIR/didio-progress.py"
