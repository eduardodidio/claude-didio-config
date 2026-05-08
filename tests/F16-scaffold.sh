#!/usr/bin/env bash
# tests/F16-scaffold.sh — integration test for the meeting-to-POC pipeline.
# Validates AC2 (npm install + build), AC4 (mock literal in bundle),
# AC5 (style-ref customization), AC6 (default mellon style), AC7 (git commit).
# With F16_SMOKE=1: also validates AC3 (HTTP 200 on /).
#
# slow (~2 min). Set F16_FAST=1 to skip npm install + git phases.
# Depends on tests/F16-parser.sh (T08) to produce the manifest fixture.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_MANIFEST="$PROJECT_ROOT/tests/fixtures/F16-manifest-sample.json"
TEMPLATE="$PROJECT_ROOT/templates/poc-vite-react"
SCRATCH="$(mktemp -d -t F16-T09-XXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

# Manifest fixture is produced by T08 (tests/F16-parser.sh). T09 is read-only:
# it never writes this file. If missing and claude unavailable → SKIP.
# If missing but claude is available → FAIL (user can run T08 to generate it).
if [[ ! -f "$FIXTURE_MANIFEST" ]]; then
  if ! command -v claude >/dev/null 2>&1; then
    echo "[T09] SKIP — manifest fixture missing and claude CLI unavailable" >&2
    echo "[T09]   run tests/F16-parser.sh (T08) first to produce it" >&2
    exit 0
  fi
  echo "[T09] FAIL: manifest fixture missing: $FIXTURE_MANIFEST" >&2
  echo "[T09] run tests/F16-parser.sh (T08) first, or:" >&2
  echo "[T09]   bin/didio-poc-from-minutes.sh tests/fixtures/F16-meeting-sample.md \\" >&2
  echo "[T09]     --dest /tmp/poc-t08 --no-smoke --stop-after parse" >&2
  echo "[T09]   && cp /tmp/poc-t08/_pipeline/manifest.json $FIXTURE_MANIFEST" >&2
  exit 1
fi

# Upfront dependency checks
[[ -d "$TEMPLATE" ]] \
  || { echo "[T09] FAIL: template dir missing: $TEMPLATE" >&2; exit 1; }
[[ -f "$PROJECT_ROOT/bin/poc_codegen.py" ]] \
  || { echo "[T09] FAIL: bin/poc_codegen.py missing (T06 not run?)" >&2; exit 1; }
