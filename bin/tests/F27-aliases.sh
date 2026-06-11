#!/usr/bin/env bash
# F27 alias smoke test — validates /bmad-* aliases delegate without
# reimplementing logic.
# Run: bash bin/tests/F27-aliases.sh
# Covers: AC1, AC8 (data-driven; discovers aliases by glob)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/templates/commands"
MIRROR_DIR="$REPO_ROOT/.claude/commands"

# Pre-baked spawn/skill tokens that bmad-* aliases may delegate to without a
# 1:1 templates/commands/<base>.md file (T04/T05 must not need to edit this
# test when adding their own aliases that reuse these tokens).
SPAWN_SKILL_TOKENS=(run-wave qa-retro code-review techlead)

# Aliases not yet implemented (future tasks) and the selector itself —
# excluded so this test only validates aliases that already exist.
EXCLUDE_NAMES=(
  bmad
  bmad-generate-project-context
  bmad-create-ux-design
  bmad-testarch-framework
  bmad-testarch-ci
  bmad-sprint-planning
  bmad-testarch-atdd
  bmad-correct-course
  bmad-testarch-automate
)

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

is_excluded() {
  local name="$1"
  for ex in "${EXCLUDE_NAMES[@]}"; do
    [[ "$name" == "$ex" ]] && return 0
  done
  return 1
}

is_spawn_skill_token() {
  local target="$1"
  for tok in "${SPAWN_SKILL_TOKENS[@]}"; do
    [[ "$target" == "$tok" ]] && return 0
  done
  return 1
}

shopt -s nullglob
ALIAS_FILES=("$TEMPLATES_DIR"/bmad-*.md)
shopt -u nullglob

CHECKED=0

for f in "${ALIAS_FILES[@]}"; do
  base_name="$(basename "$f" .md)"

  if is_excluded "$base_name"; then
    continue
  fi

  CHECKED=$((CHECKED+1))

  # (a) marker line present
  marker_line=$(grep -m1 '^<!-- bmad-alias: delegates-to=' "$f" || true)
  if [[ -z "$marker_line" ]]; then
    fail "$base_name: missing 'bmad-alias: delegates-to=' marker line"
    continue
  fi
  pass "$base_name: marker line present"

  # extract delegates-to=<target>
  target=$(echo "$marker_line" | sed -E 's/.*delegates-to=([^ ]+).*/\1/')
  target_norm="${target#/}"

  # (b) target valid: either templates/commands/<base>.md exists, or a
  # pre-baked spawn/skill token
  if [[ -f "$TEMPLATES_DIR/$target_norm.md" ]]; then
    pass "$base_name: delegates-to target '$target' resolves to templates/commands/$target_norm.md"
  elif is_spawn_skill_token "$target_norm"; then
    pass "$base_name: delegates-to target '$target' is a pre-baked spawn/skill token"
  else
    fail "$base_name: delegates-to target '$target' does not resolve to a command file or spawn/skill token"
  fi

  # (c) mirror exists and is identical
  mirror="$MIRROR_DIR/$base_name.md"
  if [[ -f "$mirror" ]] && cmp -s "$f" "$mirror"; then
    pass "$base_name: mirror .claude/commands/$base_name.md exists and is identical"
  else
    fail "$base_name: mirror .claude/commands/$base_name.md missing or diverges"
  fi

  # (d) body must not contain own implementation steps
  if grep -qE '(mkdir -p|^## Step )' "$f"; then
    fail "$base_name: body contains own implementation steps (mkdir -p or '## Step ')"
  else
    pass "$base_name: body contains no own implementation steps"
  fi
done

if [[ "$CHECKED" -eq 0 ]]; then
  echo "[WARN] no bmad-* aliases found to check (vacuous pass)"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
