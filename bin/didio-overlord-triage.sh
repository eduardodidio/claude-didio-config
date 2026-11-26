#!/usr/bin/env bash
# didio-overlord-triage.sh — Overlord triage CLI (single / batch / auto modes)
#
# Usage:
#   didio overlord triage --card WR-XXXXXXXX-NNN   # triage single card
#   didio overlord triage                           # triage ALL incoming cards (batch)
#   didio overlord triage --auto                    # continuous loop
#
# Flags:
#   --card <id>    Triage a single card by ID
#   --auto         Run batch triage in a continuous loop
#   --dry-run      Show what would happen without spawning agents or writing files
#   --help, -h     Show this help and exit
#
# Exit codes:
#   0 = success
#   1 = runtime error
#   2 = config / preflight issue

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$(pwd)}"
CARDS_DIR="$PROJECT_ROOT/logs/warroom/cards"
TRIAGE_LOG_DIR="$PROJECT_ROOT/logs/warroom"
CONTEXT_FILE="$TRIAGE_LOG_DIR/.triage-context.md"

# ---------------------------------------------------------------------------
# Source config lib
# ---------------------------------------------------------------------------

if [[ -f "$PROJECT_ROOT/bin/didio-config-lib.sh" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/bin/didio-config-lib.sh"
elif [[ -f "$DIDIO_HOME/bin/didio-config-lib.sh" ]]; then
  # shellcheck disable=SC1090
  source "$DIDIO_HOME/bin/didio-config-lib.sh"
else
  echo "[overlord-triage] ERROR: didio-config-lib.sh not found" >&2
  exit 2
fi

# Source triage library if it exists (T09 delivers lib/overlord-triage.sh)
TRIAGE_LIB="$PROJECT_ROOT/lib/overlord-triage.sh"
if [[ -f "$TRIAGE_LIB" ]]; then
  # shellcheck disable=SC1090
  source "$TRIAGE_LIB"
fi

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

show_help() {
  cat <<'EOF'
USAGE:
  didio overlord triage --card <card-id>   Triage a single War Room card
  didio overlord triage                    Batch triage ALL incoming cards
  didio overlord triage --auto             Continuous loop (runs every interval)

FLAGS:
  --card <id>    Card ID to triage (e.g. WR-20261126-001)
  --auto         Run batch triage in a periodic loop
  --dry-run      Preview what would happen without writing files or spawning
  --help, -h     Show this help and exit

EXIT CODES:
  0  Success
  1  Runtime error
  2  Config / preflight issue

EXAMPLES:
  didio overlord triage --card WR-20261126-001
  didio overlord triage --dry-run
  didio overlord triage --auto
EOF
}

# ---------------------------------------------------------------------------
# Timestamp helpers (portable across Git Bash / MINGW)
# ---------------------------------------------------------------------------

_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_now_file_ts() {
  date -u +"%Y%m%d-%H%M%S"
}

# ---------------------------------------------------------------------------
# JSON helpers (python3 — always available, no jq dependency)
# ---------------------------------------------------------------------------

# Read a field from a card JSON file
_card_field() {
  local file="$1" field="$2"
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
v = d.get(sys.argv[2])
if v is None:
    print('')
elif isinstance(v, (dict, list)):
    print(json.dumps(v))
else:
    print(str(v))
" "$file" "$field" 2>/dev/null || echo ""
}

# Update a card JSON file (sets key=value, updates updated_at)
_card_update() {
  local file="$1" now
  shift
  now="$(_now_iso)"
  python3 - "$file" "$now" "$@" <<'PY'
import json, sys
path = sys.argv[1]
now = sys.argv[2]
updates = {}
i = 3
while i < len(sys.argv):
    key = sys.argv[i]
    val = sys.argv[i+1]
    # Auto-detect type
    if val == "null":
        updates[key] = None
    elif val in ("true", "false"):
        updates[key] = val == "true"
    else:
        try:
            updates[key] = json.loads(val)
        except (json.JSONDecodeError, ValueError):
            updates[key] = val
    i += 2

with open(path, 'r', encoding='utf-8') as f:
    d = json.load(f)
for k, v in updates.items():
    d[k] = v
d['updated_at'] = now
with open(path, 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
PY
}

# Read a nested assessment field
_assessment_field() {
  local file="$1" field="$2"
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
a = d.get('overlord_assessment')
if a and isinstance(a, dict):
    v = a.get(sys.argv[2], '')
    if isinstance(v, (dict, list)):
        print(json.dumps(v))
    else:
        print(str(v) if v else '')
else:
    print('')
" "$file" "$field" 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

preflight() {
  local errors=0

  # 1. Config exists and overlord is enabled
  local config
  config="$(didio_find_config)"
  if [[ -z "$config" ]]; then
    echo "[overlord-triage] ERROR: didio.config.json not found." >&2
    echo "  Run /install-claude-didio-framework first." >&2
    return 2
  fi

  local enabled
  enabled="$(didio_overlord_enabled)"
  if [[ "$enabled" != "true" ]]; then
    echo "[overlord-triage] ERROR: Overlord is disabled in config." >&2
    echo "  Set overlord.enabled = true in didio.config.json to enable." >&2
    return 2
  fi

  # 2. Cards directory exists (or can be created)
  if [[ ! -d "$CARDS_DIR" ]]; then
    mkdir -p "$CARDS_DIR" 2>/dev/null || {
      echo "[overlord-triage] ERROR: Cannot create cards directory: $CARDS_DIR" >&2
      errors=$((errors + 1))
    }
  fi

  # 3. python3 available (used for JSON parsing)
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[overlord-triage] ERROR: python3 is required but not found in PATH." >&2
    errors=$((errors + 1))
  fi

  # 4. spawn-agent script exists
  local spawn_script="$PROJECT_ROOT/bin/didio-spawn-agent.sh"
  if [[ ! -f "$spawn_script" ]]; then
    spawn_script="$DIDIO_HOME/bin/didio-spawn-agent.sh"
  fi
  if [[ ! -f "$spawn_script" ]]; then
    echo "[overlord-triage] ERROR: didio-spawn-agent.sh not found." >&2
    errors=$((errors + 1))
  fi

  if [[ $errors -gt 0 ]]; then
    return 2
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Knowledge gathering
# ---------------------------------------------------------------------------

gather_knowledge() {
  # If the triage library provides this, delegate
  if declare -F gather_knowledge_impl >/dev/null 2>&1; then
    gather_knowledge_impl
    return $?
  fi

  mkdir -p "$TRIAGE_LOG_DIR"

  local adr_count=0 learnings_count=0 feature_count=0

  {
    echo "# Triage Knowledge Context"
    echo ""
    echo "Generated at: $(_now_iso)"
    echo ""

    # ADRs
    echo "## Architecture Decision Records"
    echo ""
    if compgen -G "$PROJECT_ROOT/docs/adr/*.md" > /dev/null 2>&1; then
      for f in "$PROJECT_ROOT"/docs/adr/*.md; do
        [[ -f "$f" ]] || continue
        adr_count=$((adr_count + 1))
        echo "### $(basename "$f")"
        cat "$f"
        echo ""
      done
    fi
    if [[ $adr_count -eq 0 ]]; then
      echo "(no ADRs found)"
      echo ""
    fi

    # Agent learnings
    echo "## Agent Learnings"
    echo ""
    if compgen -G "$PROJECT_ROOT/memory/agent-learnings/*.md" > /dev/null 2>&1; then
      for f in "$PROJECT_ROOT"/memory/agent-learnings/*.md; do
        [[ -f "$f" ]] || continue
        learnings_count=$((learnings_count + 1))
        echo "### $(basename "$f")"
        cat "$f"
        echo ""
      done
    fi
    if [[ $learnings_count -eq 0 ]]; then
      echo "(no learnings found)"
      echo ""
    fi

    # Existing features (for dedup)
    echo "## Existing Features"
    echo ""
    if compgen -G "$PROJECT_ROOT/tasks/features/*/F*-README.md" > /dev/null 2>&1; then
      for f in "$PROJECT_ROOT"/tasks/features/*/F*-README.md; do
        [[ -f "$f" ]] || continue
        feature_count=$((feature_count + 1))
        echo "- $(basename "$(dirname "$f")"): $(head -1 "$f" | sed 's/^#\s*//')"
      done
    fi
    if [[ $feature_count -eq 0 ]]; then
      echo "(no existing features)"
    fi
    echo ""

    # Recent decisions (last 10)
    echo "## Recent Decisions"
    echo ""
    if compgen -G "$PROJECT_ROOT/logs/decisions/D-*.json" > /dev/null 2>&1; then
      local dec_files
      # Sort by name descending, take last 10
      dec_files=("$PROJECT_ROOT"/logs/decisions/D-*.json)
      local start=0
      if [[ ${#dec_files[@]} -gt 10 ]]; then
        start=$(( ${#dec_files[@]} - 10 ))
      fi
      for ((i=start; i<${#dec_files[@]}; i++)); do
        echo "- $(basename "${dec_files[$i]}")"
      done
    else
      echo "(no decisions found)"
    fi
    echo ""

    # Recent governance reviews (last 10)
    echo "## Recent Governance Reviews"
    echo ""
    if compgen -G "$PROJECT_ROOT/logs/governance/G-*.json" > /dev/null 2>&1; then
      local gov_files
      gov_files=("$PROJECT_ROOT"/logs/governance/G-*.json)
      local start=0
      if [[ ${#gov_files[@]} -gt 10 ]]; then
        start=$(( ${#gov_files[@]} - 10 ))
      fi
      for ((i=start; i<${#gov_files[@]}; i++)); do
        echo "- $(basename "${gov_files[$i]}")"
      done
    else
      echo "(no governance reviews found)"
    fi
    echo ""

  } > "$CONTEXT_FILE"

  echo "$adr_count ADRs, $learnings_count learnings, $feature_count features"
}

# ---------------------------------------------------------------------------
# Next feature ID allocation
# ---------------------------------------------------------------------------

_next_feature_id() {
  local max=0
  if compgen -G "$PROJECT_ROOT/tasks/features/F*-*" > /dev/null 2>&1; then
    for d in "$PROJECT_ROOT"/tasks/features/F*-*/; do
      [[ -d "$d" ]] || continue
      local dirname
      dirname="$(basename "$d")"
      local num_str="${dirname%%-*}"
      num_str="${num_str#F}"
      local num
      num=$((10#$num_str)) 2>/dev/null || continue
      if [[ $num -gt $max ]]; then max=$num; fi
    done
  fi

  local next=$((max + 1))
  printf 'F%02d' "$next"
}

# ---------------------------------------------------------------------------
# Promote card to feature
# ---------------------------------------------------------------------------

promote_card() {
  local card_id="$1"
  local card_file="$CARDS_DIR/${card_id}.json"

  local title body promoted_as
  title="$(_card_field "$card_file" "title")"
  body="$(_card_field "$card_file" "body")"
  promoted_as="$(_assessment_field "$card_file" "promoted_as")"

  # Determine feature name from assessment or card title
  local feature_name="${promoted_as:-$title}"

  local feature_id
  feature_id="$(_next_feature_id)"

  # Create slug from feature name
  local slug
  slug="$(echo "$feature_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-40)"

  local feature_dir="$PROJECT_ROOT/tasks/features/${feature_id}-${slug}"

  # Handle race condition: if directory exists, bump ID
  while [[ -d "$feature_dir" ]]; do
    local num="${feature_id#F}"
    num=$((10#$num + 1))
    feature_id="$(printf 'F%02d' "$num")"
    feature_dir="$PROJECT_ROOT/tasks/features/${feature_id}-${slug}"
  done

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [DRY_RUN] Would create feature: ${feature_id} -- ${feature_name}"
    echo "  [DRY_RUN] Directory: ${feature_dir}"
    return 0
  fi

  mkdir -p "$feature_dir"

  # Create feature README stub
  cat > "$feature_dir/${feature_id}-README.md" <<READMEEOF
# ${feature_id} -- ${feature_name}

**Status:** planned
**Origin:** War Room card ${card_id}

## Goal

${body:-(no description provided)}

## Wave Manifest

_To be planned by Architect._
READMEEOF

  # Update card: status = promoted, promoted_to = feature_id
  _card_update "$card_file" \
    "status" "promoted" \
    "promoted_to" "$feature_id"

  echo "${feature_id} -- ${feature_name}"
}

# ---------------------------------------------------------------------------
# Defer card
# ---------------------------------------------------------------------------

defer_card() {
  local card_id="$1"
  local card_file="$CARDS_DIR/${card_id}.json"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [DRY_RUN] Would defer card: ${card_id}"
    return 0
  fi

  _card_update "$card_file" "status" "deferred"
}

# ---------------------------------------------------------------------------
# Archive card
# ---------------------------------------------------------------------------

archive_card() {
  local card_id="$1"
  local card_file="$CARDS_DIR/${card_id}.json"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [DRY_RUN] Would archive card: ${card_id}"
    return 0
  fi

  _card_update "$card_file" "status" "archived"
}

# ---------------------------------------------------------------------------
# Assess a single card
# ---------------------------------------------------------------------------

assess_card() {
  local card_id="$1"
  local card_file="$CARDS_DIR/${card_id}.json"

  if [[ ! -f "$card_file" ]]; then
    echo "[overlord-triage] ERROR: Card not found: ${card_id}" >&2
    echo "  Expected file: ${card_file}" >&2
    return 1
  fi

  # Validate card status
  local status
  status="$(_card_field "$card_file" "status")"
  if [[ "$status" != "incoming" && "$status" != "triaging" ]]; then
    echo "[overlord-triage] ERROR: Card ${card_id} has status '${status}'." >&2
    echo "  Only 'incoming' or 'triaging' cards can be triaged." >&2
    return 1
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    local title
    title="$(_card_field "$card_file" "title")"
    echo "  [DRY_RUN] Would triage card: ${card_id} (\"${title}\")"
    echo "  [DRY_RUN]   Set status -> triaging"
    echo "  [DRY_RUN]   Spawn overlord agent with card + context"
    echo "  [DRY_RUN]   Process assessment and update card"
    return 0
  fi

  # Set status to triaging
  _card_update "$card_file" "status" "triaging"

  # Build task file for the overlord agent
  local task_tmp
  task_tmp="$(mktemp "${TMPDIR:-/tmp}/overlord-triage-XXXXXX.md")"

  {
    echo "# Overlord Triage Task"
    echo ""
    echo "## Mode: Single Card Triage"
    echo ""
    echo "TRIAGE_MODE=single"
    echo "CARD_ID=${card_id}"
    echo ""
    echo "## Card to Triage"
    echo ""
    echo '```json'
    cat "$card_file"
    echo '```'
    echo ""
    echo "## Knowledge Context"
    echo ""
    if [[ -f "$CONTEXT_FILE" ]]; then
      cat "$CONTEXT_FILE"
    else
      echo "(no context gathered)"
    fi
    echo ""
    echo "## Instructions"
    echo ""
    echo "Assess this card following the triage process in your prompt."
    echo "Write your assessment by updating the card JSON file at:"
    echo "  ${card_file}"
    echo ""
    echo "Update the card with:"
    echo "1. Set overlord_assessment object (recommendation, priority, rationale, knowledge_refs)"
    echo "2. If recommending 'promote', include promoted_as with a suggested feature title"
    echo "3. Do NOT change the card status -- the CLI will handle status transitions"
  } > "$task_tmp"

  # Spawn overlord agent
  local spawn_script="$PROJECT_ROOT/bin/didio-spawn-agent.sh"
  if [[ ! -f "$spawn_script" ]]; then
    spawn_script="$DIDIO_HOME/bin/didio-spawn-agent.sh"
  fi

  local spawn_exit=0
  DIDIO_TOLERATE_TOOL_ERRORS=1 \
    "$spawn_script" overlord WARROOM "$task_tmp" \
    "TRIAGE_MODE=single CARD_ID=${card_id}" || spawn_exit=$?

  rm -f "$task_tmp"

  if [[ $spawn_exit -ne 0 ]]; then
    echo "[overlord-triage] WARN: Overlord agent exited with code ${spawn_exit}" >&2
  fi

  # Read the updated card to determine recommendation
  local recommendation
  recommendation="$(_assessment_field "$card_file" "recommendation")"

  if [[ -z "$recommendation" ]]; then
    echo "[overlord-triage] WARN: No assessment found in card after agent run." >&2
    echo "  Card ${card_id} remains in 'triaging' status." >&2
    return 0
  fi

  # Act on recommendation
  local result_line=""
  case "$recommendation" in
    promote)
      local promoted
      promoted="$(promote_card "$card_id")"
      local priority
      priority="$(_assessment_field "$card_file" "priority")"
      result_line="promote (${priority}) -> ${promoted}"
      ;;
    defer)
      defer_card "$card_id"
      local rationale
      rationale="$(_assessment_field "$card_file" "rationale")"
      result_line="defer -- ${rationale}"
      ;;
    archive)
      archive_card "$card_id"
      local rationale
      rationale="$(_assessment_field "$card_file" "rationale")"
      result_line="archive -- ${rationale}"
      ;;
    needs_input)
      # Keep in triaging, raise flag for operator
      local questions
      questions="$(_assessment_field "$card_file" "questions")"
      result_line="needs_input -- ${questions:-No specific questions provided}"

      # Raise a flag if the flags lib is available
      local flags_lib="$PROJECT_ROOT/bin/didio-flags-lib.sh"
      if [[ -f "$flags_lib" ]]; then
        # shellcheck disable=SC1090
        source "$flags_lib"
        if declare -F didio_flag_raise >/dev/null 2>&1; then
          didio_flag_raise "overlord-needs-input" \
            "Card ${card_id} needs operator input: ${questions:-see card}" \
            "overlord" 2>/dev/null || true
        fi
      fi
      ;;
    *)
      echo "[overlord-triage] WARN: Unknown recommendation '${recommendation}' for ${card_id}" >&2
      result_line="unknown (${recommendation})"
      ;;
  esac

  echo "$result_line"
}

# ---------------------------------------------------------------------------
# Single-card triage
# ---------------------------------------------------------------------------

triage_single() {
  local card_id="$1"

  echo "Triaging card ${card_id}..."

  # Gather knowledge
  printf '  Gathering knowledge sources... '
  local knowledge_summary
  knowledge_summary="$(gather_knowledge)"
  echo "done (${knowledge_summary})"

  # Run assessment
  printf '  Running Overlord assessment... '
  local result
  result="$(assess_card "$card_id")"
  local exit_code=$?
  echo "done"

  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Print result
  local card_file="$CARDS_DIR/${card_id}.json"
  local recommendation priority rationale promoted_as
  recommendation="$(_assessment_field "$card_file" "recommendation")"
  priority="$(_assessment_field "$card_file" "priority")"
  rationale="$(_assessment_field "$card_file" "rationale")"

  if [[ -n "$recommendation" ]]; then
    echo "  Recommendation: ${recommendation} (priority: ${priority})"
    echo "  Rationale: ${rationale}"

    if [[ "$recommendation" == "promote" ]]; then
      local promoted_to
      promoted_to="$(_card_field "$card_file" "promoted_to")"
      promoted_as="$(_assessment_field "$card_file" "promoted_as")"
      echo "  Promoted as: ${promoted_to} -- ${promoted_as}"
    fi
  else
    echo "  (no assessment produced)"
  fi
}

# ---------------------------------------------------------------------------
# Batch triage
# ---------------------------------------------------------------------------

triage_batch() {
  echo "Overlord batch triage starting..."

  # Gather knowledge
  printf '  Gathering knowledge sources... '
  local knowledge_summary
  knowledge_summary="$(gather_knowledge)"
  echo "done (${knowledge_summary})"

  # Find all incoming cards
  local incoming_cards=()
  if compgen -G "$CARDS_DIR/WR-*.json" > /dev/null 2>&1; then
    for card_file in "$CARDS_DIR"/WR-*.json; do
      [[ -f "$card_file" ]] || continue
      local status
      status="$(_card_field "$card_file" "status")"
      if [[ "$status" == "incoming" ]]; then
        local cid
        cid="$(_card_field "$card_file" "card_id")"
        incoming_cards+=("$cid")
      fi
    done
  fi

  local total=${#incoming_cards[@]}

  if [[ $total -eq 0 ]]; then
    echo "  No incoming cards to triage."
    echo ""
    echo "Triage complete: 0 cards processed"
    return 0
  fi

  echo "  Found ${total} incoming cards"
  echo ""

  # Check max_concurrent_promotions
  local max_promotions
  max_promotions="$(didio_overlord_max_promotions)"
  local current_promotions=0
  if compgen -G "$CARDS_DIR/WR-*.json" > /dev/null 2>&1; then
    for card_file in "$CARDS_DIR"/WR-*.json; do
      [[ -f "$card_file" ]] || continue
      local s
      s="$(_card_field "$card_file" "status")"
      if [[ "$s" == "promoted" ]]; then
        current_promotions=$((current_promotions + 1))
      fi
    done
  fi
  local promotions_remaining=$((max_promotions - current_promotions))
  if [[ $promotions_remaining -lt 0 ]]; then promotions_remaining=0; fi

  # Process each card
  local promote_count=0 defer_count=0 archive_count=0 needs_input_count=0
  local results_json="["
  local results_first=1
  local idx=0

  for card_id in "${incoming_cards[@]}"; do
    idx=$((idx + 1))
    local card_file="$CARDS_DIR/${card_id}.json"
    local title
    title="$(_card_field "$card_file" "title")"

    printf '  [%d/%d] %s: "%s"\n' "$idx" "$total" "$card_id" "$title"

    local result
    result="$(assess_card "$card_id")"
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
      printf '        -> ERROR (exit %d)\n' "$exit_code"
      continue
    fi

    # Read recommendation from updated card
    local rec priority rationale promoted_as promoted_to
    rec="$(_assessment_field "$card_file" "recommendation")"
    priority="$(_assessment_field "$card_file" "priority")"
    rationale="$(_assessment_field "$card_file" "rationale")"

    case "$rec" in
      promote)
        promote_count=$((promote_count + 1))
        promoted_to="$(_card_field "$card_file" "promoted_to")"
        promoted_as="$(_assessment_field "$card_file" "promoted_as")"
        printf '        -> promote (%s) -> %s -- %s\n' "$priority" "$promoted_to" "$promoted_as"
        ;;
      defer)
        defer_count=$((defer_count + 1))
        printf '        -> defer (%s) -- %s\n' "$priority" "$rationale"
        ;;
      archive)
        archive_count=$((archive_count + 1))
        printf '        -> archive -- %s\n' "$rationale"
        ;;
      needs_input)
        needs_input_count=$((needs_input_count + 1))
        local questions
        questions="$(_assessment_field "$card_file" "questions")"
        printf '        -> needs_input -- %s\n' "${questions:-Need more information}"
        ;;
      *)
        printf '        -> (no recommendation)\n'
        ;;
    esac

    # Build results JSON entry
    if [[ $results_first -eq 1 ]]; then results_first=0; else results_json+=","; fi
    results_json+="$(python3 -c "
import json, sys
entry = {'card_id': sys.argv[1], 'recommendation': sys.argv[2]}
if sys.argv[2] == 'promote':
    entry['promoted_as'] = sys.argv[3]
else:
    entry['rationale'] = sys.argv[4]
print(json.dumps(entry))
" "$card_id" "${rec:-unknown}" "${promoted_as:-}" "${rationale:-}" 2>/dev/null || echo "{\"card_id\":\"$card_id\"}")"
  done

  results_json+="]"

  echo ""
  printf 'Triage complete: %d promoted, %d deferred, %d archived, %d needs_input\n' \
    "$promote_count" "$defer_count" "$archive_count" "$needs_input_count"

  # Write triage summary
  if [[ "$DRY_RUN" != "1" ]]; then
    mkdir -p "$TRIAGE_LOG_DIR"

    local ts
    ts="$(_now_file_ts)"
    local summary_file="$TRIAGE_LOG_DIR/triage-${ts}.json"

    # Determine triage sequence number for today
    local today
    today="$(date -u +%Y%m%d)"
    local seq=1
    if compgen -G "$TRIAGE_LOG_DIR/triage-${today}-*.json" > /dev/null 2>&1; then
      seq=$(( $(ls -1 "$TRIAGE_LOG_DIR"/triage-"${today}"-*.json 2>/dev/null | wc -l) + 1 ))
    fi

    local triage_id
    triage_id="$(printf 'OT-%s-%03d' "$today" "$seq")"

    python3 -c "
import json, sys
summary = {
    'triage_id': sys.argv[1],
    'timestamp': sys.argv[2],
    'cards_processed': int(sys.argv[3]),
    'results': json.loads(sys.argv[4]),
    'promotions_remaining': int(sys.argv[5])
}
with open(sys.argv[6], 'w', encoding='utf-8') as f:
    json.dump(summary, f, indent=2)
    f.write('\n')
" "$triage_id" "$(_now_iso)" "$total" "$results_json" "$promotions_remaining" "$summary_file"

    echo "Summary written to ${summary_file}"
  fi
}

# ---------------------------------------------------------------------------
# Auto (continuous) triage
# ---------------------------------------------------------------------------

triage_auto() {
  local auto_enabled
  auto_enabled="$(didio_overlord_auto_triage)"

  if [[ "$auto_enabled" != "true" ]]; then
    echo "[overlord-triage] Auto-triage is disabled in config (overlord.auto_triage = false)." >&2
    echo "  Set overlord.auto_triage = true in didio.config.json to enable." >&2
    exit 2
  fi

  local interval_minutes
  interval_minutes="$(didio_overlord_triage_interval)"
  local interval_seconds=$((interval_minutes * 60))

  echo "Overlord auto-triage starting (interval: ${interval_minutes}m)..."
  echo "  Press Ctrl+C to stop."
  echo ""

  # Graceful shutdown on SIGINT / SIGTERM
  local running=1
  _shutdown() {
    echo ""
    echo "[overlord-triage] Received signal, shutting down gracefully..."
    running=0
  }
  trap _shutdown INT TERM

  while [[ $running -eq 1 ]]; do
    echo "--- Triage cycle at $(_now_iso) ---"
    echo ""

    triage_batch || true

    echo ""

    if [[ $running -eq 0 ]]; then
      break
    fi

    echo "Next cycle in ${interval_minutes} minutes ($(date -u -d "+${interval_minutes} minutes" +%H:%M 2>/dev/null || echo "~"))..."

    # Sleep in small increments so we can respond to signals
    local slept=0
    while [[ $slept -lt $interval_seconds && $running -eq 1 ]]; do
      sleep 1
      slept=$((slept + 1))
    done
  done

  echo "[overlord-triage] Auto-triage stopped."
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

MODE="batch"       # default
CARD_ID=""
DRY_RUN="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_help
      exit 0
      ;;
    --card)
      MODE="single"
      CARD_ID="${2:?--card requires a card ID}"
      shift 2
      ;;
    --card=*)
      MODE="single"
      CARD_ID="${1#--card=}"
      shift
      ;;
    --auto)
      MODE="auto"
      shift
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    *)
      echo "[overlord-triage] Unknown option: $1" >&2
      echo "  Try: didio overlord triage --help" >&2
      exit 1
      ;;
  esac
done

export DRY_RUN

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Preflight
preflight || exit $?

if [[ "$DRY_RUN" == "1" ]]; then
  echo "[DRY_RUN] Mode: ${MODE}"
  if [[ "$MODE" == "single" ]]; then
    echo "[DRY_RUN] Card: ${CARD_ID}"
  fi
  echo ""
fi

case "$MODE" in
  single)
    if [[ -z "$CARD_ID" ]]; then
      echo "[overlord-triage] ERROR: --card requires a card ID" >&2
      exit 1
    fi
    triage_single "$CARD_ID"
    ;;
  batch)
    triage_batch
    ;;
  auto)
    triage_auto
    ;;
esac
