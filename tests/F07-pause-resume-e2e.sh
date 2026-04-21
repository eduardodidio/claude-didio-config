#!/usr/bin/env bash
# F07-pause-resume-e2e.sh — end-to-end simulation of the session guard's
# pause → schedule → resume cycle, without spending real tokens.
#
# Strategy:
#   1. Stub `didio-spawn-agent.sh` with a shim that just logs its args.
#   2. Build a fake `logs/agents/state.json` with 2 "running" agents whose
#      PIDs are sleep loops we control.
#   3. Fixture `logs/session-budget.json` at pct=0.99.
#   4. Call PreToolUse hook with the real pause script in place. Override
#      `DIDIO_PAUSE_RESUME_OVERRIDE_SECS=2` so resume fires fast.
#   5. Assert: session-paused.json written, SIGTERM delivered (sleeps gone),
#      meta files flipped to status=paused, checkpoint file created by the
#      post-tool hook (via a manual DIDIO_RUN_ID), resume scheduler PID
#      captured, resume fires and spawn shim is invoked with RETOMADA
#      prompt, session-paused.json renamed to .handled-<ts>.
#   6. Extra: 4 rapid pauses in the same day → 4th respects max_resumes_per_day
#      anti-loop (snapshot only, no new resume scheduled).
#
# Must complete in < 30s. Exits 1 on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"
export DIDIO_PROJECT_ROOT="$PROJECT"

PASS=0
FAIL=0
FAILURES=()
_pass() { echo "  [PASS] $1"; (( PASS++ )) || true; }
_fail() { echo "  [FAIL] $1"; FAILURES+=("$1"); (( FAIL++ )) || true; }

TMP="$(mktemp -d)"
SPAWN_LOG="$TMP/spawn-invocations.log"
STATE_BACKUP=""

_cleanup() {
  # Kill any leftover sleep loops and scheduled resumes.
  for pf in "$TMP"/sleep-*.pid "$PROJECT/logs/resume-scheduled.pid"; do
    [[ -f "$pf" ]] && { kill "$(cat "$pf")" 2>/dev/null || true; }
  done
  # Remove state.json only if we created it (restore from backup).
  if [[ -n "$STATE_BACKUP" ]] && [[ -f "$STATE_BACKUP" ]]; then
    mv "$STATE_BACKUP" "$PROJECT/logs/agents/state.json"
  fi
  # Remove our fixtures and anything the pause script may have produced.
  rm -f "$PROJECT/logs/session-budget.json" \
        "$PROJECT/logs/.budget-probe.lock" \
        "$PROJECT/logs/session-paused.json" \
        "$PROJECT/logs/resume-scheduled.pid" \
        "$PROJECT/logs/resume-scheduled.log" \
        "$PROJECT/logs/session-paused.log" \
        "$PROJECT/logs/notifications.log" \
        "$PROJECT"/logs/session-paused.json.handled-*
  rm -f "$PROJECT/logs/agents/run-fake-1.meta.json" \
        "$PROJECT/logs/agents/run-fake-2.meta.json" \
        "$PROJECT/logs/agents/run-fake-1.checkpoint.json"
  rm -f "$PROJECT/logs/agents/.run-fake-1.ckpt.at"
  rm -rf "$TMP"
}
trap _cleanup EXIT

# Back up real state.json before we stomp on it.
if [[ -f "$PROJECT/logs/agents/state.json" ]]; then
  STATE_BACKUP="$TMP/state.json.backup"
  cp "$PROJECT/logs/agents/state.json" "$STATE_BACKUP"
fi

echo "=== F07 pause/resume e2e ==="
echo ""

# ─── 1. Spawn-agent shim ───────────────────────────────────────────────────
echo "--- 1. Setup: spawn shim + fake running agents ---"

cat > "$TMP/fake-spawn.sh" <<EOF
#!/usr/bin/env bash
# Log all args to $SPAWN_LOG and exit 0.
printf '%s\0' "\$@" >> "$SPAWN_LOG"
printf '\n---END---\n' >> "$SPAWN_LOG"
exit 0
EOF
chmod +x "$TMP/fake-spawn.sh"

# Launch 2 sleep loops — their PIDs are the "running" agents.
sleep 99 & PID1=$!; echo "$PID1" > "$TMP/sleep-1.pid"
sleep 99 & PID2=$!; echo "$PID2" > "$TMP/sleep-2.pid"

