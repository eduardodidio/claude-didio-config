#!/usr/bin/env bash
# didio-t1000.sh — Saruman Governance Reviewer launcher
#
# Usage:
#   didio t1000 --decision <decision-id>
#   didio t1000 --pending
#
# Spawns the Saruman meta-agent to review a decision produced by Gandalf.
# The Saruman reads ONLY the decision record, CLAUDE.md, and didio.config.json.

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
  didio t1000 --decision <decision-id>
  didio t1000 --pending

Spawns the Saruman governance reviewer to audit a Gandalf decision.

OPTIONS:
  --decision <id>   Review a specific decision (e.g. D-20260605-001)
  --pending         Find and review all decisions with status=pending
  --help, -h        Show this help and exit.

REQUIRES: meta_agents.t1000.enabled = true in didio.config.json
EOF
  exit 0
fi

# Check if Saruman is enabled
T1000_ENABLED="$(didio_t1000_enabled)"
if [[ "$T1000_ENABLED" != "true" ]]; then
  echo "[didio-t1000] Saruman is disabled. Set meta_agents.t1000.enabled=true in didio.config.json" >&2
  exit 1
fi

DECISIONS_DIR="$PROJECT_ROOT/logs/decisions"
GOVERNANCE_DIR="$PROJECT_ROOT/logs/governance"
mkdir -p "$GOVERNANCE_DIR"

# Parse arguments
DECISION_ID=""
REVIEW_PENDING=false

case "${1:-}" in
  --decision)
    DECISION_ID="${2:?decision-id required (e.g. D-20260605-001)}"
    ;;
  --pending)
    REVIEW_PENDING=true
    ;;
  *)
    echo "[didio-t1000] usage: didio t1000 --decision <id> | --pending" >&2
    exit 1
    ;;
esac

review_decision() {
  local decision_id="$1"
  local decision_file="$DECISIONS_DIR/${decision_id}.json"

  if [[ ! -f "$decision_file" ]]; then
    echo "[didio-t1000] decision not found: $decision_file" >&2
    return 2
  fi

  echo "[didio-t1000] reviewing $decision_id..." >&2

  # Spawn Saruman with restricted context
  "$DIDIO_HOME/bin/didio-spawn-agent.sh" t1000 "META" "$decision_file" \
    "RESTRICTED_CONTEXT=true — You may ONLY read: this decision record, CLAUDE.md, didio.config.json, and other files in logs/decisions/. Do NOT read any other files."
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    echo "[didio-t1000] Saruman review failed for $decision_id (exit=$exit_code)" >&2
    return $exit_code
  fi

  # Check if governance report was produced
  local gov_file="$GOVERNANCE_DIR/G-${decision_id}.json"
  if [[ ! -f "$gov_file" ]]; then
    echo "[didio-t1000] WARNING: no governance report produced for $decision_id" >&2
    return 0
  fi

  # Read verdict
  local verdict
  verdict=$(python3 -c "
import json
with open('$gov_file') as f:
    g = json.load(f)
print(g.get('verdict', 'unknown'))
" 2>/dev/null || echo "unknown")

  # Update decision record with governance section
  python3 - "$decision_file" "$gov_file" <<'PY' 2>/dev/null || true
import json, sys
dec_path, gov_path = sys.argv[1], sys.argv[2]
with open(dec_path) as f:
    d = json.load(f)
with open(gov_path) as f:
    g = json.load(f)
d['governance'] = g
d['status'] = 'reviewed'
with open(dec_path, 'w') as f:
    json.dump(d, f, indent=2)
PY

  echo "[didio-t1000] verdict for $decision_id: $verdict" >&2

  # Handle escalation
  if [[ "$verdict" == "escalate" ]]; then
    ESCALATION_BLOCKS="$(didio_read_config_path 'meta_agents.t1000.escalation_blocks_pipeline' 'true')"
    if [[ "$ESCALATION_BLOCKS" == "true" ]]; then
      echo "[didio-t1000] ESCALATION: pipeline blocked for $decision_id" >&2
      echo "[didio-t1000]   Decision: $decision_file" >&2
      echo "[didio-t1000]   Report:   $gov_file" >&2
      echo "[didio-t1000]   Action:   Human review required before pipeline can proceed" >&2
      return 3
    fi
  fi

  return 0
}

if [[ "$REVIEW_PENDING" == "true" ]]; then
  # Find all pending decisions
  FOUND=0
  for f in "$DECISIONS_DIR"/D-*.json; do
    [[ -f "$f" ]] || continue
    STATUS=$(python3 -c "
import json
with open('$f') as fp:
    print(json.load(fp).get('status', ''))
" 2>/dev/null || echo "")
    if [[ "$STATUS" == "pending" ]]; then
      DID="$(basename "$f" .json)"
      review_decision "$DID"
      FOUND=$((FOUND + 1))
    fi
  done
  if [[ $FOUND -eq 0 ]]; then
    echo "[didio-t1000] no pending decisions found" >&2
  else
    echo "[didio-t1000] reviewed $FOUND pending decision(s)" >&2
  fi
else
  review_decision "$DECISION_ID"
fi
