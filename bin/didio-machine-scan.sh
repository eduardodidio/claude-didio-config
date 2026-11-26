#!/usr/bin/env bash
# didio-machine-scan.sh — Detects hardware capabilities and suggests optimal parallelism
# Usage: didio-machine-scan [--json] [--quiet] [--write]
#
# Flags:
#   --json    Output machine-readable JSON instead of human-readable summary
#   --quiet   Suppress informational output (exit code only)
#   --write   Update didio.config.json with the recommended max_parallel value
#
# Cross-platform: Linux, macOS, Windows (Git Bash / MINGW / MSYS)

set -euo pipefail

# --- Parse flags ---
JSON_OUTPUT=false
QUIET=false
WRITE_CONFIG=false

for arg in "$@"; do
  case "$arg" in
    --json)   JSON_OUTPUT=true ;;
    --quiet)  QUIET=true ;;
    --write)  WRITE_CONFIG=true ;;
    --help|-h)
      sed -n '2,/^$/s/^# \?//p' "$0"
      exit 0
      ;;
    *)
      echo "didio-machine-scan: unknown flag '$arg'. Try --help." >&2
      exit 1
      ;;
  esac
done

# --- Helpers ---
say() {
  if [[ "$QUIET" == "false" && "$JSON_OUTPUT" == "false" ]]; then
    printf '\033[1;36m[machine-scan]\033[0m %s\n' "$*"
  fi
}

warn() {
  if [[ "$QUIET" == "false" && "$JSON_OUTPUT" == "false" ]]; then
    printf '\033[1;33m[machine-scan]\033[0m %s\n' "$*" >&2
  fi
}

# --- Detect CPU cores ---
detect_cores() {
  if command -v nproc &>/dev/null; then
    nproc
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    sysctl -n hw.ncpu 2>/dev/null || echo 4
  elif [[ -n "${NUMBER_OF_PROCESSORS:-}" ]]; then
    echo "$NUMBER_OF_PROCESSORS"
  else
    echo 4  # safe fallback
  fi
}

# --- Detect available RAM (GB) ---
detect_ram_gb() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    local bytes
    bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    if (( bytes > 0 )); then
      echo $(( bytes / 1073741824 ))
    else
      echo 8
    fi
  elif command -v free &>/dev/null; then
    free -g 2>/dev/null | awk '/^Mem:/ { print $2 }' || echo 8
  elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "mingw"* || "$OSTYPE" == "cygwin"* ]]; then
    # Windows Git Bash: try PowerShell
    local ram_gb
    ram_gb=$(powershell.exe -NoProfile -Command \
      "[math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)" \
      2>/dev/null | tr -d '\r\n') || ram_gb=""
    if [[ -n "$ram_gb" && "$ram_gb" =~ ^[0-9]+$ ]]; then
      echo "$ram_gb"
    else
      echo 8  # fallback
    fi
  else
    echo 8  # safe fallback
  fi
}

# --- Detect OS ---
detect_os() {
  case "$OSTYPE" in
    linux*)       echo "linux" ;;
    darwin*)      echo "macos" ;;
    msys*|mingw*|cygwin*) echo "windows" ;;
    *)            echo "unknown" ;;
  esac
}

# --- Detect architecture ---
detect_arch() {
  local arch
  arch=$(uname -m 2>/dev/null || echo "unknown")
  case "$arch" in
    x86_64|amd64)   echo "x86_64" ;;
    aarch64|arm64)   echo "arm64" ;;
    *)               echo "$arch" ;;
  esac
}

# --- Check for Rust toolchain ---
detect_rust() {
  if command -v rustc &>/dev/null; then
    echo "true"
  else
    echo "false"
  fi
}

# --- Count running claude sessions ---
detect_claude_sessions() {
  local count=0
  if command -v pgrep &>/dev/null; then
    count=$(pgrep -c -f "claude" 2>/dev/null) || count=0
  elif [[ "$(detect_os)" == "windows" ]]; then
    count=$(tasklist.exe 2>/dev/null | grep -ci "claude") || count=0
  fi
  # Ensure we output a clean integer
  count="${count//[^0-9]/}"
  echo "${count:-0}"
}

