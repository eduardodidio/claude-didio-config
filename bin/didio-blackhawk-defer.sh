#!/usr/bin/env bash
# didio-blackhawk-defer.sh — Defer a triaged War Room card
#
# Usage:
#   didio blackhawk defer <card-id>
#
# Reads the card JSON, updates status to "deferred", and writes the
# rationale from the overlord_assessment.

set -euo pipefail

PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$PWD}"
CARDS_DIR="$PROJECT_ROOT/logs/warroom/cards"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ---------------------------------------------------------------------------
# Main: defer
# ---------------------------------------------------------------------------

cmd_help() {
  cat <<'EOF'
USAGE:
  didio blackhawk defer <card-id>

Defers a triaged War Room card.

Requirements:
  - Card must exist in logs/warroom/cards/

Actions:
  - Updates card status to "deferred"
  - Writes rationale from overlord_assessment (if present)
  - Updates updated_at timestamp
  - Prints: "Deferred WR-XXX: <rationale>"
EOF
}

cmd_defer() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: didio blackhawk defer <card-id>" >&2
    exit 1
  fi

  local card_id="$1"
  local card_file="$CARDS_DIR/${card_id}.json"

  # 1. Validate card exists
  if [[ ! -f "$card_file" ]]; then
    echo "Error: card '$card_id' not found at $card_file" >&2
    exit 1
  fi

  # 2. Read assessment rationale (if any)
  local rationale
  rationale="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
a = d.get('overlord_assessment')
if a and isinstance(a, dict):
    print(a.get('rationale', 'No rationale provided'))
else:
    print('No assessment found -- deferred by operator')
" "$card_file" 2>/dev/null || echo "No rationale available")"

  # 3. Read card title for display
  local title
  title="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('title', ''))
" "$card_file" 2>/dev/null || echo "(unknown)")"

  # 4. Update card JSON: status=deferred, updated_at
  local now
  now="$(_now_iso)"

  python3 -c "
import json, sys
card_file = sys.argv[1]
now = sys.argv[2]

with open(card_file, 'r', encoding='utf-8') as f:
    d = json.load(f)

d['status'] = 'deferred'
d['updated_at'] = now

# If no assessment exists, add a minimal one
if not d.get('overlord_assessment') or not isinstance(d.get('overlord_assessment'), dict):
    d['overlord_assessment'] = {
        'assessed_at': now,
        'recommendation': 'defer',
        'priority': 'low',
        'rationale': 'Deferred by operator',
        'knowledge_refs': []
    }
elif d['overlord_assessment'].get('recommendation') != 'defer':
    # Update recommendation to match the action
    d['overlord_assessment']['recommendation'] = 'defer'

with open(card_file, 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$card_file" "$now"

  # 5. Print summary
  echo "Deferred ${card_id}: ${title}"
  echo "  Rationale: ${rationale}"
}

# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cmd_help
  exit 0
fi

cmd_defer "$@"
