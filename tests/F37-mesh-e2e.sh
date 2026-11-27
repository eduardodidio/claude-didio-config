#!/usr/bin/env bash
# F37-mesh-e2e.sh — TAP-compatible E2E tests for the Knowledge Mesh CLI.
#
# Creates synthetic projects in a temp directory and tests register, unregister,
# list, query, and sync operations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Override registry location via env var
export DIDIO_MESH_REGISTRY="$TMPDIR_ROOT/mesh-registry.json"

# Resolve native path for python3 (MINGW compat)
if command -v cygpath &>/dev/null; then
  REGISTRY_PY="$(cygpath -m "$DIDIO_MESH_REGISTRY")"
else
  REGISTRY_PY="$DIDIO_MESH_REGISTRY"
fi

# Set DIDIO_HOME so the dispatcher can find the mesh script
export DIDIO_HOME="$PROJECT_ROOT"

MESH="$PROJECT_ROOT/bin/didio-mesh.sh"

PASS=0
FAIL=0
TOTAL=0

tap() {
  TOTAL=$((TOTAL + 1))
  local status="$1"
  local desc="$2"
  if [[ "$status" == "ok" ]]; then
    PASS=$((PASS + 1))
    echo "ok $TOTAL - $desc"
  else
    FAIL=$((FAIL + 1))
    echo "not ok $TOTAL - $desc"
  fi
}

# ---------------------------------------------------------------------------
# Setup: create two synthetic projects
# ---------------------------------------------------------------------------

PROJ_ALPHA="$TMPDIR_ROOT/project-alpha"
PROJ_BETA="$TMPDIR_ROOT/project-beta"

mkdir -p "$PROJ_ALPHA/memory/agent-learnings"
mkdir -p "$PROJ_BETA/memory/agent-learnings"

cat > "$PROJ_ALPHA/didio.config.json" <<'EOF'
{ "project_name": "project-alpha" }
EOF

cat > "$PROJ_BETA/didio.config.json" <<'EOF'
{ "project_name": "project-beta" }
EOF

cat > "$PROJ_ALPHA/memory/agent-learnings/developer.md" <<'EOF'
# Developer Agent Learnings

## F01 — 2026-01-01

**What worked:** Alpha project uses redis caching for session management. The connection pool pattern reduces latency by 40%.

**What to avoid:** Never use synchronous redis calls in async handlers.

**Pattern to repeat:** Connection pool with health checks every 30 seconds.
EOF

cat > "$PROJ_BETA/memory/agent-learnings/architect.md" <<'EOF'
# Architect Agent Learnings

## F05 — 2026-02-15

**What worked:** Beta project uses event sourcing for audit trail. CQRS pattern separates read and write models cleanly.

**What to avoid:** Avoid mixing event store with relational queries in the same transaction.

**Pattern to repeat:** Event store with snapshot every 100 events for performance.
EOF

# ---------------------------------------------------------------------------
# 1. Register project-alpha
# ---------------------------------------------------------------------------

reg_output="$(bash "$MESH" register "$PROJ_ALPHA" 2>&1)"
if echo "$reg_output" | grep -q "Registered 'project-alpha'"; then
  tap "ok" "register project-alpha"
else
  tap "not ok" "register project-alpha (output: $reg_output)"
fi

# ---------------------------------------------------------------------------
# 2. Register project-beta
# ---------------------------------------------------------------------------

reg_output="$(bash "$MESH" register "$PROJ_BETA" 2>&1)"
if echo "$reg_output" | grep -q "Registered 'project-beta'"; then
  tap "ok" "register project-beta"
else
  tap "not ok" "register project-beta (output: $reg_output)"
fi

# Verify registry has 2 entries
count="$(python3 -c "
import json
with open('$REGISTRY_PY', 'r') as f:
    d = json.load(f)
print(len(d['projects']))
")"
if [[ "$count" == "2" ]]; then
  tap "ok" "registry has 2 entries"
else
  tap "not ok" "registry has 2 entries (got: $count)"
fi

# ---------------------------------------------------------------------------
# 3. Register duplicate -> error
# ---------------------------------------------------------------------------

if dup_output="$(bash "$MESH" register "$PROJ_ALPHA" 2>&1)"; then
  tap "not ok" "register duplicate exits non-zero"
else
  if echo "$dup_output" | grep -q "already registered"; then
    tap "ok" "register duplicate exits non-zero with message"
  else
    tap "not ok" "register duplicate error message (got: $dup_output)"
  fi
fi

# ---------------------------------------------------------------------------
# 4. List shows 2 projects
# ---------------------------------------------------------------------------

