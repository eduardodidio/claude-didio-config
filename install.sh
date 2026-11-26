#!/usr/bin/env bash
# install.sh — claude-didio-config bootstrap
# Usage:
#   curl -sSL https://raw.githubusercontent.com/eduardodidio/claude-didio-config/main/install.sh | bash
#   OR (from an already-cloned repo):
#   ./install.sh
#
# What it does:
#   1. Clones (or updates) the repo at ~/.claude-didio-config
#   2. Symlinks ~/.local/bin/didio to the repo's bin/didio
#   3. Prints next steps

set -euo pipefail

REPO_URL="${DIDIO_REPO_URL:-https://github.com/eduardodidio/claude-didio-config.git}"
DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
BIN_DIR="${DIDIO_BIN_DIR:-$HOME/.local/bin}"

say() { printf '\033[1;36m[didio-install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[didio-install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[didio-install]\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required"
command -v claude >/dev/null 2>&1 || warn "claude CLI not found in PATH — the framework will not work until you install Claude Code"

if [[ -d "$DIDIO_HOME/.git" ]]; then
  say "updating existing install at $DIDIO_HOME"
  git -C "$DIDIO_HOME" pull --ff-only || warn "git pull failed; continuing with current state"
elif [[ -d "$DIDIO_HOME" && -f "$DIDIO_HOME/bin/didio" ]]; then
  say "found local install at $DIDIO_HOME (not a git clone) — reusing"
else
  say "cloning $REPO_URL -> $DIDIO_HOME"
  git clone "$REPO_URL" "$DIDIO_HOME"
fi

mkdir -p "$BIN_DIR"
ln -sf "$DIDIO_HOME/bin/didio" "$BIN_DIR/didio"
chmod +x "$DIDIO_HOME/bin/"*.sh "$DIDIO_HOME/bin/didio" 2>/dev/null || true

# =========================================================================
# Helper: write a key=value into didio.config.json (create if missing)
# Usage: didio_config_set <key> <value>
#   key uses dot notation: "persona.theme" => {"persona":{"theme":"value"}}
# =========================================================================
DIDIO_CONFIG="${DIDIO_HOME}/didio.config.json"

didio_config_set() {
  local key="$1" val="$2"
  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found — cannot write config key $key"
    return 1
  fi
  python3 - "$DIDIO_CONFIG" "$key" "$val" <<'PYEOF'
import json, sys, os
path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
# coerce booleans and integers
if val.lower() in ("true","yes"):  val = True
elif val.lower() in ("false","no"): val = False
else:
    try: val = int(val)
    except ValueError: pass
cfg = {}
if os.path.isfile(path):
    with open(path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
parts = key.split(".")
obj = cfg
for p in parts[:-1]:
    obj = obj.setdefault(p, {})
obj[parts[-1]] = val
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
}

# =========================================================================
# Non-interactive detection
# =========================================================================
NON_INTERACTIVE=false
if [[ ! -t 0 ]]; then
  NON_INTERACTIVE=true
fi
if [[ "${DIDIO_DEFAULTS_OK:-}" == "yes" ]]; then
  NON_INTERACTIVE=true
fi

# --- Machine scan + parallelism (F29B) ---
if command -v nproc >/dev/null 2>&1; then
  CORES=$(nproc)
elif command -v sysctl >/dev/null 2>&1; then
  CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
else
  CORES=${NUMBER_OF_PROCESSORS:-4}
fi

if [ "$CORES" -le 4 ]; then
  SUGGESTED=2
elif [ "$CORES" -le 8 ]; then
  SUGGESTED=5
else
  SUGGESTED=10
fi

MAX_PARALLEL="${DIDIO_MAX_PARALLEL:-}"
if [[ -z "$MAX_PARALLEL" ]]; then
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    MAX_PARALLEL=$SUGGESTED
  else
    say "Detected $CORES CPU cores. Recommended parallelism: $SUGGESTED"
    printf '\033[1;36m[didio-install]\033[0m Set max_parallel to %d? [Y/n] ' "$SUGGESTED"
    read -r ans
    case "${ans:-Y}" in
      n|N|no|NO)
        printf '\033[1;36m[didio-install]\033[0m Enter max_parallel value: '
        read -r custom_par
        MAX_PARALLEL="${custom_par:-$SUGGESTED}"
        ;;
      *)
        MAX_PARALLEL=$SUGGESTED
        ;;
    esac
  fi
