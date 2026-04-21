#!/usr/bin/env bash
# didio-budget-pause.sh — fires when PreToolUse sees pct >= hard_pct.
#
# Responsibilities:
#   1. Anti-loop: respect session_guard.max_resumes_per_day
#   2. Snapshot paused state to logs/session-paused.json (schema: F07-paused)
#   3. Append one line to logs/session-paused.log (for daily counting)
#   4. SIGTERM running agents listed in logs/agents/state.json
#   5. Mark their meta files as status=paused
#   6. Schedule resume via backgrounded `sleep $N && didio-resume-feature.sh`
#   7. Best-effort user notification
#
# Args:
#   $1  window_resets_at ISO8601 (optional — falls back to budget.json)
#
# Env overrides (tests):
#   DIDIO_PAUSE_DRY=1                    don't kill, don't schedule
#   DIDIO_PAUSE_RESUME_OVERRIDE_SECS=N   force sleep=N for scheduled resume
#   DIDIO_PAUSE_LOG_OVERRIDE=<path>      use alt session-paused.log (tests)

set -u

PROJECT="${DIDIO_PROJECT_ROOT:-$(pwd)}"
LOG_DIR="$PROJECT/logs"
AGENTS_DIR="$LOG_DIR/agents"
BUDGET="$LOG_DIR/session-budget.json"
SNAP="$LOG_DIR/session-paused.json"
PAUSE_LOG="${DIDIO_PAUSE_LOG_OVERRIDE:-$LOG_DIR/session-paused.log}"
STATE="$AGENTS_DIR/state.json"

mkdir -p "$LOG_DIR" "$AGENTS_DIR"

# shellcheck disable=SC1090
source "$PROJECT/bin/didio-config-lib.sh" 2>/dev/null || true

MAX_RESUMES="$(didio_read_config_path session_guard.max_resumes_per_day 3 2>/dev/null || echo 3)"
BUFFER_MIN="$(didio_read_config_path session_guard.resume_buffer_minutes 2 2>/dev/null || echo 2)"

RESUME_AT="${1:-}"
PCT="0"
if [[ -f "$BUDGET" ]]; then
  read -r PCT BUDGET_RESUME <<<"$(python3 -c "
import json
try:
  d = json.load(open('$BUDGET'))
  print(d.get('pct',0), d.get('window_resets_at',''))
except Exception:
  print(0, '')
" 2>/dev/null)"
  [[ -z "$RESUME_AT" ]] && RESUME_AT="${BUDGET_RESUME:-}"
fi

NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TODAY="$(date -u +%Y-%m-%d)"

# Anti-loop: count already-logged pauses today.
RESUMES_TODAY=0
if [[ -f "$PAUSE_LOG" ]]; then
  RESUMES_TODAY=$(grep -c "\"date\":\"$TODAY\"" "$PAUSE_LOG" 2>/dev/null || echo 0)
fi

# Extract feature + running agents from state.json.
FEATURE=""
RUNNING_JSON="[]"
if [[ -f "$STATE" ]]; then
  read -r FEATURE RUNNING_JSON <<<"$(python3 -c "
import json
try:
  d = json.load(open('$STATE'))
  agents = [a for a in d.get('agents',[]) if a.get('status')=='running']
  feat = agents[0]['feature'] if agents else (d.get('features',[{}])[0].get('feature','') if d.get('features') else '')
  print(feat or 'F00', json.dumps(agents))
except Exception:
  print('F00', '[]')
" 2>/dev/null)"
fi

# ── Write the snapshot (always) ───────────────────────────────────────────────
python3 - "$SNAP" "$FEATURE" "$RUNNING_JSON" "$NOW_ISO" "$RESUME_AT" "$RESUMES_TODAY" "$PCT" <<'PY' 2>/dev/null
import json, sys, os
snap_path, feat, running_raw, now_iso, resume_at, resumes_today, pct = sys.argv[1:8]
try:
    running = json.loads(running_raw)
except Exception:
    running = []
