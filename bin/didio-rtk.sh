#!/usr/bin/env bash
# didio-rtk.sh — thin wrapper for the RTK CLI.
# Checks enabled + PATH, then execs rtk with all args.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIDIO_HOME="${DIDIO_HOME:-$(dirname "$SCRIPT_DIR")}"

# shellcheck disable=SC1090
source "$DIDIO_HOME/bin/didio-config-lib.sh"

ENABLED="$(didio_rtk_enabled)"
if [[ "$ENABLED" != "true" ]]; then
  echo "didio-rtk: rtk is disabled in didio.config.json" >&2
  echo "  Enable with: set \"rtk.enabled\": true" >&2
  exit 1
fi

if ! command -v rtk >/dev/null 2>&1; then
  echo "didio-rtk: rtk binary not found on PATH" >&2
  echo "  Install with: didio install-rtk" >&2
  exit 1
fi

exec rtk "$@"