fi
didio_config_set "max_parallel" "$MAX_PARALLEL"
say "max_parallel set to $MAX_PARALLEL"

# --- Persona setup prompt (F29B) ---
PERSONA_THEME="${DIDIO_PERSONA_THEME:-}"
HANDLER_NAME=""
GATEKEEPER_NAME=""

if [[ -z "$PERSONA_THEME" ]]; then
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    PERSONA_THEME="default"
  else
    say "Meta-agents (Handler + GateKeeper + TEA) will be enabled by default."
    echo ""
    say "Would you like to customize the agent persona names?"
    echo "  (1) Default       -- Handler / GateKeeper  [recommended]"
    echo "  (2) Lord of Rings -- Gandalf / Saruman"
    echo "  (3) Terminator    -- T-800 / T-1000"
    echo "  (4) Custom        -- enter your own names"
    printf '\033[1;36m[didio-install]\033[0m Choice [1]: '
    read -r choice
    case "${choice:-1}" in
      2)
        PERSONA_THEME="lotr"
        HANDLER_NAME="Gandalf"
        GATEKEEPER_NAME="Saruman"
        ;;
      3)
        PERSONA_THEME="terminator"
        HANDLER_NAME="T-800"
        GATEKEEPER_NAME="T-1000"
        ;;
      4)
        PERSONA_THEME="custom"
        printf '\033[1;36m[didio-install]\033[0m Handler name: '
        read -r HANDLER_NAME
        printf '\033[1;36m[didio-install]\033[0m GateKeeper name: '
        read -r GATEKEEPER_NAME
        HANDLER_NAME="${HANDLER_NAME:-Handler}"
        GATEKEEPER_NAME="${GATEKEEPER_NAME:-GateKeeper}"
        ;;
      *)
        PERSONA_THEME="default"
        HANDLER_NAME="Handler"
        GATEKEEPER_NAME="GateKeeper"
        ;;
    esac
  fi
fi

# Fill in names from theme if not already set
case "$PERSONA_THEME" in
  lotr)       HANDLER_NAME="${HANDLER_NAME:-Gandalf}"; GATEKEEPER_NAME="${GATEKEEPER_NAME:-Saruman}" ;;
  terminator) HANDLER_NAME="${HANDLER_NAME:-T-800}";   GATEKEEPER_NAME="${GATEKEEPER_NAME:-T-1000}" ;;
  *)          HANDLER_NAME="${HANDLER_NAME:-Handler}";  GATEKEEPER_NAME="${GATEKEEPER_NAME:-GateKeeper}" ;;
esac

didio_config_set "persona.theme" "$PERSONA_THEME"
didio_config_set "persona.handler_name" "$HANDLER_NAME"
didio_config_set "persona.gatekeeper_name" "$GATEKEEPER_NAME"
didio_config_set "persona.configured" "true"
say "Persona: theme=$PERSONA_THEME, handler=$HANDLER_NAME, gatekeeper=$GATEKEEPER_NAME"

# --- Feature toggle confirmation (F29B) ---
FEATURES_OK="${DIDIO_DEFAULTS_OK:-}"
if [[ -z "$FEATURES_OK" ]]; then
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    FEATURES_OK="yes"
  else
    say "The following will be enabled by default:"
    echo "  - Handler (strategic orchestrator)"
    echo "  - GateKeeper (governance reviewer)"
    echo "  - TEA (test architect)"
    echo "  - Autonomous pipeline execution"
    echo "  - Token budget monitoring"
    printf '\033[1;36m[didio-install]\033[0m Accept defaults? [Y/n] '
    read -r ans
    case "${ans:-Y}" in
      n|N|no|NO) FEATURES_OK="no" ;;
      *)         FEATURES_OK="yes" ;;
    esac
  fi
fi

