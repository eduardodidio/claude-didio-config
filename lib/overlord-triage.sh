#!/usr/bin/env bash
# lib/overlord-triage.sh — Core triage functions for the Overlord agent
#
# This library is sourced by bin/didio-overlord-triage.sh (T10).
# It provides: gather_knowledge, assess_card, promote_card, triage_batch.
#
# Dependencies:
#   - python3 (for JSON manipulation)
#   - bin/didio-warroom.sh helpers (card format)
#   - bin/didio-spawn-agent.sh (for agent spawning)
#   - bin/didio-overlord-promote.sh (for promotion bridge)
#   - bin/didio-overlord-defer.sh (for deferral)

# Guard: only source once
[[ -n "${_OVERLORD_TRIAGE_LOADED:-}" ]] && return 0
_OVERLORD_TRIAGE_LOADED=1

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

_OT_PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$PWD}"
_OT_CARDS_DIR="$_OT_PROJECT_ROOT/logs/warroom/cards"
_OT_FEATURES_DIR="$_OT_PROJECT_ROOT/tasks/features"
_OT_WARROOM_DIR="$_OT_PROJECT_ROOT/logs/warroom"
_OT_CONFIG_FILE="$_OT_PROJECT_ROOT/didio.config.json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_ot_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_ot_today() {
  date -u +"%Y%m%d"
}

# Read a config value from didio.config.json via python3
_ot_config_val() {
  local path="$1" default="${2:-}"
  if [[ ! -f "$_OT_CONFIG_FILE" ]]; then
    echo "$default"
    return
  fi
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
keys = sys.argv[2].split('.')
v = d
for k in keys:
    if isinstance(v, dict):
        v = v.get(k)
    else:
        v = None
        break
if v is None:
    print(sys.argv[3] if len(sys.argv) > 3 else '')
else:
    if isinstance(v, bool):
        print('true' if v else 'false')
    elif isinstance(v, list):
        print(','.join(str(x) for x in v))
    else:
        print(str(v))
" "$_OT_CONFIG_FILE" "$path" "$default" 2>/dev/null || echo "$default"
}

