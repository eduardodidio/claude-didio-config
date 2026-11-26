#!/usr/bin/env bash
# didio-blackhawk.sh — Black Hawk Alpha sub-routing dispatcher
#
# Usage:
#   didio blackhawk triage [--dry-run]
#   didio blackhawk promote <card-id>
#   didio blackhawk defer <card-id>

set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"

cmd_help() {
  cat <<'EOF'
USAGE:
  didio blackhawk triage [--dry-run]
      Run Black Hawk Alpha triage batch on all INCOMING War Room cards.
      Assesses each card, promotes/defers/archives based on assessment.
      Writes triage summary to logs/warroom/triage-<timestamp>.json.
      --dry-run: show what would happen without spawning agents.

  didio blackhawk promote <card-id>
      Promote a triaged card to a Standard Board feature.
      Requires overlord_assessment.recommendation=promote on the card.

  didio blackhawk defer <card-id>
      Defer a card. Updates status to "deferred" and writes rationale.

EXAMPLES:
  didio blackhawk triage
  didio blackhawk promote WR-20261126-001
  didio blackhawk defer WR-20261126-002
  didio blackhawk triage --dry-run
EOF
}

SUBCMD="${1:-}"
shift || true

case "$SUBCMD" in
  triage)
    # T10 will create didio-blackhawk-triage.sh; for now source the library
    # and call triage_batch directly
    # shellcheck disable=SC1091
    source "$DIDIO_HOME/lib/blackhawk-triage.sh" 2>/dev/null \
      || source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/blackhawk-triage.sh"

    # Pass --dry-run through
    for arg in "$@"; do
      if [[ "$arg" == "--dry-run" ]]; then
        export DIDIO_DRY_RUN=1
      fi
    done

    triage_batch
    ;;
  promote)
    exec "$DIDIO_HOME/bin/didio-blackhawk-promote.sh" "$@"
    ;;
  defer)
    exec "$DIDIO_HOME/bin/didio-blackhawk-defer.sh" "$@"
    ;;
  help|--help|-h|"")
    cmd_help
    ;;
  *)
    echo "didio blackhawk: unknown subcommand '$SUBCMD'. Try 'didio blackhawk --help'." >&2
    exit 1
    ;;
esac
