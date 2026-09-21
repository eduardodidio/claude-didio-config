#!/usr/bin/env bash
# tests/F28-sync.sh — tests that sync-project merges graphify/rtk config blocks
# and appends graphify-out/ to .gitignore in downstream projects.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
DIDIO_REPO="$(cd "$THIS_DIR/.." && pwd)"
SYNC="$DIDIO_REPO/bin/didio-sync-project.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAIL=0
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; FAIL=1; }

# Create a DIDIO_HOME overlay with a no-op compile script to avoid
# the real compile-skills (which may fail due to unrelated issues).
DIDIO_OVERLAY="$SANDBOX/didio-overlay"
mkdir -p "$DIDIO_OVERLAY/bin"
# Copy the real bin/ and templates/ from the repo
cp -r "$DIDIO_REPO/bin/"* "$DIDIO_OVERLAY/bin/"
cp -r "$DIDIO_REPO/templates" "$DIDIO_OVERLAY/templates"
# Replace compile-skills with a no-op
cat > "$DIDIO_OVERLAY/bin/didio-compile-skills.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$DIDIO_OVERLAY/bin/didio-compile-skills.sh"

# ── T1: sync-project --dry-run reports graphify/rtk merge ──
(
  target="$SANDBOX/t1-project"
  mkdir -p "$target"
  git -C "$target" init -q

  # Create a minimal didio.config.json WITHOUT graphify/rtk blocks
  cat > "$target/didio.config.json" <<JSON
{
  "turbo": false,
  "economy": false,
  "models": {
    "architect": { "model": "opus", "fallback": "sonnet" }
  }
}
JSON

  # Create minimal .gitignore
  echo "node_modules/" > "$target/.gitignore"

  output="$(DIDIO_HOME="$DIDIO_OVERLAY" bash "$SYNC" --dry-run "$target" 2>&1)" && rc=0 || rc=$?

  ok=true
  echo "$output" | grep -qi 'graphify' || ok=false

  if $ok; then
    pass "T1: sync --dry-run reports graphify block merge"
  else
    fail "T1: expected graphify mention in sync output, got output='$(echo "$output" | tail -20)'"
  fi
) || FAIL=1

# ── T2: sync-project actually merges graphify/rtk blocks ──
(
  target="$SANDBOX/t2-project"
  mkdir -p "$target"
  git -C "$target" init -q

  cat > "$target/didio.config.json" <<JSON
{
  "turbo": false,
  "economy": false,
  "models": {
    "architect": { "model": "opus", "fallback": "sonnet" }
  }
}
JSON

  echo "node_modules/" > "$target/.gitignore"

  DIDIO_HOME="$DIDIO_OVERLAY" bash "$SYNC" "$target" >/dev/null 2>&1 || true

  # Check config was merged (use cygpath for python3 on MSYS/Windows)
  ok=true
  cfg="$target/didio.config.json"
  py_cfg="$cfg"
  if command -v cygpath >/dev/null 2>&1; then
    py_cfg="$(cygpath -w "$cfg")"
  fi

  if [[ ! -f "$cfg" ]]; then
    fail "T2: didio.config.json does not exist after sync"
    exit 1
  fi

  python3 -c "
import json
with open(r'$py_cfg') as f:
    c = json.load(f)
assert 'graphify' in c, 'graphify block missing'
assert 'rtk' in c, 'rtk block missing'
assert c['graphify']['enabled'] == False, 'graphify should be disabled by default'
assert c['rtk']['enabled'] == False, 'rtk should be disabled by default'
print('config OK')
" 2>&1 || ok=false

  # Check .gitignore has graphify-out/
  if ! grep -qF 'graphify-out/' "$target/.gitignore"; then
    ok=false
  fi

  if $ok; then
    pass "T2: sync merges graphify/rtk blocks + appends graphify-out/ to .gitignore"
  else
    fail "T2: config or gitignore merge failed"
  fi
) || FAIL=1

# ── T3: sync-project is idempotent — second run doesn't duplicate ──
(
  target="$SANDBOX/t3-project"
  mkdir -p "$target"
  git -C "$target" init -q

  cat > "$target/didio.config.json" <<JSON
{
  "turbo": false,
  "graphify": { "enabled": true, "output_dir": "my-custom-dir" },
  "rtk": { "enabled": true }
}
JSON

  echo "graphify-out/" > "$target/.gitignore"

  DIDIO_HOME="$DIDIO_OVERLAY" bash "$SYNC" "$target" >/dev/null 2>&1 || true

  # Verify custom output_dir was preserved (not overwritten)
  cfg="$target/didio.config.json"
  py_cfg="$cfg"
  if command -v cygpath >/dev/null 2>&1; then
    py_cfg="$(cygpath -w "$cfg")"
  fi

  dir="$(python3 -c "
import json
with open(r'$py_cfg') as f:
    c = json.load(f)
print(c.get('graphify', {}).get('output_dir', ''))
")"

  # Count graphify-out/ lines in .gitignore
  count="$(grep -c 'graphify-out/' "$target/.gitignore" || true)"

  if [[ "$dir" == "my-custom-dir" && "$count" -eq 1 ]]; then
    pass "T3: idempotent — custom config preserved, no duplicate .gitignore"
  else
    fail "T3: dir='$dir' count='$count' (expected my-custom-dir, 1)"
  fi
) || FAIL=1

# ── Summary ──
if [[ "$FAIL" -ne 0 ]]; then
  echo "----"
  echo "F28-sync.sh: FAILED"
  exit 1
fi
echo "----"
echo "F28-sync.sh: ALL PASS"
