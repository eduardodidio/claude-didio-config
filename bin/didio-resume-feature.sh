#!/usr/bin/env bash
# didio-resume-feature.sh — invoked by the scheduled sleep+exec kicked off
# by didio-budget-pause.sh. Reads logs/session-paused.json and re-spawns
# the paused agents with an extra RETOMADA prompt.
#
# Usage: didio-resume-feature.sh <feature-id>
#
# Env overrides (tests):
#   DIDIO_RESUME_DRY=1     don't actually spawn, just print commands
#   DIDIO_SPAWN_CMD=<path> override path to didio-spawn-agent.sh

set -u
FEATURE="${1:?feature id required (e.g. F07)}"

PROJECT="${DIDIO_PROJECT_ROOT:-$(pwd)}"
SNAP="$PROJECT/logs/session-paused.json"
SPAWN="${DIDIO_SPAWN_CMD:-$PROJECT/bin/didio-spawn-agent.sh}"
RESTORE="$PROJECT/bin/didio-checkpoint-restore.sh"

[[ -f "$SNAP" ]] || { echo "[resume] no paused snapshot — nothing to do"; exit 0; }

# Confirm the snapshot matches this feature (no accidental cross-resume).
SNAP_FEAT="$(python3 -c "
import json
try:
  print(json.load(open('$SNAP')).get('feature',''))
except Exception:
  print('')
" 2>/dev/null)"
if [[ "$SNAP_FEAT" != "$FEATURE" ]]; then
  echo "[resume] snapshot feature ($SNAP_FEAT) != requested ($FEATURE) — skip"
  exit 0
fi

# Walk tasks_running and relaunch each.
python3 - "$SNAP" "$FEATURE" "$PROJECT" "$SPAWN" "$RESTORE" "${DIDIO_RESUME_DRY:-0}" <<'PY'
import json, os, subprocess, sys
snap_path, feature, project, spawn_cmd, restore_cmd, dry = sys.argv[1:7]
dry = dry == "1"
with open(snap_path) as f:
    snap = json.load(f)
tasks = snap.get("tasks_running", [])
if not tasks:
    print("[resume] no tasks_running in snapshot")
    sys.exit(0)

for t in tasks:
    run_id = t.get("run_id", "")
    role = t.get("role", "")
    task_file = t.get("task_file", "")
    if not role or not task_file:
        print(f"[resume] skipping incomplete task entry: {t}", file=sys.stderr)
        continue
    ckpt = f"{project}/logs/agents/{run_id}.checkpoint.json"
    hint = ""
    if os.path.isfile(ckpt):
        try:
            r = subprocess.run([restore_cmd, ckpt], capture_output=True, text=True, check=False)
            if r.returncode == 0:
                hint = r.stdout.strip()
        except Exception:
            pass
    if hint:
        extra = (f"RETOMADA DE SESSÃO — você foi pausado em 98% de budget. "
                 f"Checkpoint em {ckpt}. Continue EXATAMENTE a partir de: {hint}. "
                 f"NÃO repita trabalho já registrado no task_progress.")
    else:
        extra = (f"RETOMADA DE SESSÃO — você foi pausado em 98% de budget. "
                 f"Checkpoint em {ckpt} AUSENTE ou inválido. "
                 f"Reinicie esta task do começo.")
    cmd = [spawn_cmd, role, feature, task_file, extra]
    print(f"[resume] spawning: role={role} task_file={task_file} hint_ok={bool(hint)}")
    if dry:
        print("  DRY:", " ".join(cmd))
        continue
    try:
        subprocess.Popen(cmd, cwd=project,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        print(f"[resume] spawn failed for {run_id}: {e}", file=sys.stderr)
PY

# Mark snapshot handled (rename with timestamp so history is preserved).
TS="$(date +%s)"
mv "$SNAP" "${SNAP}.handled-$TS" 2>/dev/null || true

# Notify (best-effort).
COUNT="$(python3 -c "import json; print(len(json.load(open('${SNAP}.handled-$TS')).get('tasks_running',[])))" 2>/dev/null || echo '?')"
"$PROJECT/bin/didio-notify.sh" "▶️ Retomando $FEATURE ($COUNT task(s))" >/dev/null 2>&1 || true

exit 0
