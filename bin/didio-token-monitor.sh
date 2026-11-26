#!/usr/bin/env bash
# didio-token-monitor.sh -- Token budget monitor and scheduling suggester
#
# Usage:
#   didio token-monitor              # Full report (writes suggestion JSON)
#   didio token-monitor --check-only # Quick check: prints OK/WARNING/CRITICAL
#   didio token-monitor --suggest    # Print scheduling suggestion to stdout
#
# Reads logs/session-budget.json and session_guard config.
# Outputs logs/agents/token-schedule-suggestion.json.
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# shellcheck source=didio-config-lib.sh
source "${DIDIO_HOME}/bin/didio-config-lib.sh"

# ── Defaults ────────────────────────────────────────────────────────
BUDGET_FILE="${PROJECT_ROOT}/logs/session-budget.json"
SUGGESTION_FILE="${PROJECT_ROOT}/logs/agents/token-schedule-suggestion.json"
MAX_SNAPSHOT_AGE_SECS="${MAX_SNAPSHOT_AGE_SECS:-600}"  # 10 minutes

# Thresholds: ok < 70%, warning 70-90%, critical >= 90%
THRESHOLD_WARNING=0.70
THRESHOLD_CRITICAL=0.90

# Resume buffer from config (default 5 minutes)
RESUME_BUFFER_MINUTES="$(didio_read_config_path 'session_guard.resume_buffer_minutes' '5')"

# ── Argument parsing ────────────────────────────────────────────────
MODE="full"   # full | check-only | suggest
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) MODE="check-only"; shift ;;
    --suggest)    MODE="suggest";    shift ;;
    --help|-h)
      echo "Usage: didio token-monitor [--check-only | --suggest]" >&2
      exit 0
      ;;
    *)
      echo "didio-token-monitor: unknown option '$1'" >&2
      exit 1
      ;;
  esac
done

# ── Helper: ISO-8601 now ───────────────────────────────────────────
iso_now() {
  python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).isoformat())"
}

# ── Guard: budget file must exist ──────────────────────────────────
if [[ ! -f "$BUDGET_FILE" ]]; then
  if [[ "$MODE" == "check-only" ]]; then
    echo "OK"
    exit 0
  fi
  echo "[token-monitor] Budget file not found: $BUDGET_FILE" >&2
  echo "[token-monitor] No budget data available -- assuming OK." >&2
  exit 0
fi

# ── Read and analyze budget via Python ─────────────────────────────
# Python does all the heavy lifting: JSON parsing, date math, threshold
# evaluation, and output generation.
ANALYSIS="$(python3 - "$BUDGET_FILE" "$THRESHOLD_WARNING" "$THRESHOLD_CRITICAL" \
  "$RESUME_BUFFER_MINUTES" "$MAX_SNAPSHOT_AGE_SECS" "$PROJECT_ROOT" "$MODE" <<'PYEOF'
import json, sys, os
from datetime import datetime, timezone, timedelta

budget_file   = sys.argv[1]
warn_pct      = float(sys.argv[2])
crit_pct      = float(sys.argv[3])
resume_buffer = int(sys.argv[4])
max_age_secs  = int(sys.argv[5])
project_root  = sys.argv[6]
mode          = sys.argv[7]

now = datetime.now(timezone.utc)

# ── Load budget JSON ──────────────────────────────────────────
try:
    with open(budget_file, encoding="utf-8") as f:
        b = json.load(f)
except Exception as e:
    print(json.dumps({"error": f"Cannot read budget file: {e}"}))
    sys.exit(0)

# ── Parse fields (match actual session-budget.json format) ────
tokens_used     = b.get("tokens_used", 0)
tokens_limit    = b.get("limit", 200000000)
burn_rate       = b.get("burn_rate_tokens_per_min", 0)
updated_at_str  = b.get("updated_at", "")
window_resets   = b.get("window_resets_at", "")
window_started  = b.get("window_started_at", "")

# Parse updated_at for staleness check
stale = False
stale_msg = ""
if updated_at_str:
    try:
        updated_at = datetime.fromisoformat(updated_at_str.replace("Z", "+00:00"))
        age_secs = (now - updated_at).total_seconds()
        if age_secs > max_age_secs:
            stale = True
            stale_msg = f"Budget snapshot is {int(age_secs)}s old (max {max_age_secs}s)"
    except Exception:
        pass

# ── Calculations ──────────────────────────────────────────────
if tokens_limit <= 0:
    tokens_limit = 200000000

pct_used = tokens_used / tokens_limit
remaining_tokens = tokens_limit - tokens_used

# Minutes to depletion
if burn_rate > 0:
    minutes_to_depletion = remaining_tokens / burn_rate
else:
    minutes_to_depletion = -1  # unknown

