#!/usr/bin/env bash
# F09-archive-script.sh — smoke tests for didio-archive-feature.sh
# Tests all modes: default, --list, --dry-run, --force, --help
# Uses git-dated fixtures so last_commit_age_days is deterministic.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0; FAILURES=()
_pass() { echo "  [PASS] $1"; (( PASS++ )) || true; }
_fail() { echo "  [FAIL] $1"; FAILURES+=("$1"); (( FAIL++ )) || true; }

TMP="$(mktemp -d)"
FAKE_HOME="$TMP/fakehome"

_cleanup() { rm -rf "$TMP"; }
trap '_cleanup' EXIT

# ---------------------------------------------------------------------------
# Build fake project structure
# ---------------------------------------------------------------------------
mkdir -p "$FAKE_HOME"/{tasks/features,archive/features,memory/retrospectives,bin}
cp "$PROJECT/bin/didio-archive-feature.sh" "$FAKE_HOME/bin/"

( cd "$FAKE_HOME" && git init -q && git config user.email "test@test.com" && git config user.name "Test" )

# Helper: commit in FAKE_HOME with an explicit date (ISO 8601 format)
_commit() {
  local msg="$1" date="${2:-}"
  if [[ -n "$date" ]]; then
    ( cd "$FAKE_HOME" && \
      GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
      git commit -q -m "$msg" 2>/dev/null || true )
  else
    ( cd "$FAKE_HOME" && git commit -q -m "$msg" 2>/dev/null || true )
  fi
}

# ── Fixture F90: eligible (qa PASSED + commit 115 days before 2026-04-25 = 2026-01-01) ──
mk_F90() {
  local d="$FAKE_HOME/tasks/features/F90-eligible"
  mkdir -p "$d"
  echo "# F90 brief"       > "$d/_brief.md"
  echo "verdict: PASSED"   > "$d/qa-report-20260101-000000.md"
  echo "## Retro content"  > "$d/retrospective.md"
  ( cd "$FAKE_HOME" && git add . )
  _commit "feat: F90 eligible" "2026-01-01T12:00:00"
}

# ── Fixture F91: no qa-report ──────────────────────────────────────────────
mk_F91() {
  local d="$FAKE_HOME/tasks/features/F91-no-qa"
  mkdir -p "$d"
  echo "# F91 brief" > "$d/_brief.md"
  ( cd "$FAKE_HOME" && git add . )
  _commit "feat: F91 no-qa" "2026-01-01T12:00:00"
}

# ── Fixture F92: qa FAILED ─────────────────────────────────────────────────
mk_F92() {
  local d="$FAKE_HOME/tasks/features/F92-qa-failed"
  mkdir -p "$d"
  echo "# F92 brief"    > "$d/_brief.md"
  echo "verdict: FAILED" > "$d/qa-report-20260101-000000.md"
  ( cd "$FAKE_HOME" && git add . )
  _commit "feat: F92 qa-failed" "2026-01-01T12:00:00"
}

# ── Fixture F93: qa PASSED but commit recent (current time → 0 days old) ──
mk_F93() {
  local d="$FAKE_HOME/tasks/features/F93-recent"
  mkdir -p "$d"
  echo "# F93 brief"    > "$d/_brief.md"
  echo "verdict: PASSED" > "$d/qa-report-20260425-000000.md"
  ( cd "$FAKE_HOME" && git add . )
  _commit "feat: F93 recent"
}

# ── Fixture F94: eligible but NO retrospective.md ─────────────────────────
mk_F94() {
  local d="$FAKE_HOME/tasks/features/F94-no-retro"
  mkdir -p "$d"
  echo "# F94 brief"    > "$d/_brief.md"
  echo "verdict: PASSED" > "$d/qa-report-20260101-000000.md"
  # intentionally no retrospective.md
  ( cd "$FAKE_HOME" && git add . )
  _commit "feat: F94 no-retro" "2026-01-01T12:00:00"
}

