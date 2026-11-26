#!/usr/bin/env bash
# overlord-governance.sh — pattern-detection library for Overlord governance monitoring.
#
# Source this file (do NOT execute directly):
#   source "$DIDIO_HOME/lib/overlord-governance.sh"
#
# Functions:
#   analyze_decision_patterns [--since YYYY-MM-DD] [--dry-run]
#   create_strategic_card <pattern_type> <title> <priority> <body>
#   check_repeated_challenges [since_epoch]
#   check_blocked_pipelines [since_epoch]
#   check_low_confidence [since_epoch]
#   check_escalation_frequency [since_epoch]
#   check_persistent_flags
#   check_token_budget_pressure
#
# Requires: didio-warroom.sh, didio-config-lib.sh sourced before this file.

# -- Resolve project root --
_gov_project_root() {
  if [[ -n "${DIDIO_PROJECT_ROOT:-}" ]]; then
    echo "$DIDIO_PROJECT_ROOT"
  elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    echo "$PROJECT_ROOT"
  else
    echo "$PWD"
  fi
}

# Directories
_gov_governance_dir() { echo "$(_gov_project_root)/logs/governance"; }
_gov_decisions_dir()  { echo "$(_gov_project_root)/logs/decisions"; }
_gov_flags_dir()      { echo "$(_gov_project_root)/logs/agents/flags"; }
_gov_cards_dir()      { echo "$(_gov_project_root)/logs/warroom/cards"; }

# Track detections for summary
_GOV_DETECTIONS=()
_GOV_DRY_RUN=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Convert YYYY-MM-DD to epoch seconds (portable)
_date_to_epoch() {
  local d="${1:-}"
  [[ -z "$d" ]] && echo "0" && return
  python3 -c "
import datetime, sys
try:
    dt = datetime.datetime.strptime(sys.argv[1], '%Y-%m-%d')
    print(int(dt.timestamp()))
except Exception:
    print(0)
" "$d" 2>/dev/null || echo "0"
}

# Get epoch for N days ago
_days_ago_epoch() {
  local n="${1:-7}"
  python3 -c "
import datetime, sys
dt = datetime.datetime.now() - datetime.timedelta(days=int(sys.argv[1]))
print(int(dt.timestamp()))
" "$n" 2>/dev/null || echo "0"
}

# Get epoch for N hours ago
_hours_ago_epoch() {
  local n="${1:-24}"
  python3 -c "
import datetime, sys
dt = datetime.datetime.now() - datetime.timedelta(hours=int(sys.argv[1]))
print(int(dt.timestamp()))
" "$n" 2>/dev/null || echo "0"
}

# Parse ISO timestamp from JSON to epoch
_iso_to_epoch() {
  local ts="${1:-}"
  [[ -z "$ts" ]] && echo "0" && return
  python3 -c "
import datetime, sys
ts = sys.argv[1].replace('Z', '+00:00')
try:
    dt = datetime.datetime.fromisoformat(ts)
    print(int(dt.timestamp()))
except Exception:
    print(0)
" "$ts" 2>/dev/null || echo "0"
}

