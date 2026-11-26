#!/usr/bin/env bash
# didio-pipeline-pause.sh — Pause a running pipeline
#
# Usage:
#   didio pipeline-pause <feature-id>
#
# Creates a pause signal file. The pipeline will pause after its current
# stage completes.
#
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
source "$DIDIO_HOME/bin/didio-config-lib.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
STATE_DIR="$PROJECT_ROOT/logs/agents"

FXX="${1:-}"

if [[ -z "$FXX" ]]; then
  echo "Usage: didio pipeline-pause <feature-id>" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Validate pipeline exists
# ---------------------------------------------------------------------------
STATE_FILE="$STATE_DIR/pipeline-${FXX}.state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Error: No pipeline state found for $FXX" >&2
  echo "  Expected: $STATE_FILE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Read current status (pass path via argv for Windows compatibility)
# ---------------------------------------------------------------------------
STATUS="$(python3 - "$STATE_FILE" <<'PY' 2>/dev/null || echo "unknown"
import json, sys, os, re
fpath = sys.argv[1]
if not os.path.exists(fpath) and fpath.startswith('/'):
    m = re.match(r'^/([a-zA-Z])/(.*)', fpath)
    if m:
        fpath = m.group(1).upper() + ':/' + m.group(2)
try:
    with open(fpath) as f:
        print(json.load(f).get('status', 'unknown'))
except Exception:
    print('unknown')
PY
)"

case "$STATUS" in
  running)
    # OK — proceed to create signal
    ;;
  paused)
    echo "Error: Pipeline $FXX is already paused" >&2
    exit 1
    ;;
  completed|succeeded)
    echo "Error: Pipeline $FXX has already completed" >&2
    exit 1
    ;;
  failed)
    echo "Error: Pipeline $FXX has failed (nothing to pause)" >&2
    exit 1
    ;;
  cancelled)
    echo "Error: Pipeline $FXX has been cancelled" >&2
    exit 1
    ;;
  *)
    echo "Error: Pipeline $FXX has unexpected status: $STATUS" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Create pause signal
# ---------------------------------------------------------------------------
SIGNAL_DIR="$PROJECT_ROOT/$(didio_pipeline_signal_dir)"
mkdir -p "$SIGNAL_DIR"

SIGNAL_FILE="$SIGNAL_DIR/${FXX}.pause"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SIGNAL_FILE"

echo "Pipeline $FXX will pause after current stage completes"
echo "  Signal file: $SIGNAL_FILE"