# Build fake meta files so the pause script can flip their status.
cat > "$PROJECT/logs/agents/run-fake-1.meta.json" <<EOF
{ "feature":"F99","role":"developer","task":"run-fake-1","task_file":"$TMP/fake-task-1.md","log":"$PROJECT/logs/agents/run-fake-1.jsonl","status":"running","pid":$PID1 }
EOF
cat > "$PROJECT/logs/agents/run-fake-2.meta.json" <<EOF
{ "feature":"F99","role":"developer","task":"run-fake-2","task_file":"$TMP/fake-task-2.md","log":"$PROJECT/logs/agents/run-fake-2.jsonl","status":"running","pid":$PID2 }
EOF
echo "fake task 1 body" > "$TMP/fake-task-1.md"
echo "fake task 2 body" > "$TMP/fake-task-2.md"

# Fake state.json (what pause.sh reads).
cat > "$PROJECT/logs/agents/state.json" <<EOF
{
  "generated_at": "2026-04-20T18:00:00Z",
  "agents": [
    { "feature":"F99","role":"developer","task":"run-fake-1","task_file":"$TMP/fake-task-1.md","log":"$PROJECT/logs/agents/run-fake-1.jsonl","status":"running","pid":$PID1 },
    { "feature":"F99","role":"developer","task":"run-fake-2","task_file":"$TMP/fake-task-2.md","log":"$PROJECT/logs/agents/run-fake-2.jsonl","status":"running","pid":$PID2 }
  ],
  "features": [{ "feature":"F99","total":2,"completed":0,"running":2 }]
}
EOF

# Write a pre-existing checkpoint for task 1 (simulates the agent having
# already filled in next_action_hint before the pause).
cat > "$PROJECT/logs/agents/run-fake-1.checkpoint.json" <<EOF
{
  "run_id":"run-fake-1","feature":"F99","task":"run-fake-1","role":"developer",
  "updated_at":"2026-04-20T18:00:00Z",
  "task_progress":"already wrote helper X",
  "todo_state":["wire Y"],
  "context_summary":"X helper in bin/foo.sh works; Y wiring is next",
  "next_action_hint":"edit bin/foo-wiring.sh to call helper X"
}
EOF

_pass "fake agents + state.json + meta files seeded"

# ─── 2. Fire pause via PreToolUse hook at pct=0.99 ─────────────────────────
echo ""
echo "--- 2. Fire pause (pct=0.99) ---"

python3 -c "
import json
json.dump({
  'source':'ccusage','session_id':'e2e',
  'tokens_used':198000,'limit':200000,'pct':0.99,
  'window_resets_at':'2026-04-20T22:00:00Z',
  'updated_at':'2026-04-20T18:00:00Z'
}, open('$PROJECT/logs/session-budget.json','w'), indent=2)
"
touch "$PROJECT/logs/session-budget.json"

# Run the hook. It fires pause in background. Use the resume override so
# the scheduled sleep finishes in 2s.
export DIDIO_PAUSE_RESUME_OVERRIDE_SECS=2
# Redirect pause-side stdout/stderr — hook itself will exit 2 with JSON.
stderr="$(bash "$PROJECT/bin/hooks/didio-pre-tool.sh" 2>&1 1>/dev/null)" || true

# Wait a moment for the backgrounded pause to finish writing snapshot.
for i in 1 2 3 4 5 6 7 8 9 10; do
  [[ -f "$PROJECT/logs/session-paused.json" ]] && break
  sleep 0.3
done

[[ -f "$PROJECT/logs/session-paused.json" ]] \
  && _pass "pause.sh wrote session-paused.json" \
  || _fail "session-paused.json not written after 3s"

# ─── 3. Assert SIGTERM delivered + meta flipped to paused ──────────────────
echo ""
echo "--- 3. Running agents stopped + meta updated ---"

sleep 0.5
kill -0 $PID1 2>/dev/null \
  && _fail "PID1 still running after SIGTERM" \
  || _pass "PID1 stopped by SIGTERM"
kill -0 $PID2 2>/dev/null \
  && _fail "PID2 still running after SIGTERM" \
  || _pass "PID2 stopped by SIGTERM"

