#!/usr/bin/env bash
# didio-warroom.sh — War Room card management CLI
#
# Usage:
#   didio warroom add "title" [--body "text"] [--tags "tag1,tag2"] [--priority medium] [--source operator]
#   didio warroom list [--status incoming|triaging|promoted|deferred|archived] [--all] [--format table|json]
#   didio warroom show <card-id>
#   didio warroom move <card-id> <status>

set -euo pipefail

# -- Resolve project root (cards live in the project, not DIDIO_HOME) --
PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$PWD}"
CARDS_DIR="$PROJECT_ROOT/logs/warroom/cards"

VALID_STATUSES="incoming triaging promoted deferred archived"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_ensure_cards_dir() {
  mkdir -p "$CARDS_DIR"
}

# Generate ISO-8601 timestamp compatible with Git Bash / MINGW
_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Today as YYYYMMDD
_today() {
  date -u +"%Y%m%d"
}

# Build a JSON string without requiring jq (printf fallback for Windows Git Bash).
# If jq is available, we use it for correctness; otherwise printf.
_has_jq() {
  command -v jq >/dev/null 2>&1
}

# Escape a string for safe JSON embedding (printf fallback)
_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Build tags JSON array from comma-separated string
_tags_to_json() {
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    printf '[]'
    return
  fi
  local first=1 out="["
  IFS=',' read -ra parts <<< "$raw"
  for t in "${parts[@]}"; do
    t="$(echo "$t" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$t" ]] && continue
    if [[ $first -eq 1 ]]; then first=0; else out+=","; fi
    out+="\"$(_json_escape "$t")\""
  done
  out+="]"
  printf '%s' "$out"
}

# Validate status value
_validate_status() {
  local s="$1"
  for valid in $VALID_STATUSES; do
    [[ "$s" == "$valid" ]] && return 0
  done
  echo "Error: invalid status '$s'. Must be one of: $VALID_STATUSES" >&2
  return 1
}

# Read a JSON field from a card file using python3 (portable)
_card_field() {
  local file="$1" field="$2"
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
v = d.get(sys.argv[2])
if v is None:
    print('')
elif isinstance(v, list):
    print(', '.join(str(x) for x in v))
elif isinstance(v, dict):
    print(json.dumps(v, indent=2))
else:
    print(str(v))
" "$file" "$field" 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# Subcommand: add
# ---------------------------------------------------------------------------
cmd_add() {
  if [[ $# -lt 1 || "${1:-}" == --* ]]; then
    echo "Usage: didio warroom add \"title\" [--body \"text\"] [--tags \"a,b\"] [--priority medium] [--source operator]" >&2
    exit 1
  fi

  local title="$1"; shift
  local body="" tags_raw="" priority="" source_val="operator"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body)     body="${2:?--body requires a value}"; shift 2 ;;
      --body=*)   body="${1#--body=}"; shift ;;
      --tags)     tags_raw="${2:?--tags requires a value}"; shift 2 ;;
      --tags=*)   tags_raw="${1#--tags=}"; shift ;;
      --priority) priority="${2:?--priority requires a value}"; shift 2 ;;
      --priority=*) priority="${1#--priority=}"; shift ;;
      --source)   source_val="${2:?--source requires a value}"; shift 2 ;;
      --source=*) source_val="${1#--source=}"; shift ;;
      *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done

  _ensure_cards_dir

  local today
  today="$(_today)"

  # Determine next sequence number
  local seq=1
  if compgen -G "$CARDS_DIR/WR-${today}-*.json" > /dev/null 2>&1; then
    local max=0
    for f in "$CARDS_DIR"/WR-"${today}"-*.json; do
      local basename_f
      basename_f="$(basename "$f" .json)"
      local num_str="${basename_f##*-}"
      # Strip leading zeros for arithmetic
      local num=$((10#$num_str))
      if [[ $num -gt $max ]]; then max=$num; fi
    done
    seq=$((max + 1))
  fi

  local card_id
  card_id="$(printf 'WR-%s-%03d' "$today" "$seq")"
  local now
  now="$(_now_iso)"
  local tags_json
  tags_json="$(_tags_to_json "$tags_raw")"

  local priority_json="null"
  if [[ -n "$priority" ]]; then
    priority_json="\"$(_json_escape "$priority")\""
  fi

  local card_file="$CARDS_DIR/${card_id}.json"

  if _has_jq; then
    jq -n \
      --arg card_id "$card_id" \
      --arg title "$title" \
      --arg body "$body" \
      --arg source "$source_val" \
      --arg created_at "$now" \
      --arg status "incoming" \
      --argjson priority_suggestion "$priority_json" \
      --argjson tags "$tags_json" \
      '{
        card_id: $card_id,
        title: $title,
        body: $body,
        source: $source,
        created_at: $created_at,
        updated_at: null,
        status: $status,
        priority_suggestion: $priority_suggestion,
        overlord_assessment: null,
        promoted_to: null,
        tags: $tags,
        source_agent: null,
        source_feature: null
      }' > "$card_file"
  else
    # printf fallback
    cat > "$card_file" <<ENDJSON
{
  "card_id": "$(_json_escape "$card_id")",
  "title": "$(_json_escape "$title")",
  "body": "$(_json_escape "$body")",
  "source": "$(_json_escape "$source_val")",
  "created_at": "$(_json_escape "$now")",
  "updated_at": null,
  "status": "incoming",
  "priority_suggestion": ${priority_json},
  "overlord_assessment": null,
  "promoted_to": null,
  "tags": ${tags_json},
  "source_agent": null,
  "source_feature": null
}
ENDJSON
  fi

  echo "Created card ${card_id}: ${title}"
  echo "  File: ${card_file}"
}

