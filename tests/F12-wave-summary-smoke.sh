#!/usr/bin/env bash
# F12-wave-summary-smoke.sh — verifica que o post-Wave summary spawn
# está em vigor: prompt do TechLead documenta wave-summary mode,
# run-wave.sh invoca techlead com EXTRA correto, e kill-switch via
# sharding.wave_summary funciona.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }

echo "== F12 wave-summary smoke =="

# --- Cenário 1: prompt do TechLead documenta Wave Summary Mode ---
echo "[1] techlead prompt — Wave Summary Mode documented"
TL=templates/agents/prompts/techlead.md
grep -q '## Wave Summary Mode' "$TL"       && ok "section present"          || fail "section missing"
grep -qF 'MODE=wave-summary' "$TL"         && ok "trigger documented"       || fail "trigger missing"
grep -qF '<FXX>-wave-<N>-summary.md' "$TL" && ok "output path documented"   || fail "output path missing"
grep -qF 'Files touched' "$TL"             && ok "Files touched section"     || fail "Files touched missing"
grep -qF 'Decisions' "$TL"                 && ok "Decisions section"         || fail "Decisions missing"
grep -qF 'Notes for next Wave' "$TL"       && ok "Notes section"             || fail "Notes missing"

# --- Cenário 2: run-wave.sh tem o bloco post-Wave summary ---
echo "[2] run-wave.sh — post-Wave summary block"
RW=bin/didio-run-wave.sh
grep -q 'Post-Wave summary' "$RW"       && ok "block label present"              || fail "block label missing"
grep -q 'MODE=wave-summary' "$RW"       && ok "EXTRA arg includes mode"          || fail "mode arg missing"
grep -q 'sharding.wave_summary' "$RW"   && ok "config key consulted"             || fail "config key missing"
grep -q 'non-blocking' "$RW"            && ok "non-blocking semantics documented" || fail "non-blocking missing"
bash -n "$RW"                           && ok "syntax valid"                      || fail "syntax broken"

# --- Cenário 3: DRY_RUN invocation prints expected EXTRA ---
echo "[3] DRY_RUN run-wave — spawn-agent invoked with right EXTRA"
# Build a minimal fixture: a feature dir with a README that has Wave 0.
FIX_DIR="tasks/features/F99-fixture"
rm -rf "$FIX_DIR"
mkdir -p "$FIX_DIR"
cat > "$FIX_DIR/F99-README.md" <<'READMEEOF'
# F99 — fixture
- **Wave 0**: F99-T01
READMEEOF
cat > "$FIX_DIR/F99-T01.md" <<'TASKEOF'
# F99-T01 — fixture task
TASKEOF
trap 'rm -rf "$FIX_DIR" /tmp/f12-wave.out /tmp/f12-wave-off.out 2>/dev/null || true' EXIT

# Run with DRY_RUN; spawn-agent will print [DRY_RUN] and exit 0 for each
# spawn (the dev task and the post-Wave summary one).
DIDIO_DRY_RUN=1 DIDIO_HOME="$PROJECT_ROOT" \
  bash "$RW" F99 0 developer > /tmp/f12-wave.out 2>&1 || true
grep -q 'MODE=wave-summary' /tmp/f12-wave.out \
  && ok "post-Wave techlead spawn observed in DRY_RUN" \
  || fail "post-Wave spawn not observed"
grep -q 'FEATURE=F99' /tmp/f12-wave.out \
  && ok "FEATURE arg in EXTRA" \
  || fail "FEATURE arg missing"
grep -q 'WAVE=0' /tmp/f12-wave.out \
  && ok "WAVE arg in EXTRA" \
  || fail "WAVE arg missing"

# --- Cenário 4: kill-switch via sharding.wave_summary=false ---
echo "[4] kill-switch (sharding.wave_summary=false skips spawn)"
cp didio.config.json didio.config.json.bak
trap 'rm -rf "$FIX_DIR" /tmp/f12-wave.out /tmp/f12-wave-off.out 2>/dev/null || true; mv -f didio.config.json.bak didio.config.json 2>/dev/null || true' EXIT
python3 -c "
import json
c = json.load(open('didio.config.json'))
c.setdefault('sharding', {})['wave_summary'] = False
json.dump(c, open('didio.config.json','w'), indent=2)
"
DIDIO_DRY_RUN=1 DIDIO_HOME="$PROJECT_ROOT" \
  bash "$RW" F99 0 developer > /tmp/f12-wave-off.out 2>&1 || true
if ! grep -q 'MODE=wave-summary' /tmp/f12-wave-off.out; then
  ok "kill-switch suppressed post-Wave spawn"
else
  fail "kill-switch did not suppress spawn"
fi

# Cleanup explicit (trap also covers)
mv -f didio.config.json.bak didio.config.json
rm -rf "$FIX_DIR" /tmp/f12-wave.out /tmp/f12-wave-off.out 2>/dev/null || true

echo "== Result: $PASS passed, $FAIL failed =="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
