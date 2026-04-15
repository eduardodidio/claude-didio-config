#!/usr/bin/env bash
# didio-sync-all.sh — sync all downstream projects listed in target-projects.json
# Usage: didio-sync-all.sh [path/to/target-projects.json]
#
# Default config file: $DIDIO_HOME/tasks/features/F04-sync-downstream/target-projects.json
# Calls didio-sync-project.sh for each project path in the JSON.

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

DIDIO_HOME="${DIDIO_HOME:-/Users/eduardodidio/claude-didio-config}"
SYNC_SCRIPT="$DIDIO_HOME/bin/didio-sync-project.sh"
DEFAULT_CONFIG="$DIDIO_HOME/tasks/features/F04-sync-downstream/target-projects.json"
CONFIG_FILE="${1:-$DEFAULT_CONFIG}"

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
if [[ ! -f "$SYNC_SCRIPT" ]]; then
  echo -e "${RED}ERROR:${RESET} sync script not found: $SYNC_SCRIPT" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo -e "${RED}ERROR:${RESET} target-projects.json not found: $CONFIG_FILE" >&2
  echo "Usage: didio-sync-all.sh [path/to/target-projects.json]" >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo -e "${RED}ERROR:${RESET} python3 is required to parse target-projects.json" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Read project list
# ---------------------------------------------------------------------------
mapfile -t PROJECTS < <(python3 - "$CONFIG_FILE" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for p in data.get("projects", []):
    print(p["path"])
PY
)

echo -e "${BOLD}=== didio-sync-all: ${#PROJECTS[@]} project(s) ===${RESET}"
echo

# ---------------------------------------------------------------------------
# Sync each project
# ---------------------------------------------------------------------------
PASS=0
FAIL=0

for project_path in "${PROJECTS[@]}"; do
  echo -e "${BOLD}--- $project_path ---${RESET}"
  if bash "$SYNC_SCRIPT" "$project_path"; then
    PASS=$((PASS + 1))
  else
    echo -e "${RED}[FAILED]${RESET} $project_path" >&2
    FAIL=$((FAIL + 1))
  fi
  echo
done

# ---------------------------------------------------------------------------
# Final tally
# ---------------------------------------------------------------------------
echo -e "${BOLD}=== sync-all complete: ${GREEN}$PASS ok${RESET}${BOLD}," \
  "${RED}$FAIL failed${RESET}${BOLD} ===${RESET}"

[[ $FAIL -eq 0 ]]
