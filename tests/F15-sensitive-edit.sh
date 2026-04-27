#!/usr/bin/env bash
# F15 smoke: exercises the real spawn pipeline.
# Cost: ~2 developer spawns (sonnet, ~$0.02–0.05 in tokens).
# Run after merge or when modifying the permission hook / spawn-agent.
# Do NOT run in tight loops — each invocation burns real API tokens.
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIXT="tests/F15-fixtures"
MARK="templates/commands/_f15-fixture.md"
SETTINGS_HASH_BEFORE="$(md5 -q .claude/settings.json)"

cleanup() {
  rm -f "$MARK"
  rm -f logs/agents/F99-developer-*.jsonl logs/agents/F99-developer-*.meta.json 2>/dev/null || true
}
trap cleanup EXIT

echo "=== F15 smoke: permission fix + honest exit signal ==="
echo ""

# Test 1 — AC1+AC2: edit + create succeeds (path is templates/commands/, outside .claude/)
echo "--- Test 1: AC1+AC2 — developer can create and edit slash-command fixture ---"
./bin/didio-spawn-agent.sh developer F99 "$FIXT/F99-T01-edit.md"

if [[ -f "$MARK" ]]; then
  printf "${GREEN}PASS${RESET}: AC1+AC2 — %s created\n" "$MARK"
else
  printf "${RED}FAIL${RESET}: AC1+AC2 — %s not created\n" "$MARK"
  exit 1
fi

if grep -q "F15 fixture marker" "$MARK"; then
  printf "${GREEN}PASS${RESET}: AC1+AC2 — marker text present\n"
else
  printf "${RED}FAIL${RESET}: AC1+AC2 — 'F15 fixture marker' missing from %s\n" "$MARK"
  exit 1
fi

echo ""

# Test 2 — AC4 + AC8: deny on settings.json forces non-zero exit, file unchanged
echo "--- Test 2: AC4+AC8 — deny on .claude/settings.json returns non-zero, file unchanged ---"
set +e
./bin/didio-spawn-agent.sh developer F99 "$FIXT/F99-T02-deny.md"
RC=$?
set -e

if [[ "$RC" -ne 0 ]]; then
  printf "${GREEN}PASS${RESET}: AC4 — deny task exited %d (non-zero as expected)\n" "$RC"
else
  printf "${RED}FAIL${RESET}: AC4 — deny task exited 0, expected non-zero\n"
  exit 1
fi

SETTINGS_HASH_AFTER="$(md5 -q .claude/settings.json)"
if [[ "$SETTINGS_HASH_BEFORE" == "$SETTINGS_HASH_AFTER" ]]; then
  printf "${GREEN}PASS${RESET}: AC8 — .claude/settings.json is byte-identical (unchanged)\n"
else
  printf "${RED}FAIL${RESET}: AC8 — .claude/settings.json was modified\n"
  exit 1
fi

echo ""
echo "F15 smoke: ALL PASS"