# ---------------------------------------------------------------------------
# Subcommand: list
# ---------------------------------------------------------------------------
cmd_list() {
  local filter_status="" show_all=0 format="table"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status)  filter_status="${2:?--status requires a value}"; shift 2 ;;
      --status=*) filter_status="${1#--status=}"; shift ;;
      --all)     show_all=1; shift ;;
      --format)  format="${2:?--format requires a value}"; shift 2 ;;
      --format=*) format="${1#--format=}"; shift ;;
      *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done

  _ensure_cards_dir

  # Validate filter_status if provided (allow "all" as a special value)
  if [[ -n "$filter_status" && "$filter_status" != "all" ]]; then
    _validate_status "$filter_status"
  fi
  if [[ "$filter_status" == "all" ]]; then
    show_all=1
    filter_status=""
  fi

  local cards=()
  local json_out="["
  local json_first=1
  local has_cards=0

  if [[ "$format" == "table" ]]; then
    printf '%-18s  %-10s  %-8s  %-50s  %-15s  %s\n' "CARD_ID" "STATUS" "PRIORITY" "TITLE" "TAGS" "CREATED"
    printf '%-18s  %-10s  %-8s  %-50s  %-15s  %s\n' "--------" "--------" "--------" "--------------------------------------------------" "---------------" "-------------------"
  fi

  for card_file in "$CARDS_DIR"/WR-*.json; do
    [[ -f "$card_file" ]] || continue

    local status
    status="$(_card_field "$card_file" "status")"

    # Filter: skip archived unless --all
    if [[ $show_all -eq 0 && "$status" == "archived" ]]; then
      continue
    fi

    # Filter by specific status
    if [[ -n "$filter_status" && "$status" != "$filter_status" ]]; then
      continue
    fi

    has_cards=1

    if [[ "$format" == "json" ]]; then
      local content
      content="$(cat "$card_file")"
      if [[ $json_first -eq 1 ]]; then json_first=0; else json_out+=","; fi
      json_out+="$content"
    else
      local card_id title priority tags created_at
      card_id="$(_card_field "$card_file" "card_id")"
      title="$(_card_field "$card_file" "title")"
      priority="$(_card_field "$card_file" "priority_suggestion")"
      tags="$(_card_field "$card_file" "tags")"
      created_at="$(_card_field "$card_file" "created_at")"

      [[ -z "$priority" ]] && priority="-"

      # Truncate title to 50 chars
      if [[ ${#title} -gt 50 ]]; then
        title="${title:0:47}..."
      fi

      printf '%-18s  %-10s  %-8s  %-50s  %-15s  %s\n' \
        "$card_id" "[$status]" "[$priority]" "$title" "$tags" "$created_at"
    fi
  done

  if [[ "$format" == "json" ]]; then
    json_out+="]"
    echo "$json_out"
  elif [[ $has_cards -eq 0 ]]; then
    echo "(no cards found)"
  fi
}

# ---------------------------------------------------------------------------
# Subcommand: show
# ---------------------------------------------------------------------------
cmd_show() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: didio warroom show <card_id>" >&2
    exit 1
  fi

  local card_id="$1"
  local card_file="$CARDS_DIR/${card_id}.json"

  if [[ ! -f "$card_file" ]]; then
    echo "Error: card '$card_id' not found at $card_file" >&2
    exit 1
  fi

  local title status source_val priority tags created_at body
  title="$(_card_field "$card_file" "title")"
  status="$(_card_field "$card_file" "status")"
  source_val="$(_card_field "$card_file" "source")"
  priority="$(_card_field "$card_file" "priority_suggestion")"
  tags="$(_card_field "$card_file" "tags")"
  created_at="$(_card_field "$card_file" "created_at")"
  body="$(_card_field "$card_file" "body")"

  [[ -z "$priority" ]] && priority="(none)"
  [[ -z "$tags" ]] && tags="(none)"

  cat <<EOF
Card ID:    $card_id
Title:      $title
Status:     $status
Source:     $source_val
Priority:   $priority
Tags:       $tags
Created:    $created_at

Body:
${body:-(empty)}

EOF

  # Show Overlord assessment if present
  local assessment
  assessment="$(_card_field "$card_file" "overlord_assessment")"
  if [[ -z "$assessment" || "$assessment" == "{}" ]]; then
    echo "Overlord Assessment:"
    echo "  (not yet triaged)"
  else
    echo "Overlord Assessment:"
    # Parse assessment fields
    local rec assess_priority rationale promoted_as
    rec="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
a = d.get('overlord_assessment')
if a and isinstance(a, dict):
    print(a.get('recommendation', ''))
else:
    print('')
" "$card_file" 2>/dev/null || echo "")"

    if [[ -n "$rec" ]]; then
      assess_priority="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
a = d.get('overlord_assessment', {})
print(a.get('priority', ''))
" "$card_file" 2>/dev/null || echo "")"
      rationale="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
a = d.get('overlord_assessment', {})
print(a.get('rationale', ''))
" "$card_file" 2>/dev/null || echo "")"
      promoted_as="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
a = d.get('overlord_assessment', {})
v = a.get('promoted_as')
print(v if v else '')
" "$card_file" 2>/dev/null || echo "")"

      echo "  Recommendation: $rec"
      echo "  Priority:       $assess_priority"
      echo "  Rationale:      $rationale"
      if [[ -n "$promoted_as" ]]; then
        echo "  Promoted as:    $promoted_as"
      fi
    else
      echo "  (not yet triaged)"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Subcommand: move
# ---------------------------------------------------------------------------
cmd_move() {
  if [[ $# -lt 2 ]]; then
    echo "Usage: didio warroom move <card_id> <status>" >&2
    echo "  Valid statuses: $VALID_STATUSES" >&2
    exit 1
  fi

  local card_id="$1"
  local new_status="$2"
  local card_file="$CARDS_DIR/${card_id}.json"

  if [[ ! -f "$card_file" ]]; then
    echo "Error: card '$card_id' not found at $card_file" >&2
    exit 1
  fi

  _validate_status "$new_status"

  local now
  now="$(_now_iso)"

  if _has_jq; then
    local tmp_file="${card_file}.tmp"
    jq --arg status "$new_status" --arg updated_at "$now" \
      '.status = $status | .updated_at = $updated_at' \
      "$card_file" > "$tmp_file" && mv "$tmp_file" "$card_file"
  else
    # python3 fallback
    python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
d['status'] = sys.argv[2]
d['updated_at'] = sys.argv[3]
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$card_file" "$new_status" "$now"
  fi

  echo "Card $card_id moved to '$new_status'"
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
cmd_help() {
  cat <<'EOF'
USAGE:
  didio warroom add "title" [--body "text"] [--tags "a,b"] [--priority medium] [--source operator]
      Create a new War Room card. Card ID is auto-generated as WR-YYYYMMDD-NNN.

  didio warroom list [--status <status>] [--all] [--format table|json]
      List War Room cards. Default: non-archived in table format.
      --status <s>     Filter by status (incoming|triaging|promoted|deferred|archived)
      --all            Include archived cards
      --format json    Output as JSON array

  didio warroom show <card_id>
      Display full details of a card, including Overlord assessment if present.

  didio warroom move <card_id> <status>
      Move a card to a new status.
      Valid statuses: incoming, triaging, promoted, deferred, archived

EXAMPLES:
  didio warroom add "Auth refactor needed" --body "Full description" --priority high --tags "auth,q1"
  didio warroom list --status incoming
  didio warroom list --format json
  didio warroom show WR-20261126-001
  didio warroom move WR-20261126-001 triaging
EOF
}

# ---------------------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------------------

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cmd_help
  exit 0
fi

SUBCMD="${1:-}"
shift || true

case "$SUBCMD" in
  add)   cmd_add "$@" ;;
  list)  cmd_list "$@" ;;
  show)  cmd_show "$@" ;;
  move)  cmd_move "$@" ;;
  help|""|--help|-h)
    cmd_help
    ;;
  *)
    echo "didio warroom: unknown subcommand '$SUBCMD'. Try 'didio warroom --help'." >&2
    exit 1
    ;;
esac