# Projected depletion time
if minutes_to_depletion > 0:
    projected_depletion_at = now + timedelta(minutes=minutes_to_depletion)
    projected_depletion_iso = projected_depletion_at.isoformat()
else:
    projected_depletion_iso = ""

# Window reset
window_resets_iso = window_resets if window_resets else ""

# Suggested resume = window_resets_at + resume_buffer_minutes
suggested_resume_iso = ""
cron_line = ""
at_command = ""
if window_resets:
    try:
        wr = datetime.fromisoformat(window_resets.replace("Z", "+00:00"))
        suggested_resume = wr + timedelta(minutes=resume_buffer)
        suggested_resume_iso = suggested_resume.isoformat()
        # Build cron and at commands
        cron_line = f"{suggested_resume.minute} {suggested_resume.hour} * * * cd {project_root} && didio resume-pending"
        at_command = f"echo 'cd {project_root} && didio resume-pending' | at {suggested_resume.strftime('%H:%M')}"
    except Exception:
        pass

# ── Status determination ──────────────────────────────────────
if pct_used >= crit_pct:
    status = "critical"
    recommendation = "CRITICAL: budget nearly exhausted -- schedule resumption after window reset"
elif pct_used >= warn_pct:
    status = "warning"
    recommendation = "Consider scheduling resumption -- budget running low"
else:
    status = "ok"
    recommendation = "Budget is healthy"

if stale:
    recommendation += f" [STALE: {stale_msg}]"

# ── Build output object ──────────────────────────────────────
output = {
    "analyzed_at": now.isoformat(),
    "pct_used": round(pct_used, 4),
    "remaining_tokens": int(remaining_tokens),
    "burn_rate_per_min": round(burn_rate, 2),
    "minutes_to_depletion": round(minutes_to_depletion, 1) if minutes_to_depletion > 0 else None,
    "projected_depletion_at": projected_depletion_iso or None,
    "window_resets_at": window_resets_iso or None,
    "suggested_resume_at": suggested_resume_iso or None,
    "cron_line": cron_line or None,
    "at_command": at_command or None,
    "status": status,
    "recommendation": recommendation,
    "stale": stale,
}

# ── Mode-specific behavior ────────────────────────────────────
if mode == "check-only":
    # Print just the status word (uppercased) to stdout
    print(status.upper())
    sys.exit(0)

# For full and suggest modes, emit the JSON to stdout
print(json.dumps(output, indent=2))
PYEOF
)"

# ── check-only: Python already printed the status word ────────────
if [[ "$MODE" == "check-only" ]]; then
  echo "$ANALYSIS"
  exit 0
fi

# ── Handle error from Python ───────────────────────────────────────
if echo "$ANALYSIS" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'error' not in d else 1)" 2>/dev/null; then
  : # no error
else
  echo "[token-monitor] $ANALYSIS" >&2
  exit 0
fi

# ── Full and suggest modes: write suggestion file and print report ─
if [[ "$MODE" == "full" ]]; then
  # Write the suggestion JSON
  mkdir -p "$(dirname "$SUGGESTION_FILE")"
  echo "$ANALYSIS" > "$SUGGESTION_FILE"
  echo "[token-monitor] Suggestion written to: $SUGGESTION_FILE" >&2
fi

if [[ "$MODE" == "suggest" ]]; then
  # Just print the JSON to stdout (already done by Python)
  echo "$ANALYSIS"
  exit 0
fi

# ── Human-readable summary to stderr ──────────────────────────────
echo "$ANALYSIS" | python3 -c '
import json, sys
data = json.load(sys.stdin)

pct = data["pct_used"] * 100
remaining = data["remaining_tokens"]
burn = data["burn_rate_per_min"]
status = data["status"].upper()
rec = data["recommendation"]
mtd = data.get("minutes_to_depletion")
depl = data.get("projected_depletion_at", "N/A") or "N/A"
resets = data.get("window_resets_at", "N/A") or "N/A"
resume = data.get("suggested_resume_at", "N/A") or "N/A"

print("=" * 60)
print(f"  Token Budget Monitor -- Status: {status}")
print("=" * 60)
print(f"  Used:          {pct:.1f}%")
print(f"  Remaining:     {remaining:,} tokens")
print(f"  Burn rate:     {burn:,.0f} tokens/min")
if mtd and mtd > 0:
    if mtd >= 60:
        print(f"  Depletion in:  {mtd/60:.1f} hours")
    else:
        print(f"  Depletion in:  {mtd:.0f} minutes")
    print(f"  Depletion at:  {depl}")
print(f"  Window resets: {resets}")
print(f"  Resume after:  {resume}")
print("-" * 60)
print(f"  >> {rec}")
if data.get("stale"):
    print("  >> WARNING: budget snapshot is stale")
print("=" * 60)
' >&2

# Also print the JSON to stdout for piping
echo "$ANALYSIS"
