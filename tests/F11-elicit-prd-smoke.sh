#!/usr/bin/env bash
# F11-elicit-prd-smoke.sh — structural lint for /elicit-prd artefacts
# Validates AC1, AC2, AC3, AC4, AC6, AC7, AC8 without invoking the command.
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; RESET='\033[0m'
PASS=0; FAIL=0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

_pass() { printf "${GREEN}[PASS]${RESET} %s\n" "$1"; (( PASS++ )) || true; }
_fail() { printf "${RED}[FAIL]${RESET} %s\n" "$1"; (( FAIL++ )) || true; }
_warn() { printf "${YELLOW}[WARN]${RESET} %s\n" "$1"; }

# ── Helpers ───────────────────────────────────────────────────────────────────

assert_file() {
  local path="$1" desc="$2"
  if [[ -f "$path" ]]; then
    _pass "$desc"
  else
    _fail "$desc — file not found: $path"
  fi
}

# assert_grep <pattern> <file> <desc>
assert_grep() {
  local pattern="$1" file="$2" desc="$3"
  if grep -qF "$pattern" "$file" 2>/dev/null; then
    _pass "$desc"
  else
    _fail "$desc — pattern not found: '$pattern' in $file"
  fi
}

# assert_grep_re <pattern> <file> <desc>
assert_grep_re() {
  local pattern="$1" file="$2" desc="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    _pass "$desc"
  else
    _fail "$desc — pattern not found: '$pattern' in $file"
  fi
}

# assert_grep_count_exact <pattern> <file> <expected> <desc>
assert_grep_count_exact() {
  local pattern="$1" file="$2" expected="$3" desc="$4"
  local count
  # grep -c exits 1 when count=0 but still prints "0"; use || : to stay set -e safe
  count=$(grep -cE "$pattern" "$file" 2>/dev/null || :)
  count="${count:-0}"
  if [[ "$count" -eq "$expected" ]]; then
    _pass "$desc (count=$count)"
  else
    _fail "$desc — expected $expected, got $count (pattern: $pattern)"
  fi
}

# assert_grep_zero <pattern> <file> <desc>  (negative: must NOT match)
assert_grep_zero() {
  local pattern="$1" file="$2" desc="$3"
  local count
  count=$(grep -cF "$pattern" "$file" 2>/dev/null || :)
  count="${count:-0}"
  if [[ "$count" -eq 0 ]]; then
    _pass "$desc"
  else
    _fail "$desc — forbidden pattern found ($count times): '$pattern' in $file"
  fi
}

# assert_grep_zero_re <pattern> <file> <desc>
assert_grep_zero_re() {
  local pattern="$1" file="$2" desc="$3"
  local count
  count=$(grep -cE "$pattern" "$file" 2>/dev/null || :)
  count="${count:-0}"
  if [[ "$count" -eq 0 ]]; then
    _pass "$desc"
  else
    _fail "$desc — forbidden pattern found ($count times): '$pattern' in $file"
  fi
}

CMD_TEMPLATE="templates/.claude/commands/elicit-prd.md"
CMD_LOCAL=".claude/commands/elicit-prd.md"
QUESTIONS="templates/docs/prd/elicit-questions.md"
DIDIO_TEMPLATE="templates/.claude/commands/didio.md"
DIDIO_LOCAL=".claude/commands/didio.md"

echo "=== F11 — /elicit-prd smoke ==="
echo ""

# ── AC1: command files exist + body references key paths ─────────────────────
echo "--- AC1: command files exist and reference key artefacts ---"

assert_file "$CMD_TEMPLATE"  "AC1: template command file exists"
assert_file "$CMD_LOCAL"     "AC1: project-local command file exists"
assert_grep "elicit-questions.md"     "$CMD_TEMPLATE" "AC1: body references question template"
assert_grep "claude-didio-out/prd-drafts/" "$CMD_TEMPLATE" "AC1: body references prd-drafts output dir"
assert_grep "tasks/features"          "$CMD_TEMPLATE" "AC1: body references tasks/features brief path"
assert_grep "/plan-feature"           "$CMD_TEMPLATE" "AC1: body references /plan-feature next step"

# ── AC2: skip placeholder ─────────────────────────────────────────────────────
echo ""
echo "--- AC2: skip and placeholder documented ---"

assert_grep '**Não respondido — preencher antes de planejar**' \
  "$CMD_TEMPLATE" "AC2: literal skip placeholder documented"
assert_grep_re "skip" \
  "$CMD_TEMPLATE" "AC2: 'skip' keyword documented (case-insensitive check)"

# ── AC3: copy-to-brief + slug derivation ─────────────────────────────────────
echo ""
echo "--- AC3: copy-to-brief and slug derivation documented ---"

assert_grep "copiar"       "$CMD_TEMPLATE" "AC3: brief copy confirmation question references 'copiar'"
assert_grep "kebab"        "$CMD_TEMPLATE" "AC3: slug derivation mentions kebab-case"
assert_grep "_brief.md"    "$CMD_TEMPLATE" "AC3: body cites _brief.md destination"

# ── AC4: single source of truth — questions template ─────────────────────────
echo ""
echo "--- AC4: question template is single source of truth ---"

assert_file "$QUESTIONS" "AC4: elicit-questions.md exists"
assert_grep_count_exact '^## Q[1-8]' "$QUESTIONS" 8 "AC4: exactly 8 Q sections in questions template"
assert_grep_count_exact '^## C[1-2]' "$QUESTIONS" 2 "AC4: exactly 2 C sections in questions template"

# 10 canonical IDs
for id in problem persona out_of_scope risks constraints success dependencies deadline stakeholders platform; do
  assert_grep "**id:** $id" "$QUESTIONS" "AC4: canonical id '$id' present in questions template"
done

# Negative: Q1 prompt text must NOT live inside the command file
assert_grep_zero "Problema/dor" "$CMD_TEMPLATE" \
  "AC4 (negative): Q1 text 'Problema/dor' does NOT appear in command body"

# ── AC6: command does not duplicate template.md section headers ───────────────
echo ""
echo "--- AC6: command does not duplicate template.md section headers ---"

assert_grep_zero_re \
  '^## (Problem|Goal|Scope|User flows|Success metrics|Open questions)$' \
  "$CMD_TEMPLATE" \
  "AC6: zero template.md section headers in command"

assert_grep "templates/docs/prd/template.md" \
  "$CMD_TEMPLATE" "AC6: command references template.md path (not inlines it)"

# ── AC7: didio.md references /elicit-prd (soft/non-regression) ───────────────
echo ""
echo "--- AC7: didio.md references /elicit-prd (soft, non-regression) ---"

assert_grep "elicit-prd" "$DIDIO_TEMPLATE" "AC7: template didio.md references /elicit-prd"
assert_grep "elicit-prd" "$DIDIO_LOCAL"    "AC7: local didio.md references /elicit-prd"

# ── AC8: command does not spawn agents ────────────────────────────────────────
echo ""
echo "--- AC8: command does not spawn agents ---"

assert_grep_zero_re "didio (spawn-agent|run-wave)" \
  "$CMD_TEMPLATE" "AC8: command body contains no 'didio spawn-agent' or 'didio run-wave'"
assert_grep_zero "Task tool" \
  "$CMD_TEMPLATE" "AC8: command body does not invoke Task tool"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
