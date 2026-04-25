#!/usr/bin/env bash
# F08-effort-smoke.sh — assert spawn-agent passes --effort only for
# developer/techlead/qa, and never for architect.
# Uses DIDIO_DRY_RUN=1 so no real claude is invoked.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT"

PASS=0; FAIL=0; FAILURES=()
_pass() { echo "  [PASS] $1"; (( PASS++ )) || true; }
_fail() { echo "  [FAIL] $1"; FAILURES+=("$1"); (( FAIL++ )) || true; }

TMP="$(mktemp -d)"
COMPAT_PROJ="$(mktemp -d)"
cat > "$TMP/ping.md" <<'EOF'
# Ping
EOF

_cleanup() {
  rm -rf "$TMP" "$COMPAT_PROJ"
  rm -f "$PROJECT"/logs/agents/F99-*
}
trap '_cleanup' EXIT

echo "=== F08 effort smoke tests ==="
echo ""

# ─── 1. Sonnet roles must get --effort medium ────────────────────────────────
echo "--- 1. Sonnet roles (developer / techlead / qa) ---"

for role in developer techlead qa; do
  out="$(DIDIO_DRY_RUN=1 bash bin/didio-spawn-agent.sh "$role" F99 "$TMP/ping.md" 2>&1 || true)"
  if echo "$out" | LC_ALL=C grep -aq -- '--effort medium'; then
    _pass "$role gets --effort medium"
  else
    _fail "$role missing --effort medium (out: $out)"
  fi
  if echo "$out" | LC_ALL=C grep -aq -- '--model sonnet'; then
    _pass "$role gets --model sonnet (regression check)"
  else
    _fail "$role missing --model sonnet"
  fi
done

# ─── 2. Architect must NOT get --effort ───────────────────────────────────────
echo ""
echo "--- 2. Architect role ---"

out="$(DIDIO_DRY_RUN=1 bash bin/didio-spawn-agent.sh architect F99 "$TMP/ping.md" 2>&1 || true)"
if echo "$out" | LC_ALL=C grep -aq -- '--effort'; then
  _fail "architect got --effort (must not): $out"
else
  _pass "architect correctly has no --effort"
fi
if echo "$out" | LC_ALL=C grep -aq -- '--model opus'; then
  _pass "architect gets --model opus"
else
  _fail "architect missing --model opus"
fi

# ─── 3. DRY_RUN must not write a JSONL log ────────────────────────────────────
echo ""
echo "--- 3. DRY_RUN does not write JSONL ---"

before=$(ls "$PROJECT"/logs/agents/F99-developer-ping-*.jsonl 2>/dev/null | wc -l | tr -d ' ' || echo 0)
DIDIO_DRY_RUN=1 bash bin/didio-spawn-agent.sh developer F99 "$TMP/ping.md" >/dev/null 2>&1 || true
after=$(ls "$PROJECT"/logs/agents/F99-developer-ping-*.jsonl 2>/dev/null | wc -l | tr -d ' ' || echo 0)
if [[ "$before" == "$after" ]]; then
  _pass "DRY_RUN did not write JSONL"
else
  _fail "DRY_RUN wrote a JSONL file (before=$before after=$after)"
fi

# ─── 4. Meta file integrity: dry-run writes meta with effort + status=running ──
echo ""
echo "--- 4. meta.json has effort field and status=running ---"

DIDIO_DRY_RUN=1 bash bin/didio-spawn-agent.sh developer F99 "$TMP/ping.md" >/dev/null 2>&1 || true
meta_latest=$(ls -t "$PROJECT/logs/agents/F99-developer-ping-"*.meta.json 2>/dev/null | head -1 || true)
if [[ -n "$meta_latest" ]]; then
  py_check="$TMP/meta_check.py"
  printf 'import json, sys\nm = json.load(open(sys.argv[1]))\nassert "effort" in m, f"effort key missing; keys={list(m.keys())}"\nassert m["effort"] == "medium", f"effort={m[\"effort\"]!r}, expected medium"\nassert m["status"] == "running", f"status={m[\"status\"]!r}, expected running (dry-run must not rewrite)"\nprint("OK")\n' > "$py_check"
  result=$(python3 "$py_check" "$meta_latest" 2>&1 || echo "ERROR")
  if [[ "$result" == "OK" ]]; then
    _pass "developer meta.json has effort=medium and status=running"
  else
    _fail "developer meta.json assertion failed: $result (file: $meta_latest)"
  fi
else
  _fail "developer meta.json not found after DRY_RUN"
fi

# ─── 5. Compat: no didio_effort_for_role → no --effort, no crash ─────────────
# Simulate an old lib without the effort helper by running spawn-agent
# from a temp project whose didio-config-lib.sh lacks the function.
echo ""
echo "--- 5. Compat: missing didio_effort_for_role (old lib) ---"

mkdir -p "$COMPAT_PROJ/bin" "$COMPAT_PROJ/logs/agents"
ln -sf "$PROJECT/agents" "$COMPAT_PROJ/agents"
cp "$PROJECT/didio.config.json" "$COMPAT_PROJ/"
cp "$PROJECT/bin/didio-spawn-agent.sh" "$COMPAT_PROJ/bin/"

# Build a stripped lib: everything except the didio_effort_for_role block.
# Regex matches from the comment line through the closing } on its own line.
python3 - "$PROJECT/bin/didio-config-lib.sh" "$COMPAT_PROJ/bin/didio-config-lib.sh" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
stripped = re.sub(
    r'\n# Returns the --effort value.*?^\}$\n',
    '\n',
    src,
    flags=re.DOTALL | re.MULTILINE
)
open(sys.argv[2], 'w').write(stripped)
PY

compat_out="$(cd "$COMPAT_PROJ" && DIDIO_DRY_RUN=1 bash bin/didio-spawn-agent.sh developer F99 "$TMP/ping.md" 2>&1 || true)"
if echo "$compat_out" | LC_ALL=C grep -aq -- '--effort'; then
  _fail "compat: got --effort despite no helper (out: $compat_out)"
else
  _pass "compat: no --effort when didio_effort_for_role absent"
fi
# Verify it still ran (no crash — DRY_RUN output present)
if echo "$compat_out" | LC_ALL=C grep -aq '\[DRY_RUN\]'; then
  _pass "compat: spawn-agent completed without crash"
else
  _fail "compat: spawn-agent crashed or produced no DRY_RUN output"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf 'Failures:\n'
  for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
echo "All smoke tests passed."
