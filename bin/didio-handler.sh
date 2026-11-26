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

# Auto-governance: spawn GateKeeper if enabled
AUTO_GOV="$(didio_auto_governance)"
if [[ "$AUTO_GOV" == "true" ]]; then
  GATEKEEPER_ENABLED="$(didio_gatekeeper_enabled)"
  if [[ "$GATEKEEPER_ENABLED" == "true" ]]; then
    echo "[didio-handler] auto-governance: spawning GateKeeper for $DECISION_ID..." >&2
    "$DIDIO_HOME/bin/didio-gatekeeper.sh" --decision "$DECISION_ID"
    GATEKEEPER_EXIT=$?

    if [[ $GATEKEEPER_EXIT -ne 0 ]]; then
      echo "[didio-handler] GateKeeper governance review failed (exit=$GATEKEEPER_EXIT)" >&2
    fi

    # Check governance verdict
    GOV_FILE="$PROJECT_ROOT/logs/governance/G-${DECISION_ID}.json"
    if [[ -f "$GOV_FILE" ]]; then
      VERDICT=$(python3 -c "
import json
with open('$GOV_FILE') as f:
    print(json.load(f).get('verdict', 'unknown'))
" 2>/dev/null || echo "unknown")

      case "$VERDICT" in
        agree)
          echo "[didio-handler] governance: AGREE — proceeding with pipeline" >&2
          ;;
        challenge)
          echo "[didio-handler] governance: CHALLENGE — Handler re-evaluating (max 1 round)..." >&2
          # Re-spawn Handler with governance feedback
          "$DIDIO_HOME/bin/didio-spawn-agent.sh" handler "$FEATURE" "$LATEST_DECISION" \
            "MODE=re-evaluate GOVERNANCE_FILE=$GOV_FILE — The GateKeeper has challenged your decision. Read the governance report and reconsider. Update the decision record if warranted. This is the final round — no further challenges."
          ;;
        escalate)
          echo "[didio-handler] governance: ESCALATE — pipeline BLOCKED. Human review required." >&2
          echo "[didio-handler] decision: $LATEST_DECISION" >&2
          echo "[didio-handler] governance: $GOV_FILE" >&2
          # Update decision status to blocked
          python3 -c "
import json
with open('$LATEST_DECISION') as f:
    d = json.load(f)
d['status'] = 'escalated'
with open('$LATEST_DECISION', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null || true
          exit 3
          ;;
        *)
          echo "[didio-handler] governance: unknown verdict '$VERDICT' — proceeding cautiously" >&2
          ;;
      esac
    fi
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
