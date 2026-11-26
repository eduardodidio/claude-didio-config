#!/usr/bin/env bash
# didio-learnings-import.sh -- import shared learnings into local agent memory
# Usage: didio-learnings-import.sh <input-file.json> [--role ROLE] [--dry-run]
#
# Reads a shared-learnings JSON file and appends relevant lessons
# to the appropriate memory/agent-learnings/<role>.md files.
set -euo pipefail

# --- Dependency check -------------------------------------------------------
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required but not found on PATH." >&2
  exit 1
fi

# --- Defaults ---------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
LEARNINGS_DIR="${PROJECT_ROOT}/memory/agent-learnings"
INPUT_FILE=""
ROLE_FILTER=""
DRY_RUN=0

# --- Parse arguments --------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)    ROLE_FILTER="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h)
      echo "Usage: didio-learnings-import.sh <input-file.json> [--role ROLE] [--dry-run]"
      echo ""
      echo "  <input-file.json>  Path to the shared-learnings JSON file"
      echo "  --role ROLE        Import only learnings for this role"
      echo "  --dry-run          Show what would be imported without writing"
      exit 0
      ;;
    *)
      if [[ -z "$INPUT_FILE" ]]; then
        INPUT_FILE="$1"
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$INPUT_FILE" ]]; then
  echo "ERROR: input file required." >&2
  echo "Usage: didio-learnings-import.sh <input-file.json> [--role ROLE] [--dry-run]" >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "ERROR: file not found: $INPUT_FILE" >&2
  exit 1
fi

# --- Import logic -----------------------------------------------------------
python3 - "$INPUT_FILE" "$LEARNINGS_DIR" "$ROLE_FILTER" "$DRY_RUN" <<'PYEOF'
import json
import os
import sys
from collections import defaultdict

input_file = sys.argv[1]
learnings_dir = sys.argv[2]
role_filter = sys.argv[3] if len(sys.argv) > 3 else ""
dry_run = sys.argv[4] == "1" if len(sys.argv) > 4 else False

with open(input_file, "r", encoding="utf-8") as f:
    learnings = json.load(f)

if not isinstance(learnings, list):
    print("ERROR: input file must contain a JSON array.", file=sys.stderr)
    sys.exit(1)

# Group by role
by_role = defaultdict(list)
for entry in learnings:
    role = entry.get("role", "")
    if role_filter and role != role_filter:
        continue
    by_role[role].append(entry)

total_imported = 0
total_skipped = 0

for role, entries in sorted(by_role.items()):
    md_path = os.path.join(learnings_dir, f"{role}.md")

    # Read existing content to detect duplicates
    existing_content = ""
    if os.path.isfile(md_path):
        with open(md_path, "r", encoding="utf-8") as f:
            existing_content = f.read()

    # Group entries by project
    by_project = defaultdict(list)
    for e in entries:
        by_project[e.get("project", "unknown")].append(e)

    lines_to_append = []
    imported_header_exists = "## Imported Learnings" in existing_content

    if not imported_header_exists and by_project:
        lines_to_append.append("\n## Imported Learnings\n")

    for project, project_entries in sorted(by_project.items()):
        # Determine date from first entry
        date = project_entries[0].get("created_at", "")[:10] if project_entries else ""
        section_header = f"### From {project} ({date})"

        new_lessons = []
        for e in project_entries:
            lesson = e.get("lesson", "").strip()
            if not lesson:
                continue
            # Skip duplicates: check if the lesson text already exists
            if lesson in existing_content:
                total_skipped += 1
                continue
            new_lessons.append(lesson)

        if not new_lessons:
            continue

        lines_to_append.append(f"\n{section_header}\n")
        for lesson in new_lessons:
            lines_to_append.append(f"- {lesson}")
            total_imported += 1

    if not lines_to_append:
        continue

    content_to_add = "\n".join(lines_to_append) + "\n"

    if dry_run:
        print(f"[dry-run] Would append to {md_path}:")
        print(content_to_add)
    else:
        os.makedirs(learnings_dir, exist_ok=True)
        with open(md_path, "a", encoding="utf-8") as f:
            f.write(content_to_add)
        print(f"Updated {md_path}")

action = "Would import" if dry_run else "Imported"
print(f"{action} {total_imported} learnings, skipped {total_skipped} duplicates.")
PYEOF
