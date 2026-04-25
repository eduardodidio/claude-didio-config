#!/usr/bin/env bash
# F09-scan-exclusion.sh — assert that archive/ and claude-didio-out/ are
# excluded from agent discovery according to the mechanism chosen in
# docs/F09-scan-exclusion-check.md.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT"

PASS=0; FAIL=0; FAILURES=()
_pass() { echo "  [PASS] $1"; (( PASS++ )) || true; }
_fail() { echo "  [FAIL] $1"; FAILURES+=("$1"); (( FAIL++ )) || true; }
_info() { echo "  [INFO] $1"; }

echo "=== F09 scan-exclusion tests ==="
echo ""

# 1. Read decision from docs/F09-scan-exclusion-check.md
DECISION_DOC="$PROJECT/docs/F09-scan-exclusion-check.md"
if [[ ! -f "$DECISION_DOC" ]]; then
  echo "ERROR: missing $DECISION_DOC"
  exit 1
fi
DECISION="$(awk '/^## Decision/{found=1; next} found && NF{print; exit}' "$DECISION_DOC")"
_info "Decision: '$DECISION'"

# 2. Create temp fixtures inside the actual directories (validates that
#    git ignores those paths — a tmpdir fixture would prove nothing).
TMP_ARCH="$PROJECT/archive/_smoke-fixture.txt"
TMP_OUT="$PROJECT/claude-didio-out/_smoke-fixture.txt"
echo "smoke fixture archive"          > "$TMP_ARCH"
echo "smoke fixture claude-didio-out" > "$TMP_OUT"
trap 'rm -f "$TMP_ARCH" "$TMP_OUT"' EXIT

echo ""
echo "--- Decision branch ---"

case "$DECISION" in
  settings.json:*)
    FIELD="${DECISION#settings.json:}"
    FIELD="${FIELD// /}"
    _info "Branch A — asserting settings.json field: $FIELD"
    if python3 -c "
import json, sys
s = json.load(open('.claude/settings.json'))
have_arch = any('archive' in v for v in s.get('$FIELD', []))
have_out  = any('claude-didio-out' in v for v in s.get('$FIELD', []))
sys.exit(0 if '$FIELD' in s and have_arch and have_out else 1)
" 2>/dev/null; then
      _pass "settings.json has $FIELD with archive/ and claude-didio-out/"
    else
      _fail "settings.json missing $FIELD or required entries"
    fi
    ;;

  gitignore-only*)
    _info "Branch B — gitignore-only. settings.json NOT modified."
    if grep -qE '^archive/$' "$PROJECT/.gitignore"; then
      _pass ".gitignore ignores archive/"
    else
      _fail ".gitignore missing archive/ entry"
    fi
    if grep -qE '^claude-didio-out/$' "$PROJECT/.gitignore"; then
      _pass ".gitignore ignores claude-didio-out/"
    else
      _fail ".gitignore missing claude-didio-out/ entry"
    fi
    _info "LIMITATION: auto-attach context may still ingest archive/ and claude-didio-out/ — gitignore covers Glob/Grep (ripgrep) only. See docs/F09-scan-exclusion-check.md"
    # Verify settings.json was NOT modified (Branch B contract)
    if python3 -c "
import json, sys
s = json.load(open('.claude/settings.json'))
sys.exit(0 if 'permissions' not in s or 'deny' not in s.get('permissions', {}) else 1)
" 2>/dev/null; then
      _pass "settings.json NOT modified (Branch B — no permissions.deny added)"
    else
      _fail "settings.json unexpectedly has permissions.deny (Branch B should be no-op)"
    fi
    ;;

  none*)
    _info "Branch B (degraded) — no exclusion mechanism available."
    if grep -qE '^## Decision' "$DECISION_DOC"; then
      _pass "decision recorded in $DECISION_DOC"
    else
      _fail "decision section missing from $DECISION_DOC"
    fi
    ;;

  *)
    _fail "Unknown decision in $DECISION_DOC: '$DECISION'"
    ;;
esac

echo ""
echo "--- git check-ignore (common to all branches) ---"

# Verify git honors .gitignore for both directories
if git check-ignore -q "$TMP_ARCH" 2>/dev/null; then
  _pass "git check-ignore: archive/_smoke-fixture.txt is ignored"
else
  _fail "git check-ignore: archive/_smoke-fixture.txt NOT ignored"
fi

if git check-ignore -q "$TMP_OUT" 2>/dev/null; then
  _pass "git check-ignore: claude-didio-out/_smoke-fixture.txt is ignored"
else
  _fail "git check-ignore: claude-didio-out/_smoke-fixture.txt NOT ignored"
fi

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"

if (( FAIL > 0 )); then
  echo "FAILURES:"
  for f in "${FAILURES[@]}"; do echo "  - $f"; done
  exit 1
fi
exit 0
