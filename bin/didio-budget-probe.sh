#!/usr/bin/env bash
# didio-budget-probe.sh — write current 5h-window token utilization to
# logs/session-budget.json. Two sources:
#   1. `npx -y ccusage blocks --active --json --token-limit max` (primary)
#   2. transcript parsing (fallback; reads $DIDIO_TRANSCRIPT_PATH jsonl)
#
# The key difference from prior versions: we use `blocks`, not `session`.
# A block = Anthropic's 5h rolling billing window, which is what the
# rate-limiter actually uses. `session` = per-chat — useless for a
# window-aware guard.
#
# Throttled via mtime so rapid invocations produce at most 1 write per
# $DIDIO_BUDGET_THROTTLE_SECS (default 5). Called by the PostToolUse hook —
# must never break the session, so all failure paths exit 0 silently.
#
# Test hooks (for tests/F07-budget-smoke.sh — no impact in production):
#   FAKE_CCUSAGE_JSON   override ccusage stdout with literal JSON
#   FAKE_CCUSAGE_FAIL   set to 1 to simulate ccusage failure (force fallback)
#   DIDIO_BUDGET_THROTTLE_SECS  override throttle window (default 5)

set -u

PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$(pwd)}"
LOG_DIR="$PROJECT_ROOT/logs"
BUDGET="$LOG_DIR/session-budget.json"
LOCK="$LOG_DIR/.budget-probe.lock"
THROTTLE="${DIDIO_BUDGET_THROTTLE_SECS:-5}"

mkdir -p "$LOG_DIR"

# Throttle: skip if another probe ran within THROTTLE seconds.
if [[ -f "$BUDGET" ]]; then
  NOW=$(date +%s)
  LAST=$(stat -f '%m' "$BUDGET" 2>/dev/null || stat -c '%Y' "$BUDGET" 2>/dev/null || echo 0)
  if (( NOW - LAST < THROTTLE )); then
    exit 0
  fi
fi

# Serialize concurrent probes if `flock` is available (not on macOS by
# default). When absent, the mtime-based throttle above plus the atomic
# os.replace at the end is enough to prevent corruption.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK" 2>/dev/null || exit 0
  flock -n 9 || exit 0
fi

# shellcheck disable=SC1090
source "$PROJECT_ROOT/bin/didio-config-lib.sh" 2>/dev/null \
  || source "${DIDIO_HOME:-/Users/eduardodidio/claude-didio-config}/bin/didio-config-lib.sh" 2>/dev/null \
  || exit 0

ENABLED="$(didio_read_config_path session_guard.enabled true 2>/dev/null || echo true)"
[[ "$ENABLED" != "true" ]] && exit 0

SOURCE_PREF="$(didio_read_config_path session_guard.source ccusage 2>/dev/null || echo ccusage)"
LIMIT_FALLBACK="$(didio_read_config_path session_guard.window_limit_tokens 200000000 2>/dev/null || echo 200000000)"

CC_JSON=""
CC_OK=0

try_ccusage() {
  if [[ -n "${FAKE_CCUSAGE_JSON:-}" ]]; then
    CC_JSON="$FAKE_CCUSAGE_JSON"
    CC_OK=1
    return
  fi
  if [[ "${FAKE_CCUSAGE_FAIL:-0}" == "1" ]]; then
    CC_OK=0
    return
  fi
  if ! command -v npx >/dev/null 2>&1; then
    CC_OK=0
    return
  fi
  # blocks --active --json --token-limit max is the canonical call.
  # --active returns only the current 5h window.
  # --token-limit max uses the historical max block as limit reference.
  CC_JSON="$(npx -y ccusage blocks --active --json --token-limit max 2>/dev/null || true)"
  [[ -n "$CC_JSON" ]] && CC_OK=1 || CC_OK=0
}

if [[ "$SOURCE_PREF" == "ccusage" ]]; then
  try_ccusage
fi

export DIDIO_CC_JSON="$CC_JSON"
python3 - "$BUDGET" "$SOURCE_PREF" "$LIMIT_FALLBACK" "${DIDIO_TRANSCRIPT_PATH:-}" "$CC_OK" <<'PY' || exit 0
import json, os, sys
from datetime import datetime, timezone

