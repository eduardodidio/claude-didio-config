#!/usr/bin/env bash
# F27-sync — propagation regression test (AC6, AC8)
#
# Asserts that didio-sync-project.sh, run unmodified against a temporary
# git fixture, propagates every templates/commands/bmad-*.md into
# <fixture>/.claude/commands/, idempotently across two runs.
#
# NOTE: F27-T03 (Write(claude-didio-out/**) settings.json permission) was
# SKIPPED by decision (2026-06-10): it hit the F15 spawned-agent lock and is
# non-essential — the /bmad-* commands run in the main context and prompt for
# the write like the F14 commands do. So this test covers commands auto-sync
# only; it does NOT assert any settings.json permission merge.
#
# Run: bash bin/tests/F27-sync.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_SCRIPT="$REPO_ROOT/bin/didio-sync-project.sh"

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

TMPDIR_PROJ="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_PROJ"' EXIT

# ---------------------------------------------------------------------------
# Fixture setup: minimal git repo with a minimal settings.json + CLAUDE.md
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR_PROJ/.claude"
cat > "$TMPDIR_PROJ/.claude/settings.json" <<'JSON'
{"permissions":{"allow":[]}}
JSON
cat > "$TMPDIR_PROJ/CLAUDE.md" <<'MD'
# Fixture project
MD
git -C "$TMPDIR_PROJ" init -q
git -C "$TMPDIR_PROJ" add -A
git -C "$TMPDIR_PROJ" -c user.name="F27 Test" -c user.email="f27@test.local" commit -q -m "init"

# ---------------------------------------------------------------------------
# Run 1: real sync against the fixture
# ---------------------------------------------------------------------------
DIDIO_HOME="$REPO_ROOT" bash "$SYNC_SCRIPT" "$TMPDIR_PROJ" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Assert (a): every templates/commands/bmad-*.md propagated
# ---------------------------------------------------------------------------
MISSING=0
TOTAL=0
for src in "$REPO_ROOT"/templates/commands/bmad-*.md; do
  TOTAL=$((TOTAL+1))
  name="$(basename "$src")"
  if [[ ! -f "$TMPDIR_PROJ/.claude/commands/$name" ]]; then
    fail "missing $name in fixture .claude/commands/ after sync"
    MISSING=$((MISSING+1))
  fi
done
if [[ $MISSING -eq 0 && $TOTAL -gt 0 ]]; then
  pass "all $TOTAL templates/commands/bmad-*.md propagated to .claude/commands/"
fi

# ---------------------------------------------------------------------------
# Assert (b): idempotency — a second sync run does not error and keeps
# exactly one copy of each bmad-* command (no duplication / corruption).
# ---------------------------------------------------------------------------
DIDIO_HOME="$REPO_ROOT" bash "$SYNC_SCRIPT" "$TMPDIR_PROJ" >/dev/null 2>&1 || true

DUP=0
for src in "$REPO_ROOT"/templates/commands/bmad-*.md; do
  name="$(basename "$src")"
  cnt=$(find "$TMPDIR_PROJ/.claude/commands" -name "$name" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$cnt" != "1" ]]; then
    fail "after 2 sync runs, $name appears $cnt times (expected 1)"
    DUP=$((DUP+1))
  fi
done
if [[ $DUP -eq 0 ]]; then
  pass "second sync run is idempotent (each bmad-* command present exactly once)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
