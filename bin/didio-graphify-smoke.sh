#!/usr/bin/env bash
# didio-graphify-smoke.sh — preflight check for the Graphify CLI.
#
# Exit codes:
#   0  → proceed (available, disabled, or degraded gracefully)
#
# Never exits non-zero — Graphify is optional and never blocks the pipeline.

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
if [[ -f "$PROJECT_ROOT/bin/didio-config-lib.sh" ]]; then
  LIB="$PROJECT_ROOT/bin/didio-config-lib.sh"
else
  LIB="${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-config-lib.sh"
fi
# shellcheck disable=SC1090
source "$LIB"

ENABLED="$(didio_graphify_enabled)"

if [[ "$ENABLED" != "true" ]]; then
  echo "[smoke] graphify disabled (opt-out)" >&2
  exit 0
fi

if command -v graphify >/dev/null 2>&1; then
  echo "[smoke] graphify available" >&2
  exit 0
fi

echo "[smoke] WARN: graphify enabled but binary not found on PATH." >&2
echo "[smoke]       Install with: didio install-graphify" >&2
echo "[smoke]       Or disable:   set \"graphify.enabled\": false in didio.config.json" >&2
exit 0
