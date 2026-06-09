#!/usr/bin/env bash
# didio-meta-metrics.sh — Compute meta-agent KPI report from live logs
#
# Usage:
#   didio meta-metrics [--root <path>]
#   didio meta-metrics --help

set -euo pipefail

if [[ "${1:-}" = "--help" || "${1:-}" = "-h" ]]; then
  cat <<'EOF'
USAGE:
  didio meta-metrics [--root <path>]    Compute KPI report from live logs
  didio meta-metrics --help             Show this help

OUTPUT:
  logs/agents/meta-metrics.json         JSON report (MetaMetricsReport)
  stdout                                Human-readable text report

SOURCES:
  logs/decisions/D-*.json               Gandalf decision records
  logs/governance/G-*.json              Saruman governance reports
  logs/agents/state.json                Agent run state (latency, exit_code)
EOF
  exit 0
fi

PROJECT_ROOT="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="$SCRIPT_DIR/../dashboard"

if [[ ! -d "$DASHBOARD_DIR/node_modules" ]]; then
  echo "[didio-meta-metrics] node_modules not found in $DASHBOARD_DIR — run 'npm install' first" >&2
  exit 1
fi

cd "$DASHBOARD_DIR"
exec node_modules/.bin/vite-node scripts/meta-metrics.ts --root "$PROJECT_ROOT" "$@"