budget_path, source_pref, limit_fb, transcript, cc_ok = sys.argv[1:6]
limit_fb = int(limit_fb)
cc_ok = cc_ok == "1"
cc_raw = os.environ.get("DIDIO_CC_JSON", "")

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def parse_ccusage_blocks(raw, limit_fallback):
    """Parse `ccusage blocks --active --json --token-limit max` output.

    Expected shape:
      {"blocks": [{ "id": "...", "startTime": "...", "endTime": "...",
                    "isActive": true, "totalTokens": N,
                    "tokenLimitStatus": {"limit": N, "percentUsed": P, ...},
                    "burnRate": {"tokensPerMinute": ...},
                    "projection": {"remainingMinutes": ...} }]}
    """
    try:
        d = json.loads(raw)
    except Exception:
        return None
    if not isinstance(d, dict):
        return None
    blocks = d.get("blocks") or []
    if not isinstance(blocks, list) or not blocks:
        return None
    # Prefer the active block; fall back to last block if --active wasn't honored.
    active = next((b for b in blocks if isinstance(b, dict) and b.get("isActive")), None)
    if active is None:
        active = blocks[-1] if isinstance(blocks[-1], dict) else None
    if active is None:
        return None

    used = active.get("totalTokens")
    if used is None:
        tc = active.get("tokenCounts") or {}
        used = int(tc.get("inputTokens", 0) or 0) + int(tc.get("outputTokens", 0) or 0) \
             + int(tc.get("cacheCreationInputTokens", 0) or 0) \
             + int(tc.get("cacheReadInputTokens", 0) or 0)
    try:
        used = int(used)
    except Exception:
        return None

    tls = active.get("tokenLimitStatus") or {}
    try:
        limit = int(tls.get("limit") or limit_fallback)
    except Exception:
        limit = limit_fallback
    if limit <= 0:
        limit = limit_fallback
    if limit <= 0:
        return None

    end_time = str(active.get("endTime") or "")       # window resets at
    start_time = str(active.get("startTime") or "")
    session_id = str(active.get("id") or "")

    # Normalise to Z suffix so hook's python3 fromisoformat accepts either.
    def norm(ts):
        return ts.replace(".000Z", "Z").replace(".000", "") if ts else ts
    end_time = norm(end_time)
    start_time = norm(start_time)

    burn = active.get("burnRate") or {}
    proj = active.get("projection") or {}

    return {
        "source": "ccusage",
        "session_id": session_id,
        "tokens_used": used,
        "limit": limit,
        "pct": round(used / limit, 4),
        "window_resets_at": end_time,
        "window_started_at": start_time,
        "weekly_resets_at": "",
        "burn_rate_tokens_per_min": burn.get("tokensPerMinute"),
        "remaining_minutes": proj.get("remainingMinutes"),
        "projected_tokens": proj.get("totalTokens"),
        "updated_at": now_iso(),
    }

def parse_transcript(path, limit):
    if not path or not os.path.isfile(path):
        return None
    used = 0
    session_id = ""
    try:
        with open(path, "r", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except Exception:
                    continue
                if not session_id:
                    session_id = row.get("session_id", "") or row.get("sessionId", "")
                msg = row.get("message") or row
                usage = (msg.get("usage") if isinstance(msg, dict) else None) or {}
                used += int(usage.get("input_tokens", 0) or 0)
                used += int(usage.get("output_tokens", 0) or 0)
                used += int(usage.get("cache_creation_input_tokens", 0) or 0)
                used += int(usage.get("cache_read_input_tokens", 0) or 0)
    except Exception:
        return None
    if used <= 0:
        return None
    return {
        "source": "transcript",
        "session_id": session_id,
        "tokens_used": used,
        "limit": limit,
        "pct": round(used / limit, 4),
        "window_resets_at": "",
        "window_started_at": "",
        "weekly_resets_at": "",
        "updated_at": now_iso(),
        "degraded": True,
    }

snap = None
if cc_ok and source_pref == "ccusage":
    snap = parse_ccusage_blocks(cc_raw, limit_fb)
if snap is None:
    snap = parse_transcript(transcript, limit_fb)

if snap is None:
    sys.exit(0)

tmp = budget_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(snap, f, indent=2)
    f.write("\n")
os.replace(tmp, budget_path)
PY
exit 0
