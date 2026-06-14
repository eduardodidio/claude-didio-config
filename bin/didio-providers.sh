#!/usr/bin/env bash
# didio-providers.sh — list configured providers and validate their CLI
# binaries are present on PATH.
#
# Usage: didio-providers.sh [list|validate|validate-roles <role...>]
#   list      Print every provider in didio.config.json `providers{}` plus
#              its resolved binary and whether it is found on PATH.
#              Always exits 0.
#   validate  Check only the providers actually referenced by a role in
#              the active config (models + models_economy). Exits 1 and
#              lists missing binaries if any are not on PATH.
#   validate-roles <role...>
#             Like validate, but scoped to the given roles only (e.g. the
#             roles a single Wave will spawn). Roles not present in config
#             default to provider "claude". Exits 1 and lists missing
#             binaries if any are not on PATH.
#
# See _brief/03-cli-config-surface.md for the config schema.
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./didio-config-lib.sh
source "$SCRIPT_DIR/didio-config-lib.sh"

SUBCMD="${1:-list}"

case "$SUBCMD" in
  list)
    config="$(didio_find_config)"
    if [[ -z "$config" ]]; then
      echo "didio providers list: no didio.config.json found" >&2
      exit 0
    fi
    providers="$(python3 -c "
import json
with open('$config') as f:
    c = json.load(f)
for name in c.get('providers', {}).keys():
    print(name)
")"
    if [[ -z "$providers" ]]; then
      echo "(no providers configured)"
      exit 0
    fi
    while IFS= read -r provider; do
      [[ -z "$provider" ]] && continue
      bin="$(didio_provider_bin "$provider")"
      if command -v "$bin" >/dev/null 2>&1; then
        echo "$provider -> $bin (found)"
      else
        echo "$provider -> $bin (missing)"
      fi
    done <<< "$providers"
    ;;

  validate)
    config="$(didio_find_config)"
    if [[ -z "$config" ]]; then
      echo "didio providers validate: no didio.config.json found" >&2
      exit 0
    fi
    economy="$(didio_is_economy)"
    roles="$(python3 -c "
import json
with open('$config') as f:
    c = json.load(f)
key = 'models_economy' if '$economy' == 'true' else 'models'
roles = c.get(key, c.get('models', {}))
for role in roles.keys():
    print(role)
")"

    declare -A seen_providers=()
    used_providers=()
    while IFS= read -r role; do
      [[ -z "$role" ]] && continue
      provider="$(didio_provider_for_role "$role")"
      [[ -z "$provider" ]] && provider="claude"
      if [[ -z "${seen_providers[$provider]:-}" ]]; then
        seen_providers[$provider]=1
        used_providers+=("$provider")
      fi
    done <<< "$roles"

    missing=()
    for provider in "${used_providers[@]}"; do
      bin="$(didio_provider_bin "$provider")"
      if ! command -v "$bin" >/dev/null 2>&1; then
        missing+=("$provider ($bin)")
      fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
      echo "didio providers validate: missing CLI binaries:" >&2
      for m in "${missing[@]}"; do
        echo "  - $m" >&2
      done
      exit 1
    fi

    echo "didio providers validate: all configured provider binaries found."
    ;;

  validate-roles)
    shift
    if [[ $# -eq 0 ]]; then
      echo "didio providers validate-roles: at least one role required" >&2
      exit 1
    fi

    declare -A seen_providers=()
    used_providers=()
    for role in "$@"; do
      [[ -z "$role" ]] && continue
      provider="$(didio_provider_for_role "$role")"
      [[ -z "$provider" ]] && provider="claude"
      if [[ -z "${seen_providers[$provider]:-}" ]]; then
        seen_providers[$provider]=1
        used_providers+=("$provider")
      fi
    done

    missing=()
    for provider in "${used_providers[@]}"; do
      bin="$(didio_provider_bin "$provider")"
      if ! command -v "$bin" >/dev/null 2>&1; then
        missing+=("$provider ($bin)")
      fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
      echo "didio providers validate-roles: missing CLI binaries:" >&2
      for m in "${missing[@]}"; do
        echo "  - $m" >&2
        provider_name="${m%% *}"
        case "$provider_name" in
          codex) echo "    install: npm install -g @openai/codex (or see Codex CLI docs); auth: codex login" >&2 ;;
          claude) echo "    install: see https://docs.anthropic.com/claude-code; auth: claude login" >&2 ;;
          *) echo "    install/auth: ensure '$provider_name' CLI is installed and on PATH" >&2 ;;
        esac
      done
      exit 1
    fi

    echo "didio providers validate-roles: all configured provider binaries found for roles: $*"
    ;;

  *)
    echo "didio providers: unknown subcommand '$SUBCMD'. Use 'list', 'validate', or 'validate-roles'." >&2
    exit 1
    ;;
esac
