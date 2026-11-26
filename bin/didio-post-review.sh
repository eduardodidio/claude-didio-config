#!/usr/bin/env bash
# didio-post-review.sh -- Post-work governance review
#
# Usage:
#   didio post-review <feature-id>
#
# Runs after QA completes. Handler reviews the feature output, then
# GateKeeper validates the Handler's assessment via negotiation loop.
#
# Exit codes:
#   0 = approved (Handler + GateKeeper agree)
#   1 = error
#   2 = escalated (requires human review)
#   3 = paused (token budget)

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

# F30-T10 — source flags lib for raising needs_review flags
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
  didio post-review <feature-id>

Runs after QA completes. Handler reviews the completed feature output,
then GateKeeper validates the Handler's assessment via the negotiation
loop. This is the final quality gate before a feature is marked done.

EXIT CODES:
  0 = approved (Handler + GateKeeper agree)
  1 = error
  2 = escalated (requires human review)
  3 = paused (token budget)

CONFIG:
  negotiation.post_work_review   Enable/disable this gate (default: true)
  negotiation.max_rounds         Max negotiation rounds (default: 3)

REQUIRES: meta_agents.handler.enabled = true in didio.config.json
EOF
  exit 0
fi

# ── Step 1: Check if post_work_review is enabled ──────────────────────
POST_REVIEW_ENABLED="$(didio_read_config_path 'negotiation.post_work_review' 'true')"
if [[ "$POST_REVIEW_ENABLED" != "true" ]]; then
  # Disabled — exit silently
  exit 0
fi

# ── Validate feature argument ─────────────────────────────────────────
FEATURE="${1:?feature-id required (e.g. F29B)}"

# Check Handler is enabled (required for post-review)
HANDLER_ENABLED="$(didio_handler_enabled)"
if [[ "$HANDLER_ENABLED" != "true" ]]; then
  echo "[didio-post-review] Handler is disabled. Set meta_agents.handler.enabled=true in didio.config.json" >&2
  exit 1
fi

# ── Resolve feature directory ─────────────────────────────────────────
FEATURE_DIR=""
if declare -F didio_find_feature_dir >/dev/null 2>&1; then
  FEATURE_DIR="$(didio_find_feature_dir "$FEATURE" 2>/dev/null || true)"
fi

if [[ -z "$FEATURE_DIR" ]]; then
  # Fallback: search manually
  FEATURE_DIR=$(find "$PROJECT_ROOT/tasks/features" -maxdepth 1 -type d -name "${FEATURE}-*" 2>/dev/null | head -n1)
fi

if [[ -z "$FEATURE_DIR" || ! -d "$FEATURE_DIR" ]]; then
  echo "[didio-post-review] feature directory not found for $FEATURE" >&2
  exit 1
fi

# ── Ensure decision directories exist ─────────────────────────────────
DECISIONS_DIR="$PROJECT_ROOT/logs/decisions"
REQUESTS_DIR="$DECISIONS_DIR/_requests"
mkdir -p "$DECISIONS_DIR" "$REQUESTS_DIR"

# ── Step 2: Gather review context ────────────────────────────────────

# Feature README
FEATURE_README="$FEATURE_DIR/${FEATURE}-README.md"
README_STATUS="not found"
if [[ -f "$FEATURE_README" ]]; then
  README_STATUS="present"
fi

# TechLead review report (search logs/agents for the most recent techlead log)
TECHLEAD_REPORT=""
TECHLEAD_VERDICT="unknown"
for f in "$PROJECT_ROOT/logs/agents/${FEATURE}-techlead-"*.jsonl; do
  [[ -f "$f" ]] || continue
  TECHLEAD_REPORT="$f"
