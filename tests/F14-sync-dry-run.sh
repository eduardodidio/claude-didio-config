#!/usr/bin/env bash
# tests/F14-sync-dry-run.sh — Validate F14 propagation via sync --dry-run.
# Verifies that 3 new commands + research config block + 3 permissions propagate
# to a downstream fixture without modifying pre-existing customisations.
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
PASS=0; FAIL=0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------
TMPDIR_REAL="$(cd "${TMPDIR:-/tmp}" && pwd)"
TARGET="$(mktemp -d -t F14-sync-fixture-XXXXXX)"
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

# Init git repo (sync script requires it)
git -C "$TARGET" init -q
git -C "$TARGET" -c user.email='test@example.com' -c user.name='F14-Test' \
  commit --allow-empty -q -m "init"

# Populate fixture with pre-existing content
mkdir -p "$TARGET/.claude/commands" "$TARGET/.claude/agents" \
  "$TARGET/docs" "$TARGET/tasks" "$TARGET/agents" "$TARGET/memory"
echo '# pre-existing command' > "$TARGET/.claude/commands/existing-cmd.md"
cat > "$TARGET/.claude/settings.json" <<'JSON'
{
  "permissions": { "allow": ["Bash(ls:*)"] }
}
JSON
cat > "$TARGET/didio.config.json" <<'JSON'
{ "max_parallel": 0 }
JSON
touch "$TARGET/.gitignore"

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

assert_cooccur() {
  local path="$1"
  local token="$2"
  local label="$3"
  local output="$4"
  if echo "$output" | grep -F "$path" | grep -qF "$token"; then
    echo -e "${GREEN}PASS${RESET}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${RESET}: $label (path '$path' not seen with token '$token')"
    FAIL=$((FAIL + 1))
  fi
}

assert_grep_e() {
  local pattern="$1"
  local label="$2"
  local output="$3"
  if echo "$output" | grep -qE "$pattern"; then
    echo -e "${GREEN}PASS${RESET}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${RESET}: $label (pattern not found: '$pattern')"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Run sync --dry-run, strip ANSI codes
# ---------------------------------------------------------------------------
rc=0
OUT="$(DIDIO_HOME="$ROOT" "$ROOT/bin/didio-sync-project.sh" \
  --dry-run "$TARGET" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g')" || rc=$?

assert_pass "dry-run exits 0" test "$rc" -eq 0

# ---------------------------------------------------------------------------
# AC6 — 3 new commands reported as ADDED
# ---------------------------------------------------------------------------
for cmd in brainstorm research product-brief; do
  assert_cooccur ".claude/commands/$cmd.md" "[ADDED]" \
    "AC6 — ADDED .claude/commands/$cmd.md" "$OUT"
done

# ---------------------------------------------------------------------------
# AC8 — settings.json MERGED with ≥3 new permissions
# (format: "N permissions + M hooks + K deny-exclusions added")
# [3-9] matches any digit in the count — covers 3..9 and multi-digit like 13,16
# ---------------------------------------------------------------------------
assert_grep_e 'MERGED.*settings\.json.*[3-9].*permissions' \
  "AC8 — settings.json MERGED with >=3 permissions" "$OUT"

# ---------------------------------------------------------------------------
# AC5 — didio.config.json MERGED with research block added
# (format: "added: ...,research,..." or "added: research")
# ---------------------------------------------------------------------------
assert_grep_e 'MERGED.*didio\.config\.json.*research' \
  "AC5 — didio.config.json MERGED added research block" "$OUT"

# ---------------------------------------------------------------------------
# Dry-run did NOT modify the fixture on disk
# ---------------------------------------------------------------------------
assert_pass "settings.json allow array unchanged (no expansion)" \
  python3 -c "
import json,sys
cfg = json.load(open('$TARGET/.claude/settings.json'))
allow = cfg['permissions']['allow']
sys.exit(0 if allow == ['Bash(ls:*)'] else 1)
"

assert_pass "didio.config.json unchanged (no research block added)" \
  python3 -c "
import json,sys
cfg = json.load(open('$TARGET/didio.config.json'))
sys.exit(0 if 'research' not in cfg else 1)
"

assert_pass "pre-existing existing-cmd.md content untouched" \
  grep -q 'pre-existing command' "$TARGET/.claude/commands/existing-cmd.md"

assert_pass "brainstorm.md NOT created on disk (dry-run)" \
  test ! -f "$TARGET/.claude/commands/brainstorm.md"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "F14 sync dry-run: $PASS assertions passed, $FAIL failed"
exit $FAIL
