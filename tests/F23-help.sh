#!/usr/bin/env bash
# F23-T06 — assert --help surfaces F22 flags.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX"
export DIDIO_HOME="$REPO_ROOT"
export PATH="$REPO_ROOT/bin:$PATH"
# Force non-CI so default mode stays "wait" — but --help shouldn't care.
unset CI DIDIO_CI

pass=0
fail=0
check() {
  local name="$1" haystack="$2" needle="$3"
  if grep -q -- "$needle" <<<"$haystack"; then
    echo "  ok   [$name] contains '$needle'"
    pass=$((pass+1))
  else
    echo "  FAIL [$name] missing '$needle'"
    fail=$((fail+1))
  fi
}

echo "[F23-T06] spawn-agent --help"
HELP_SA="$(bash "$REPO_ROOT/bin/didio-spawn-agent.sh" --help)"
for tok in 'USAGE:' 'FLAGS:' 'ENV VARS:' 'EXAMPLES:' \
           '--on-rate-limit' '--max-retries' '--help' \
           'DIDIO_CI' 'DIDIO_HOME' 'DIDIO_MAX_RETRIES' \
           'DIDIO_RATE_LIMIT_MARGIN_SEC'; do
  check "spawn-agent" "$HELP_SA" "$tok"
done

echo "[F23-T06] spawn-agent -h (alias)"
HELP_SA_SHORT="$(bash "$REPO_ROOT/bin/didio-spawn-agent.sh" -h)"
if [[ "$HELP_SA_SHORT" = "$HELP_SA" ]]; then
  echo "  ok   [-h] alias matches --help"
  pass=$((pass+1))
else
  echo "  FAIL [-h] alias differs from --help"
  fail=$((fail+1))
fi

echo "[F23-T06] didio help (dispatcher)"
HELP_D="$(bash "$REPO_ROOT/bin/didio" help)"
for tok in 'resume-pending' '--on-rate-limit' '--max-retries' 'DIDIO_CI'; do
  check "didio-help" "$HELP_D" "$tok"
done

echo "[F23-T06] didio --help equivalence"
HELP_D_FLAG="$(bash "$REPO_ROOT/bin/didio" --help 2>/dev/null || true)"
if [[ -n "$HELP_D_FLAG" ]]; then
  for tok in 'resume-pending' '--on-rate-limit'; do
    check "didio--help" "$HELP_D_FLAG" "$tok"
  done
else
  echo "  skip [didio --help] no output (acceptable if dispatcher uses 'help' only)"
fi

echo
echo "[F23-T06] pass=$pass fail=$fail"
exit $(( fail > 0 ? 1 : 0 ))
