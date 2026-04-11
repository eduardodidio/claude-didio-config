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

# Make DIDIO_HOME available in shell configs if user wants
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
