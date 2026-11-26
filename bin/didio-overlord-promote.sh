#!/usr/bin/env bash
# didio-overlord-promote.sh — Promote a triaged War Room card to a Standard Board feature
#
# Usage:
#   didio overlord promote <card-id>
#
# Reads the card JSON, validates that overlord_assessment.recommendation=promote,
# determines the next feature ID, creates a feature brief stub, updates the card,
# and prints the promotion summary.

set -euo pipefail

PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$PWD}"
CARDS_DIR="$PROJECT_ROOT/logs/warroom/cards"
FEATURES_DIR="$PROJECT_ROOT/tasks/features"

# ---------------------------------------------------------------------------
# Helpers (shared with warroom CLI)
# ---------------------------------------------------------------------------

_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# Feature ID allocation
# ---------------------------------------------------------------------------

# Scan tasks/features/ for directories matching F<digits>-* and return the
# next sequential feature number. Handles race conditions by checking if the
# directory already exists and incrementing.
_next_feature_id() {
  local max=0
  if [[ -d "$FEATURES_DIR" ]]; then
    for dir in "$FEATURES_DIR"/F[0-9]*-*/; do
      [[ -d "$dir" ]] || continue
      local base
      base="$(basename "$dir")"
      # Extract numeric part: F32-foo -> 32
      local num_str="${base#F}"
      num_str="${num_str%%-*}"
      # Skip non-pure-numeric (e.g. F29A, FXX)
      [[ "$num_str" =~ ^[0-9]+$ ]] || continue
      local num=$((10#$num_str))
      if [[ $num -gt $max ]]; then max=$num; fi
    done
    # Also check _tmp-brief files (e.g. F29A-_tmp-brief.md patterns)
    for brief in "$FEATURES_DIR"/F[0-9]*-_tmp-brief.md; do
      [[ -f "$brief" ]] || continue
      local base
      base="$(basename "$brief")"
      local num_str="${base#F}"
      num_str="${num_str%%-*}"
      # Only pure numeric (skip F29A etc)
      if [[ "$num_str" =~ ^[0-9]+$ ]]; then
        local num=$((10#$num_str)) 2>/dev/null || continue
        if [[ $num -gt $max ]]; then max=$num; fi
      fi
    done
  fi
  local next=$((max + 1))
  printf 'F%02d' "$next"
}

# ---------------------------------------------------------------------------
# Slugify a title for directory/file naming
# ---------------------------------------------------------------------------
_slugify() {
  local title="$1"
  # Lowercase, replace spaces/special chars with hyphens, trim
  echo "$title" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' \
    | cut -c1-40
}

# ---------------------------------------------------------------------------
# Main: promote
# ---------------------------------------------------------------------------

cmd_help() {
  cat <<'EOF'
USAGE:
  didio overlord promote <card-id>

Promotes a triaged War Room card to a Standard Board feature.

Requirements:
  - Card must exist in logs/warroom/cards/
  - Card must have overlord_assessment with recommendation="promote"

Actions:
  - Determines next feature ID (scans tasks/features/)
  - Creates feature brief at tasks/features/<FXX>-_tmp-brief.md
  - Updates card: promoted_to="<FXX>", status="promoted"
  - Prints: "Promoted WR-XXX -> F<NN>: <title>"
EOF
}

cmd_promote() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: didio overlord promote <card-id>" >&2
    exit 1
  fi

  local card_id="$1"
  local card_file="$CARDS_DIR/${card_id}.json"

  # 1. Validate card exists
  if [[ ! -f "$card_file" ]]; then
    echo "Error: card '$card_id' not found at $card_file" >&2
    exit 1
  fi

  # 2. Validate assessment exists and recommendation is "promote"
  local recommendation
  recommendation="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
a = d.get('overlord_assessment')
if a and isinstance(a, dict):
    print(a.get('recommendation', ''))
else:
    print('')
" "$card_file" 2>/dev/null || echo "")"

  if [[ -z "$recommendation" ]]; then
    echo "Error: card '$card_id' has no overlord_assessment. Run triage first." >&2
    exit 1
  fi

  if [[ "$recommendation" != "promote" ]]; then
    echo "Error: card '$card_id' assessment recommendation is '$recommendation', not 'promote'." >&2
    exit 1
  fi

  # 3. Read card title and body
  local title body
  title="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('title', ''))
" "$card_file")"

  body="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('body', ''))
" "$card_file")"

  # 4. Determine next feature ID
  local feature_id
  feature_id="$(_next_feature_id)"

  # 5. Create feature brief at tasks/features/<FXX>-_tmp-brief.md
  mkdir -p "$FEATURES_DIR"
  local brief_file="$FEATURES_DIR/${feature_id}-_tmp-brief.md"

  # Handle race condition: if brief already exists, increment
  while [[ -f "$brief_file" ]] || [[ -d "$FEATURES_DIR/${feature_id}-"* ]]; do
    local num="${feature_id#F}"
    num=$((10#$num + 1))
    feature_id="$(printf 'F%02d' "$num")"
    brief_file="$FEATURES_DIR/${feature_id}-_tmp-brief.md"
  done

  cat > "$brief_file" <<EOF
# ${feature_id} -- ${title}

**Status:** planned
**Origin:** War Room card ${card_id}

## Goal

${body:-_(no body provided in War Room card)_}

## Wave Manifest

_To be planned by Architect._
EOF

  # 6. Update card JSON: promoted_to, status, updated_at
  local now
  now="$(_now_iso)"

  python3 -c "
import json, sys
card_file = sys.argv[1]
feature_id = sys.argv[2]
now = sys.argv[3]
title = sys.argv[4]

with open(card_file, 'r', encoding='utf-8') as f:
    d = json.load(f)

d['promoted_to'] = feature_id
d['status'] = 'promoted'
d['updated_at'] = now

# Also update the assessment's promoted_as field
if d.get('overlord_assessment') and isinstance(d['overlord_assessment'], dict):
    d['overlord_assessment']['promoted_as'] = feature_id + ' -- ' + title

with open(card_file, 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$card_file" "$feature_id" "$now" "$title"

  # 7. Print summary
  echo "Promoted ${card_id} -> ${feature_id}: ${title}"
  echo "  Brief: ${brief_file}"
}

# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cmd_help
  exit 0
fi

cmd_promote "$@"
