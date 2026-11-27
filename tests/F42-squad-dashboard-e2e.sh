#!/usr/bin/env bash
# F42-squad-dashboard-e2e.sh — Structural tests for Squad Dashboard components
#
# Validates wiring: types, hook, view, bridge, App integration.
# No Tauri runtime needed — grep-based structural checks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DESKTOP="$PROJECT_ROOT/blackhawk-desktop/src"

PASS=0; FAIL=0; TOTAL=0
tap() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "ok" ]]; then PASS=$((PASS + 1)); echo "ok $TOTAL - $2"
  else FAIL=$((FAIL + 1)); echo "not ok $TOTAL - $2"; fi
}

# ---------------------------------------------------------------------------
# 1: Squad types defined
# ---------------------------------------------------------------------------
if grep -q 'SquadReport' "$DESKTOP/lib/types.ts"; then
  tap "ok" "types: SquadReport interface defined"
else
  tap "not ok" "types: SquadReport interface"
fi

# ---------------------------------------------------------------------------
# 2: ScannerStatus type defined
# ---------------------------------------------------------------------------
if grep -q 'ScannerStatus' "$DESKTOP/lib/types.ts"; then
  tap "ok" "types: ScannerStatus type defined"
else
  tap "not ok" "types: ScannerStatus type"
fi

# ---------------------------------------------------------------------------
# 3: SquadCorrelation type defined
# ---------------------------------------------------------------------------
if grep -q 'SquadCorrelation' "$DESKTOP/lib/types.ts"; then
  tap "ok" "types: SquadCorrelation interface defined"
else
  tap "not ok" "types: SquadCorrelation interface"
fi

# ---------------------------------------------------------------------------
# 4: Bridge has getSquadReport
# ---------------------------------------------------------------------------
if grep -q 'getSquadReport' "$DESKTOP/lib/tauriBridge.ts"; then
  tap "ok" "bridge: getSquadReport function exported"
else
  tap "not ok" "bridge: getSquadReport"
fi

# ---------------------------------------------------------------------------
# 5: Bridge has triggerSquadScan
# ---------------------------------------------------------------------------
if grep -q 'triggerSquadScan' "$DESKTOP/lib/tauriBridge.ts"; then
  tap "ok" "bridge: triggerSquadScan function exported"
else
  tap "not ok" "bridge: triggerSquadScan"
fi

# ---------------------------------------------------------------------------
# 6: Hook file exists and exports useSquadHealth
# ---------------------------------------------------------------------------
if [[ -f "$DESKTOP/hooks/useSquadHealth.ts" ]] && grep -q 'useSquadHealth' "$DESKTOP/hooks/useSquadHealth.ts"; then
  tap "ok" "hook: useSquadHealth exists and exported"
else
  tap "not ok" "hook: useSquadHealth"
fi

# ---------------------------------------------------------------------------
# 7: Hook uses getSquadReport from bridge
# ---------------------------------------------------------------------------
if grep -q 'getSquadReport' "$DESKTOP/hooks/useSquadHealth.ts"; then
  tap "ok" "hook: imports getSquadReport from bridge"
else
  tap "not ok" "hook: getSquadReport import"
fi

# ---------------------------------------------------------------------------
# 8: View file exists and exports SquadHealth
# ---------------------------------------------------------------------------
if [[ -f "$DESKTOP/views/SquadHealth.tsx" ]] && grep -q 'export function SquadHealth' "$DESKTOP/views/SquadHealth.tsx"; then
  tap "ok" "view: SquadHealth component exists and exported"
else
  tap "not ok" "view: SquadHealth component"
fi

# ---------------------------------------------------------------------------
# 9: View uses useSquadHealth hook
# ---------------------------------------------------------------------------
if grep -q 'useSquadHealth' "$DESKTOP/views/SquadHealth.tsx"; then
  tap "ok" "view: uses useSquadHealth hook"
else
  tap "not ok" "view: useSquadHealth usage"
fi

# ---------------------------------------------------------------------------
# 10: View renders all three scanner cards
# ---------------------------------------------------------------------------
if grep -q 'bravo' "$DESKTOP/views/SquadHealth.tsx" && grep -q 'charlie' "$DESKTOP/views/SquadHealth.tsx" && grep -q 'delta' "$DESKTOP/views/SquadHealth.tsx"; then
  tap "ok" "view: renders bravo + charlie + delta scanner cards"
else
  tap "not ok" "view: scanner cards"
fi

# ---------------------------------------------------------------------------
# 11: View renders correlations
# ---------------------------------------------------------------------------
if grep -q 'CorrelationItem' "$DESKTOP/views/SquadHealth.tsx"; then
  tap "ok" "view: renders correlation items"
else
  tap "not ok" "view: correlation items"
fi

# ---------------------------------------------------------------------------
# 12: App.tsx has Squad tab
# ---------------------------------------------------------------------------
if grep -q 'value="squad"' "$DESKTOP/App.tsx"; then
  tap "ok" "App: Squad tab registered"
else
  tap "not ok" "App: Squad tab"
fi

# ---------------------------------------------------------------------------
# 13: App.tsx imports SquadHealth view
# ---------------------------------------------------------------------------
if grep -q 'SquadHealth' "$DESKTOP/App.tsx"; then
  tap "ok" "App: imports SquadHealth component"
else
  tap "not ok" "App: SquadHealth import"
fi

# ---------------------------------------------------------------------------
# 14: App.tsx uses 5-column grid
# ---------------------------------------------------------------------------
if grep -q 'grid-cols-5' "$DESKTOP/App.tsx"; then
  tap "ok" "App: tab grid is 5 columns"
else
  tap "not ok" "App: grid-cols-5"
fi

# ---------------------------------------------------------------------------
echo ""
echo "1..$TOTAL"
echo "# pass $PASS / $TOTAL"
if [[ $FAIL -gt 0 ]]; then echo "# FAIL $FAIL test(s) failed"; exit 1; fi
echo "# All tests passed"; exit 0