if [[ "$FEATURES_OK" == "yes" ]]; then
  didio_config_set "features.handler" "true"
  didio_config_set "features.gatekeeper" "true"
  didio_config_set "features.tea" "true"
  didio_config_set "features.autonomous_pipeline" "true"
  didio_config_set "features.token_budget" "true"
else
  for feat in handler gatekeeper tea autonomous_pipeline token_budget; do
    label="$feat"
    printf '\033[1;36m[didio-install]\033[0m Enable %s? [Y/n] ' "$label"
    read -r ans
    case "${ans:-Y}" in
      n|N|no|NO) didio_config_set "features.$feat" "false" ;;
      *)         didio_config_set "features.$feat" "true" ;;
    esac
  done
fi

# --- Easter eggs opt-in (F29B) ---
EASTER_EGGS="${DIDIO_EASTER_EGGS:-}"
if [[ -z "$EASTER_EGGS" ]]; then
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    EASTER_EGGS="no"
  else
    printf '\033[1;36m[didio-install]\033[0m Enable themed easter eggs (fun agent phrases)? [y/N] '
    read -r ans
    case "${ans:-N}" in
      y|Y|yes|YES) EASTER_EGGS="yes" ;;
      *)           EASTER_EGGS="no" ;;
    esac
  fi
fi
didio_config_set "persona.easter_eggs" "$EASTER_EGGS"
if [[ "$EASTER_EGGS" == "yes" ]]; then
  say "Easter eggs enabled"
fi

# --- second-brain MCP auto-install (F24) ---
SB_HOME=""
if [[ -n "${DIDIO_SECOND_BRAIN_HOME:-}" && -d "$DIDIO_SECOND_BRAIN_HOME/.git" ]]; then
  SB_HOME="$DIDIO_SECOND_BRAIN_HOME"
elif [[ -d "$HOME/didio-second-brain-claude/.git" ]]; then
  SB_HOME="$HOME/didio-second-brain-claude"
elif [[ -d "$HOME/.claude-second-brain/.git" ]]; then
  SB_HOME="$HOME/.claude-second-brain"
fi

SB_DECISION=""
if [[ -n "$SB_HOME" ]]; then
  say "second-brain MCP already present at $SB_HOME"
  SB_DECISION="present"
else
  case "${DIDIO_INSTALL_SB:-}" in
    yes|y|auto|1)  SB_DECISION="install" ;;
    no|n|0)        SB_DECISION="skip" ;;
    *)
      if [[ -t 0 ]]; then
        printf '\033[1;36m[didio-install]\033[0m didio-second-brain-claude is not installed.\n'
        printf '\033[1;36m[didio-install]\033[0m Clone it from github.com/eduardodidio/didio-second-brain-claude? [y/N] '
        read -r ans
        case "${ans:-N}" in
          y|Y|yes|YES) SB_DECISION="install" ;;
          *)           SB_DECISION="skip" ;;
        esac
      else
        warn "no TTY and DIDIO_INSTALL_SB not set — skipping second-brain install (re-run interactively or set DIDIO_INSTALL_SB=yes)"
        SB_DECISION="skip"
      fi
      ;;
  esac
fi

if [[ "$SB_DECISION" == "install" ]]; then
  SB_TARGET="${DIDIO_SECOND_BRAIN_HOME:-$HOME/didio-second-brain-claude}"
  if [[ -x "$DIDIO_HOME/bin/didio-install-second-brain.sh" ]]; then
    if bash "$DIDIO_HOME/bin/didio-install-second-brain.sh" "$SB_TARGET"; then
      SB_HOME="$SB_TARGET"
      say "second-brain MCP installed at $SB_HOME"
    else
      warn "second-brain clone failed; you can run '$DIDIO_HOME/bin/didio-install-second-brain.sh' later"
    fi
  else
    warn "helper missing — re-run install.sh after the framework is fully set up"
  fi
fi