# --- Recommend max_parallel based on hardware ---
recommend_parallel() {
  local cores=$1 ram=$2
  local by_cores by_ram suggested

  # Score by cores
  if (( cores >= 16 )); then
    by_cores=10
  elif (( cores >= 8 )); then
    by_cores=5
  elif (( cores >= 4 )); then
    by_cores=2
  else
    by_cores=1
  fi

  # Score by RAM
  if (( ram >= 32 )); then
    by_ram=10
  elif (( ram >= 16 )); then
    by_ram=5
  elif (( ram >= 8 )); then
    by_ram=2
  else
    by_ram=1
  fi

  # Take the minimum of the two (bottleneck determines limit)
  if (( by_cores < by_ram )); then
    suggested=$by_cores
  else
    suggested=$by_ram
  fi

  echo "$suggested"
}

# --- Build rationale string ---
build_rationale() {
  local cores=$1 ram=$2 suggested=$3
  echo "${cores} cores, ${ram}GB RAM -> ${suggested} parallel agents recommended"
}

# --- Write to config ---
write_config() {
  local val="$1"
  local config_file="${DIDIO_HOME:-$HOME/.claude-didio-config}/didio.config.json"

  if command -v python3 &>/dev/null; then
    python3 - "$config_file" "$val" <<'PYEOF'
import json, sys, os
path, val = sys.argv[1], int(sys.argv[2])
cfg = {}
if os.path.isfile(path):
    with open(path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
cfg["max_parallel"] = val
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
  elif command -v node &>/dev/null; then
    node -e "
const fs = require('fs');
const p = process.argv[1];
const v = parseInt(process.argv[2], 10);
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(p, 'utf8')); } catch {}
cfg.max_parallel = v;
fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
" "$config_file" "$val"
  else
    warn "Neither python3 nor node found -- cannot write config"
    return 1
  fi
}

# =========================================================================
# Main
# =========================================================================

CPU_CORES=$(detect_cores)
RAM_GB=$(detect_ram_gb)
OS=$(detect_os)
ARCH=$(detect_arch)
RUST_AVAILABLE=$(detect_rust)
CLAUDE_SESSIONS=$(detect_claude_sessions)
SUGGESTED=$(recommend_parallel "$CPU_CORES" "$RAM_GB")
RATIONALE=$(build_rationale "$CPU_CORES" "$RAM_GB" "$SUGGESTED")

# --- JSON output ---
if [[ "$JSON_OUTPUT" == "true" ]]; then
  cat <<ENDJSON
{
  "cpu_cores": ${CPU_CORES},
  "ram_gb": ${RAM_GB},
  "os": "${OS}",
  "arch": "${ARCH}",
  "rust_available": ${RUST_AVAILABLE},
  "claude_sessions": ${CLAUDE_SESSIONS},
  "suggested_max_parallel": ${SUGGESTED},
  "suggestion_rationale": "${RATIONALE}"
}
ENDJSON
else
  # --- Human-readable output ---
  say "CPU cores:        $CPU_CORES"
  say "RAM:              ${RAM_GB} GB"
  say "OS:               $OS"
  say "Architecture:     $ARCH"
  say "Rust toolchain:   $( [[ "$RUST_AVAILABLE" == "true" ]] && echo "available" || echo "not found" )"
  say "Claude sessions:  $CLAUDE_SESSIONS"
  say "---"
  say "Suggested max_parallel: $SUGGESTED"
  say "Rationale: $RATIONALE"
fi

# --- Write config if requested ---
if [[ "$WRITE_CONFIG" == "true" ]]; then
  if write_config "$SUGGESTED"; then
    say "Updated didio.config.json: max_parallel=$SUGGESTED"
  else
    warn "Failed to write config"
    exit 1
  fi
fi

exit 0
