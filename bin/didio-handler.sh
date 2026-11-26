#!/usr/bin/env bash
# didio-handler.sh — Handler Strategic Orchestrator launcher
#
# Usage:
#   didio handler <feature-id> <brief-or-request-file> [extra-prompt]
#   didio handler --checkpoint <decision-id>
#
# Spawns the Handler meta-agent to make a strategic decision. If
# auto_governance is enabled, automatically spawns GateKeeper after.

set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
PROJECT_ROOT="$(pwd)"

# Source config lib
if [[ -f "$PROJECT_ROOT/bin/didio-config-lib.sh" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/bin/didio-config-lib.sh"
else
  # shellcheck disable=SC1090
  source "$DIDIO_HOME/bin/didio-config-lib.sh"
fi

# F30-T10 — source flags lib for raising escalated flags
FLAGS_LIB="${DIDIO_HOME}/bin/didio-flags-lib.sh"
if [[ -f "$PROJECT_ROOT/bin/didio-flags-lib.sh" ]]; then
  FLAGS_LIB="$PROJECT_ROOT/bin/didio-flags-lib.sh"
fi
if [[ -f "$FLAGS_LIB" ]]; then
  # shellcheck disable=SC1090
  source "$FLAGS_LIB"
fi

# --help
if [[ "${1:-}" = "--help" || "${1:-}" = "-h" ]]; then
  cat <<'EOF'
USAGE:
  didio handler <feature-id> <brief-or-request-file> [extra-prompt]
  didio handler --checkpoint <decision-id>

Spawns the Handler strategic orchestrator to produce a decision record
in logs/decisions/D-YYYYMMDD-NNN.json.

If meta_agents.handler.auto_governance is true, the GateKeeper governance
reviewer is automatically spawned after the decision is produced.

OPTIONS:
  --checkpoint <id>   Re-evaluate an existing decision (mid-pipeline check)
  --help, -h          Show this help and exit.

REQUIRES: meta_agents.handler.enabled = true in didio.config.json
EOF
  exit 0
fi

# Check if Handler is enabled
HANDLER_ENABLED="$(didio_handler_enabled)"
if [[ "$HANDLER_ENABLED" != "true" ]]; then
  echo "[didio-handler] Handler is disabled. Set meta_agents.handler.enabled=true in didio.config.json" >&2
  exit 1
fi

# Ensure decision directories exist
DECISIONS_DIR="$PROJECT_ROOT/logs/decisions"
REQUESTS_DIR="$DECISIONS_DIR/_requests"
mkdir -p "$DECISIONS_DIR" "$REQUESTS_DIR"

# Handle checkpoint mode
if [[ "${1:-}" = "--checkpoint" ]]; then
  DECISION_ID="${2:?decision-id required for --checkpoint}"
  DECISION_FILE="$DECISIONS_DIR/${DECISION_ID}.json"
  if [[ ! -f "$DECISION_FILE" ]]; then
    echo "[didio-handler] decision not found: $DECISION_FILE" >&2
    exit 2
  fi
  echo "[didio-handler] checkpoint mode for $DECISION_ID" >&2
  "$DIDIO_HOME/bin/didio-spawn-agent.sh" handler "META" "$DECISION_FILE" "MODE=checkpoint"
  exit $?
fi

# Normal decision mode
FEATURE="${1:?feature-id required (e.g. F01)}"
REQUEST_FILE="${2:?brief or request file required}"
EXTRA="${3:-}"

if [[ ! -f "$REQUEST_FILE" ]]; then
  echo "[didio-handler] request file not found: $REQUEST_FILE" >&2
  exit 2
fi

# Copy request to _requests/ for audit trail
TS="$(date +%Y%m%d-%H%M%S)"
cp "$REQUEST_FILE" "$REQUESTS_DIR/${FEATURE}-${TS}.md"

echo "[didio-handler] spawning Handler for $FEATURE..." >&2

# Spawn Handler
"$DIDIO_HOME/bin/didio-spawn-agent.sh" handler "$FEATURE" "$REQUEST_FILE" "$EXTRA"
HANDLER_EXIT=$?

if [[ $HANDLER_EXIT -ne 0 ]]; then
  echo "[didio-handler] Handler failed (exit=$HANDLER_EXIT)" >&2
  exit $HANDLER_EXIT
fi

# Find the most recent decision record for this feature
LATEST_DECISION=""
for f in "$DECISIONS_DIR"/D-*.json; do
  [[ -f "$f" ]] || continue
  LATEST_DECISION="$f"
done

if [[ -z "$LATEST_DECISION" ]]; then
  echo "[didio-handler] WARNING: no decision record found in $DECISIONS_DIR" >&2
  exit 0
fi

DECISION_ID="$(basename "$LATEST_DECISION" .json)"
echo "[didio-handler] decision record: $LATEST_DECISION" >&2

# Source negotiation loop library
if [[ -f "$PROJECT_ROOT/bin/didio-negotiation-loop.sh" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/bin/didio-negotiation-loop.sh"
else
  # shellcheck disable=SC1090
  source "$DIDIO_HOME/bin/didio-negotiation-loop.sh"
fi

# Auto-governance: negotiate with GateKeeper if enabled
AUTO_GOV="$(didio_auto_governance)"
if [[ "$AUTO_GOV" == "true" ]]; then
  GATEKEEPER_ENABLED="$(didio_gatekeeper_enabled)"
  if [[ "$GATEKEEPER_ENABLED" == "true" ]]; then
    echo "[didio-handler] auto-governance: starting negotiation for $DECISION_ID..." >&2
    didio_negotiate "$FEATURE" "$LATEST_DECISION" "$EXTRA"
    NEGOTIATE_EXIT=$?

    case $NEGOTIATE_EXIT in
      0)
        echo "[didio-handler] governance: AGREED — proceeding with pipeline" >&2
        ;;
      1)
        echo "[didio-handler] governance: negotiation FAILED (agent error)" >&2
        exit 1
        ;;
      2)
        echo "[didio-handler] governance: ESCALATED — pipeline BLOCKED. Human review required." >&2
        echo "[didio-handler] decision: $LATEST_DECISION" >&2
        echo "[didio-handler] summary: $PROJECT_ROOT/logs/governance/G-${DECISION_ID}-summary.json" >&2
        # F30-T10 — raise an escalated flag when negotiation escalates
        if declare -F didio_flag_raise >/dev/null 2>&1; then
          didio_flag_raise "$FEATURE" "escalated" "" "Negotiation escalated for decision $DECISION_ID — human review required" >/dev/null 2>&1 || true
        fi
        exit 3
        ;;
      *)
        echo "[didio-handler] governance: unexpected exit code $NEGOTIATE_EXIT — proceeding cautiously" >&2
        ;;
    esac
  else
    echo "[didio-handler] auto-governance: GateKeeper disabled, skipping governance review" >&2
  fi
fi

# Execute actions from the decision (if not escalated)
STATUS=$(python3 -c "
import json
with open('$LATEST_DECISION') as f:
    print(json.load(f).get('status', 'pending'))
" 2>/dev/null || echo "pending")

if [[ "$STATUS" == "escalated" ]]; then
  echo "[didio-handler] decision escalated — not executing actions" >&2
  exit 3
fi

# Read and execute actions
echo "[didio-handler] executing actions from $DECISION_ID..." >&2
python3 - "$LATEST_DECISION" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
actions = d.get('actions', [])
for i, a in enumerate(actions):
    action = a.get('action', '')
    feature = a.get('feature', '')
    print(f"  [{i+1}/{len(actions)}] {action} {feature}")
PY

# Update decision status to executed
python3 -c "
import json
from datetime import datetime, timezone
with open('$LATEST_DECISION') as f:
    d = json.load(f)
d['status'] = 'executed'
d['executed_at'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
with open('$LATEST_DECISION', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null || true

echo "[didio-handler] decision $DECISION_ID executed" >&2
