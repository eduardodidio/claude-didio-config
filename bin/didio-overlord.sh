#!/usr/bin/env bash
# didio-overlord.sh — Overlord sub-routing dispatcher
#
# Usage:
#   didio overlord triage [--dry-run]
#   didio overlord promote <card-id>
#   didio overlord defer <card-id>

set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"

cmd_help() {
  cat <<'EOF'
USAGE:
  didio overlord triage [--dry-run]
      Run the Overlord triage batch on all INCOMING War Room cards.
      Assesses each card, promotes/defers/archives based on assessment.
      Writes triage summary to logs/warroom/triage-<timestamp>.json.
      --dry-run: show what would happen without spawning agents.

  didio overlord promote <card-id>
      Promote a triaged card to a Standard Board feature.
      Requires overlord_assessment.recommendation=promote on the card.

  didio overlord defer <card-id>
      Defer a card. Updates status to "deferred" and writes rationale.

EXAMPLES:
  didio overlord triage
  didio overlord promote WR-20261126-001
  didio overlord defer WR-20261126-002
  didio overlord triage --dry-run
EOF
}

SUBCMD="${1:-}"
shift || true

case "$SUBCMD" in
  triage)
    # T10 will create didio-overlord-triage.sh; for now source the library
    # and call triage_batch directly
    # shellcheck disable=SC1091
    source "$DIDIO_HOME/lib/overlord-triage.sh" 2>/dev/null \
      || source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/overlord-triage.sh"

    # Pass --dry-run through
    for arg in "$@"; do
      if [[ "$arg" == "--dry-run" ]]; then
        export DIDIO_DRY_RUN=1
      fi
    done

    triage_batch
    ;;
  promote)
    exec "$DIDIO_HOME/bin/didio-overlord-promote.sh" "$@"
    ;;
  defer)
    exec "$DIDIO_HOME/bin/didio-overlord-defer.sh" "$@"
    ;;
  help|--help|-h|"")
    cmd_help
    ;;
  *)
    echo "didio overlord: unknown subcommand '$SUBCMD'. Try 'didio overlord --help'." >&2
    exit 1
    ;;
esac
