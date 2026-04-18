#!/usr/bin/env bash
# didio-migrate-learnings.sh — one-shot ingestion of
# memory/agent-learnings/<role>.md into the second-brain MCP memory store.
#
# Usage:
#   bin/didio-migrate-learnings.sh                  # real run (spawns claude -p)
#   DIDIO_MIGRATE_DRY=1 bin/didio-migrate-learnings.sh   # print JSON list and exit
#
# Parsing rule: each top-level `## <header>` block inside
# memory/agent-learnings/<role>.md becomes one entry. Entries are prefixed with
# `[ROLE:<role>] ` in content so memory_search can filter by role via query.
#
# This script is idempotent at the "safe-to-re-run" level: calling memory_add
# twice with the same content does create a duplicate, but it won't crash. Use
# memory_search for a de-dup check if needed.

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
LEARNINGS_DIR="$PROJECT_ROOT/memory/agent-learnings"

if [[ ! -d "$LEARNINGS_DIR" ]]; then
  echo "[migrate] no memory/agent-learnings/ directory — nothing to migrate" >&2
  exit 0
fi

# Build a JSON array of {role, header, content} entries from all *.md files.
ENTRIES="$(python3 - "$LEARNINGS_DIR" <<'PY'
import json, os, re, sys
root = sys.argv[1]
out = []
for fn in sorted(os.listdir(root)):
    if not fn.endswith(".md"):
        continue
    role = fn[:-3]
    path = os.path.join(root, fn)
    with open(path) as f:
        text = f.read()
    # Split by top-level "## " headers (keep the header line)
    # The first chunk (before any ##) is the file title/preamble, skip.
    chunks = re.split(r'^(## [^\n]+)\n', text, flags=re.MULTILINE)
    # chunks = [preamble, header1, body1, header2, body2, ...]
    i = 1
    while i < len(chunks):
        header = chunks[i].strip()
        body = chunks[i+1] if i+1 < len(chunks) else ""
        content = f"[ROLE:{role}] {header.lstrip('# ').strip()}\n\n{body.strip()}"
        out.append({"role": role, "header": header, "content": content})
        i += 2
print(json.dumps(out, indent=2, ensure_ascii=False))
PY
)"

COUNT="$(echo "$ENTRIES" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')"

if [[ "${DIDIO_MIGRATE_DRY:-0}" == "1" ]]; then
  echo "[migrate] DRY RUN — would ingest $COUNT entries"
  echo "$ENTRIES"
  exit 0
fi

if [[ "$COUNT" == "0" ]]; then
  echo "[migrate] 0 entries parsed — nothing to do"
  exit 0
fi

# Build a Claude prompt that calls memory_add N times.
PROMPT_FILE="$(mktemp)"
trap 'rm -f "$PROMPT_FILE"' EXIT

cat > "$PROMPT_FILE" <<EOF
You are a one-shot migration agent. For each entry in the JSON array below,
call the tool mcp__second-brain__memory_add with:
  project="claude-didio-config"
  category="agent-learnings"
  content=<the "content" field of the entry>

Do NOT invent roles or modify the content. After calling memory_add for all
entries, print the single line:

MIGRATE_DONE:<count>

Entries (count=$COUNT):
$ENTRIES
EOF

echo "[migrate] invoking claude -p to ingest $COUNT entries..." >&2

claude \
  -p "$(cat "$PROMPT_FILE")" \
  --output-format text \
  --dangerously-skip-permissions
