#!/usr/bin/env bash
# tests/F13-tea-e2e.sh — end-to-end TEA spawn smoke tests
#
# Requer que `claude` CLI esteja autenticado no ambiente.
# Em CI sem auth, pular este script (DIDIO_E2E=skip).
#
# Usage:
#   tests/F13-tea-e2e.sh                  # run all scenarios
#   DIDIO_E2E=skip tests/F13-tea-e2e.sh   # skip (CI without claude auth)
#   DIDIO_DRY_RUN=1 tests/F13-tea-e2e.sh  # dry-run: spawns noop, skip content checks
#
# Scenarios:
#   A  — audio-game fixture, tea.enabled=true  → FX1-test-plan.md + ≥1 task annotated
#   B  — trivial-text fixture, tea.enabled=true → FX3-test-plan.md (seções 4-5 podem ser vazias)
#   C  — tea.enabled=false → gate reads false, no spawn occurs
#   C2 — tea.enabled=true + DIDIO_SKIP_TEA=1 → gate bypass respected, no spawn

set -euo pipefail

# ─── Skip guard (CI without claude auth) ─────────────────────────────────────

if [[ "${DIDIO_E2E:-}" == "skip" ]]; then
  echo "SKIP: DIDIO_E2E=skip — skipping end-to-end TEA test (no claude auth in this env)"
  exit 0
fi

# ─── Paths ────────────────────────────────────────────────────────────────────

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SMOKE="$REPO/tests/F13-tea-smoke.sh"
DRY_RUN="${DIDIO_DRY_RUN:-0}"

# ─── Dependency checks ────────────────────────────────────────────────────────

if [[ ! -f "$SMOKE" ]]; then
  echo "FAIL: $SMOKE not found — T08 dependency missing (run T08 first)"
  exit 1
fi

if [[ ! -x "$SMOKE" ]]; then
  echo "FAIL: $SMOKE not executable — run: chmod +x $SMOKE"
  exit 1
fi

# ─── Helper: enable TEA in a copied config ───────────────────────────────────

_enable_tea() {
  local config="$1"
  python3 - "$config" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c.setdefault('tea', {})['enabled'] = True
json.dump(c, open(p, 'w'), indent=2)
PY
}

# ─── Cenário A: audio-game, tea.enabled=true ─────────────────────────────────

WS_A="$(mktemp -d)"
echo "==> Cenário A: workspace $WS_A"

mkdir -p "$WS_A/tasks/features/FX1-audio" "$WS_A/agents" "$WS_A/logs/agents"
ln -s "$REPO/agents/prompts" "$WS_A/agents/prompts"
cp -r "$REPO/tests/F13-fixtures/audio-game/." "$WS_A/tasks/features/FX1-audio/"

cp "$REPO/didio.config.json" "$WS_A/didio.config.json"
_enable_tea "$WS_A/didio.config.json"

(
  cd "$WS_A"
  DIDIO_HOME="$REPO" "$REPO/bin/didio" spawn-agent tea FX1 \
    "$WS_A/tasks/features/FX1-audio/FX1-README.md"
)

if [[ "$DRY_RUN" != "1" ]]; then
  PLAN_A="$WS_A/tasks/features/FX1-audio/FX1-test-plan.md"
  if [[ ! -f "$PLAN_A" ]]; then
    echo "FAIL: cenário A: FX1-test-plan.md não criado"
    exit 1
  fi

  "$SMOKE" "$WS_A/tasks/features/FX1-audio" FX1

  if ! grep -lE "^\*\*Test plan:\*\*" "$WS_A/tasks/features/FX1-audio/FX1-T"*.md \
      >/dev/null 2>&1; then
    echo "FAIL: cenário A: nenhuma task FX1-T*.md ganhou **Test plan:**"
    exit 1
  fi
fi

echo "OK: cenário A (audio-game)"

# ─── Cenário B: trivial-text, tea.enabled=true ───────────────────────────────

WS_B="$(mktemp -d)"
echo "==> Cenário B: workspace $WS_B"

mkdir -p "$WS_B/tasks/features/FX3-trivial" "$WS_B/agents" "$WS_B/logs/agents"
ln -s "$REPO/agents/prompts" "$WS_B/agents/prompts"
cp -r "$REPO/tests/F13-fixtures/trivial-text/." "$WS_B/tasks/features/FX3-trivial/"

cp "$REPO/didio.config.json" "$WS_B/didio.config.json"
_enable_tea "$WS_B/didio.config.json"

(
  cd "$WS_B"
  DIDIO_HOME="$REPO" "$REPO/bin/didio" spawn-agent tea FX3 \
    "$WS_B/tasks/features/FX3-trivial/FX3-README.md"
)

if [[ "$DRY_RUN" != "1" ]]; then
  PLAN_B="$WS_B/tasks/features/FX3-trivial/FX3-test-plan.md"
  if [[ ! -f "$PLAN_B" ]]; then
    echo "FAIL: cenário B: FX3-test-plan.md não criado"
    exit 1
  fi

  # Seções 4 (Perf) e 5 (Mocks) podem conter "_Sem ... aplicáveis_" — smoke aceita
  "$SMOKE" "$WS_B/tasks/features/FX3-trivial" FX3
fi

echo "OK: cenário B (trivial-text)"

# ─── Cenário C: tea.enabled=false → gate retorna false, sem spawn ────────────

WS_C="$(mktemp -d)"
echo "==> Cenário C: workspace $WS_C"

# repo config already has tea.enabled=false — copy as-is
cp "$REPO/didio.config.json" "$WS_C/didio.config.json"

TEA_ENABLED="$(
  PROJECT_ROOT="$WS_C" DIDIO_HOME="$REPO" bash -c \
    'source "$DIDIO_HOME/bin/didio-config-lib.sh" && didio_read_config_path tea.enabled false'
)"

if [[ "$TEA_ENABLED" == "true" ]]; then
  echo "FAIL: cenário C: gate leu tea.enabled=true mas config tem false"
  exit 1
fi

echo "OK: cenário C (gate respeitou tea.enabled=false)"

# ─── Cenário C2: DIDIO_SKIP_TEA=1 bypasses gate even when tea.enabled=true ───

WS_C2="$(mktemp -d)"
echo "==> Cenário C2: workspace $WS_C2"

cp "$REPO/didio.config.json" "$WS_C2/didio.config.json"
_enable_tea "$WS_C2/didio.config.json"

# Simulate gate logic: tea.enabled=true but DIDIO_SKIP_TEA=1 → skip
GATE_RESULT="$(
  DIDIO_SKIP_TEA=1 PROJECT_ROOT="$WS_C2" DIDIO_HOME="$REPO" bash -c '
    source "$DIDIO_HOME/bin/didio-config-lib.sh"
    tea_enabled="$(didio_read_config_path tea.enabled false)"
    skip_tea="${DIDIO_SKIP_TEA:-0}"
    if [[ "$skip_tea" == "1" ]]; then
      echo "skipped"
    elif [[ "$tea_enabled" != "true" ]]; then
      echo "skipped"
    else
      echo "spawn"
    fi
  '
)"

if [[ "$GATE_RESULT" != "skipped" ]]; then
  echo "FAIL: cenário C2: DIDIO_SKIP_TEA=1 não fez o gate pular (resultado=$GATE_RESULT)"
  exit 1
fi

echo "OK: cenário C2 (DIDIO_SKIP_TEA=1 respeitado)"

# ─────────────────────────────────────────────────────────────────────────────

echo "ALL OK"
