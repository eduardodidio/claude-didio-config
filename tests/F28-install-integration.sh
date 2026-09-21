#!/usr/bin/env bash
# tests/F28-install-integration.sh — integration tests for didio help + CLI routing.
# Verifies new subcommands appear in help and route correctly.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
DIDIO_REPO="$(cd "$THIS_DIR/.." && pwd)"
DIDIO_BIN="$DIDIO_REPO/bin/didio"

FAIL=0
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; FAIL=1; }

# ── T1: didio help includes graphify entries ──
(
  output="$(DIDIO_HOME="$DIDIO_REPO" bash "$DIDIO_BIN" help 2>&1)"

  ok=true
  echo "$output" | grep -q 'didio graphify'          || ok=false
  echo "$output" | grep -q 'didio install-graphify'   || ok=false
  echo "$output" | grep -q 'didio rtk'                || ok=false
  echo "$output" | grep -q 'didio install-rtk'        || ok=false

  if $ok; then
    pass "T1: didio help includes graphify + rtk entries"
  else
    fail "T1: missing entries in didio help output"
  fi
) || FAIL=1

# ── T2: didio graphify --help routes correctly (via mock) ──
(
  SANDBOX="$(mktemp -d)"
  trap "rm -rf '$SANDBOX'" EXIT

  # Config with graphify enabled
  cat > "$SANDBOX/didio.config.json" <<JSON
{ "graphify": { "enabled": true }, "rtk": { "enabled": false } }
JSON

  # Mock graphify
  mkdir -p "$SANDBOX/bin"
  cat > "$SANDBOX/bin/graphify" <<'EOF'
#!/usr/bin/env bash
echo "GRAPHIFY_MOCK_CALLED: $*"
EOF
  chmod +x "$SANDBOX/bin/graphify"

  output="$(
    PROJECT_ROOT="$SANDBOX" DIDIO_HOME="$DIDIO_REPO" \
    PATH="$SANDBOX/bin:$PATH" \
    bash "$DIDIO_BIN" graphify --help 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$output" | grep -q 'GRAPHIFY_MOCK_CALLED'; then
    pass "T2: didio graphify routes to graphify binary"
  else
    fail "T2: expected graphify mock call, got rc=$rc output='$output'"
  fi
) || FAIL=1

# ── T3: didio rtk --help routes correctly (via mock) ──
(
  SANDBOX="$(mktemp -d)"
  trap "rm -rf '$SANDBOX'" EXIT

  cat > "$SANDBOX/didio.config.json" <<JSON
{ "graphify": { "enabled": false }, "rtk": { "enabled": true } }
JSON

  mkdir -p "$SANDBOX/bin"
  cat > "$SANDBOX/bin/rtk" <<'EOF'
#!/usr/bin/env bash
echo "RTK_MOCK_CALLED: $*"
EOF
  chmod +x "$SANDBOX/bin/rtk"

  output="$(
    PROJECT_ROOT="$SANDBOX" DIDIO_HOME="$DIDIO_REPO" \
    PATH="$SANDBOX/bin:$PATH" \
    bash "$DIDIO_BIN" rtk --help 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$output" | grep -q 'RTK_MOCK_CALLED'; then
    pass "T3: didio rtk routes to rtk binary"
  else
    fail "T3: expected rtk mock call, got rc=$rc output='$output'"
  fi
) || FAIL=1

# ── T4: didio install-graphify --help works ──
(
  output="$(DIDIO_HOME="$DIDIO_REPO" bash "$DIDIO_BIN" install-graphify --help 2>&1)" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$output" | grep -q 'uv tool install'; then
    pass "T4: didio install-graphify --help works"
  else
    fail "T4: expected help text, got rc=$rc output='$output'"
  fi
) || FAIL=1

# ── T5: didio install-rtk --help works ──
(
  output="$(DIDIO_HOME="$DIDIO_REPO" bash "$DIDIO_BIN" install-rtk --help 2>&1)" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$output" | grep -q 'rtk init -g'; then
    pass "T5: didio install-rtk --help works"
  else
    fail "T5: expected help text, got rc=$rc output='$output'"
  fi
) || FAIL=1

# ── Summary ──
if [[ "$FAIL" -ne 0 ]]; then
  echo "----"
  echo "F28-install-integration.sh: FAILED"
  exit 1
fi
echo "----"
echo "F28-install-integration.sh: ALL PASS"