# Read a JSON field from a card file
_ot_card_field() {
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
# gather_knowledge()
#
# Reads all configured knowledge sources and writes a consolidated context
# file for the Overlord agent prompt.
#
# Output: logs/warroom/.triage-context.md
# ---------------------------------------------------------------------------
gather_knowledge() {
  mkdir -p "$_OT_WARROOM_DIR"
  local ctx_file="$_OT_WARROOM_DIR/.triage-context.md"
  local sources
  sources="$(_ot_config_val "overlord.knowledge_sources" "adr,learnings")"

  cat > "$ctx_file" <<'HEADER'
# Triage Context (auto-generated)

This context was gathered for the Overlord triage session.

HEADER

  # -- ADRs --
  if [[ "$sources" == *"adr"* ]] || true; then
    echo "## Architecture Decision Records" >> "$ctx_file"
    echo "" >> "$ctx_file"
    if compgen -G "$_OT_PROJECT_ROOT/docs/adr/*.md" > /dev/null 2>&1; then
      for adr in "$_OT_PROJECT_ROOT"/docs/adr/*.md; do
        echo "### $(basename "$adr")" >> "$ctx_file"
        echo "" >> "$ctx_file"
        cat "$adr" >> "$ctx_file"
        echo "" >> "$ctx_file"
        echo "---" >> "$ctx_file"
        echo "" >> "$ctx_file"
      done
    else
      echo "_No ADRs found._" >> "$ctx_file"
      echo "" >> "$ctx_file"
    fi
  fi

  # -- Agent learnings --
  if [[ "$sources" == *"learnings"* ]]; then
    echo "## Agent Learnings" >> "$ctx_file"
    echo "" >> "$ctx_file"
    if compgen -G "$_OT_PROJECT_ROOT/memory/agent-learnings/*.md" > /dev/null 2>&1; then
      for learn in "$_OT_PROJECT_ROOT"/memory/agent-learnings/*.md; do
        echo "### $(basename "$learn")" >> "$ctx_file"
        echo "" >> "$ctx_file"
        cat "$learn" >> "$ctx_file"
        echo "" >> "$ctx_file"
        echo "---" >> "$ctx_file"
        echo "" >> "$ctx_file"
      done
    else
      echo "_No learnings found._" >> "$ctx_file"
      echo "" >> "$ctx_file"
    fi
  fi

  # -- Feature READMEs (always, for dedup) --
  echo "## Existing Features" >> "$ctx_file"
  echo "" >> "$ctx_file"
  if compgen -G "$_OT_FEATURES_DIR/*/F*-README.md" > /dev/null 2>&1; then
    for readme in "$_OT_FEATURES_DIR"/*/F*-README.md; do
      echo "### $(basename "$(dirname "$readme")")" >> "$ctx_file"
      echo "" >> "$ctx_file"
      head -20 "$readme" >> "$ctx_file"
      echo "" >> "$ctx_file"
      echo "---" >> "$ctx_file"
      echo "" >> "$ctx_file"
    done
  else
    echo "_No feature READMEs found._" >> "$ctx_file"
    echo "" >> "$ctx_file"
  fi

  # -- Recent decisions (last 10) --
  echo "## Recent Decisions" >> "$ctx_file"
  echo "" >> "$ctx_file"
  if compgen -G "$_OT_PROJECT_ROOT/logs/decisions/D-*.json" > /dev/null 2>&1; then
    # shellcheck disable=SC2012
    ls -t "$_OT_PROJECT_ROOT"/logs/decisions/D-*.json 2>/dev/null | head -10 | while read -r dfile; do
      echo "### $(basename "$dfile")" >> "$ctx_file"
      echo '```json' >> "$ctx_file"
      cat "$dfile" >> "$ctx_file"
      echo '```' >> "$ctx_file"
      echo "" >> "$ctx_file"
    done
  else
    echo "_No decision records found._" >> "$ctx_file"
    echo "" >> "$ctx_file"
  fi

  # -- Recent governance reviews (last 10) --
  echo "## Recent Governance Reviews" >> "$ctx_file"
  echo "" >> "$ctx_file"
  if compgen -G "$_OT_PROJECT_ROOT/logs/governance/G-*.json" > /dev/null 2>&1; then
    # shellcheck disable=SC2012
    ls -t "$_OT_PROJECT_ROOT"/logs/governance/G-*.json 2>/dev/null | head -10 | while read -r gfile; do
      echo "### $(basename "$gfile")" >> "$ctx_file"
      echo '```json' >> "$ctx_file"
      cat "$gfile" >> "$ctx_file"
      echo '```' >> "$ctx_file"
      echo "" >> "$ctx_file"
    done
  else
    echo "_No governance records found._" >> "$ctx_file"
    echo "" >> "$ctx_file"
  fi

  echo "[overlord-triage] Knowledge context written to $ctx_file" >&2
  echo "$ctx_file"
}

# ---------------------------------------------------------------------------
# assess_card(card_id)
#
# Runs the full Overlord assessment on a single card.
# 1. Set status to "triaging"
# 2. Spawn Overlord agent
# 3. Parse output and write overlord_assessment to card JSON
# 4. Update status based on recommendation
# ---------------------------------------------------------------------------
assess_card() {
  local card_id="${1:?card_id required}"
  local card_file="$_OT_CARDS_DIR/${card_id}.json"

  if [[ ! -f "$card_file" ]]; then
    echo "Error: card '$card_id' not found at $card_file" >&2
    return 1
  fi

  local now
  now="$(_ot_now_iso)"

  # 1. Set status to "triaging"
  python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
d['status'] = 'triaging'
d['updated_at'] = sys.argv[2]
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$card_file" "$now"

  echo "[overlord-triage] Card $card_id -> triaging" >&2

  # 2. Gather context (reuse if already generated this session)
  local ctx_file="$_OT_WARROOM_DIR/.triage-context.md"
  if [[ ! -f "$ctx_file" ]]; then
    ctx_file="$(gather_knowledge)"
  fi

  # 3. Spawn the Overlord agent
  #    Build a task payload that includes the card JSON + triage context
  local task_payload_file="$_OT_WARROOM_DIR/.triage-task-${card_id}.md"
  cat > "$task_payload_file" <<EOF
# Triage Card: ${card_id}

## Card Data
\`\`\`json
$(cat "$card_file")
\`\`\`

## Triage Context
$(cat "$ctx_file")

## Instructions

Assess this card following the Overlord triage process. Write your assessment
as a JSON object with these fields:
- recommendation: promote|defer|archive|needs_input
- priority: low|medium|high|max
- rationale: 2-3 sentences
- promoted_as: (only if recommending promote) suggested feature title
- knowledge_refs: list of ADRs or learnings that informed this decision
- questions: (only if needs_input) list of questions

Output your assessment as a fenced JSON block:
\`\`\`json
{ "recommendation": "...", "priority": "...", ... }
\`\`\`
EOF

  local spawn_exit=0
  if [[ "${DIDIO_DRY_RUN:-0}" == "1" ]]; then
    echo "[overlord-triage][DRY_RUN] Would spawn overlord agent for $card_id" >&2
    # In dry-run, skip the agent spawn and leave card in triaging
    return 0
  fi

  # Spawn overlord agent; capture output for assessment parsing
  local agent_output_file="$_OT_WARROOM_DIR/.triage-output-${card_id}.txt"
  set +e
  bash "${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-spawn-agent.sh" \
    overlord "TRIAGE" "$task_payload_file" \
    > "$agent_output_file" 2>&1
  spawn_exit=$?
  set -e

  if [[ $spawn_exit -ne 0 ]]; then
    echo "[overlord-triage] WARN: Overlord agent exited with code $spawn_exit for $card_id" >&2
  fi

  # 4. Parse agent output to extract the assessment JSON block
  local assessment_json
  assessment_json="$(python3 -c "
import re, sys, json

with open(sys.argv[1], 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

# Find JSON block in fenced code blocks
pattern = r'\`\`\`json\s*\n(.*?)\n\s*\`\`\`'
matches = re.findall(pattern, content, re.DOTALL)

# Find the assessment block (has 'recommendation' key)
for m in matches:
    try:
        d = json.loads(m)
        if 'recommendation' in d:
            print(json.dumps(d))
            sys.exit(0)
    except json.JSONDecodeError:
        continue

# Fallback: try to find any JSON object with 'recommendation'
pattern2 = r'\{[^{}]*\"recommendation\"[^{}]*\}'
matches2 = re.findall(pattern2, content)
for m in matches2:
    try:
        d = json.loads(m)
        if 'recommendation' in d:
            print(json.dumps(d))
            sys.exit(0)
    except json.JSONDecodeError:
        continue

# No assessment found
print('')
" "$agent_output_file" 2>/dev/null || echo "")"

  # 5. Write overlord_assessment to card JSON
  now="$(_ot_now_iso)"

  if [[ -n "$assessment_json" ]]; then
    python3 -c "
import json, sys

card_file = sys.argv[1]
assessment_raw = sys.argv[2]
now = sys.argv[3]

with open(card_file, 'r', encoding='utf-8') as f:
    d = json.load(f)

assessment = json.loads(assessment_raw)
assessment['assessed_at'] = now

d['overlord_assessment'] = assessment
d['updated_at'] = now

# 6. Update status based on recommendation
rec = assessment.get('recommendation', 'needs_input')
if rec == 'promote':
    d['status'] = 'promoted'
elif rec == 'defer':
    d['status'] = 'deferred'
elif rec == 'archive':
    d['status'] = 'archived'
else:
    d['status'] = 'triaging'  # needs_input stays triaging

with open(card_file, 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')

print(rec)
" "$card_file" "$assessment_json" "$now"
  else
    echo "[overlord-triage] WARN: No assessment extracted for $card_id; leaving in triaging" >&2
    # Leave the card in triaging state with a note
    python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
d['overlord_assessment'] = {
    'assessed_at': sys.argv[2],
    'recommendation': 'needs_input',
    'priority': 'medium',
    'rationale': 'Overlord agent did not produce a parseable assessment. Manual review needed.',
    'knowledge_refs': [],
    'questions': ['Agent output could not be parsed. Please review manually.']
}
d['updated_at'] = sys.argv[2]
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$card_file" "$now"
    echo "needs_input"
  fi

  # Cleanup temp files
  rm -f "$task_payload_file" "$agent_output_file"
}

# ---------------------------------------------------------------------------
# promote_card(card_id)
#
# Called when Overlord recommends "promote". Delegates to the promote script.
# ---------------------------------------------------------------------------
promote_card() {
  local card_id="${1:?card_id required}"
  bash "${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-overlord-promote.sh" "$card_id"
}

# ---------------------------------------------------------------------------
# triage_batch()
#
# Process all INCOMING cards, respecting max_concurrent_promotions.
# Writes triage summary to logs/warroom/triage-<timestamp>.json
# ---------------------------------------------------------------------------
triage_batch() {
  mkdir -p "$_OT_CARDS_DIR" "$_OT_WARROOM_DIR"

  # Read config limits
  local max_promotions
  max_promotions="$(_ot_config_val "overlord.max_concurrent_promotions" "5")"
  local requires_confirmation
  requires_confirmation="$(_ot_config_val "overlord.promotion_requires_confirmation" "false")"

  # Count current promoted cards (not yet picked up)
  local current_promoted=0
  for card_file in "$_OT_CARDS_DIR"/WR-*.json; do
    [[ -f "$card_file" ]] || continue
    local status
    status="$(_ot_card_field "$card_file" "status")"
    if [[ "$status" == "promoted" ]]; then
      current_promoted=$((current_promoted + 1))
    fi
  done

  local promotions_remaining=$((max_promotions - current_promoted))
  if [[ $promotions_remaining -lt 0 ]]; then promotions_remaining=0; fi

  echo "[overlord-triage] Batch triage: max_promotions=$max_promotions current=$current_promoted remaining=$promotions_remaining" >&2

  # Gather knowledge once for the batch
  gather_knowledge > /dev/null

  # Collect incoming cards
  local cards_processed=0
  local promote_count=0
  local defer_count=0
  local archive_count=0
  local needs_input_count=0
  local results_json="[]"

  for card_file in "$_OT_CARDS_DIR"/WR-*.json; do
    [[ -f "$card_file" ]] || continue
    local status
    status="$(_ot_card_field "$card_file" "status")"
    [[ "$status" != "incoming" ]] && continue

    local card_id
    card_id="$(_ot_card_field "$card_file" "card_id")"

    echo "[overlord-triage] Processing $card_id..." >&2

    # Assess the card
    local recommendation
    recommendation="$(assess_card "$card_id")"
    cards_processed=$((cards_processed + 1))

    # Build result entry
    local result_entry=""
    case "$recommendation" in
      promote)
        if [[ $promotions_remaining -gt 0 && "$requires_confirmation" != "true" ]]; then
          promote_card "$card_id"
          promotions_remaining=$((promotions_remaining - 1))
          promote_count=$((promote_count + 1))

          local promoted_to
          promoted_to="$(_ot_card_field "$card_file" "promoted_to")"
          local title
          title="$(_ot_card_field "$card_file" "title")"

          result_entry="{\"card_id\":\"$card_id\",\"recommendation\":\"promote\",\"promoted_as\":\"$promoted_to -- $title\"}"
        elif [[ "$requires_confirmation" == "true" ]]; then
          echo "[overlord-triage] Card $card_id recommended for promotion but requires confirmation" >&2
          # Leave in triaging per spec
          python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
d['status'] = 'triaging'
d['updated_at'] = sys.argv[2]
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$card_file" "$(_ot_now_iso)"
          needs_input_count=$((needs_input_count + 1))
          result_entry="{\"card_id\":\"$card_id\",\"recommendation\":\"promote\",\"note\":\"awaiting confirmation\"}"
        else
          echo "[overlord-triage] Card $card_id recommended for promotion but limit reached" >&2
          needs_input_count=$((needs_input_count + 1))
          result_entry="{\"card_id\":\"$card_id\",\"recommendation\":\"promote\",\"note\":\"promotion limit reached\"}"
        fi
        ;;
      defer)
        defer_count=$((defer_count + 1))
        local rationale
        rationale="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
a = d.get('overlord_assessment', {})
print(a.get('rationale', ''))
" "$card_file" 2>/dev/null || echo "")"
        local esc_rationale="${rationale//\"/\\\"}"
        result_entry="{\"card_id\":\"$card_id\",\"recommendation\":\"defer\",\"rationale\":\"$esc_rationale\"}"
        ;;
      archive)
        archive_count=$((archive_count + 1))
        result_entry="{\"card_id\":\"$card_id\",\"recommendation\":\"archive\"}"
        ;;
      *)
        needs_input_count=$((needs_input_count + 1))
        result_entry="{\"card_id\":\"$card_id\",\"recommendation\":\"needs_input\"}"
        ;;
    esac

    # Append to results array
    if [[ -n "$result_entry" ]]; then
      results_json="$(python3 -c "
import json, sys
arr = json.loads(sys.argv[1])
entry = json.loads(sys.argv[2])
arr.append(entry)
print(json.dumps(arr))
" "$results_json" "$result_entry")"
    fi
  done

  # Write triage summary
  local today
  today="$(_ot_today)"

  # Determine sequence number for triage ID
  local triage_seq=1
  if compgen -G "$_OT_WARROOM_DIR/triage-*.json" > /dev/null 2>&1; then
    local max_seq=0
    for f in "$_OT_WARROOM_DIR"/triage-*.json; do
      local bname
      bname="$(basename "$f" .json)"
      local snum="${bname##*-}"
      if [[ "$snum" =~ ^[0-9]+$ ]]; then
        local n=$((10#$snum))
        if [[ $n -gt $max_seq ]]; then max_seq=$n; fi
      fi
    done
    triage_seq=$((max_seq + 1))
  fi

  local triage_id
  triage_id="$(printf 'OT-%s-%03d' "$today" "$triage_seq")"
  local now
  now="$(_ot_now_iso)"

  local summary_file="$_OT_WARROOM_DIR/triage-${today}-$(printf '%03d' "$triage_seq").json"

  python3 -c "
import json, sys

triage_id = sys.argv[1]
timestamp = sys.argv[2]
cards_processed = int(sys.argv[3])
results = json.loads(sys.argv[4])
promotions_remaining = int(sys.argv[5])
output_file = sys.argv[6]

summary = {
    'triage_id': triage_id,
    'timestamp': timestamp,
    'cards_processed': cards_processed,
    'results': results,
    'promotions_remaining': promotions_remaining
}

with open(output_file, 'w', encoding='utf-8') as f:
    json.dump(summary, f, indent=2)
    f.write('\n')
" "$triage_id" "$now" "$cards_processed" "$results_json" "$promotions_remaining" "$summary_file"

  echo "[overlord-triage] Batch complete: processed=$cards_processed promote=$promote_count defer=$defer_count archive=$archive_count needs_input=$needs_input_count" >&2
  echo "[overlord-triage] Summary: $summary_file" >&2
  echo "DIDIO_DONE: overlord triaged $cards_processed cards promote=$promote_count defer=$defer_count archive=$archive_count needs_input=$needs_input_count"
}
