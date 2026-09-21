#!/usr/bin/env bash
# didio-install-graphify.sh — install the Graphify CLI (knowledge graph via tree-sitter AST).
#
# Usage: didio-install-graphify.sh
#
# Exit codes:
#   0  success (already installed or freshly installed)
#   1  installation failed

set -euo pipefail

say()  { printf '\033[1;36m[didio-install-graphify]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[didio-install-graphify]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[didio-install-graphify]\033[0m %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  -h|--help)
    cat <<EOF
Usage: didio-install-graphify.sh

Install the Graphify CLI via uv tool install.

Steps:
  1. Check if graphify is already on PATH
  2. Verify uv is available
  3. Run: uv tool install graphifyy
  4. Run: graphify install (downloads tree-sitter grammars)
  5. Sanity check: graphify --version

Exit codes:
  0  success
  1  installation failed
EOF
    exit 0
    ;;
esac

# 1. Already installed?
if command -v graphify >/dev/null 2>&1; then
  say "graphify already installed: $(graphify --version 2>&1 || echo 'version unknown')"
  exit 0
fi

# 2. Check uv
if ! command -v uv >/dev/null 2>&1; then
  die "uv is required but not found on PATH.
  Install uv first:
    curl -LsSf https://astral.sh/uv/install.sh | sh
  Or see: https://docs.astral.sh/uv/getting-started/installation/"
fi

# 3. Install via uv
say "installing graphify via uv tool install graphifyy..."
if ! uv tool install graphifyy; then
  die "uv tool install graphifyy failed"
fi

# 4. Download tree-sitter grammars
say "downloading tree-sitter grammars (graphify install)..."
if ! graphify install; then
  warn "graphify install failed — grammars may need to be installed manually"
fi

# 5. Sanity check
if command -v graphify >/dev/null 2>&1; then
  say "graphify installed successfully: $(graphify --version 2>&1 || echo 'version unknown')"
else
  die "graphify not found on PATH after installation — check your uv tool bin directory is on PATH"
fi