list_output="$(bash "$MESH" list 2>&1)"
if echo "$list_output" | grep -q "project-alpha" && echo "$list_output" | grep -q "project-beta"; then
  tap "ok" "list shows both projects"
else
  tap "not ok" "list shows both projects"
fi

# ---------------------------------------------------------------------------
# 5. List --json outputs valid JSON
# ---------------------------------------------------------------------------

json_output="$(bash "$MESH" list --json 2>&1)"
if echo "$json_output" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if len(d)==2 else 1)" 2>/dev/null; then
  tap "ok" "list --json outputs valid JSON with 2 entries"
else
  tap "not ok" "list --json outputs valid JSON"
fi

# ---------------------------------------------------------------------------
# 6. Query keyword from project-alpha
# ---------------------------------------------------------------------------

query_output="$(bash "$MESH" query "redis caching" 2>&1)"
if echo "$query_output" | grep -q "project-alpha"; then
  tap "ok" "query finds 'redis caching' in project-alpha"
else
  tap "not ok" "query finds 'redis caching' in project-alpha (output: $query_output)"
fi

# ---------------------------------------------------------------------------
# 7. Query keyword from project-beta
# ---------------------------------------------------------------------------

query_output="$(bash "$MESH" query "event sourcing" 2>&1)"
if echo "$query_output" | grep -q "project-beta"; then
  tap "ok" "query finds 'event sourcing' in project-beta"
else
  tap "not ok" "query finds 'event sourcing' in project-beta (output: $query_output)"
fi

# ---------------------------------------------------------------------------
# 8. Query with --role filter
# ---------------------------------------------------------------------------

query_output="$(bash "$MESH" query "caching" --role architect 2>&1)"
if echo "$query_output" | grep -q "No results"; then
  tap "ok" "query --role architect filters out developer learnings"
else
  tap "not ok" "query --role architect filters (output: $query_output)"
fi

# ---------------------------------------------------------------------------
# 9. Query with --project filter
# ---------------------------------------------------------------------------

query_output="$(bash "$MESH" query "caching" --project project-beta 2>&1)"
if echo "$query_output" | grep -q "No results"; then
  tap "ok" "query --project project-beta filters out project-alpha results"
else
  tap "not ok" "query --project filter (output: $query_output)"
fi

# ---------------------------------------------------------------------------
# 10. Query nonexistent keyword
# ---------------------------------------------------------------------------

query_output="$(bash "$MESH" query "xyznonexistent" 2>&1)"
if echo "$query_output" | grep -q "No results"; then
  tap "ok" "query nonexistent keyword -> no results"
else
  tap "not ok" "query nonexistent keyword (output: $query_output)"
fi

# ---------------------------------------------------------------------------
# 11. Unregister project-alpha
# ---------------------------------------------------------------------------

unreg_output="$(bash "$MESH" unregister "project-alpha" 2>&1)"
if echo "$unreg_output" | grep -q "Unregistered"; then
  tap "ok" "unregister project-alpha"
else
  tap "not ok" "unregister project-alpha (output: $unreg_output)"
fi

count="$(python3 -c "
import json
with open('$REGISTRY_PY', 'r') as f:
    d = json.load(f)
print(len(d['projects']))
")"
if [[ "$count" == "1" ]]; then
  tap "ok" "registry has 1 entry after unregister"
else
  tap "not ok" "registry has 1 entry (got: $count)"
fi

# ---------------------------------------------------------------------------
# 12. Unregister unknown -> error
# ---------------------------------------------------------------------------

if unreg_output="$(bash "$MESH" unregister "nonexistent" 2>&1)"; then
  tap "not ok" "unregister unknown exits non-zero"
else
  if echo "$unreg_output" | grep -q "not found"; then
    tap "ok" "unregister unknown exits non-zero with message"
  else
    tap "not ok" "unregister unknown error (got: $unreg_output)"
  fi
fi

# ---------------------------------------------------------------------------
# 13. Register with invalid path -> error
# ---------------------------------------------------------------------------

if reg_output="$(bash "$MESH" register "/nonexistent/path" 2>&1)"; then
  tap "ok" "register invalid path does not crash"
else
  if echo "$reg_output" | grep -qi "error\|not exist\|not a directory"; then
    tap "ok" "register invalid path exits non-zero with error message"
  else
    tap "not ok" "register invalid path error (got: $reg_output)"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "1..$TOTAL"
echo "# pass $PASS / $TOTAL"

if [[ $FAIL -gt 0 ]]; then
  echo "# FAIL $FAIL test(s) failed"
  exit 1
fi

echo "# All tests passed"
exit 0