# ── Fixture F95: bold markdown verdict (**Verdict:** Passed) ──────────────
mk_F95() {
  local d="$FAKE_HOME/tasks/features/F95-bold-verdict"
  mkdir -p "$d"
  echo "# F95 brief"        > "$d/_brief.md"
  echo "**Verdict:** Passed" > "$d/qa-report-20260101-000000.md"
  echo "## Retro F95"       > "$d/retrospective.md"
  ( cd "$FAKE_HOME" && git add . )
  _commit "feat: F95 bold-verdict" "2026-01-01T12:00:00"
}

# ── Fixture F96: ambiguous (two dirs with same prefix) ───────────────────
mk_F96() {
  mkdir -p "$FAKE_HOME/tasks/features/F96-ambig-a"
  mkdir -p "$FAKE_HOME/tasks/features/F96-ambig-b"
  echo "# F96a" > "$FAKE_HOME/tasks/features/F96-ambig-a/_brief.md"
  echo "# F96b" > "$FAKE_HOME/tasks/features/F96-ambig-b/_brief.md"
  ( cd "$FAKE_HOME" && git add . )
  _commit "feat: F96 ambiguous" "2026-01-01T12:00:00"
}

mk_F90
mk_F91
mk_F92
mk_F93
mk_F94
mk_F95
mk_F96

ARC_CMD="DIDIO_HOME=$FAKE_HOME bash $FAKE_HOME/bin/didio-archive-feature.sh"

echo "=== F09 archive smoke tests ==="
echo ""

# ─── 1. F90 eligible — default archive ───────────────────────────────────────
echo "--- 1. F90 eligible: default archive ---"
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" F90 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  _pass "1. exit 0 for eligible F90"
else
  _fail "1. expected exit 0, got $rc (out: $out)"
fi
if [[ -d "$FAKE_HOME/archive/features/F90-eligible" ]]; then
  _pass "1. F90 moved to archive/features/"
else
  _fail "1. F90 not found in archive/features/"
fi
if [[ -f "$FAKE_HOME/memory/retrospectives/F90.md" ]]; then
  _pass "1. retrospective copied to memory/retrospectives/F90.md"
else
  _fail "1. memory/retrospectives/F90.md not created"
fi
if [[ ! -d "$FAKE_HOME/tasks/features/F90-eligible" ]]; then
  _pass "1. F90 removed from tasks/features/"
else
  _fail "1. F90 still in tasks/features/ after archive"
fi

# ─── 2. Idempotence: F90 already archived ────────────────────────────────────
echo ""
echo "--- 2. Idempotence: F90 already archived ---"
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" F90 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  _pass "2. exit 0 (idempotent)"
else
  _fail "2. expected exit 0, got $rc"
fi
if echo "$out" | grep -q "NO_CHANGE"; then
  _pass "2. prints NO_CHANGE"
else
  _fail "2. missing NO_CHANGE message (out: $out)"
fi

# ─── 3. F91 no qa-report — ineligible ────────────────────────────────────────
echo ""
echo "--- 3. F91 no qa-report ---"
rc=0
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" F91 2>&1)" || rc=$?
if [[ "$rc" -eq 1 ]]; then
  _pass "3. exit 1 for F91 (no qa-report)"
else
  _fail "3. expected exit 1, got $rc"
fi
if echo "$out" | grep -q "INELIGIBLE"; then
  _pass "3. prints INELIGIBLE"
else
  _fail "3. missing INELIGIBLE message (out: $out)"
fi
if [[ ! -d "$FAKE_HOME/archive/features/F91-no-qa" ]]; then
  _pass "3. F91 not moved to archive"
else
  _fail "3. F91 incorrectly moved to archive"
fi

# ─── 4. F92 qa FAILED — ineligible ───────────────────────────────────────────
echo ""
echo "--- 4. F92 qa FAILED ---"
rc=0
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" F92 2>&1)" || rc=$?
if [[ "$rc" -eq 1 ]]; then
  _pass "4. exit 1 for F92 (qa FAILED)"
