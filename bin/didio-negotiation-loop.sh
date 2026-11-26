#!/usr/bin/env bash
# didio-negotiation-loop.sh — Multi-round Handler/GateKeeper negotiation library
#
# Source this file (do NOT execute it directly):
#   source "$DIDIO_HOME/bin/didio-negotiation-loop.sh"
#
# Requires: didio-config-lib.sh already sourced.
#
# Usage:
#   didio_negotiate <feature-id> <decision-file> [extra-context]
#
# Returns:
#   0 = agreed  (verdict: agree)
#   1 = failed  (agent error / unexpected failure)
#   2 = escalated (verdict: escalate, or max_rounds exhausted)
#
# Side effects:
#   - Writes logs/governance/G-<id>-round-<N>.json for each round
#   - Writes logs/governance/G-<id>-summary.json after all rounds
#   - Updates decision record with governance history

# Guard: only source once
if [[ -n "${_DIDIO_NEGOTIATION_LOOP_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_DIDIO_NEGOTIATION_LOOP_LOADED=1

# ---------------------------------------------------------------------------
# Config helper
# ---------------------------------------------------------------------------

# Returns the max negotiation rounds from config (default 3).
didio_negotiation_max_rounds() {
  didio_read_config_path 'negotiation.max_rounds' '3'
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# _negotiate_read_verdict <gov-file>
# Reads the verdict field from a governance JSON file. Prints one of:
# agree, challenge, escalate, unknown
_negotiate_read_verdict() {
  local gov_file="$1"
  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get('verdict', 'unknown'))
except Exception:
    print('unknown')
" "$gov_file" 2>/dev/null || echo "unknown"
}

# _negotiate_write_round_log <governance-dir> <decision-id> <round> <handler-action> <verdict> <gov-file>
# Writes the per-round log file G-<id>-round-<N>.json
_negotiate_write_round_log() {
  local gov_dir="$1" decision_id="$2" round="$3"
  local handler_action="$4" verdict="$5" gov_file="$6"

  python3 - "$gov_dir" "$decision_id" "$round" "$handler_action" "$verdict" "$gov_file" <<'PY' 2>/dev/null || true
import json, sys
from datetime import datetime, timezone

gov_dir, decision_id, round_n = sys.argv[1], sys.argv[2], int(sys.argv[3])
handler_action, verdict, gov_file = sys.argv[4], sys.argv[5], sys.argv[6]

# Read the full governance report if it exists
gk_report = {}
try:
    with open(gov_file) as f:
        gk_report = json.load(f)
except Exception:
    pass

# Build cumulative lists from the report
blind_spots = gk_report.get('blind_spots', [])
recommendations = gk_report.get('recommendations', [])

round_log = {
    "decision_id": decision_id,
    "round": round_n,
    "timestamp": datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    "handler_action": handler_action,
    "gatekeeper_verdict": verdict,
    "gatekeeper_report": gk_report,
    "cumulative_blind_spots": blind_spots,
    "cumulative_recommendations": recommendations
}

out_path = f"{gov_dir}/G-{decision_id}-round-{round_n}.json"
with open(out_path, 'w') as f:
    json.dump(round_log, f, indent=2)
    f.write('\n')
PY
}

# _negotiate_write_summary <governance-dir> <decision-id> <total-rounds> <final-verdict>
# Reads all round logs and writes G-<id>-summary.json
_negotiate_write_summary() {
  local gov_dir="$1" decision_id="$2" total_rounds="$3" final_verdict="$4"

  python3 - "$gov_dir" "$decision_id" "$total_rounds" "$final_verdict" <<'PY' 2>/dev/null || true
import json, sys, glob
from datetime import datetime, timezone

gov_dir, decision_id = sys.argv[1], sys.argv[2]
total_rounds, final_verdict = int(sys.argv[3]), sys.argv[4]

rounds = []
all_blind_spots = []
all_recommendations = []

for r in range(1, total_rounds + 1):
    path = f"{gov_dir}/G-{decision_id}-round-{r}.json"
    try:
        with open(path) as f:
            rd = json.load(f)
        rounds.append({
            "round": r,
            "verdict": rd.get("gatekeeper_verdict", "unknown"),
            "handler_action": rd.get("handler_action", "unknown"),
            "blind_spots": rd.get("cumulative_blind_spots", []),
            "recommendations": rd.get("cumulative_recommendations", [])
        })
        for bs in rd.get("cumulative_blind_spots", []):
            if bs not in all_blind_spots:
                all_blind_spots.append(bs)
        for rec in rd.get("cumulative_recommendations", []):
            if rec not in all_recommendations:
                all_recommendations.append(rec)
    except Exception:
        rounds.append({"round": r, "verdict": "missing", "error": "round log not found"})

summary = {
    "decision_id": decision_id,
    "timestamp": datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    "total_rounds": total_rounds,
    "final_verdict": final_verdict,
    "rounds": rounds,
    "cumulative_blind_spots": all_blind_spots,
    "cumulative_recommendations": all_recommendations
}

out_path = f"{gov_dir}/G-{decision_id}-summary.json"
with open(out_path, 'w') as f:
    json.dump(summary, f, indent=2)
    f.write('\n')
PY
}

# _negotiate_build_prior_rounds_context <governance-dir> <decision-id> <up-to-round>
# Builds a text summary of all prior round verdicts for prompt injection.
# Prints the summary to stdout.
_negotiate_build_prior_rounds_context() {
  local gov_dir="$1" decision_id="$2" up_to_round="$3"

  python3 - "$gov_dir" "$decision_id" "$up_to_round" <<'PY' 2>/dev/null || true
import json, sys

gov_dir, decision_id, up_to = sys.argv[1], sys.argv[2], int(sys.argv[3])

lines = ["=== PRIOR NEGOTIATION ROUNDS ==="]
for r in range(1, up_to + 1):
    path = f"{gov_dir}/G-{decision_id}-round-{r}.json"
    try:
        with open(path) as f:
            rd = json.load(f)
        verdict = rd.get("gatekeeper_verdict", "unknown")
        lines.append(f"\n--- Round {r}: {verdict} ---")
        report = rd.get("gatekeeper_report", {})
        if report.get("blind_spots"):
            lines.append("Blind spots: " + "; ".join(report["blind_spots"]))
        if report.get("recommendations"):
            lines.append("Recommendations: " + "; ".join(report["recommendations"]))
        if report.get("rationale"):
            lines.append("Rationale: " + str(report["rationale"]))
    except Exception:
        lines.append(f"\n--- Round {r}: [log not found] ---")

lines.append("\n=== END PRIOR ROUNDS ===")
print("\n".join(lines))
PY
}

# _negotiate_update_decision_status <decision-file> <status>
# Updates the status field on a decision record JSON file.
_negotiate_update_decision_status() {
  local decision_file="$1" status="$2"
  python3 -c "
import json, sys
path, status = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        d = json.load(f)
    d['status'] = status
    with open(path, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
except Exception:
    pass
" "$decision_file" "$status" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main negotiation function
# ---------------------------------------------------------------------------

# didio_negotiate <feature-id> <decision-file> [extra-context]
#
# Runs up to negotiation.max_rounds of Handler -> GateKeeper negotiation.
# Returns:
#   0 = agreed  (verdict: agree)
#   1 = failed  (agent error)
#   2 = escalated (verdict: escalate, or max_rounds exhausted)
didio_negotiate() {
  local feature="${1:?feature-id required}"
  local decision_file="${2:?decision-file required}"
  local extra="${3:-}"

  local project_root="${PROJECT_ROOT:-$(pwd)}"
  local didio_home="${DIDIO_HOME:-$HOME/.claude-didio-config}"
  local governance_dir="$project_root/logs/governance"
  mkdir -p "$governance_dir"

  # Extract decision ID from filename
  local decision_id
  decision_id="$(basename "$decision_file" .json)"

  local max_rounds
  max_rounds="$(didio_negotiation_max_rounds)"

  echo "[didio-negotiate] starting negotiation for $decision_id (max $max_rounds rounds)" >&2

  local round=1
  local verdict=""

  while [[ $round -le $max_rounds ]]; do
    local handler_action="initial"

    # Round > 1: re-spawn Handler with governance feedback first
    if [[ $round -gt 1 ]]; then
      handler_action="re-evaluate"
      echo "[didio-negotiate] round $round/$max_rounds: re-spawning Handler with governance context..." >&2

      local prior_context
      prior_context="$(_negotiate_build_prior_rounds_context "$governance_dir" "$decision_id" "$((round - 1))")"

      "$didio_home/bin/didio-spawn-agent.sh" handler "$feature" "$decision_file" \
        "MODE=re-evaluate GOVERNANCE_DIR=$governance_dir $prior_context — The GateKeeper has challenged your decision. Read the governance reports from prior rounds and address the specific concerns. Update the decision record if warranted. This is round $round of $max_rounds."
      local handler_exit=$?

      if [[ $handler_exit -ne 0 ]]; then
        echo "[didio-negotiate] Handler re-evaluation failed in round $round (exit=$handler_exit)" >&2
        _negotiate_write_summary "$governance_dir" "$decision_id" "$((round - 1))" "handler_error"
        return 1
      fi
    fi

    # Spawn GateKeeper to review the decision
    echo "[didio-negotiate] round $round/$max_rounds: spawning GateKeeper..." >&2

    local gk_extra="RESTRICTED_CONTEXT=true"
    if [[ $round -gt 1 ]]; then
      local prior_for_gk
      prior_for_gk="$(_negotiate_build_prior_rounds_context "$governance_dir" "$decision_id" "$((round - 1))")"
      gk_extra="$gk_extra ROUND=$round $prior_for_gk"
    fi
    gk_extra="$gk_extra — You may ONLY read: this decision record, CLAUDE.md, didio.config.json, and other files in logs/decisions/ and logs/governance/. Do NOT read any other files."

    "$didio_home/bin/didio-spawn-agent.sh" gatekeeper "META" "$decision_file" "$gk_extra"
    local gk_exit=$?

    if [[ $gk_exit -ne 0 ]]; then
      echo "[didio-negotiate] GateKeeper failed in round $round (exit=$gk_exit)" >&2
      _negotiate_write_summary "$governance_dir" "$decision_id" "$round" "gatekeeper_error"
      return 1
    fi

    # Read the governance report (GateKeeper writes G-<decision-id>.json)
    local gov_file="$governance_dir/G-${decision_id}.json"
    if [[ ! -f "$gov_file" ]]; then
      echo "[didio-negotiate] WARNING: no governance report produced in round $round" >&2
      _negotiate_write_round_log "$governance_dir" "$decision_id" "$round" "$handler_action" "unknown" "$gov_file"
      _negotiate_write_summary "$governance_dir" "$decision_id" "$round" "no_report"
      return 1
    fi

    # Read verdict
    verdict="$(_negotiate_read_verdict "$gov_file")"

    # Write round log
    _negotiate_write_round_log "$governance_dir" "$decision_id" "$round" "$handler_action" "$verdict" "$gov_file"

    echo "[didio-negotiate] round $round/$max_rounds: verdict=$verdict" >&2

    case "$verdict" in
      agree)
        echo "[didio-negotiate] AGREED on round $round" >&2
        _negotiate_write_summary "$governance_dir" "$decision_id" "$round" "agree"
        return 0
        ;;
      escalate)
        echo "[didio-negotiate] ESCALATED on round $round — pipeline BLOCKED. Human review required." >&2
        _negotiate_update_decision_status "$decision_file" "escalated"
        _negotiate_write_summary "$governance_dir" "$decision_id" "$round" "escalate"
        return 2
        ;;
      challenge)
        if [[ $round -eq $max_rounds ]]; then
          echo "[didio-negotiate] max rounds exhausted with unresolved challenge — ESCALATING to operator" >&2
          _negotiate_update_decision_status "$decision_file" "escalated"
          _negotiate_write_summary "$governance_dir" "$decision_id" "$round" "max_rounds_exhausted"
          return 2
        fi
        echo "[didio-negotiate] CHALLENGE on round $round — will re-evaluate..." >&2
        ;;
      *)
        echo "[didio-negotiate] unknown verdict '$verdict' in round $round — treating as challenge" >&2
        if [[ $round -eq $max_rounds ]]; then
          _negotiate_update_decision_status "$decision_file" "escalated"
          _negotiate_write_summary "$governance_dir" "$decision_id" "$round" "unknown_verdict_exhausted"
          return 2
        fi
        ;;
    esac

    round=$((round + 1))
  done

  # Should not reach here, but safety net
  _negotiate_write_summary "$governance_dir" "$decision_id" "$max_rounds" "max_rounds_exhausted"
  return 2
}
