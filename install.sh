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
        printf '\033[1;36m[didio-install]\033[0m Clone it from github.com/eduardodidio/didio-second-brain-claude? [Y/n] '
        read -r ans
        case "${ans:-Y}" in
          n|N|no|NO) SB_DECISION="skip" ;;
          *)         SB_DECISION="install" ;;
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
