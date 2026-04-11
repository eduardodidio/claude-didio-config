#!/usr/bin/env bash
# didio-easter-egg.sh — print a random thematic one-liner for an agent result.
#
# Usage:
#   didio-easter-egg.sh <role> <exit_code>
#
# Roles: architect | developer | techlead | qa
# Prints a single line to stdout. Exit codes:
#   0   -> success phrase (from the role's mapped franchises)
#   1   -> failure phrase
#   >=2 -> critical failure (villain from critical_failure_villains)
#
# Data source: $DIDIO_HOME/easter-eggs.json
# Disable: set DIDIO_EASTER_EGGS=0

set -euo pipefail

if [[ "${DIDIO_EASTER_EGGS:-1}" == "0" ]]; then
  exit 0
fi

ROLE="${1:-developer}"
EXIT_CODE="${2:-0}"
DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
EGG_FILE="$DIDIO_HOME/easter-eggs.json"

if [[ ! -f "$EGG_FILE" ]]; then
  exit 0
fi

python3 - "$EGG_FILE" "$ROLE" "$EXIT_CODE" <<'PY' 2>/dev/null || true
import json, random, sys
path, role, code = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(path) as f:
    data = json.load(f)

franchises = data.get("franchises", {})
role_map = data.get("role_mapping", {})
villains = data.get("critical_failure_villains", [])

# Critical failure -> villain line
if code >= 2 and villains:
    v = random.choice(villains)
    print(f"[{role}] {v['line']}")
    sys.exit(0)

bucket = "success" if code == 0 else "failure"
choices = role_map.get(role, list(franchises.keys()))
# Flatten all phrases from the role's franchises for that bucket
pool = []
for fname in choices:
    f = franchises.get(fname, {})
    pool.extend(f.get(bucket, []))
if not pool:
    sys.exit(0)
print(f"[{role}] {random.choice(pool)}")
PY