tasks = []
for a in running:
    log = a.get("log", "")
    run_id = os.path.basename(log).rsplit(".jsonl", 1)[0] if log else ""
    tasks.append({
        "run_id": run_id,
        "task": a.get("task", ""),
        "role": a.get("role", ""),
        "task_file": a.get("task_file", ""),
        "pid": a.get("pid"),
        "meta_file": log.rsplit(".jsonl", 1)[0] + ".meta.json" if log else "",
    })
payload = {
    "feature": feat,
    "wave": None,
    "tasks_running": tasks,
    "paused_at": now_iso,
    "resume_at": resume_at or "",
    "resumes_today": int(resumes_today),
    "pct_at_pause": float(pct) if pct else 0.0,
    "reason": "session_guard hard_pct reached",
}
tmp = snap_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")
os.replace(tmp, snap_path)
PY

# Append one-line log entry.
printf '{"date":"%s","paused_at":"%s","feature":"%s","resume_at":"%s"}\n' \
  "$TODAY" "$NOW_ISO" "$FEATURE" "$RESUME_AT" >> "$PAUSE_LOG" 2>/dev/null || true

# Best-effort notify.
"$PROJECT/bin/didio-notify.sh" "⏸️ Sessão pausada ($(awk -v p="$PCT" 'BEGIN{printf "%d", p*100}')%). $FEATURE será retomado em ${RESUME_AT:-breve}." >/dev/null 2>&1 || true

# Anti-loop short-circuit: skip killing + scheduling.
if (( RESUMES_TODAY >= MAX_RESUMES )); then
  echo "[pause] max_resumes_per_day ($MAX_RESUMES) reached — snapshot only, no reschedule" >&2
  exit 0
fi

# Dry-run stops here (tests).
if [[ "${DIDIO_PAUSE_DRY:-0}" == "1" ]]; then
  exit 0
fi

# ── SIGTERM running agents ────────────────────────────────────────────────────
python3 - "$RUNNING_JSON" "$AGENTS_DIR" <<'PY' 2>/dev/null
import json, os, sys, signal
running_raw, agents_dir = sys.argv[1:3]
try:
    running = json.loads(running_raw)
except Exception:
    running = []
for a in running:
    pid = a.get("pid")
    if not pid:
        continue
    try:
        os.kill(int(pid), signal.SIGTERM)
    except Exception:
        pass
    log = a.get("log", "")
    meta = log.rsplit(".jsonl", 1)[0] + ".meta.json" if log else ""
    if meta and os.path.isfile(meta):
        try:
            with open(meta) as f:
                m = json.load(f)
            m["status"] = "paused"
            with open(meta + ".tmp", "w") as f:
                json.dump(m, f, indent=2)
            os.replace(meta + ".tmp", meta)
        except Exception:
            pass
PY

# ── Schedule resume ───────────────────────────────────────────────────────────
if [[ -n "${DIDIO_PAUSE_RESUME_OVERRIDE_SECS:-}" ]]; then
  SLEEP_SECS="$DIDIO_PAUSE_RESUME_OVERRIDE_SECS"
else
  # macOS + Linux-portable: try python (universal) to compute seconds until
  # RESUME_AT + buffer.
  SLEEP_SECS=$(python3 -c "
import sys
from datetime import datetime, timezone
resume_at = '$RESUME_AT'.strip()
buf_min = int('$BUFFER_MIN')
try:
    if not resume_at:
        raise ValueError
    ra = resume_at.replace('Z','+00:00')
    t = datetime.fromisoformat(ra)
    now = datetime.now(timezone.utc)
    secs = int((t - now).total_seconds()) + buf_min*60
    print(max(secs, 60))
except Exception:
    print(3600)
" 2>/dev/null || echo 3600)
fi

# Spawn the deferred resume.
PIDFILE="$LOG_DIR/resume-scheduled.pid"
nohup bash -c "sleep $SLEEP_SECS && '$PROJECT/bin/didio-resume-feature.sh' '$FEATURE'" \
  >>"$LOG_DIR/resume-scheduled.log" 2>&1 &
echo $! > "$PIDFILE"
disown 2>/dev/null || true

exit 0
