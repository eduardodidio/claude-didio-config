#!/usr/bin/env bash
# tests/F01-sync-compile.sh — Validate F01-T14: didio-sync-project.sh invokes
# `didio compile-skills` before copying, so synced projects receive compiled
# skill artifacts (.claude/commands, .claude/agents, agents/prompts).
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
PASS=0; FAIL=0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------
TMPDIR_REAL="$(cd "${TMPDIR:-/tmp}" && pwd)"
TARGET="$(mktemp -d -t F01-sync-compile-fixture-XXXXXX)"
trap '
  case "$TARGET" in
    /tmp/*|"$TMPDIR_REAL"/*) rm -rf "$TARGET" ;;
    *) echo "WARN: skipping rm -rf on suspect path: $TARGET" >&2 ;;
  esac
' EXIT
case "$TARGET" in
  /tmp/*|"$TMPDIR_REAL"/*) ;;
  *) echo "ERROR: fixture path suspect: $TARGET"; exit 2 ;;
esac

git -C "$TARGET" init -q
git -C "$TARGET" -c user.email='test@example.com' -c user.name='F01-Test' \
  commit --allow-empty -q -m "init"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
assert_pass() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${RESET}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${RESET}: $label"
    FAIL=$((FAIL + 1))
  fi
}

assert_grep() {
  local pattern="$1"
  local label="$2"
  local output="$3"
  if echo "$output" | grep -qF "$pattern"; then
    echo -e "${GREEN}PASS${RESET}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${RESET}: $label (pattern not found: '$pattern')"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Happy path — real sync into a fresh temp project
# ---------------------------------------------------------------------------
rc=0
OUT="$(DIDIO_HOME="$ROOT" "$ROOT/bin/didio-sync-project.sh" "$TARGET" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g')" || rc=$?

assert_pass "sync exits 0" test "$rc" -eq 0
assert_grep "[COMPILE]" "compile step ran before copy" "$OUT"

# Compiled commands present in the target after sync
for cmd in brainstorm research product-brief; do
  assert_pass "compiled .claude/commands/$cmd.md present in target" \
    test -f "$TARGET/.claude/commands/$cmd.md"
done

# Compiled agents/prompts present
assert_pass "compiled agents/prompts/developer.md present in target" \
  test -f "$TARGET/agents/prompts/developer.md"

# Compiled .claude/agents present
assert_pass "compiled .claude/agents/developer.md present in target" \
  test -f "$TARGET/.claude/agents/developer.md"

# Rollback tag still created (existing behavior intact)
assert_pass "rollback tag created" \
  bash -c "git -C '$TARGET' tag | grep -q '^pre-didio-sync-'"

# No writes to ~/.codex or AGENTS.md for a Claude-only project (boundary)
assert_pass "no AGENTS.md written to target (claude-only project)" \
  test ! -f "$TARGET/AGENTS.md"

# ---------------------------------------------------------------------------
# Idempotent re-sync — no diff, no deletions
# ---------------------------------------------------------------------------
git -C "$TARGET" add -A
git -C "$TARGET" -c user.email='test@example.com' -c user.name='F01-Test' \
  commit -q -m "after first sync"

rc=0
OUT2="$(DIDIO_HOME="$ROOT" "$ROOT/bin/didio-sync-project.sh" "$TARGET" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g')" || rc=$?

assert_pass "re-sync exits 0" test "$rc" -eq 0

# git status should report no tracked-file changes (compiled outputs are
# idempotent; sync_dir is copy-if-missing so nothing is overwritten)
assert_pass "re-sync produces no diff to tracked files" \
  bash -c "git -C '$TARGET' diff --quiet HEAD"

assert_pass "re-sync deletes no files (git status clean of deletions)" \
  bash -c "! git -C '$TARGET' status --porcelain | grep -q '^ D'"

# ---------------------------------------------------------------------------
# dry-run still works with the compile step
# ---------------------------------------------------------------------------
rc=0
OUT3="$(DIDIO_HOME="$ROOT" "$ROOT/bin/didio-sync-project.sh" --dry-run "$TARGET" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g')" || rc=$?

assert_pass "dry-run exits 0" test "$rc" -eq 0
assert_grep "DRY-RUN" "dry-run compile step is announced" "$OUT3"
assert_grep "DRY-RUN ONLY" "dry-run summary footer present" "$OUT3"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "F01 sync-compile: $PASS assertions passed, $FAIL failed"
exit $FAIL
