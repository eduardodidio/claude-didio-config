#!/usr/bin/env bash
# didio-resume-pending.sh — F22 — scan logs/agents/_pending/ and
# re-spawn jobs whose rate-limit reset has passed.
# Sources didio-rate-limit-lib.sh; idempotent; lockfile-protected.
set -euo pipefail

FEATURE_FILTER=""
DRY_RUN=0
MAX_RETRIES_OVERRIDE=""
RESUME_FUTURE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature) FEATURE_FILTER="$2"; shift 2 ;;
    --feature=*) FEATURE_FILTER="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --max-retries) MAX_RETRIES_OVERRIDE="$2"; shift 2 ;;
    --max-retries=*) MAX_RETRIES_OVERRIDE="${1#*=}"; shift ;;
    --all-future) RESUME_FUTURE=1; shift ;;
    -h|--help)
      cat <<EOF
didio resume-pending — scan logs/agents/_pending/ and re-spawn ready jobs.
Usage:
  didio resume-pending [--feature FXX] [--dry-run] [--max-retries N] [--all-future]
EOF
      exit 0 ;;
    *) echo "didio resume-pending: unknown arg: $1" >&2; exit 2 ;;
  esac
done

PROJECT_ROOT="$(pwd)"
PENDING_DIR="$PROJECT_ROOT/logs/agents/_pending"
[[ -d "$PENDING_DIR" ]] || { echo "[resume-pending] no pending dir at $PENDING_DIR — nothing to do"; exit 0; }

RL_LIB="${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-rate-limit-lib.sh"
[[ -f "$RL_LIB" ]] || { echo "[resume-pending] FATAL: lib not found at $RL_LIB" >&2; exit 2; }
# shellcheck disable=SC1090
source "$RL_LIB"

shopt -s nullglob
COUNT_TOTAL=0
COUNT_RESUMED=0
COUNT_SKIPPED_FUTURE=0
COUNT_SKIPPED_LOCKED=0
COUNT_FAILED=0

NOW=$(date +%s)

for f in "$PENDING_DIR"/*.json; do
  COUNT_TOTAL=$((COUNT_TOTAL+1))
  base=$(basename "$f" .json)

  # Filter by feature
  if [[ -n "$FEATURE_FILTER" ]] && [[ "$base" != "$FEATURE_FILTER"-* ]]; then
    continue
  fi

  # Schema check — refuse unknown schema versions
  schema=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('schema_version','?'))" "$f" 2>/dev/null || echo "?")
  if [[ "$schema" != "1" ]]; then
    echo "[resume-pending] WARN: skipping $base (unknown schema_version=$schema)" >&2
    continue
  fi

  # Parse reset time — prefer reset_at_unix, fall back to ISO reset_at
  reset_at=$(python3 - "$f" <<'PYEOF' 2>/dev/null || echo "0"
import json, sys
data = json.load(open(sys.argv[1]))
raw = data.get("reset_at_unix")
if raw:
    print(int(raw))
else:
    from datetime import datetime
    print(int(datetime.fromisoformat(data["reset_at"].replace("Z", "+00:00")).timestamp()))
PYEOF
  )

  if (( reset_at > NOW )) && (( RESUME_FUTURE == 0 )); then
    echo "[resume-pending] skip $base — reset in $((reset_at - NOW))s"
    COUNT_SKIPPED_FUTURE=$((COUNT_SKIPPED_FUTURE+1))
    continue
  fi

  if ! didio_rl_acquire_lock "$f"; then
    echo "[resume-pending] skip $base — lock held"
    COUNT_SKIPPED_LOCKED=$((COUNT_SKIPPED_LOCKED+1))
    continue
  fi
  trap 'didio_rl_release_lock "$f"' EXIT

  if (( DRY_RUN == 1 )); then
    echo "[resume-pending] dry-run: would resume $base"
    didio_rl_release_lock "$f"
    trap - EXIT
    continue
  fi

  # Atomic consume — if rename fails, another invocation got there first
  if ! didio_rl_consume_pending "$f"; then
    echo "[resume-pending] skip $base — consumed by another invocation"
    didio_rl_release_lock "$f"
    trap - EXIT
    continue
  fi

  # Read job spec from .consumed file
  CONSUMED="${f}.consumed"
  job_role=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['role'])" "$CONSUMED")
  job_feature=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['feature'])" "$CONSUMED")
  job_task_file=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['task_file'])" "$CONSUMED")
  job_extra=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('extra_prompt',''))" "$CONSUMED")
  job_cwd=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['cwd'])" "$CONSUMED")
  job_retries=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('retries',0))" "$CONSUMED")

  # Restore whitelisted env vars (whitelist enforced by lib at persist time)
  while IFS=$'\t' read -r k v; do
    [[ -n "$k" ]] && export "$k=$v"
  done < <(python3 -c "import json,sys; d=json.load(open(sys.argv[1]))['env']; [print(f'{k}\t{v}') for k,v in d.items()]" "$CONSUMED")

  export DIDIO_RETRIES_SO_FAR=$((job_retries + 1))
  [[ -n "$MAX_RETRIES_OVERRIDE" ]] && export DIDIO_MAX_RETRIES="$MAX_RETRIES_OVERRIDE"

  didio_rl_append_telemetry "$PENDING_DIR" "$(printf '{"event":"resume","role":"%s","feature":"%s","task":"%s","retries":%s,"ts":"%s"}' \
    "$job_role" "$job_feature" "$(basename "$job_task_file" .md)" "$DIDIO_RETRIES_SO_FAR" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"

  rc=0
  ( cd "$job_cwd" && "${DIDIO_HOME:-$HOME/.claude-didio-config}/bin/didio-spawn-agent.sh" \
      "$job_role" "$job_feature" "$job_task_file" "$job_extra" ) || rc=$?

  didio_rl_release_lock "$f"
  trap - EXIT

  if [[ $rc -eq 0 ]]; then
    COUNT_RESUMED=$((COUNT_RESUMED+1))
  else
    COUNT_FAILED=$((COUNT_FAILED+1))
  fi
done
shopt -u nullglob

if (( COUNT_TOTAL == 0 )); then
  echo "[resume-pending] no pending jobs at $PENDING_DIR — nothing to do"
  exit 0
fi

echo "[resume-pending] total=$COUNT_TOTAL resumed=$COUNT_RESUMED skipped_future=$COUNT_SKIPPED_FUTURE skipped_locked=$COUNT_SKIPPED_LOCKED failed=$COUNT_FAILED"
[[ $COUNT_FAILED -gt 0 ]] && exit 1 || exit 0