else
  _fail "4. expected exit 1, got $rc"
fi
if echo "$out" | grep -q "INELIGIBLE"; then
  _pass "4. prints INELIGIBLE"
else
  _fail "4. missing INELIGIBLE message (out: $out)"
fi

# ─── 5. F93 recent commit — ineligible by age ────────────────────────────────
echo ""
echo "--- 5. F93 recent commit (age ineligible) ---"
rc=0
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" F93 2>&1)" || rc=$?
if [[ "$rc" -eq 1 ]]; then
  _pass "5. exit 1 for F93 (recent commit)"
else
  _fail "5. expected exit 1, got $rc"
fi
if echo "$out" | grep -q "INELIGIBLE"; then
  _pass "5. prints INELIGIBLE (age)"
else
  _fail "5. missing INELIGIBLE message (out: $out)"
fi

# ─── 6. --list: F94 and F95 eligible; F91/F92/F93/F90 absent ─────────────────
echo ""
echo "--- 6. --list (F94/F95 eligible, others absent) ---"
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" --list 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  _pass "6. --list exits 0"
else
  _fail "6. --list expected exit 0, got $rc"
fi
if echo "$out" | grep -q "F94"; then
  _pass "6. --list includes F94 (eligible)"
else
  _fail "6. --list missing F94 (out: $out)"
fi
if echo "$out" | grep -q "F95"; then
  _pass "6. --list includes F95 (eligible)"
else
  _fail "6. --list missing F95 (out: $out)"
fi
if echo "$out" | grep -qE "F91|F92|F93"; then
  _fail "6. --list contains ineligible feature(s) (out: $out)"
else
  _pass "6. --list excludes F91/F92/F93"
fi
if echo "$out" | grep -q "F90"; then
  _fail "6. --list contains F90 (already archived)"
else
  _pass "6. --list excludes F90 (already archived)"
fi

# ─── 7. --dry-run F94 — prints actions, fs intact ────────────────────────────
echo ""
echo "--- 7. --dry-run F94 ---"
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" --dry-run F94 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  _pass "7. --dry-run exits 0"
else
  _fail "7. --dry-run expected exit 0, got $rc (out: $out)"
fi
if echo "$out" | LC_ALL=C grep -qi "dry.run"; then
  _pass "7. --dry-run output mentions DRY_RUN"
else
  _fail "7. --dry-run missing DRY_RUN in output (out: $out)"
fi
if [[ -d "$FAKE_HOME/tasks/features/F94-no-retro" ]]; then
  _pass "7. F94 still in tasks/features (not moved)"
else
  _fail "7. F94 was moved despite --dry-run"
fi
if [[ ! -d "$FAKE_HOME/archive/features/F94-no-retro" ]]; then
  _pass "7. F94 not in archive (dry-run)"
else
  _fail "7. F94 appeared in archive despite --dry-run"
fi
if [[ ! -f "$FAKE_HOME/memory/retrospectives/F94.md" ]]; then
  _pass "7. F94.md not created in memory (dry-run)"
else
  _fail "7. F94.md created despite --dry-run"
fi

# ─── 8. --force F92 non-tty without DIDIO_FORCE_YES → exit 2 ─────────────────
echo ""
echo "--- 8. --force non-tty no DIDIO_FORCE_YES ---"
rc=0
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" \
    --force F92 < /dev/null 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]]; then
  _pass "8. exit 2 (--force non-tty no DIDIO_FORCE_YES)"
else
  _fail "8. expected exit 2, got $rc (out: $out)"
fi
if [[ ! -d "$FAKE_HOME/archive/features/F92-qa-failed" ]]; then
  _pass "8. F92 not moved (correctly)"
else
  _fail "8. F92 incorrectly moved to archive"
fi

