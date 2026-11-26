#!/usr/bin/env bash
# F34-T07: Documentation validation checks
set -euo pipefail

PASS=0
FAIL=0

check() {
  local desc="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# Architecture diagram checks
check "Architecture diagram exists" test -f docs/diagrams/F34-architecture.mmd
check "Architecture has 4+ subgraphs" bash -c 'COUNT=$(grep -c "subgraph" docs/diagrams/F34-architecture.mmd); [ "$COUNT" -ge 4 ]'
check "Architecture has Scripts subgraph" grep -q "subgraph.*Scripts" docs/diagrams/F34-architecture.mmd
check "Architecture has Disk subgraph" grep -q "subgraph.*Disk" docs/diagrams/F34-architecture.mmd
check "Architecture has Rust subgraph" grep -q "subgraph.*Rust" docs/diagrams/F34-architecture.mmd
check "Architecture has React subgraph" grep -q "subgraph.*React" docs/diagrams/F34-architecture.mmd
check "Architecture shows pipeline writes" grep -q "writes" docs/diagrams/F34-architecture.mmd
check "Architecture shows watcher" grep -q "watcher\|WAT" docs/diagrams/F34-architecture.mmd
check "Architecture shows commands" grep -q "commands\|CMD" docs/diagrams/F34-architecture.mmd

# Journey diagram checks
check "Journey diagram exists" test -f docs/diagrams/F34-journey.mmd
check "Journey has 3+ subgraphs" bash -c 'COUNT=$(grep -c "subgraph" docs/diagrams/F34-journey.mmd); [ "$COUNT" -ge 3 ]'
check "Journey has Operator subgraph" grep -q "subgraph.*Operator" docs/diagrams/F34-journey.mmd
check "Journey has System subgraph" grep -q "subgraph.*System" docs/diagrams/F34-journey.mmd
check "Journey has External subgraph" grep -q "subgraph.*External" docs/diagrams/F34-journey.mmd
check "Journey shows chat interaction" grep -q "Chat\|chat\|CHAT" docs/diagrams/F34-journey.mmd
check "Journey shows board interaction" grep -q "Board\|board\|BOARD" docs/diagrams/F34-journey.mmd
check "Journey shows alert interaction" grep -q "alert\|Alert\|tray" docs/diagrams/F34-journey.mmd

# ADR checks
check "ADR 0012 exists" test -f docs/adr/0012-board-reads-pipeline-state.md
check "ADR has Status section" grep -q "## Status" docs/adr/0012-board-reads-pipeline-state.md
check "ADR has Context section" grep -q "## Context" docs/adr/0012-board-reads-pipeline-state.md
check "ADR has Decision section" grep -q "## Decision" docs/adr/0012-board-reads-pipeline-state.md
check "ADR has Consequences section" grep -q "## Consequences" docs/adr/0012-board-reads-pipeline-state.md
check "ADR references pipeline state files" grep -q "pipeline-.*state.json" docs/adr/0012-board-reads-pipeline-state.md
check "ADR references get_board_state" grep -q "get_board_state" docs/adr/0012-board-reads-pipeline-state.md

# README checks
check "README has F34" grep -q "F34" README.md
check "README has Desktop Wiring" grep -qi "Desktop Wiring" README.md

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "ALL CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