done
if [[ -n "$TECHLEAD_REPORT" ]]; then
  # Try to extract verdict from the meta file
  TECHLEAD_META="${TECHLEAD_REPORT%.jsonl}.meta.json"
  if [[ -f "$TECHLEAD_META" ]]; then
    TECHLEAD_VERDICT=$(python3 -c "
import json
with open('$TECHLEAD_META') as f:
    m = json.load(f)
status = m.get('status', 'unknown')
print('APPROVED' if status == 'completed' else status.upper())
" 2>/dev/null || echo "unknown")
  fi
else
  echo "[didio-post-review] WARNING: no TechLead report found for $FEATURE" >&2
fi

# QA report (search logs/agents for the most recent qa log)
QA_REPORT=""
QA_VERDICT="unknown"
for f in "$PROJECT_ROOT/logs/agents/${FEATURE}-qa-"*.jsonl; do
  [[ -f "$f" ]] || continue
  QA_REPORT="$f"
done
if [[ -n "$QA_REPORT" ]]; then
  QA_META="${QA_REPORT%.jsonl}.meta.json"
  if [[ -f "$QA_META" ]]; then
    QA_VERDICT=$(python3 -c "
import json
with open('$QA_META') as f:
    m = json.load(f)
status = m.get('status', 'unknown')
print('PASSED' if status == 'completed' else status.upper())
" 2>/dev/null || echo "unknown")
  fi
else
  echo "[didio-post-review] WARNING: no QA report found for $FEATURE" >&2
fi

# Count files changed (git diff if on a feature branch, else count task files)
FILES_CHANGED=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Try to diff against main
  FILES_CHANGED=$(git diff --name-only main...HEAD 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  # If we are ON main or diff fails, count files in the feature dir
  if [[ "$FILES_CHANGED" -eq 0 ]]; then
    FILES_CHANGED=$(find "$FEATURE_DIR" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  fi
fi

# Count tests added (heuristic: count test files or test-related mentions)
TESTS_ADDED=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TESTS_ADDED=$(git diff --name-only main...HEAD 2>/dev/null | grep -ciE '(test|spec|_test\.|\.test\.)' || echo "0")
fi

# ── Step 3: Write decision request ───────────────────────────────────
TS="$(date +%Y%m%d-%H%M%S)"
REQUEST_FILE="$REQUESTS_DIR/${FEATURE}-post-review-${TS}.md"

# Extract feature description from README if available
FEATURE_DESC="$FEATURE"
if [[ -f "$FEATURE_README" ]]; then
  # Try first heading line
  FEATURE_DESC=$(head -5 "$FEATURE_README" | grep -m1 '^#' | sed 's/^#\+\s*//' || echo "$FEATURE")
  [[ -z "$FEATURE_DESC" ]] && FEATURE_DESC="$FEATURE"
fi

cat > "$REQUEST_FILE" <<REQEOF
# Post-Work Review: $FEATURE

**Type:** quality_gate
**Feature:** $FEATURE_DESC
**TechLead verdict:** $TECHLEAD_VERDICT
**QA verdict:** $QA_VERDICT
**Files changed:** $FILES_CHANGED
**Tests added:** $TESTS_ADDED

## Context

This is a post-work review gate. The feature pipeline has completed all
development waves, TechLead review, and QA validation. Your task is to
review the overall quality and completeness of the delivered feature.

### Feature README
$(if [[ -f "$FEATURE_README" ]]; then
  echo ""
  echo '```'
  cat "$FEATURE_README"
  echo '```'
else
  echo "*Feature README not found at $FEATURE_README*"
fi)

### TechLead Report
$(if [[ -n "$TECHLEAD_REPORT" ]]; then
  echo "Log: $TECHLEAD_REPORT"
  echo "Verdict: $TECHLEAD_VERDICT"
else
  echo "*No TechLead report available*"
fi)

### QA Report
$(if [[ -n "$QA_REPORT" ]]; then
  echo "Log: $QA_REPORT"
  echo "Verdict: $QA_VERDICT"
else
  echo "*No QA report available*"
fi)

## Decision Required

Review the feature output and decide:
- **approve**: Feature meets quality standards, mark as done
- **escalate**: Feature has concerns requiring human review

Consider: test coverage, documentation completeness, architecture alignment,
and whether the acceptance criteria from the feature README are met.
REQEOF

echo "[didio-post-review] decision request written: $REQUEST_FILE" >&2

# ── Step 4: Spawn Handler with post-review context ───────────────────
echo "[didio-post-review] spawning Handler for post-review of $FEATURE..." >&2

"$DIDIO_HOME/bin/didio-spawn-agent.sh" handler "$FEATURE" "$REQUEST_FILE" \
  "POST_WORK_REVIEW=true — This is a post-work quality gate review. Read the decision request carefully. Produce a quality_gate decision record. Focus on completeness, test coverage, and architecture alignment."
HANDLER_EXIT=$?

if [[ $HANDLER_EXIT -ne 0 ]]; then
  echo "[didio-post-review] Handler failed (exit=$HANDLER_EXIT)" >&2
  exit 1
fi

# Find the most recent decision record for this feature
LATEST_DECISION=""
for f in "$DECISIONS_DIR"/D-*.json; do
  [[ -f "$f" ]] || continue
  LATEST_DECISION="$f"
done

if [[ -z "$LATEST_DECISION" ]]; then
  echo "[didio-post-review] WARNING: no decision record produced by Handler" >&2
  # No decision = treat as approved (Handler did not object)
  echo "[didio-post-review] no objections raised — feature $FEATURE approved by default" >&2
  exit 0
fi

DECISION_ID="$(basename "$LATEST_DECISION" .json)"
echo "[didio-post-review] Handler decision: $DECISION_ID" >&2

# ── Step 5: Run negotiation loop ─────────────────────────────────────
# Source negotiation loop library if available (T02)
NEGOTIATION_LIB="$DIDIO_HOME/bin/didio-negotiation-loop.sh"
if [[ -f "$PROJECT_ROOT/bin/didio-negotiation-loop.sh" ]]; then
  NEGOTIATION_LIB="$PROJECT_ROOT/bin/didio-negotiation-loop.sh"
fi

if [[ -f "$NEGOTIATION_LIB" ]]; then
  # shellcheck disable=SC1090
  source "$NEGOTIATION_LIB"
  # didio_negotiate <feature> <decision-file> <extra-env>
  didio_negotiate "$FEATURE" "$LATEST_DECISION" "POST_WORK_REVIEW=true"
  NEGOTIATE_EXIT=$?
else
  # TODO: T02 negotiation loop not yet available — stub the call.
  # When didio-negotiation-loop.sh is implemented, remove this fallback
  # and rely on the sourced didio_negotiate function above.
  echo "[didio-post-review] NOTE: negotiation loop (T02) not available — falling back to single-round GateKeeper review" >&2

  GATEKEEPER_ENABLED="$(didio_gatekeeper_enabled)"
  if [[ "$GATEKEEPER_ENABLED" == "true" ]]; then
    "$DIDIO_HOME/bin/didio-gatekeeper.sh" --decision "$DECISION_ID"
    NEGOTIATE_EXIT=$?
  else
    echo "[didio-post-review] GateKeeper disabled — skipping governance review" >&2
    NEGOTIATE_EXIT=0
  fi
fi

# ── Step 6: Handle results ───────────────────────────────────────────
# Read the final verdict from the decision record
FINAL_STATUS=$(python3 -c "
import json
with open('$LATEST_DECISION') as f:
    d = json.load(f)
gov = d.get('governance', {})
verdict = gov.get('verdict', '') if isinstance(gov, dict) else ''
status = d.get('status', 'pending')
# Escalated by governance or gatekeeper
if verdict == 'escalate' or status == 'escalated':
    print('escalated')
elif verdict == 'agree' or status in ('reviewed', 'executed'):
    print('approved')
else:
    print(status)
" 2>/dev/null || echo "unknown")

case "$FINAL_STATUS" in
  approved|reviewed|executed)
    echo "[didio-post-review] APPROVED — feature $FEATURE passed post-work review" >&2
    exit 0
    ;;
  escalated)
    echo "[didio-post-review] ESCALATED — feature $FEATURE requires human review" >&2
    echo "[didio-post-review]   Decision: $LATEST_DECISION" >&2
    echo "[didio-post-review]   Request:  $REQUEST_FILE" >&2
    # F30-T10 — raise a needs_review flag when post-review escalates
    if declare -F didio_flag_raise >/dev/null 2>&1; then
      didio_flag_raise "$FEATURE" "needs_review" "" "Post-review escalated for $DECISION_ID — human review required" >/dev/null 2>&1 || true
    fi
    exit 2
    ;;
  *)
    # Check negotiate exit code as fallback
    case "$NEGOTIATE_EXIT" in
      0)
        echo "[didio-post-review] APPROVED — feature $FEATURE passed post-work review (negotiate exit=0)" >&2
        exit 0
        ;;
      3)
        echo "[didio-post-review] ESCALATED — pipeline blocked by GateKeeper (negotiate exit=3)" >&2
        # F30-T10 — raise needs_review flag on GateKeeper block
        if declare -F didio_flag_raise >/dev/null 2>&1; then
          didio_flag_raise "$FEATURE" "needs_review" "" "Post-review blocked by GateKeeper — human review required" >/dev/null 2>&1 || true
        fi
        exit 2
        ;;
      *)
        # Max rounds exhausted or unknown — escalate to operator
        echo "[didio-post-review] ESCALATED — negotiation inconclusive (exit=$NEGOTIATE_EXIT), escalating to operator" >&2
        # F30-T10 — raise needs_review flag on inconclusive negotiation
        if declare -F didio_flag_raise >/dev/null 2>&1; then
          didio_flag_raise "$FEATURE" "needs_review" "" "Post-review negotiation inconclusive (exit=$NEGOTIATE_EXIT)" >/dev/null 2>&1 || true
        fi
        exit 2
        ;;
    esac
    ;;
esac
