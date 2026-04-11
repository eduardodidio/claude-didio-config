#!/usr/bin/env bash
# didio-log-watcher.sh — aggregate logs/agents/*.meta.json into a single
# logs/agents/state.json file, regenerated every 1s. The dashboard fetches
# state.json directly (no backend needed).

set -euo pipefail
PROJECT_ROOT="$(pwd)"
LOG_DIR="$PROJECT_ROOT/logs/agents"
STATE_FILE="$LOG_DIR/state.json"

mkdir -p "$LOG_DIR"

while true; do
  python3 - "$LOG_DIR" "$STATE_FILE" <<'PY' 2>/dev/null || true
import json, os, sys, glob
from datetime import datetime, timezone
log_dir, state_file = sys.argv[1], sys.argv[2]
agents = []
for meta_path in sorted(glob.glob(os.path.join(log_dir, "*.meta.json"))):
    try:
        with open(meta_path) as f:
            agents.append(json.load(f))
    except Exception:
        continue
state = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "agents": agents,
}
tmp = state_file + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
os.replace(tmp, state_file)
PY
  sleep 1
done
