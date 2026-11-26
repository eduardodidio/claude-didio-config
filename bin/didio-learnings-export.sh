#!/usr/bin/env bash
# didio-learnings-export.sh -- export agent learnings to shareable JSON
# Usage: didio-learnings-export.sh [--output FILE] [--role ROLE] [--since DATE]
#
# Parses markdown learnings files and outputs structured JSON.
# Default output: logs/agents/shared-learnings-export.json
set -euo pipefail

# --- Dependency check -------------------------------------------------------
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required but not found on PATH." >&2
  exit 1
fi

# --- Defaults ---------------------------------------------------------------
DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${DIDIO_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
LEARNINGS_DIR="${PROJECT_ROOT}/memory/agent-learnings"
OUTPUT_FILE="${PROJECT_ROOT}/logs/agents/shared-learnings-export.json"
ROLE_FILTER=""
SINCE_FILTER=""

# --- Parse arguments --------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)  OUTPUT_FILE="$2"; shift 2 ;;
    --role)    ROLE_FILTER="$2"; shift 2 ;;
    --since)   SINCE_FILTER="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: didio-learnings-export.sh [--output FILE] [--role ROLE] [--since DATE]"
      echo ""
      echo "  --output FILE   Output JSON file (default: logs/agents/shared-learnings-export.json)"
      echo "  --role ROLE     Export only learnings for this role (architect, developer, qa, techlead, security)"
      echo "  --since DATE    Export only learnings from features on or after DATE (YYYY-MM-DD)"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

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

# --- Ensure output directory exists -----------------------------------------
mkdir -p "$(dirname "$OUTPUT_FILE")"

# --- Parse learnings and produce JSON ---------------------------------------
python3 - "$LEARNINGS_DIR" "$OUTPUT_FILE" "$PROJECT_NAME" "$ROLE_FILTER" "$SINCE_FILTER" <<'PYEOF'
import json
import os
import re
import sys
import hashlib
from datetime import datetime

learnings_dir = sys.argv[1]
output_file = sys.argv[2]
project_name = sys.argv[3]
role_filter = sys.argv[4] if len(sys.argv) > 4 else ""
since_filter = sys.argv[5] if len(sys.argv) > 5 else ""

valid_roles = {"architect", "developer", "qa", "techlead", "security",
               "readiness", "tea", "handler", "gatekeeper"}
export_roles = {"architect", "developer", "qa", "techlead", "security"}
results = []

if not os.path.isdir(learnings_dir):
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump([], f, indent=2)
    print(f"Exported 0 learnings to {output_file}")
    sys.exit(0)

for filename in sorted(os.listdir(learnings_dir)):
    if not filename.endswith(".md"):
        continue
    role = filename.replace(".md", "")
    if role not in valid_roles:
        continue
    if role not in export_roles:
        continue
    if role_filter and role != role_filter:
        continue

    filepath = os.path.join(learnings_dir, filename)
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    # Parse sections: ## Feature — Date
    section_re = re.compile(r"^## (F\d+)\b.*?(\d{4}-\d{2}-\d{2})?", re.MULTILINE)
    sections = list(section_re.finditer(content))

    for i, match in enumerate(sections):
        feature = match.group(1)
        date_str = match.group(2) or ""

        if since_filter and date_str and date_str < since_filter:
            continue

        # Extract text until next section
        start = match.end()
        end = sections[i + 1].start() if i + 1 < len(sections) else len(content)
        section_text = content[start:end].strip()

        # Extract bullet points as individual lessons
        for line in section_text.split("\n"):
            line = line.strip()
            # Skip section headers like **What worked:**
            if line.startswith("**") and line.endswith("**"):
                continue
            # Remove leading bullet and bold prefix
            lesson = re.sub(r"^[-*]\s*", "", line)
            lesson = re.sub(r"^\*\*[^*]+:\*\*\s*", "", lesson)
            if not lesson or len(lesson) < 10:
                continue

            # Extract tags from common patterns
            tags = re.findall(r"`([^`]+)`", lesson)
            feature_refs = re.findall(r"\bF\d+\b", lesson)

            learning_id = hashlib.sha256(
                f"{project_name}:{role}:{feature}:{lesson[:80]}".encode()
            ).hexdigest()[:16]

            results.append({
                "learning_id": learning_id,
                "project": project_name,
                "role": role,
                "feature": feature,
                "lesson": lesson,
                "context": section_text[:200] if section_text else "",
                "severity": "important",
                "tags": list(set(tags + feature_refs)),
                "created_at": f"{date_str}T00:00:00Z" if date_str else datetime.utcnow().isoformat() + "Z",
            })

with open(output_file, "w", encoding="utf-8") as f:
    json.dump(results, f, indent=2, ensure_ascii=False)

print(f"Exported {len(results)} learnings to {output_file}")
PYEOF
