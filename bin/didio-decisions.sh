#!/usr/bin/env bash
# didio-decisions.sh — Decision log viewer
#
# Usage:
#   didio decisions --recent [N]
#   didio decisions --status <status>
#   didio decisions --detail <decision-id>

set -euo pipefail

PROJECT_ROOT="$(pwd)"
DECISIONS_DIR="$PROJECT_ROOT/logs/decisions"

# --help
if [[ "${1:-}" = "--help" || "${1:-}" = "-h" || -z "${1:-}" ]]; then
  cat <<'EOF'
USAGE:
  didio decisions --recent [N]           List last N decisions (default: 5)
  didio decisions --status <status>      Filter by status (pending|executed|reviewed|escalated)
  didio decisions --detail <decision-id> Show full decision details

EXAMPLES:
  didio decisions --recent 5
  didio decisions --status pending
  didio decisions --detail D-20260605-001
EOF
  exit 0
fi

if [[ ! -d "$DECISIONS_DIR" ]]; then
  echo "[didio-decisions] no decisions directory at $DECISIONS_DIR" >&2
  echo "[didio-decisions] run 'didio t800' to create your first decision" >&2
  exit 0
fi

case "${1:-}" in
  --recent)
    LIMIT="${2:-5}"
    python3 - "$DECISIONS_DIR" "$LIMIT" <<'PY'
import json, sys, os, glob

decisions_dir = sys.argv[1]
limit = int(sys.argv[2])

files = sorted(glob.glob(os.path.join(decisions_dir, "D-*.json")), reverse=True)
if not files:
    print("\n  No decisions found.\n")
    sys.exit(0)

files = files[:limit]
print(f"\n  Last {len(files)} decision(s):\n")
print(f"  {'ID':<22} {'Type':<18} {'Decision':<10} {'Status':<12} {'Governance'}")
print(f"  {'-'*22} {'-'*18} {'-'*10} {'-'*12} {'-'*15}")

for f in files:
    try:
        with open(f) as fp:
            d = json.load(fp)
        did = d.get('decision_id', os.path.basename(f))
        dtype = d.get('type', '?')
        decision = d.get('decision', '?')
        status = d.get('status', '?')
        gov = d.get('governance')
        gov_str = gov.get('verdict', '?') if isinstance(gov, dict) else '-'
        print(f"  {did:<22} {dtype:<18} {decision:<10} {status:<12} {gov_str}")
    except Exception:
        print(f"  {os.path.basename(f):<22} [error reading]")

print()
PY
    ;;

  --status)
    STATUS="${2:?status required (pending|executed|reviewed|escalated)}"
    python3 - "$DECISIONS_DIR" "$STATUS" <<'PY'
import json, sys, os, glob

decisions_dir = sys.argv[1]
target_status = sys.argv[2]

files = sorted(glob.glob(os.path.join(decisions_dir, "D-*.json")), reverse=True)
matches = []

for f in files:
    try:
        with open(f) as fp:
            d = json.load(fp)
        if d.get('status', '') == target_status:
            matches.append(d)
    except Exception:
        pass

if not matches:
    print(f"\n  No decisions with status='{target_status}'.\n")
    sys.exit(0)

print(f"\n  Decisions with status='{target_status}' ({len(matches)}):\n")
print(f"  {'ID':<22} {'Type':<18} {'Context'}")
print(f"  {'-'*22} {'-'*18} {'-'*40}")

for d in matches:
    did = d.get('decision_id', '?')
    dtype = d.get('type', '?')
    ctx = d.get('context_summary', '')[:40]
    print(f"  {did:<22} {dtype:<18} {ctx}")

print()
PY
    ;;

  --detail)
    DECISION_ID="${2:?decision-id required (e.g. D-20260605-001)}"
    DECISION_FILE="$DECISIONS_DIR/${DECISION_ID}.json"
    if [[ ! -f "$DECISION_FILE" ]]; then
      echo "[didio-decisions] not found: $DECISION_FILE" >&2
      exit 2
    fi
    python3 - "$DECISION_FILE" <<'PY'
import json, sys

with open(sys.argv[1]) as f:
    d = json.load(f)

print(f"\n  Decision: {d.get('decision_id', '?')}")
print(f"  Timestamp: {d.get('timestamp', '?')}")
print(f"  Type: {d.get('type', '?')}")
print(f"  Status: {d.get('status', '?')}")
print(f"\n  Context: {d.get('context_summary', '-')}")
print(f"\n  Options considered:")
for opt in d.get('options_considered', []):
    print(f"    [{opt.get('option', '?')}] {opt.get('description', '')}")
    for pro in opt.get('pros', []):
        print(f"        + {pro}")
    for con in opt.get('cons', []):
        print(f"        - {con}")

print(f"\n  Decision: {d.get('decision', '?')}")
print(f"  Rationale: {d.get('rationale', '-')}")
print(f"\n  Actions:")
for a in d.get('actions', []):
    print(f"    - {a.get('action', '?')} {a.get('feature', '')}")

gov = d.get('governance')
if isinstance(gov, dict):
    print(f"\n  Governance:")
    print(f"    Verdict: {gov.get('verdict', '?')}")
    print(f"    Confidence: {gov.get('confidence', '?')}")
    blind = gov.get('blind_spots', [])
    if blind:
        print(f"    Blind spots:")
        for b in blind:
            print(f"      - {b}")
    risks = gov.get('risks', [])
    if risks:
        print(f"    Risks:")
        for r in risks:
            print(f"      - {r}")
    rec = gov.get('recommendation', '')
    if rec:
        print(f"    Recommendation: {rec}")
else:
    print(f"\n  Governance: not yet reviewed")

print()
PY
    ;;

  *)
    echo "[didio-decisions] unknown option: $1. Use --help." >&2
    exit 1
    ;;
esac
