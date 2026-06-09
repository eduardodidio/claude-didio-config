#!/usr/bin/env bash
# F08-sync-effort-merge.sh — assert didio-sync-project.sh propagates
# models[*].effort into a downstream that already has a "models" block.
#
# Closes the F08 gap: the config merge (step 12b) only adds MISSING top-level
# blocks and does not recurse, so a downstream that already has "models" never
# received the effort sub-key. The targeted merge must:
#   1. add effort per role where the user has none, and
#   2. NEVER overwrite an effort the user already customized.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT"

PASS=0; FAIL=0; FAILURES=()
_pass() { echo "  [PASS] $1"; (( PASS++ )) || true; }
_fail() { echo "  [FAIL] $1"; FAILURES+=("$1"); (( FAIL++ )) || true; }

TARGET="$(mktemp -d)"
_cleanup() { rm -rf "$TARGET"; }
trap '_cleanup' EXIT

# sync refuses to run outside a git repo — make the downstream one.
git -C "$TARGET" init -q

echo "=== F08 sync effort-merge tests ==="
echo ""

# Downstream config: has a "models" block (so 12b's block-loop skips it),
# developer carries a CUSTOM effort=high that must survive the merge,
# qa carries no effort and must receive the template default.
cat > "$TARGET/didio.config.json" <<'JSON'
{
  "models": {
    "developer": { "model": "sonnet", "fallback": "haiku", "effort": "high" },
    "qa":        { "model": "sonnet", "fallback": "haiku" }
  }
}
JSON

# Real run (not dry) so the merge is written to disk.
bash bin/didio-sync-project.sh "$TARGET" >/dev/null 2>&1 || true

echo "--- 1. effort propagation + customization safety ---"
result=$(python3 - "$TARGET/didio.config.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
m = c.get("models", {})
dev = m.get("developer", {}).get("effort")
qa  = m.get("qa", {}).get("effort")
print(f"dev={dev} qa={qa}")
PY
)
echo "    $result"
if [[ "$result" == "dev=high qa=medium" ]]; then
  _pass "qa.effort received template default; developer.effort=high preserved"
else
  _fail "unexpected effort state: $result (expected dev=high qa=medium)"
fi

echo ""
echo "--- 2. idempotency (second run adds nothing) ---"
before=$(md5 -q "$TARGET/didio.config.json" 2>/dev/null || md5sum "$TARGET/didio.config.json" | cut -d' ' -f1)
bash bin/didio-sync-project.sh "$TARGET" >/dev/null 2>&1 || true
after=$(md5 -q "$TARGET/didio.config.json" 2>/dev/null || md5sum "$TARGET/didio.config.json" | cut -d' ' -f1)
if [[ "$before" == "$after" ]]; then
  _pass "second sync left didio.config.json byte-identical"
else
  _fail "second sync mutated didio.config.json (not idempotent)"
fi

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf 'Failures:\n'
  for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
echo "All sync effort-merge tests passed."
