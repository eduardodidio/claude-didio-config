#!/usr/bin/env bash
# F27 structural test — validates the 8 new BMAD commands (AC8)
# Run: bash bin/tests/F27-new-commands.sh
# Covers: existence, frontmatter, marker line, mirror in .claude/commands/,
#         claude-didio-out/ reference, and absence of run-wave/spawn-agent.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/templates/commands"
CLAUDE_DIR="$REPO_ROOT/.claude/commands"

COMMANDS=(
  "bmad-generate-project-context"
  "bmad-create-ux-design"
  "bmad-testarch-framework"
  "bmad-testarch-ci"
  "bmad-sprint-planning"
  "bmad-testarch-atdd"
  "bmad-correct-course"
  "bmad-testarch-automate"
)

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

for cmd in "${COMMANDS[@]}"; do
  tpl="$TEMPLATES_DIR/$cmd.md"
  mirror="$CLAUDE_DIR/$cmd.md"

  # (a) existence + frontmatter description:
  if [[ -f "$tpl" ]]; then
    if grep -q '^description:' "$tpl"; then
      pass "$cmd: exists with frontmatter description"
    else
      fail "$cmd: missing 'description:' frontmatter"
    fi
  else
    fail "$cmd: $tpl does not exist"
    continue
  fi

  # (b) marker line
  if grep -qE '<!-- bmad-new: persona=.+ phase=(upstream|downstream) -->' "$tpl"; then
    pass "$cmd: has bmad-new marker line"
  else
    fail "$cmd: missing bmad-new marker line"
  fi

  # (c) mirror in .claude/commands/ identical
  if [[ -f "$mirror" ]]; then
    if diff -q "$tpl" "$mirror" >/dev/null 2>&1; then
      pass "$cmd: mirror in .claude/commands/ is identical"
    else
      fail "$cmd: mirror in .claude/commands/ differs from template"
    fi
  else
    fail "$cmd: $mirror does not exist"
  fi

  # (d) references claude-didio-out/
  if grep -q 'claude-didio-out/' "$tpl"; then
    pass "$cmd: references claude-didio-out/"
  else
    fail "$cmd: does not reference claude-didio-out/"
  fi

  # (e) negative: no run-wave / spawn-agent invocation in body
  # (mentions in prohibition text, e.g. "sem run-wave" / "Não dispare", are allowed)
  if grep -E 'run-wave|spawn-agent' "$tpl" | grep -qvE 'sem run-wave|sem .*spawn|[Nn]ão dispar|próxima a rodar via|próxima pendente'; then
    fail "$cmd: body references run-wave/spawn-agent (should be artifact-only)"
  else
    pass "$cmd: does not trigger run-wave/spawn-agent"
  fi
done

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