if [[ -n "$SB_HOME" ]]; then
  RC=""
  case "${SHELL##*/}" in
    zsh)  RC="$HOME/.zshrc" ;;
    bash) RC="$HOME/.bashrc" ;;
    fish) warn "fish shell detected — add this manually to your config.fish: set -gx DIDIO_SECOND_BRAIN_HOME \"$SB_HOME\"" ;;
    *)    warn "unknown shell $SHELL — add this manually: export DIDIO_SECOND_BRAIN_HOME=\"$SB_HOME\"" ;;
  esac
  if [[ -n "$RC" ]]; then
    touch "$RC"
    if grep -q '# >>> didio-second-brain-home' "$RC"; then
      awk '/^# >>> didio-second-brain-home/{flag=1} /^# <<< didio-second-brain-home/{flag=0; next} !flag' "$RC" > "$RC.tmp" && mv "$RC.tmp" "$RC"
    fi
    {
      echo ""
      echo "# >>> didio-second-brain-home (managed by claude-didio-config install.sh) >>>"
      echo "export DIDIO_SECOND_BRAIN_HOME=\"$SB_HOME\""
      echo "# <<< didio-second-brain-home <<<"
    } >> "$RC"
    say "✓ DIDIO_SECOND_BRAIN_HOME exported in $RC (source it or open a new shell)"
  fi
fi

# --- Graphify opt-in install (F28) ---
GF_DECISION=""
case "${DIDIO_INSTALL_GRAPHIFY:-}" in
  yes|y|auto|1) GF_DECISION="install" ;;
  no|n|0)       GF_DECISION="skip" ;;
  *)
    if [[ -t 0 ]]; then
      printf '\033[1;36m[didio-install]\033[0m Install Graphify (knowledge graph for codebase navigation)? [y/N] '
      read -r ans
      case "${ans:-N}" in
        y|Y|yes|YES) GF_DECISION="install" ;;
        *)           GF_DECISION="skip" ;;
      esac
    else
      GF_DECISION="skip"
    fi
    ;;
esac

if [[ "$GF_DECISION" == "install" && -x "$DIDIO_HOME/bin/didio-install-graphify.sh" ]]; then
  if bash "$DIDIO_HOME/bin/didio-install-graphify.sh"; then
    say "Graphify installed successfully"
  else
    warn "Graphify installation failed — run 'didio install-graphify' later"
  fi
fi

# --- RTK opt-in install (F28) ---
RTK_DECISION=""
case "${DIDIO_INSTALL_RTK:-}" in
  yes|y|auto|1) RTK_DECISION="install" ;;
  no|n|0)       RTK_DECISION="skip" ;;
  *)
    if [[ -t 0 ]]; then
      printf '\033[1;36m[didio-install]\033[0m Install RTK (context compression for bash output)? [y/N] '
      read -r ans
      case "${ans:-N}" in
        y|Y|yes|YES) RTK_DECISION="install" ;;
        *)           RTK_DECISION="skip" ;;
      esac
    else
      RTK_DECISION="skip"
    fi
    ;;
esac

if [[ "$RTK_DECISION" == "install" && -x "$DIDIO_HOME/bin/didio-install-rtk.sh" ]]; then
  if bash "$DIDIO_HOME/bin/didio-install-rtk.sh"; then
    say "RTK installed successfully"
  else
    warn "RTK installation failed — run 'didio install-rtk' later"
  fi
fi

cat <<EOF

  ✓ didio installed at $DIDIO_HOME
  ✓ symlink: $BIN_DIR/didio -> $DIDIO_HOME/bin/didio

  Next steps:
    1. Make sure $BIN_DIR is on your PATH:
         export PATH="\$PATH:$BIN_DIR"
    2. cd into a new or existing project
    3. Start claude and run:
         /install-claude-didio-framework
       (the skill is bundled at $DIDIO_HOME/skills/install-claude-didio-framework)

  To use the install skill inside Claude Code, symlink it into your
  user-level Claude config:
       mkdir -p ~/.claude/skills
       ln -sf $DIDIO_HOME/skills/install-claude-didio-framework ~/.claude/skills/install-claude-didio-framework

EOF
if [[ -n "$SB_HOME" ]]; then
  echo "  • second-brain MCP: $SB_HOME"
  echo "    (register with Claude Code: see $SB_HOME/README.md)"
  echo ""
fi
