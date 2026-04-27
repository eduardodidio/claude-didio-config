#!/usr/bin/env bash
# F10-T10 — Dry-run sync propagation test for the readiness role
# Validates that didio-sync-project.sh --dry-run reports ADDED for the three
# readiness files without destroying pre-existing downstream customizations.
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TARGET="tests/F10-fixture-target"
LOGFILE="tests/F10-fixtures/sync-dry-run.log"

mkdir -p "$(dirname "$LOGFILE")"

trap 'rm -rf "$TARGET"' EXIT

# ---------------------------------------------------------------------------
# Setup fixture downstream project
# ---------------------------------------------------------------------------
rm -rf "$TARGET"
mkdir -p "$TARGET"/{.claude/commands,agents/prompts,memory/agent-learnings}
cd "$TARGET"
git init -q
echo "node_modules/" > .gitignore
git add . && git -c user.email=t@t -c user.name=t commit -qm init
cd -

# Downstream customization that must NOT be touched
echo "# downstream-custom" > "$TARGET/.claude/commands/my-custom.md"

# 4 existing agent-learnings placeholders (without readiness)
for role in architect developer techlead qa; do
  printf "# %s — Agent Learnings\n(placeholder)\n" "$role" \
    > "$TARGET/memory/agent-learnings/${role}.md"
done

# 4 existing prompt stubs (without readiness)
for role in architect developer techlead qa; do
  echo "# $role" > "$TARGET/agents/prompts/${role}.md"
done

cd "$TARGET" && git add . && git -c user.email=t@t -c user.name=t commit -qm baseline && cd -

# ---------------------------------------------------------------------------
# Run sync dry-run and capture output (strip ANSI codes for reliable grep)
# ---------------------------------------------------------------------------
"$DIDIO_HOME/bin/didio-sync-project.sh" --dry-run "$TARGET" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' \
  | tee "$LOGFILE"

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
FAIL=0

for path in \
  ".claude/commands/check-readiness.md" \
  "agents/prompts/readiness.md" \
  "memory/agent-learnings/readiness.md"
do
  if grep -F "$path" "$LOGFILE" | grep -qF "[ADDED]"; then
    echo "OK: $path mentioned as ADDED in sync log"
  else
    echo "FAIL: $path NOT found as ADDED in sync log"
    FAIL=1
  fi
done

# Custom downstream file must NOT appear in the change log
if grep -qF "my-custom.md" "$LOGFILE"; then
  echo "FAIL: my-custom.md appeared in log (should not be touched)"
  FAIL=1
else
  echo "OK: my-custom.md not mentioned in log (preserved)"
fi

[[ $FAIL -eq 0 ]]
