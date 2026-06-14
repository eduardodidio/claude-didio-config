#!/usr/bin/env bash
# tests/F01-compile-codex.sh — smoke test for didio-compile-skills.sh (Codex target).
#
# Verifies (F01-T10):
#   - happy path: _example.md compiles to <out-codex>/example-skill.md with the
#     claude block removed and the codex block unwrapped; a role-prompt skill is
#     included in AGENTS.md
#   - edge case: a subagent skill targeting codex is skipped with a logged note
#     and produces no Codex prompt file
#   - error scenario: an unwritable --out-codex directory -> non-zero exit,
#     clear message, no partial AGENTS.md
#   - boundary: --target all twice = no diff in either Claude or Codex outputs,
#     sentinels preserved in Codex prompts
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
PASS=0; FAIL=0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILE="$ROOT/bin/didio-compile-skills.sh"

TMPDIR_REAL="$(cd "${TMPDIR:-/tmp}" && pwd)"
WORK="$(mktemp -d -t F01-compile-codex-XXXXXX)"
trap '
  case "$WORK" in
    /tmp/*|"$TMPDIR_REAL"/*) rm -rf "$WORK" ;;
    *) echo "WARN: skipping rm -rf on suspect path: $WORK" >&2 ;;
  esac
' EXIT
case "$WORK" in
  /tmp/*|"$TMPDIR_REAL"/*) ;;
  *) echo "ERROR: work path suspect: $WORK"; exit 2 ;;
esac

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

assert_fail() {
  local label="$1"; shift
  if ! "$@" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${RESET}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${RESET}: $label"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Happy path: _example.md + a role-prompt skill -> Codex prompts + AGENTS.md
# ---------------------------------------------------------------------------
HAPPY="$WORK/happy"
mkdir -p "$HAPPY/skills" "$HAPPY/codex-out"
cp "$ROOT/skills/_example.md" "$HAPPY/skills/"

cat > "$HAPPY/skills/sample-role.md" <<'EOF'
---
name: sample-role
description: Sample role prompt
kind: role-prompt
targets: [claude, codex]
---
# Sample Role

Shared instructions for the sample role.

<!-- didio:claude -->
Claude-only line: see CLAUDE.md.
<!-- /didio:claude -->

<!-- didio:codex -->
Codex-only line: see AGENTS.md.
<!-- /didio:codex -->
EOF

cat > "$HAPPY/CLAUDE.md" <<'EOF'
# Project Instructions

These are the project instructions.
EOF

assert_pass "compile happy path (codex target)" \
  "$COMPILE" --skills-dir "$HAPPY/skills" --output-root "$HAPPY" --out-codex "$HAPPY/codex-out" --target codex

EXAMPLE_OUT="$HAPPY/codex-out/example-skill.md"
ROLE_OUT="$HAPPY/codex-out/sample-role.md"
AGENTS_OUT="$HAPPY/AGENTS.md"

assert_pass "example-skill prompt file created" test -f "$EXAMPLE_OUT"

assert_pass "GENERATED header present" \
  grep -q "GENERATED FILE" "$EXAMPLE_OUT"

assert_pass "claude block stripped from example-skill" \
  bash -c "! grep -q '/example-skill' '$EXAMPLE_OUT'"

assert_pass "codex block unwrapped (content kept, markers removed)" \
  bash -c "grep -q 'codex exec' '$EXAMPLE_OUT' && ! grep -q 'didio:codex' '$EXAMPLE_OUT'"

assert_pass "sentinels preserved verbatim" \
  bash -c "grep -q '{{USE_SECOND_BRAIN}}' '$EXAMPLE_OUT' && grep -q '{{DIDIO_CHECKPOINT}}' '$EXAMPLE_OUT'"

assert_pass "AGENTS.md created" test -f "$AGENTS_OUT"

assert_pass "AGENTS.md includes project instructions" \
  grep -q "These are the project instructions" "$AGENTS_OUT"

assert_pass "AGENTS.md includes the sample-role section" \
  grep -q "sample-role" "$AGENTS_OUT"

assert_pass "AGENTS.md includes codex-flavored body, not claude" \
  bash -c "grep -q 'Codex-only line' '$AGENTS_OUT' && ! grep -q 'Claude-only line' '$AGENTS_OUT'"

# ---------------------------------------------------------------------------
# Edge case: a subagent skill targeting codex is skipped with a logged note
# ---------------------------------------------------------------------------
SUBAGENT="$WORK/subagent"
mkdir -p "$SUBAGENT/skills" "$SUBAGENT/codex-out"
cat > "$SUBAGENT/skills/codex-agent.md" <<'EOF'
---
name: codex-agent
description: A subagent that also opts into codex
kind: subagent
targets: [claude, codex]
---
Subagent body.
EOF

SKIP_MSG="$("$COMPILE" --skills-dir "$SUBAGENT/skills" --output-root "$SUBAGENT" --out-codex "$SUBAGENT/codex-out" --target codex 2>&1)"

assert_pass "subagent skip note is logged" \
  bash -c "echo '$SKIP_MSG' | grep -q 'skip codex: codex-agent (subagent)'"

assert_pass "no Codex prompt file for subagent" \
  test ! -f "$SUBAGENT/codex-out/codex-agent.md"

# ---------------------------------------------------------------------------
# Error scenario: unwritable --out-codex -> non-zero exit, no partial AGENTS.md
# ---------------------------------------------------------------------------
UNWRITABLE="$WORK/unwritable"
mkdir -p "$UNWRITABLE/skills"
cp "$ROOT/skills/_example.md" "$UNWRITABLE/skills/"
cp "$HAPPY/skills/sample-role.md" "$UNWRITABLE/skills/"

BLOCKED_DIR="$WORK/blocked-parent"
mkdir -p "$BLOCKED_DIR"
chmod 000 "$BLOCKED_DIR"

assert_fail "unwritable --out-codex exits non-zero" \
  "$COMPILE" --skills-dir "$UNWRITABLE/skills" --output-root "$UNWRITABLE" \
    --out-codex "$BLOCKED_DIR/prompts" --target codex

assert_pass "no partial AGENTS.md written on error" \
  test ! -f "$UNWRITABLE/AGENTS.md"

chmod 755 "$BLOCKED_DIR"

# ---------------------------------------------------------------------------
# Boundary: --target all twice = no diff; sentinels preserved
# ---------------------------------------------------------------------------
ALL="$WORK/all"
mkdir -p "$ALL/skills" "$ALL/codex-out"
cp "$ROOT/skills/_example.md" "$ALL/skills/"
cp "$HAPPY/skills/sample-role.md" "$ALL/skills/"
cp "$HAPPY/CLAUDE.md" "$ALL/CLAUDE.md"

assert_pass "first run --target all" \
  "$COMPILE" --skills-dir "$ALL/skills" --output-root "$ALL" --out-codex "$ALL/codex-out" --target all

mkdir -p "$WORK/all-snapshot"
cp -r "$ALL/.claude" "$WORK/all-snapshot/claude" 2>/dev/null || true
cp -r "$ALL/agents" "$WORK/all-snapshot/agents" 2>/dev/null || true
cp -r "$ALL/codex-out" "$WORK/all-snapshot/codex-out"
cp "$ALL/AGENTS.md" "$WORK/all-snapshot/AGENTS.md"

assert_pass "second run --target all" \
  "$COMPILE" --skills-dir "$ALL/skills" --output-root "$ALL" --out-codex "$ALL/codex-out" --target all

assert_pass "second run reports up to date" \
  bash -c "'$COMPILE' --skills-dir '$ALL/skills' --output-root '$ALL' --out-codex '$ALL/codex-out' --target all | grep -q 'up to date'"

assert_pass "idempotent: .claude unchanged" \
  diff -rq "$WORK/all-snapshot/claude" "$ALL/.claude"

assert_pass "idempotent: agents/prompts unchanged" \
  diff -rq "$WORK/all-snapshot/agents" "$ALL/agents"

assert_pass "idempotent: codex prompts unchanged" \
  diff -rq "$WORK/all-snapshot/codex-out" "$ALL/codex-out"

assert_pass "idempotent: AGENTS.md unchanged" \
  diff -q "$WORK/all-snapshot/AGENTS.md" "$ALL/AGENTS.md"

assert_pass "sentinels preserved in codex prompt (all target)" \
  bash -c "grep -q '{{USE_SECOND_BRAIN}}' '$ALL/codex-out/example-skill.md' && grep -q '{{DIDIO_CHECKPOINT}}' '$ALL/codex-out/example-skill.md'"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "F01 compile-skills (Codex target): $PASS assertions passed, $FAIL failed"
exit $FAIL
