#!/usr/bin/env bash
# tests/F01-compile-claude.sh — smoke test for didio-compile-skills.sh (Claude target).
#
# Verifies (F01-T09):
#   - happy path: _example.md compiles, codex block stripped, claude block
#     unwrapped, GENERATED header present, sentinels preserved
#   - edge case: a targets:[codex]-only skill produces NO Claude output
#   - error scenario: malformed front-matter -> non-zero exit, no partial output
#   - boundary: idempotency (second run = no diff)
#   - real skills (skills/architect.md etc.) compile to content matching the
#     checked-in originals modulo the GENERATED header
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
PASS=0; FAIL=0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILE="$ROOT/bin/didio-compile-skills.sh"

TMPDIR_REAL="$(cd "${TMPDIR:-/tmp}" && pwd)"
WORK="$(mktemp -d -t F01-compile-claude-XXXXXX)"
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
# Happy path: _example.md
# ---------------------------------------------------------------------------
HAPPY="$WORK/happy"
mkdir -p "$HAPPY/skills"
cp "$ROOT/skills/_example.md" "$HAPPY/skills/"

assert_pass "compile _example.md (happy path)" \
  "$COMPILE" --skills-dir "$HAPPY/skills" --output-root "$HAPPY" --target claude

OUT="$HAPPY/.claude/commands/example-skill.md"

assert_pass "output file created" test -f "$OUT"

assert_pass "GENERATED header present" \
  grep -q "GENERATED FILE" "$OUT"

assert_pass "codex block stripped" \
  bash -c "! grep -q 'codex exec' '$OUT'"

assert_pass "claude block unwrapped (content kept, markers removed)" \
  bash -c "grep -q '/example-skill' '$OUT' && ! grep -q 'didio:claude' '$OUT'"

assert_pass "sentinels preserved verbatim" \
  bash -c "grep -q '{{USE_SECOND_BRAIN}}' '$OUT' && grep -q '{{DIDIO_CHECKPOINT}}' '$OUT'"

# Idempotency: second run produces no diff
cp "$OUT" "$WORK/example-skill.before"
assert_pass "second run (idempotent)" \
  "$COMPILE" --skills-dir "$HAPPY/skills" --output-root "$HAPPY" --target claude
assert_pass "idempotency: byte-identical output" \
  diff -q "$WORK/example-skill.before" "$OUT"

# ---------------------------------------------------------------------------
# Edge case: targets:[codex]-only skill produces no Claude output
# ---------------------------------------------------------------------------
CODEX_ONLY="$WORK/codex-only"
mkdir -p "$CODEX_ONLY/skills"
cat > "$CODEX_ONLY/skills/codex-thing.md" <<'EOF'
---
name: codex-thing
description: codex-only skill
kind: command
targets: [codex]
---
Body for codex only.
EOF

assert_pass "compile codex-only skill (no error)" \
  "$COMPILE" --skills-dir "$CODEX_ONLY/skills" --output-root "$CODEX_ONLY" --target claude

assert_pass "no Claude output produced for codex-only skill" \
  test ! -f "$CODEX_ONLY/.claude/commands/codex-thing.md"

# ---------------------------------------------------------------------------
# Error scenario: malformed front-matter -> non-zero exit, no partial output
# ---------------------------------------------------------------------------
BAD="$WORK/bad"
mkdir -p "$BAD/skills"
cat > "$BAD/skills/bad-skill.md" <<'EOF'
---
name bad-front-matter-line
description: bad
kind: command
targets: [claude]
---
Body.
EOF

assert_fail "malformed front-matter exits non-zero" \
  "$COMPILE" --skills-dir "$BAD/skills" --output-root "$BAD" --target claude

ERR_MSG="$("$COMPILE" --skills-dir "$BAD/skills" --output-root "$BAD" --target claude 2>&1 || true)"
assert_pass "error message names the offending file" \
  bash -c "echo '$ERR_MSG' | grep -q 'bad-skill.md'"

assert_pass "no partial output written for malformed skill" \
  test ! -f "$BAD/.claude/commands/bad-front-matter-line.md"

# ---------------------------------------------------------------------------
# Real skills: compiled Claude output matches checked-in originals
# (modulo GENERATED header) — F01-T06 invariant
# ---------------------------------------------------------------------------
REAL="$WORK/real"
"$COMPILE" --skills-dir "$ROOT/skills" --output-root "$REAL" --target claude >/dev/null

if python3 - "$ROOT" "$REAL" <<'PYEOF'
import re, os, sys
root, real = sys.argv[1], sys.argv[2]

def strip_header(text):
    return re.sub(r"<!-- GENERATED FILE.*?-->\n\n?", "", text, flags=re.S)

mismatches = []
checked = 0
for dirpath, _dirs, files in os.walk(real):
    for f in files:
        comp_path = os.path.join(dirpath, f)
        rel = os.path.relpath(comp_path, real)
        orig_path = os.path.join(root, rel)
        if not os.path.exists(orig_path):
            # newly-introduced skill (e.g. _example.md, checkpoint-block) — skip
            continue
        # Both sides may carry the GENERATED header: agents/prompts/*.md are
        # now compile TARGETS (skills/ is the source after F01-T06), so they
        # legitimately ship with the header in-tree. Normalize both before
        # comparing content.
        orig = strip_header(open(orig_path).read())
        comp = strip_header(open(comp_path).read())
        checked += 1
        if orig != comp:
            mismatches.append(rel)

if mismatches:
    print("MISMATCH:", mismatches)
    sys.exit(1)
if checked == 0:
    print("NO FILES CHECKED")
    sys.exit(1)
print(f"OK: {checked} files match (modulo GENERATED header)")
PYEOF
then
  echo -e "${GREEN}PASS${RESET}: real skills compile to match checked-in originals (modulo header)"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${RESET}: real skills compile to match checked-in originals (modulo header)"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# --dry-run: prints changes without writing
# ---------------------------------------------------------------------------
DRY="$WORK/dry"
mkdir -p "$DRY/skills"
cp "$ROOT/skills/_example.md" "$DRY/skills/"

assert_pass "--dry-run reports a change" \
  bash -c "'$COMPILE' --skills-dir '$DRY/skills' --output-root '$DRY' --target claude --dry-run | grep -q 'would create'"

assert_pass "--dry-run does not write the file" \
  test ! -f "$DRY/.claude/commands/example-skill.md"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "F01 compile-skills (Claude target): $PASS assertions passed, $FAIL failed"
exit $FAIL
