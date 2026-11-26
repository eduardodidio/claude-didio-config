#!/usr/bin/env bash
# didio-pipeline-resume.sh — Resume a paused pipeline
#
# Usage:
#   didio pipeline-resume <feature-id>
#
# Creates a resume signal file so the paused pipeline continues from where
# it stopped.
#
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
source "$DIDIO_HOME/bin/didio-config-lib.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
STATE_DIR="$PROJECT_ROOT/logs/agents"

FXX="${1:-}"

if [[ -z "$FXX" ]]; then
  echo "Usage: didio pipeline-resume <feature-id>" >&2
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
# Read current status and resume_from (pass path via argv for portability)
# ---------------------------------------------------------------------------
read -r STATUS RESUME_FROM < <(python3 - "$STATE_FILE" <<'PY' 2>/dev/null || echo "unknown ?"
import json, sys, os, re
fpath = sys.argv[1]
if not os.path.exists(fpath) and fpath.startswith('/'):
    m = re.match(r'^/([a-zA-Z])/(.*)', fpath)
    if m:
        fpath = m.group(1).upper() + ':/' + m.group(2)
try:
    with open(fpath) as f:
        d = json.load(f)
    status = d.get('status', 'unknown')
    resume_from = d.get('resume_from') or d.get('stage') or '?'
    print(f'{status} {resume_from}')
except Exception:
    print('unknown ?')
PY
)

case "$STATUS" in
  paused)
    # OK — proceed to create signal
    ;;
  running)
    echo "Error: Pipeline $FXX is already running (not paused)" >&2
    exit 1
    ;;
  completed|succeeded)
    echo "Error: Pipeline $FXX has already completed" >&2
    exit 1
    ;;
  failed)
    echo "Error: Pipeline $FXX has failed (use run-pipeline to restart)" >&2
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
# Create resume signal
# ---------------------------------------------------------------------------
SIGNAL_DIR="$PROJECT_ROOT/$(didio_pipeline_signal_dir)"
mkdir -p "$SIGNAL_DIR"

SIGNAL_FILE="$SIGNAL_DIR/${FXX}.resume"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SIGNAL_FILE"

echo "Pipeline $FXX resuming from stage: $RESUME_FROM"
echo "  Signal file: $SIGNAL_FILE"
