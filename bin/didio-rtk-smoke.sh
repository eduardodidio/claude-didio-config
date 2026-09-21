#!/usr/bin/env bash
# didio-rtk-smoke.sh — preflight check for the RTK CLI.
#
# Exit codes:
#   0  → proceed (available, disabled, or degraded gracefully)
#
# Never exits non-zero — RTK is optional and never blocks the pipeline.

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
if [[ -f "$PROJECT_ROOT/bin/didio-config-lib.sh" ]]; then
  LIB="$PROJECT_ROOT/bin/didio-config-lib.sh"
else
  LIB="${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-config-lib.sh"
fi
# shellcheck disable=SC1090
source "$LIB"

ENABLED="$(didio_rtk_enabled)"

if [[ "$ENABLED" != "true" ]]; then
  echo "[smoke] rtk disabled (opt-out)" >&2
  exit 0
fi

if command -v rtk >/dev/null 2>&1; then
  echo "[smoke] rtk available" >&2
  exit 0
fi

echo "[smoke] WARN: rtk enabled but binary not found on PATH." >&2
echo "[smoke]       Install with: didio install-rtk" >&2
echo "[smoke]       Or disable:   set \"rtk.enabled\": false in didio.config.json" >&2
exit 0
