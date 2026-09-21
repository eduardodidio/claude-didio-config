#!/usr/bin/env bash
# didio-install-rtk.sh — install the RTK CLI (Rust-based context compression proxy).
#
# Usage: didio-install-rtk.sh
#
# Exit codes:
#   0  success (already installed or freshly installed)
#   1  installation failed

set -euo pipefail

say()  { printf '\033[1;36m[didio-install-rtk]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[didio-install-rtk]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[didio-install-rtk]\033[0m %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  -h|--help)
    cat <<EOF
Usage: didio-install-rtk.sh

Install the RTK CLI (context compression proxy for Claude Code).

Steps:
  1. Check if rtk is already on PATH
  2. Detect platform and install via winget/brew/curl
  3. Sanity check: rtk --version
  4. Print post-install instructions (rtk init -g)

NOTE: This script does NOT run 'rtk init -g' automatically because it
modifies ~/.claude/settings.json. You must run it manually after install.

Exit codes:
  0  success
  1  installation failed
EOF
    exit 0
    ;;
esac

# 1. Already installed?
if command -v rtk >/dev/null 2>&1; then
  say "rtk already installed: $(rtk --version 2>&1 || echo 'version unknown')"
  echo ""
  say "Post-install (if not done yet):"
  say "  Run 'rtk init -g' to enable automatic bash compression."
  say "  This modifies ~/.claude/settings.json — review the changes."
  exit 0
fi

# 2. Platform detection and install
OS="$(uname -s 2>/dev/null || echo Unknown)"
case "$OS" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    say "detected Windows — installing via winget..."
    if command -v winget >/dev/null 2>&1; then
      if ! winget install rtk-ai.rtk; then
        die "winget install rtk-ai.rtk failed. Try downloading manually from https://github.com/nicobailey/rtk"
      fi
    else
      die "winget not found. Install RTK manually from https://github.com/nicobailey/rtk"
    fi
    ;;
  Darwin)
    say "detected macOS — installing via brew..."
    if command -v brew >/dev/null 2>&1; then
      if ! brew install rtk; then
        die "brew install rtk failed"
      fi
    else
      die "brew not found. Install Homebrew first: https://brew.sh"
    fi
    ;;
  Linux)
    if command -v brew >/dev/null 2>&1; then
      say "detected Linux with brew — installing via brew..."
      if ! brew install rtk; then
        die "brew install rtk failed"
      fi
    else
      die "RTK install on Linux without brew: download the release binary from https://github.com/nicobailey/rtk/releases"
    fi
    ;;
  *)
    die "unsupported platform: $OS. Install RTK manually from https://github.com/nicobailey/rtk"
    ;;
esac

# 3. Sanity check
if command -v rtk >/dev/null 2>&1; then
  say "rtk installed successfully: $(rtk --version 2>&1 || echo 'version unknown')"
else
  warn "rtk not found on PATH after installation — you may need to restart your shell"
fi

# 4. Post-install instructions
echo ""
say "IMPORTANT — next step (manual):"
say "  Run 'rtk init -g' to enable automatic bash output compression."
say "  This modifies ~/.claude/settings.json to add RTK's hook."
say "  Review the changes before proceeding."