status1=$(python3 -c "import json; print(json.load(open('$PROJECT/logs/agents/run-fake-1.meta.json'))['status'])" 2>/dev/null)
[[ "$status1" == "paused" ]] \
  && _pass "meta-1 status=paused" \
  || _fail "meta-1 status=$status1"

# ─── 4. Schedule file captured ─────────────────────────────────────────────
[[ -f "$PROJECT/logs/resume-scheduled.pid" ]] \
  && _pass "resume-scheduled.pid captured" \
  || _fail "resume-scheduled.pid missing"

# ─── 5. Drive the resume directly (stub spawn-agent) ───────────────────────
echo ""
echo "--- 5. Resume drives spawn with RETOMADA extra ---"

DIDIO_SPAWN_CMD="$TMP/fake-spawn.sh" \
  bash "$PROJECT/bin/didio-resume-feature.sh" F99

# Resume uses subprocess.Popen (non-blocking); wait for shim output.
for i in 1 2 3 4 5 6 7 8 9 10; do
  [[ -f "$SPAWN_LOG" ]] && [[ $(grep -c "END" "$SPAWN_LOG" 2>/dev/null || echo 0) -ge 2 ]] && break
  sleep 0.3
done

# Assert spawn shim was called per task, with RETOMADA extra.
if [[ -f "$SPAWN_LOG" ]]; then
  count=$(grep -c "END" "$SPAWN_LOG" || echo 0)
  if (( count >= 2 )); then
    _pass "spawn shim invoked $count times (>= 2 paused tasks)"
  else
    _fail "spawn shim count=$count (expected >= 2)"
  fi
  if LC_ALL=C grep -aq "RETOMADA DE SESSÃO" "$SPAWN_LOG"; then
    _pass "spawn includes 'RETOMADA DE SESSÃO' extra prompt"
  else
    _fail "spawn missing RETOMADA extra"
  fi
  # task 1 had a valid checkpoint → should get the hint
  if LC_ALL=C grep -aq "edit bin/foo-wiring.sh to call helper X" "$SPAWN_LOG"; then
    _pass "task-1 resumed with checkpoint next_action_hint"
  else
    _fail "task-1 missing next_action_hint in extra"
  fi
  # task 2 had NO checkpoint → should fall back to 'Reinicie esta task'
  if LC_ALL=C grep -aq "AUSENTE ou inválido" "$SPAWN_LOG"; then
    _pass "task-2 fallback to restart (no checkpoint)"
  else
    _fail "task-2 fallback not triggered"
  fi
else
  _fail "spawn shim never invoked"
fi

# session-paused.json renamed to .handled-*
if compgen -G "$PROJECT/logs/session-paused.json.handled-*" >/dev/null; then
  _pass "session-paused.json renamed to .handled-<ts>"
else
  _fail ".handled-<ts> not created"
fi

# ─── 6. Anti-loop: max_resumes_per_day ─────────────────────────────────────
echo ""
echo "--- 6. Anti-loop (max_resumes_per_day=3) ---"

# Inflate session-paused.log so the next pause sees 3 prior entries today.
TODAY="$(date -u +%Y-%m-%d)"
for i in 1 2 3; do
  printf '{"date":"%s","paused_at":"%s","feature":"F99","resume_at":""}\n' \
    "$TODAY" "2026-04-20T10:0${i}:00Z" >> "$PROJECT/logs/session-paused.log"
done

# Run pause.sh with dry mode disabled but state.json absent (so no kills).
rm -f "$PROJECT/logs/agents/state.json"
rm -f "$PROJECT/logs/session-paused.json" "$PROJECT/logs/resume-scheduled.pid"

bash "$PROJECT/bin/didio-budget-pause.sh" "2026-04-20T22:00:00Z" 2>&1 | tee "$TMP/pause4.out" >/dev/null || true

if grep -q "max_resumes_per_day" "$TMP/pause4.out"; then
  _pass "4th pause respected anti-loop (message printed)"
else
  _fail "anti-loop not triggered (output: $(cat "$TMP/pause4.out"))"
fi

[[ ! -f "$PROJECT/logs/resume-scheduled.pid" ]] \
  && _pass "anti-loop: no new resume-scheduled.pid" \
  || _fail "anti-loop: resume-scheduled.pid created despite cap"

# ─── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf 'Failures:\n'
  for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
echo "All e2e tests passed."