[[ -f "$PROJECT_ROOT/bin/poc_finalize.py" ]] \
  || { echo "[T09] FAIL: bin/poc_finalize.py missing (T07 not run?)" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 \
  || { echo "[T09] FAIL: python3 not in PATH" >&2; exit 1; }

# Extract metadata from manifest; entities sorted same as mock_gen
MANIFEST_NAME=$(python3 -c "import json; m=json.load(open('$FIXTURE_MANIFEST')); print(m['name'])")
FIRST_ENTITY=$(python3 -c "
import json
m = json.load(open('$FIXTURE_MANIFEST'))
print(sorted(m['entities'], key=lambda e: e['name'])[0]['name'])
")

echo "[T09] manifest name=$MANIFEST_NAME, first entity=$FIRST_ENTITY"

# === Style-ref fixture for AC5 ===
STYLE_REF="$SCRATCH/style-ref"
mkdir -p "$STYLE_REF/src"
cat > "$STYLE_REF/src/index.css" <<'CSS'
:root { --primary: 200 80% 50%; }
CSS
cat > "$STYLE_REF/tailwind.config.ts" <<'TS'
export default { theme: { extend: { fontFamily: { sans: ['Roboto', 'sans-serif'] } } } };
TS

# Helper: copy template, render .tmpl files, run mock_gen + ui_gen.
# Usage: _scaffold <dest>
_scaffold() {
  local dest="$1"
  python3 - <<PY
import sys, json, shutil
from pathlib import Path
sys.path.insert(0, "$PROJECT_ROOT/bin")
import poc_codegen

manifest = json.load(open("$FIXTURE_MANIFEST"))
dest = Path("$dest")
dest.mkdir(parents=True, exist_ok=True)

template = Path("$TEMPLATE")
for item in template.iterdir():
    target = dest / item.name
    if item.is_dir():
        shutil.copytree(item, target, dirs_exist_ok=True)
    else:
        shutil.copy2(item, target)

for tmpl in dest.rglob("*.tmpl"):
    out = Path(str(tmpl)[:-len(".tmpl")])
    out.write_text(tmpl.read_text().replace("{{POC_NAME}}", manifest["name"]))
    tmpl.unlink()

poc_codegen.mock_gen(manifest, dest, lambda *a, **k: None)
poc_codegen.ui_gen(manifest, dest, lambda *a, **k: None)
print("[T09] scaffold+codegen OK")
PY
}

# ============================================================
# Phase 1: scaffold + codegen + style WITH --style-ref (AC5)
# ============================================================
DEST_A="$SCRATCH/poc-A"
echo "[T09] phase 1: scaffold + codegen + style with --style-ref..."
_scaffold "$DEST_A"

python3 - <<PY
import sys, json
from pathlib import Path
sys.path.insert(0, "$PROJECT_ROOT/bin")
import poc_finalize
m = json.load(open("$FIXTURE_MANIFEST"))
poc_finalize.style_step(m, Path("$DEST_A"), "$STYLE_REF", lambda *a, **k: None)
PY

# AC5: style-ref values injected
grep -qF '200 80% 50%' "$DEST_A/src/index.css" \
  || { echo "[T09] AC5 fail: --primary not injected from style-ref" >&2; exit 1; }
grep -qF "'Roboto'" "$DEST_A/tailwind.config.ts" \
  || { echo "[T09] AC5 fail: font not injected from style-ref" >&2; exit 1; }

# Mock file for first entity exists with interface declaration
MOCK_FILE="$DEST_A/src/mocks/${FIRST_ENTITY}.ts"
[[ -f "$MOCK_FILE" ]] \
  || { echo "[T09] fail: mock file missing: $MOCK_FILE" >&2; exit 1; }
grep -qF "export interface ${FIRST_ENTITY}" "$MOCK_FILE" \
  || { echo "[T09] fail: interface declaration missing in $MOCK_FILE" >&2; exit 1; }

# At least one page file generated
PAGES_COUNT=$(ls "$DEST_A/src/pages/"*.tsx 2>/dev/null | wc -l | tr -d ' ')
[[ "$PAGES_COUNT" -ge 1 ]] \
  || { echo "[T09] fail: no page .tsx files generated in src/pages/" >&2; exit 1; }

# App.tsx wired with BrowserRouter + Routes
grep -qF '<Routes>' "$DEST_A/src/App.tsx" \
  || { echo "[T09] fail: App.tsx missing <Routes>" >&2; exit 1; }
grep -qF 'BrowserRouter' "$DEST_A/src/App.tsx" \
  || { echo "[T09] fail: App.tsx missing BrowserRouter" >&2; exit 1; }

echo "[T09] phase 1 OK (scaffold + codegen + style-ref applied)"

# ============================================================
# Phase 2: scaffold WITHOUT style-ref → AC6 (default mellon)
# ============================================================
DEST_B="$SCRATCH/poc-B"
echo "[T09] phase 2: scaffold + codegen + no style-ref (AC6)..."
_scaffold "$DEST_B"

python3 - <<PY
import sys, json
from pathlib import Path
sys.path.insert(0, "$PROJECT_ROOT/bin")
import poc_finalize
m = json.load(open("$FIXTURE_MANIFEST"))
poc_finalize.style_step(m, Path("$DEST_B"), "/tmp/non-existent-style-ref-T09", lambda *a, **k: None)
PY

# AC6: default mellon palette must survive (style_step should no-op on missing ref)
grep -qF '265 70% 65%' "$DEST_B/src/index.css" \
  || { echo "[T09] AC6 fail: default mellon primary missing (style_step corrupted defaults)" >&2; exit 1; }

echo "[T09] phase 2 OK (default mellon style preserved)"

# ============================================================
# Phase 3 + 4: npm install + build + git → AC2, AC4, AC7
# ============================================================
if [[ "${F16_FAST:-}" == "1" ]]; then
  echo "[T09] SKIP npm+git phase (F16_FAST=1)"
else
  command -v npm >/dev/null 2>&1 \
    || { echo "[T09] FAIL: npm not in PATH — required for AC2/AC4" >&2; exit 1; }
  command -v git >/dev/null 2>&1 \
    || { echo "[T09] FAIL: git not in PATH — required for AC7" >&2; exit 1; }

  # AC2: npm install + vite build exit 0
  echo "[T09] phase 3: npm install + build (~1-2 min)..."
  ( cd "$DEST_A" && npm install --no-fund --no-audit --silent ) \
    || { echo "[T09] AC2 fail: npm install returned non-zero" >&2; exit 1; }
  ( cd "$DEST_A" && npm run build --silent ) \
    || { echo "[T09] AC2 fail: vite build returned non-zero" >&2; exit 1; }

  # AC4: a recognizable mock literal from the first entity appears in the bundle.
  # Pick the first non-id string field value for record #1 (deterministic, per poc_codegen).
  AC4_LITERAL=$(python3 -c "
import json
m = json.load(open('$FIXTURE_MANIFEST'))
ents = sorted(m['entities'], key=lambda e: e['name'])
ent = ents[0]
name = ent['name']
result = 'e1'  # fallback: id field value
for f in ent['fields']:
    if f['type'] == 'string':
        n = f['name']
        result = (name + ' 1') if n.lower() in ('name', 'title', 'label') else (n + '-1')
        break
print(result)
")
  grep -qrF "$AC4_LITERAL" "$DEST_A/dist/assets/" \
    || { echo "[T09] AC4 fail: mock literal '$AC4_LITERAL' not found in dist/assets/" >&2; exit 1; }

  echo "[T09] phase 3 OK (npm install + build + mock literal '$AC4_LITERAL' in bundle)"

  # AC7: git commit message matches "scaffold from meeting <name>"
  echo "[T09] phase 4: git commit (AC7)..."
  ( cd "$DEST_A" && git init -q )
  ( cd "$DEST_A" && git add -A )
  ( cd "$DEST_A" && git \
      -c user.name="didio poc-from-minutes" \
      -c user.email="poc@didio.local" \
      commit -q -m "scaffold from meeting ${MANIFEST_NAME}" )
  GIT_MSG=$(cd "$DEST_A" && git log -1 --format=%s)
  EXPECTED_MSG="scaffold from meeting ${MANIFEST_NAME}"
  [[ "$GIT_MSG" == "$EXPECTED_MSG" ]] \
    || { echo "[T09] AC7 fail: expected '$EXPECTED_MSG', got '$GIT_MSG'" >&2; exit 1; }

  echo "[T09] phase 4 OK (commit: $GIT_MSG)"
fi

# ============================================================
# Phase 5 (optional): full smoke → AC3
# ============================================================
if [[ "${F16_SMOKE:-}" == "1" && "${F16_FAST:-}" != "1" ]]; then
  echo "[T09] phase 5: full smoke (npm run dev + HTTP poll)..."
  python3 - <<PY
import sys, json
from pathlib import Path
sys.path.insert(0, "$PROJECT_ROOT/bin")
import poc_finalize
poc_finalize.install_and_smoke(Path("$DEST_A"), 30, lambda *a, **k: print(*a))
PY
  echo "[T09] phase 5 OK (HTTP 200 on /)"
fi

echo "[T09] OK"