# ─── 9. DIDIO_FORCE_YES=1 --force F92 → archives ─────────────────────────────
echo ""
echo "--- 9. DIDIO_FORCE_YES=1 --force F92 ---"
out="$(DIDIO_FORCE_YES=1 DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" \
    --force F92 < /dev/null 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  _pass "9. exit 0 (force archive)"
else
  _fail "9. expected exit 0, got $rc (out: $out)"
fi
if [[ -d "$FAKE_HOME/archive/features/F92-qa-failed" ]]; then
  _pass "9. F92 archived with --force"
else
  _fail "9. F92 not in archive after --force (out: $out)"
fi

# ─── 10. FXX not found (F99) → ERROR, exit 1 ─────────────────────────────────
echo ""
echo "--- 10. F99 not found ---"
rc=0
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" F99 2>&1)" || rc=$?
if [[ "$rc" -eq 1 ]]; then
  _pass "10. exit 1 (not found)"
else
  _fail "10. expected exit 1, got $rc"
fi
if echo "$out" | grep -q "ERROR"; then
  _pass "10. prints ERROR"
else
  _fail "10. missing ERROR message (out: $out)"
fi

# ─── 11. FXX ambiguous (F96-ambig-a and F96-ambig-b) → ERROR, exit 1 ─────────
echo ""
echo "--- 11. F96 ambiguous ---"
rc=0
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" F96 2>&1)" || rc=$?
if [[ "$rc" -eq 1 ]]; then
  _pass "11. exit 1 (ambiguous)"
else
  _fail "11. expected exit 1, got $rc"
fi
if echo "$out" | LC_ALL=C grep -qiE "ambig|multiple"; then
  _pass "11. prints ambiguous/multiple error"
else
  _fail "11. missing ambiguous error (out: $out)"
fi

# ─── 12. F94 no retrospective.md — archives and creates stub ─────────────────
echo ""
echo "--- 12. F94 no retrospective — creates stub ---"
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" F94 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  _pass "12. exit 0 (F94 no retro)"
else
  _fail "12. expected exit 0, got $rc (out: $out)"
fi
if [[ -d "$FAKE_HOME/archive/features/F94-no-retro" ]]; then
  _pass "12. F94 archived"
else
  _fail "12. F94 not in archive"
fi
if [[ -f "$FAKE_HOME/memory/retrospectives/F94.md" ]]; then
  _pass "12. stub F94.md created in memory/retrospectives"
  if LC_ALL=C grep -q "without explicit retrospective" "$FAKE_HOME/memory/retrospectives/F94.md"; then
    _pass "12. stub content references missing retrospective"
  else
    _fail "12. stub content missing expected text"
  fi
else
  _fail "12. F94.md not created in memory/retrospectives"
fi

# ─── 13. F95 **Verdict:** Passed (bold markdown) ─────────────────────────────
echo ""
echo "--- 13. F95 **Verdict:** Passed (bold markdown) ---"
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" F95 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  _pass "13. exit 0 (F95 bold verdict)"
else
  _fail "13. expected exit 0, got $rc (out: $out)"
fi
if [[ -d "$FAKE_HOME/archive/features/F95-bold-verdict" ]]; then
  _pass "13. F95 archived (bold Verdict: Passed detected)"
else
  _fail "13. F95 not archived (bold verdict not detected)"
fi

# ─── 14. --help ──────────────────────────────────────────────────────────────
echo ""
echo "--- 14. --help ---"
out="$(DIDIO_HOME="$FAKE_HOME" bash "$FAKE_HOME/bin/didio-archive-feature.sh" --help 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  _pass "14. --help exits 0"
else
  _fail "14. --help expected exit 0, got $rc"
fi
if echo "$out" | grep -q "archive/README.md"; then
  _pass "14. --help mentions archive/README.md"
else
  _fail "14. --help missing link to archive/README.md (out: $out)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf 'Failures:\n'
  for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
echo "All smoke tests passed."