# Check if a similar card already exists (avoid duplicates).
# Returns 0 (true) if duplicate found, 1 (false) if no duplicate.
_card_exists() {
  local pattern_type="$1"
  local cards_dir
  cards_dir="$(_gov_cards_dir)"
  [[ ! -d "$cards_dir" ]] && return 1

  python3 -c "
import json, os, sys, glob

cards_dir = sys.argv[1]
pattern_type = sys.argv[2]

for f in glob.glob(os.path.join(cards_dir, 'WR-*.json')):
    try:
        with open(f, 'r', encoding='utf-8') as fh:
            card = json.load(fh)
        # Skip archived/deferred cards
        if card.get('status') in ('archived', 'deferred'):
            continue
        tags = card.get('tags', [])
        source_agent = card.get('source_agent', '')
        if source_agent == 'overlord' and pattern_type in tags:
            sys.exit(0)  # duplicate found
    except Exception:
        continue
sys.exit(1)  # no duplicate
" "$cards_dir" "$pattern_type" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Strategic card creation
# ---------------------------------------------------------------------------

# create_strategic_card <pattern_type> <title> <priority> <body>
# Creates a War Room card via didio warroom add with overlord metadata.
create_strategic_card() {
  local pattern_type="$1"
  local title="$2"
  local priority="$3"
  local body="$4"

  # Check for duplicates
  if _card_exists "$pattern_type"; then
    echo "  [skip] Card for '$pattern_type' already exists (not archived/deferred)"
    return 0
  fi

  local tags="governance,pattern-detection,${pattern_type}"

  if [[ $_GOV_DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] Would create card: $title"
    echo "    Priority: $priority"
    echo "    Tags: $tags"
    _GOV_DETECTIONS+=("$pattern_type")
    return 0
  fi

  # Resolve the warroom script
  local warroom_sh
  local didio_home="${DIDIO_HOME:-$HOME/.claude-didio-config}"
  if [[ -f "$PWD/bin/didio-warroom.sh" ]]; then
    warroom_sh="$PWD/bin/didio-warroom.sh"
  elif [[ -f "$didio_home/bin/didio-warroom.sh" ]]; then
    warroom_sh="$didio_home/bin/didio-warroom.sh"
  else
    echo "  [error] didio-warroom.sh not found" >&2
    return 1
  fi

  # Create the card
  local output
  output="$(bash "$warroom_sh" add "$title" \
    --body "$body" \
    --tags "$tags" \
    --priority "$priority" \
    --source "agent" 2>&1)" || {
    echo "  [error] Failed to create card: $output" >&2
    return 1
  }
  echo "  $output"

  # Patch source_agent into the card file (warroom add sets source_agent=null)
  local card_id
  card_id="$(echo "$output" | head -n1 | sed 's/Created card \([^:]*\):.*/\1/')"
  local card_file
  card_file="$(_gov_cards_dir)/${card_id}.json"
  if [[ -f "$card_file" ]]; then
    python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
d['source_agent'] = 'overlord'
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$card_file" 2>/dev/null
  fi

  _GOV_DETECTIONS+=("$pattern_type")
}

# ---------------------------------------------------------------------------
# Pattern detectors
# ---------------------------------------------------------------------------

# 1. Repeated challenges: 3+ challenges in last 7 days on similar topics
check_repeated_challenges() {
  local since_epoch="${1:-0}"
  local gov_dir
  gov_dir="$(_gov_governance_dir)"
  [[ ! -d "$gov_dir" ]] && return 0

  local result
  result="$(python3 -c "
import json, os, sys, glob, datetime, collections

gov_dir = sys.argv[1]
since_epoch = int(sys.argv[2])
seven_days_ago = datetime.datetime.now().timestamp() - (7 * 86400)
cutoff = max(since_epoch, seven_days_ago)

challenges = []
for f in sorted(glob.glob(os.path.join(gov_dir, 'G-*.json'))):
    try:
        with open(f, 'r', encoding='utf-8') as fh:
            g = json.load(fh)
        # Parse timestamp
        ts_str = g.get('created_at', g.get('timestamp', ''))
        if ts_str:
            ts_str = ts_str.replace('Z', '+00:00')
            try:
                ts = datetime.datetime.fromisoformat(ts_str).timestamp()
            except Exception:
                ts = 0
        else:
            ts = 0
        if ts < cutoff:
            continue
        # Look for challenged decisions
        outcome = g.get('outcome', g.get('recommendation', ''))
        if 'challenge' in str(outcome).lower():
            summary = g.get('context_summary', g.get('summary', g.get('rationale', '')))
            challenges.append({'file': os.path.basename(f), 'summary': summary[:120], 'ts': ts_str})
    except Exception:
        continue

if len(challenges) >= 3:
    # Group by keyword similarity (simple: extract top words)
    words = collections.Counter()
    for c in challenges:
        for w in c['summary'].lower().split():
            if len(w) > 3:
                words[w] += 1
    top_topics = [w for w, cnt in words.most_common(3)]
    evidence = []
    for c in challenges:
        evidence.append(f\"- {c['file']}: {c['summary']}\")
    print('DETECTED')
    print('Topics: ' + ', '.join(top_topics))
    print('Count: ' + str(len(challenges)))
    for e in evidence[:5]:
        print(e)
else:
    print('NONE')
" "$gov_dir" "$since_epoch" 2>/dev/null)" || return 0

  if [[ "$result" == NONE* ]]; then
    return 0
  fi

  local topics count evidence_text
  topics="$(echo "$result" | sed -n '2s/Topics: //p')"
  count="$(echo "$result" | sed -n '3s/Count: //p')"
  evidence_text="$(echo "$result" | tail -n +4)"

  local body
  body="## Pattern Detected: Repeated GateKeeper Challenges

**Type:** repeated_challenges
**Occurrences:** ${count} in last 7 days

### Evidence
${evidence_text}

### Suggested Action
Consider creating an ADR to establish a clear standard on the topic(s): ${topics}.
This would reduce repeated debates and improve review throughput."

  echo "[pattern] Repeated challenges detected (${count} in 7 days, topics: ${topics})"
  create_strategic_card "repeated_challenges" \
    "Process review needed: frequent governance challenges" \
    "high" \
    "$body"
}

# 2. Blocked pipelines: 2+ decisions blocked with similar reason
check_blocked_pipelines() {
  local since_epoch="${1:-0}"
  local dec_dir
  dec_dir="$(_gov_decisions_dir)"
  [[ ! -d "$dec_dir" ]] && return 0

  local result
  result="$(python3 -c "
import json, os, sys, glob, datetime, collections

dec_dir = sys.argv[1]
since_epoch = int(sys.argv[2])

blocked = []
for f in sorted(glob.glob(os.path.join(dec_dir, 'D-*.json'))):
    try:
        with open(f, 'r', encoding='utf-8') as fh:
            d = json.load(fh)
        ts_str = d.get('created_at', d.get('timestamp', ''))
        if ts_str:
            ts_str = ts_str.replace('Z', '+00:00')
            try:
                ts = datetime.datetime.fromisoformat(ts_str).timestamp()
            except Exception:
                ts = 0
        else:
            ts = 0
        if ts < since_epoch and since_epoch > 0:
            continue
        status = d.get('status', '')
        if 'block' in str(status).lower():
            reason = d.get('block_reason', d.get('reason', d.get('rationale', '')))
            blocked.append({'file': os.path.basename(f), 'reason': reason[:120]})
    except Exception:
        continue

if len(blocked) >= 2:
    evidence = []
    for b in blocked:
        evidence.append(f\"- {b['file']}: {b['reason']}\")
    print('DETECTED')
    print('Count: ' + str(len(blocked)))
    for e in evidence[:5]:
        print(e)
else:
    print('NONE')
" "$dec_dir" "$since_epoch" 2>/dev/null)" || return 0

  if [[ "$result" == NONE* ]]; then
    return 0
  fi

  local count evidence_text
  count="$(echo "$result" | sed -n '2s/Count: //p')"
  evidence_text="$(echo "$result" | tail -n +3)"

  local body
  body="## Pattern Detected: Systemic Pipeline Blockers

**Type:** blocked_pipelines
**Occurrences:** ${count} blocked decisions

### Evidence
${evidence_text}

### Suggested Action
Investigate common root cause for pipeline blocks. Consider whether a dependency
or environment issue is causing repeated blocks across features."

  echo "[pattern] Blocked pipelines detected (${count} blocked decisions)"
  create_strategic_card "blocked_pipelines" \
    "Systemic blocker: multiple pipelines blocked" \
    "critical" \
    "$body"
}

# 3. Low confidence: 3+ consecutive reviews with confidence < 0.5
check_low_confidence() {
  local since_epoch="${1:-0}"
  local gov_dir
  gov_dir="$(_gov_governance_dir)"
  [[ ! -d "$gov_dir" ]] && return 0

  local result
  result="$(python3 -c "
import json, os, sys, glob, datetime

gov_dir = sys.argv[1]
since_epoch = int(sys.argv[2])
threshold = 0.6  # match the user prompt: average < 0.6

reviews = []
for f in sorted(glob.glob(os.path.join(gov_dir, 'G-*.json'))):
    try:
        with open(f, 'r', encoding='utf-8') as fh:
            g = json.load(fh)
        ts_str = g.get('created_at', g.get('timestamp', ''))
        if ts_str:
            ts_str = ts_str.replace('Z', '+00:00')
            try:
                ts = datetime.datetime.fromisoformat(ts_str).timestamp()
            except Exception:
                ts = 0
        else:
            ts = 0
        if ts < since_epoch and since_epoch > 0:
            continue
        conf = g.get('confidence', None)
        if conf is not None:
            reviews.append({'file': os.path.basename(f), 'confidence': float(conf)})
    except Exception:
        continue

# Check last 5 reviews: average confidence < 0.6
if len(reviews) >= 3:
    last_n = reviews[-5:] if len(reviews) >= 5 else reviews
    avg_conf = sum(r['confidence'] for r in last_n) / len(last_n)
    low_count = sum(1 for r in last_n if r['confidence'] < 0.5)
    if avg_conf < threshold:
        evidence = []
        for r in last_n:
            evidence.append(f\"- {r['file']}: confidence={r['confidence']:.2f}\")
        print('DETECTED')
        print(f'Average: {avg_conf:.2f}')
        print(f'Count: {len(last_n)}')
        for e in evidence:
            print(e)
    else:
        print('NONE')
else:
    print('NONE')
" "$gov_dir" "$since_epoch" 2>/dev/null)" || return 0

  if [[ "$result" == NONE* ]]; then
    return 0
  fi

  local avg count evidence_text
  avg="$(echo "$result" | sed -n '2s/Average: //p')"
  count="$(echo "$result" | sed -n '3s/Count: //p')"
  evidence_text="$(echo "$result" | tail -n +4)"

  local body
  body="## Pattern Detected: Low GateKeeper Confidence

**Type:** low_confidence
**Average confidence:** ${avg} (last ${count} reviews, threshold: 0.6)

### Evidence
${evidence_text}

### Suggested Action
GateKeeper confidence is trending low, suggesting possible knowledge gaps
or unclear decision context. Consider updating ADRs, adding more context
to decision records, or reviewing the GateKeeper prompt for relevance."

  echo "[pattern] Low confidence detected (avg: ${avg} in last ${count} reviews)"
  create_strategic_card "low_confidence" \
    "GateKeeper confidence trending low -- knowledge gap?" \
    "high" \
    "$body"
}

# 4. Escalation frequency: 2+ escalations in the last 10 decisions
check_escalation_frequency() {
  local since_epoch="${1:-0}"
  local dec_dir
  dec_dir="$(_gov_decisions_dir)"
  [[ ! -d "$dec_dir" ]] && return 0

  local result
  result="$(python3 -c "
import json, os, sys, glob

dec_dir = sys.argv[1]
since_epoch = int(sys.argv[2])

decisions = []
for f in sorted(glob.glob(os.path.join(dec_dir, 'D-*.json'))):
    try:
        with open(f, 'r', encoding='utf-8') as fh:
            d = json.load(fh)
        ts_str = d.get('created_at', d.get('timestamp', ''))
        if ts_str:
            ts_str = ts_str.replace('Z', '+00:00')
            try:
                import datetime
                ts = datetime.datetime.fromisoformat(ts_str).timestamp()
            except Exception:
                ts = 0
        else:
            ts = 0
        if ts < since_epoch and since_epoch > 0:
            continue
        decisions.append({'file': os.path.basename(f), 'status': d.get('status', ''), 'escalated': d.get('escalated', False)})
    except Exception:
        continue

# Check last 10
last_10 = decisions[-10:] if len(decisions) > 10 else decisions
escalated = [d for d in last_10 if d.get('escalated') or 'escalat' in str(d.get('status', '')).lower()]

if len(escalated) >= 2:
    evidence = []
    for e in escalated:
        evidence.append(f\"- {e['file']}: status={e['status']}\")
    print('DETECTED')
    print(f'Count: {len(escalated)}')
    print(f'Total: {len(last_10)}')
    for e in evidence:
        print(e)
else:
    print('NONE')
" "$dec_dir" "$since_epoch" 2>/dev/null)" || return 0

  if [[ "$result" == NONE* ]]; then
    return 0
  fi

  local esc_count total evidence_text
  esc_count="$(echo "$result" | sed -n '2s/Count: //p')"
  total="$(echo "$result" | sed -n '3s/Total: //p')"
  evidence_text="$(echo "$result" | tail -n +4)"

  local body
  body="## Pattern Detected: High Escalation Frequency

**Type:** escalation_frequency
**Occurrences:** ${esc_count} escalations in last ${total} decisions

### Evidence
${evidence_text}

### Suggested Action
Frequent escalations suggest the Handler/GateKeeper loop may be misaligned.
Consider reviewing escalation criteria, adjusting confidence thresholds,
or updating agent prompts to reduce unnecessary escalations."

  echo "[pattern] Escalation frequency detected (${esc_count} in last ${total} decisions)"
  create_strategic_card "escalation_frequency" \
    "Governance overhead: frequent escalations" \
    "medium" \
    "$body"
}

# 5. Persistent blocked flags: any flag unresolved for >24h
check_persistent_flags() {
  local flags_dir
  flags_dir="$(_gov_flags_dir)"
  [[ ! -d "$flags_dir" ]] && return 0

  local result
  result="$(python3 -c "
import json, os, sys, glob, datetime

flags_dir = sys.argv[1]
cutoff = datetime.datetime.now().timestamp() - (24 * 3600)

stale = []
for f in sorted(glob.glob(os.path.join(flags_dir, '*.json'))):
    try:
        with open(f, 'r', encoding='utf-8') as fh:
            d = json.load(fh)
        if d.get('resolved', False) or d.get('resolved_at'):
            continue
        ts_str = d.get('created_at', d.get('timestamp', ''))
        if ts_str:
            ts_str = ts_str.replace('Z', '+00:00')
            try:
                ts = datetime.datetime.fromisoformat(ts_str).timestamp()
            except Exception:
                ts = 0
        else:
            ts = 0
        if ts > 0 and ts < cutoff:
            feature = d.get('feature', d.get('feature_id', '?'))
            task = d.get('task', d.get('task_id', ''))
            flag_type = d.get('type', d.get('flag_type', ''))
            stale.append({'file': os.path.basename(f), 'feature': feature, 'task': task, 'type': flag_type, 'ts': ts_str})
    except Exception:
        continue

if stale:
    print('DETECTED')
    print(f'Count: {len(stale)}')
    for s in stale[:5]:
        task_str = f' {s[\"task\"]}' if s['task'] else ''
        print(f'- {s[\"feature\"]}{task_str}: {s[\"type\"]} (since {s[\"ts\"]}) [{s[\"file\"]}]')
else:
    print('NONE')
" "$flags_dir" 2>/dev/null)" || return 0

  if [[ "$result" == NONE* ]]; then
    return 0
  fi

  local count evidence_text
  count="$(echo "$result" | sed -n '2s/Count: //p')"
  evidence_text="$(echo "$result" | tail -n +3)"

  # Create one card per stale flag
  local line
  while IFS= read -r line; do
    [[ -z "$line" || "$line" != -* ]] && continue
    local desc="${line#- }"
    local feature_task
    feature_task="$(echo "$desc" | cut -d: -f1)"

    local body
    body="## Pattern Detected: Stale Blocked Flag

**Type:** persistent_block
**Stale for:** >24 hours

### Evidence
${line}

### Suggested Action
Investigate and resolve the blocked flag, or escalate to the operator if
the block requires external intervention."

    echo "[pattern] Stale blocked flag: ${feature_task}"
    create_strategic_card "persistent_block" \
      "Stale blocked flag: ${feature_task}" \
      "high" \
      "$body"
  done <<< "$evidence_text"
}

# 6. Token budget pressure
check_token_budget_pressure() {
  local schedule_file
  schedule_file="$(_gov_project_root)/logs/agents/token-schedule-suggestion.json"
  [[ ! -f "$schedule_file" ]] && return 0

  local result
  result="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
status = d.get('status', '')
if status == 'critical':
    pct = d.get('budget_pct_remaining', d.get('remaining_pct', '?'))
    print(f'DETECTED')
    print(f'Status: {status}')
    print(f'Remaining: {pct}%')
else:
    print('NONE')
" "$schedule_file" 2>/dev/null)" || return 0

  if [[ "$result" == NONE* ]]; then
    return 0
  fi

  local remaining
  remaining="$(echo "$result" | sed -n '3s/Remaining: //p')"

  local body
  body="## Pattern Detected: Token Budget Critical

**Type:** token_budget_critical
**Budget remaining:** ${remaining}

### Evidence
- token-schedule-suggestion.json reports status=critical

### Suggested Action
Pause non-essential pipelines and schedule resumption when budget replenishes.
Run \`didio token-monitor --suggest\` for scheduling recommendations."

  echo "[pattern] Token budget critical (remaining: ${remaining})"
  create_strategic_card "token_budget_critical" \
    "Token budget critical -- schedule resumption" \
    "critical" \
    "$body"
}

# ---------------------------------------------------------------------------
# Main analysis entrypoint
# ---------------------------------------------------------------------------

# analyze_decision_patterns [--since YYYY-MM-DD] [--dry-run]
analyze_decision_patterns() {
  local since_date="" dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since)   since_date="${2:?--since requires YYYY-MM-DD}"; shift 2 ;;
      --since=*) since_date="${1#--since=}"; shift ;;
      --dry-run) dry_run=1; shift ;;
      *)         shift ;;
    esac
  done

  _GOV_DRY_RUN=$dry_run
  _GOV_DETECTIONS=()

  local since_epoch=0
  if [[ -n "$since_date" ]]; then
    since_epoch="$(_date_to_epoch "$since_date")"
  fi

  echo "=== Overlord Governance Monitor ==="
  if [[ -n "$since_date" ]]; then
    echo "Analyzing patterns since: $since_date"
  fi
  if [[ $dry_run -eq 1 ]]; then
    echo "Mode: dry-run (no cards will be created)"
  fi
  echo ""

  # Run all pattern detectors
  check_repeated_challenges "$since_epoch"
  check_blocked_pipelines "$since_epoch"
  check_low_confidence "$since_epoch"
  check_escalation_frequency "$since_epoch"
  check_persistent_flags
  check_token_budget_pressure

  echo ""
  if [[ ${#_GOV_DETECTIONS[@]} -eq 0 ]]; then
    echo "No governance patterns detected."
  else
    echo "Detection summary: ${#_GOV_DETECTIONS[@]} pattern(s) found"
    for d in "${_GOV_DETECTIONS[@]}"; do
      echo "  - $d"
    done
  fi

  return 0
}
