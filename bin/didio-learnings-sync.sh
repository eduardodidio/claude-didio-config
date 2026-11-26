#!/usr/bin/env bash
# didio-learnings-sync.sh -- sync learnings with a shared repository
# Usage: didio-learnings-sync.sh <shared-repo-path>
#
# 1. Exports local learnings to <shared-repo-path>/learnings/<project>.json
# 2. Imports learnings from other projects in <shared-repo-path>/learnings/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# --- Parse arguments --------------------------------------------------------
SHARED_PATH="${1:-}"

if [[ -z "$SHARED_PATH" || "$SHARED_PATH" == "--help" || "$SHARED_PATH" == "-h" ]]; then
  echo "Usage: didio-learnings-sync.sh <shared-repo-path>"
  echo ""
  echo "  Exports local learnings to <shared-repo-path>/learnings/<project>.json"
  echo "  then imports learnings from other projects in the same directory."
  [[ -z "$SHARED_PATH" ]] && exit 1
  exit 0
fi

# --- Read project name from config ------------------------------------------
PROJECT_NAME="unknown"
if [[ -f "${PROJECT_ROOT}/didio.config.json" ]]; then
  PROJECT_NAME=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        cfg = json.load(f)
    print(cfg.get('project_name', 'unknown'))
except Exception:
    print('unknown')
" "${PROJECT_ROOT}/didio.config.json")
fi

# --- Ensure shared learnings directory exists --------------------------------
SHARED_LEARNINGS_DIR="${SHARED_PATH}/learnings"
mkdir -p "$SHARED_LEARNINGS_DIR"

# --- Step 1: Export local learnings -----------------------------------------
echo "=== Exporting local learnings ==="
EXPORT_FILE="${SHARED_LEARNINGS_DIR}/${PROJECT_NAME}.json"
"$SCRIPT_DIR/didio-learnings-export.sh" --output "$EXPORT_FILE"

# --- Step 2: Import learnings from other projects ---------------------------
echo ""
echo "=== Importing learnings from other projects ==="
IMPORTED_COUNT=0

for json_file in "$SHARED_LEARNINGS_DIR"/*.json; do
  [[ -f "$json_file" ]] || continue
  basename_file="$(basename "$json_file" .json)"

  # Skip our own export
  if [[ "$basename_file" == "$PROJECT_NAME" ]]; then
    continue
  fi

  echo "Importing from: $basename_file"
  "$SCRIPT_DIR/didio-learnings-import.sh" "$json_file"
  IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
done

if [[ $IMPORTED_COUNT -eq 0 ]]; then
  echo "No other project learnings found in $SHARED_LEARNINGS_DIR"
fi

echo ""
echo "Sync complete."
