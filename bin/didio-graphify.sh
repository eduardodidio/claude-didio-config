#!/usr/bin/env bash
# didio-graphify.sh — thin wrapper for the Graphify CLI.
# Checks enabled + PATH, then execs graphify with all args.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIDIO_HOME="${DIDIO_HOME:-$(dirname "$SCRIPT_DIR")}"

# shellcheck disable=SC1090
source "$DIDIO_HOME/bin/didio-config-lib.sh"

ENABLED="$(didio_graphify_enabled)"
if [[ "$ENABLED" != "true" ]]; then
  echo "didio-graphify: graphify is disabled in didio.config.json" >&2
  echo "  Enable with: set \"graphify.enabled\": true" >&2
  exit 1
fi

if ! command -v graphify >/dev/null 2>&1; then
  echo "didio-graphify: graphify binary not found on PATH" >&2
  echo "  Install with: didio install-graphify" >&2
  exit 1
fi

exec graphify "$@"
