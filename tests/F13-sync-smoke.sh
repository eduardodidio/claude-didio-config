#!/usr/bin/env bash
# tests/F13-sync-smoke.sh — Validates AC7: sync propagates TEA with per-project differentiation.
#
# Exit 0: AC7 satisfied (both greenfield and blind-warrior pass)
# Exit 1: assertion failure unrelated to per-project config
# Exit 2: blind-warrior tea.enabled=true was overwritten — bug ticket required
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SYNC="$DIDIO_HOME/bin/didio-sync-project.sh"

T_GREEN=""
T_BW=""
trap 'rm -rf "$T_GREEN" "$T_BW"' EXIT

# ---------------------------------------------------------------------------
# Fixture: greenfield (no prior framework files)
# ---------------------------------------------------------------------------
T_GREEN="$(mktemp -d)"
(cd "$T_GREEN" && git init -q && touch CLAUDE.md && \
  git -c user.email=t@t -c user.name=t add -A && \
  git -c user.email=t@t -c user.name=t commit -q -m init)

out_green="$(DIDIO_HOME="$DIDIO_HOME" "$SYNC" --dry-run "$T_GREEN" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g')"

FAIL=0

# agents/prompts/tea.md must appear as ADDED
if echo "$out_green" | grep -F "agents/prompts/tea.md" | grep -qF "[ADDED]"; then
  echo "OK: greenfield dry-run lists agents/prompts/tea.md as ADDED"
else
  echo "FAIL: greenfield sync did not list agents/prompts/tea.md as ADDED"
  FAIL=1
fi

# memory/agent-learnings/tea.md must appear as ADDED
if echo "$out_green" | grep -F "agent-learnings/tea.md" | grep -qF "[ADDED]"; then
  echo "OK: greenfield dry-run lists memory/agent-learnings/tea.md as ADDED"
else
  echo "FAIL: greenfield sync did not list memory/agent-learnings/tea.md as ADDED"
  FAIL=1
fi

# didio.config.json must appear as ADDED (whole template copy, contains tea block)
if echo "$out_green" | grep -F "didio.config.json" | grep -qF "[ADDED]"; then
  echo "OK: greenfield dry-run lists didio.config.json as ADDED (contains tea block)"
else
  echo "FAIL: greenfield sync did not list didio.config.json as ADDED"
  FAIL=1
fi

[[ $FAIL -eq 0 ]] || { echo "FAIL: greenfield checks failed"; exit 1; }

# ---------------------------------------------------------------------------
# Fixture: blind-warrior style (tea.enabled=true pre-set by user)
# ---------------------------------------------------------------------------
T_BW="$(mktemp -d)"
(cd "$T_BW" && git init -q)
cat > "$T_BW/didio.config.json" <<'EOF'
{ "turbo": false, "economy": false, "models": {}, "tea": { "enabled": true } }
EOF
(cd "$T_BW" && touch CLAUDE.md && \
  git -c user.email=t@t -c user.name=t add -A && \
  git -c user.email=t@t -c user.name=t commit -q -m init)

# Real sync (not dry-run) — errors from sync itself are non-fatal here
DIDIO_HOME="$DIDIO_HOME" "$SYNC" "$T_BW" >/dev/null 2>&1 || true

preserved="$(python3 -c "import json; print(json.load(open('$T_BW/didio.config.json'))['tea']['enabled'])")"
if [[ "$preserved" == "True" ]]; then
  echo "OK: blind-warrior tea.enabled=true preserved after sync"
else
  echo "FAIL: blind-warrior sync overwrote tea.enabled=true → $preserved"
  echo "Per-project differentiation is NOT supported; T10 must open a bug ticket."
  exit 2
fi

echo "OK: AC7 satisfied"
