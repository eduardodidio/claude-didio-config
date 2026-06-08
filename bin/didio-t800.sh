#!/usr/bin/env bash
# didio-t800.sh — Gandalf Strategic Orchestrator launcher
#
# Usage:
#   didio t800 <feature-id> <brief-or-request-file> [extra-prompt]
#   didio t800 --checkpoint <decision-id>
#
# Spawns the Gandalf meta-agent to make a strategic decision. If
# auto_governance is enabled, automatically spawns Saruman after.

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
  didio t800 <feature-id> <brief-or-request-file> [extra-prompt]
  didio t800 --checkpoint <decision-id>

Spawns the Gandalf strategic orchestrator to produce a decision record
in logs/decisions/D-YYYYMMDD-NNN.json.

If meta_agents.t800.auto_governance is true, the Saruman governance
reviewer is automatically spawned after the decision is produced.

OPTIONS:
  --checkpoint <id>   Re-evaluate an existing decision (mid-pipeline check)
  --help, -h          Show this help and exit.

REQUIRES: meta_agents.t800.enabled = true in didio.config.json
EOF
  exit 0
fi

# Check if Gandalf is enabled
T800_ENABLED="$(didio_t800_enabled)"
if [[ "$T800_ENABLED" != "true" ]]; then
  echo "[didio-t800] Gandalf is disabled. Set meta_agents.t800.enabled=true in didio.config.json" >&2
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
    echo "[didio-t800] decision not found: $DECISION_FILE" >&2
    exit 2
  fi
  echo "[didio-t800] checkpoint mode for $DECISION_ID" >&2
  "$DIDIO_HOME/bin/didio-spawn-agent.sh" t800 "META" "$DECISION_FILE" "MODE=checkpoint"
  exit $?
fi

# Normal decision mode
FEATURE="${1:?feature-id required (e.g. F01)}"
REQUEST_FILE="${2:?brief or request file required}"
EXTRA="${3:-}"

if [[ ! -f "$REQUEST_FILE" ]]; then
  echo "[didio-t800] request file not found: $REQUEST_FILE" >&2
  exit 2
fi

# Copy request to _requests/ for audit trail
TS="$(date +%Y%m%d-%H%M%S)"
cp "$REQUEST_FILE" "$REQUESTS_DIR/${FEATURE}-${TS}.md"

echo "[didio-t800] spawning Gandalf for $FEATURE..." >&2

# Spawn Gandalf
"$DIDIO_HOME/bin/didio-spawn-agent.sh" t800 "$FEATURE" "$REQUEST_FILE" "$EXTRA"
T800_EXIT=$?

if [[ $T800_EXIT -ne 0 ]]; then
  echo "[didio-t800] Gandalf failed (exit=$T800_EXIT)" >&2
  exit $T800_EXIT
fi

# Find the most recent decision record for this feature
LATEST_DECISION=""
for f in "$DECISIONS_DIR"/D-*.json; do
  [[ -f "$f" ]] || continue
  LATEST_DECISION="$f"
done

if [[ -z "$LATEST_DECISION" ]]; then
  echo "[didio-t800] WARNING: no decision record found in $DECISIONS_DIR" >&2
  exit 0
fi

DECISION_ID="$(basename "$LATEST_DECISION" .json)"
echo "[didio-t800] decision record: $LATEST_DECISION" >&2

# Auto-governance: spawn Saruman if enabled
AUTO_GOV="$(didio_auto_governance)"
if [[ "$AUTO_GOV" == "true" ]]; then
  T1000_ENABLED="$(didio_t1000_enabled)"
  if [[ "$T1000_ENABLED" == "true" ]]; then
    echo "[didio-t800] auto-governance: spawning Saruman for $DECISION_ID..." >&2
    "$DIDIO_HOME/bin/didio-t1000.sh" --decision "$DECISION_ID"
    T1000_EXIT=$?

    if [[ $T1000_EXIT -ne 0 ]]; then
      echo "[didio-t800] Saruman governance review failed (exit=$T1000_EXIT)" >&2
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
          echo "[didio-t800] governance: AGREE — proceeding with pipeline" >&2
          ;;
        challenge)
          echo "[didio-t800] governance: CHALLENGE — Gandalf re-evaluating (max 1 round)..." >&2
          # Re-spawn Gandalf with governance feedback
          "$DIDIO_HOME/bin/didio-spawn-agent.sh" t800 "$FEATURE" "$LATEST_DECISION" \
            "MODE=re-evaluate GOVERNANCE_FILE=$GOV_FILE — The Saruman has challenged your decision. Read the governance report and reconsider. Update the decision record if warranted. This is the final round — no further challenges."
          ;;
        escalate)
          echo "[didio-t800] governance: ESCALATE — pipeline BLOCKED. Human review required." >&2
          echo "[didio-t800] decision: $LATEST_DECISION" >&2
          echo "[didio-t800] governance: $GOV_FILE" >&2
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
          echo "[didio-t800] governance: unknown verdict '$VERDICT' — proceeding cautiously" >&2
          ;;
      esac
    fi
  else
    echo "[didio-t800] auto-governance: Saruman disabled, skipping governance review" >&2
  fi
fi

# Execute actions from the decision (if not escalated)
STATUS=$(python3 -c "
import json
with open('$LATEST_DECISION') as f:
    print(json.load(f).get('status', 'pending'))
" 2>/dev/null || echo "pending")

if [[ "$STATUS" == "escalated" ]]; then
  echo "[didio-t800] decision escalated — not executing actions" >&2
  exit 3
fi

# Read and execute actions
echo "[didio-t800] executing actions from $DECISION_ID..." >&2
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

echo "[didio-t800] decision $DECISION_ID executed" >&2
