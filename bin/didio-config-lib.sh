#!/usr/bin/env bash
# didio-config-lib.sh — shared config library for claude-didio-config
#
# Source this file (do NOT execute it directly):
#   source "${DIDIO_HOME}/bin/didio-config-lib.sh"
#
# Reads configuration from didio.config.json (project root first, then
# DIDIO_HOME fallback). All functions use python3 for JSON parsing (already
# a dependency of the framework).

# Locate the config file: project root first, then global fallback.
didio_find_config() {
  local project="${PROJECT_ROOT:-$(pwd)}"
  if [[ -f "$project/didio.config.json" ]]; then
    echo "$project/didio.config.json"
  elif [[ -f "${DIDIO_HOME:-$HOME/.claude-didio-config}/didio.config.json" ]]; then
    echo "${DIDIO_HOME:-$HOME/.claude-didio-config}/didio.config.json"
  else
    echo ""
  fi
}

# Read a top-level key from config. Returns empty string if not found.
didio_read_config() {
  local key="$1"
  local config
  config="$(didio_find_config)"
  [[ -z "$config" ]] && return 0
  python3 -c "
import json, sys
with open('$config') as f:
    c = json.load(f)
v = c.get('$key', '')
if isinstance(v, bool):
    print('true' if v else 'false')
elif isinstance(v, (dict, list)):
    print(json.dumps(v))
else:
    print(v)
" 2>/dev/null || true
}

# Write a top-level key to the project config file.
didio_write_config() {
  local key="$1"
  local value="$2"
  local project="${PROJECT_ROOT:-$(pwd)}"
  local config="$project/didio.config.json"

  if [[ ! -f "$config" ]]; then
    cp "${DIDIO_HOME:-$HOME/.claude-didio-config}/templates/didio.config.json" "$config" 2>/dev/null || \
    echo '{}' > "$config"
  fi

  python3 -c "
import json, sys
path, key, raw = '$config', '$key', '$value'
with open(path) as f:
    c = json.load(f)
# Detect type: bool, int, or string
if raw in ('true', 'false'):
    c[key] = raw == 'true'
elif raw.isdigit():
    c[key] = int(raw)
else:
    c[key] = raw
with open(path, 'w') as f:
    json.dump(c, f, indent=2)
    f.write('\n')
" 2>/dev/null
}

# Returns the --model value for a given role, respecting economy mode.
didio_model_for_role() {
  local role="$1"
  local config
  config="$(didio_find_config)"
  [[ -z "$config" ]] && return 0
  python3 -c "
import json
with open('$config') as f:
    c = json.load(f)
economy = c.get('economy', False)
key = 'models_economy' if economy else 'models'
models = c.get(key, c.get('models', {}))
role_cfg = models.get('$role', {})
print(role_cfg.get('model', ''))
" 2>/dev/null || true
}

# Returns the --fallback-model value for a given role, respecting economy mode.
didio_fallback_for_role() {
  local role="$1"
  local config
  config="$(didio_find_config)"
  [[ -z "$config" ]] && return 0
  python3 -c "
import json
with open('$config') as f:
    c = json.load(f)
economy = c.get('economy', False)
key = 'models_economy' if economy else 'models'
models = c.get(key, c.get('models', {}))
role_cfg = models.get('$role', {})
print(role_cfg.get('fallback', ''))
" 2>/dev/null || true
}

# Returns max parallel agents. Turbo mode overrides to 0 (unlimited).
didio_max_parallel() {
  local config
  config="$(didio_find_config)"
  [[ -z "$config" ]] && echo "0" && return 0
  python3 -c "
import json
with open('$config') as f:
    c = json.load(f)
turbo = c.get('turbo', False)
if turbo:
    print(0)
else:
    print(c.get('max_parallel', 0))
" 2>/dev/null || echo "0"
}

# Returns "true" or "false".
didio_is_turbo() {
  local val
  val="$(didio_read_config turbo)"
  echo "${val:-false}"
}

# Returns "true" or "false".
didio_is_economy() {
  local val
  val="$(didio_read_config economy)"
  echo "${val:-false}"
}

# Returns "true" or "false".
didio_is_highlander() {
  local val
  val="$(didio_read_config highlander)"
  echo "${val:-false}"
}

# Print a summary of current config (for menu display).
didio_config_summary() {
  local config
  config="$(didio_find_config)"
  if [[ -z "$config" ]]; then
    echo "  [nenhum didio.config.json encontrado]"
    return
  fi
  python3 -c "
import json
with open('$config') as f:
    c = json.load(f)

badges = []
if c.get('turbo', False): badges.append('TURBO')
if c.get('economy', False): badges.append('ECONOMY')
if c.get('highlander', False): badges.append('HIGHLANDER')

economy = c.get('economy', False)
key = 'models_economy' if economy else 'models'
models = c.get(key, c.get('models', {}))
mp = 0 if c.get('turbo', False) else c.get('max_parallel', 0)

badge_str = ' '.join(f'[{b}]' for b in badges) if badges else '[STANDARD]'
mp_str = 'ilimitado' if mp == 0 else str(mp)

print(f'  Modo: {badge_str}')
print(f'  Paralelismo max: {mp_str}')
for role in ['architect', 'developer', 'techlead', 'qa']:
    m = models.get(role, {})
    print(f'    {role:10} -> {m.get(\"model\", \"?\")} (fallback: {m.get(\"fallback\", \"?\")})')
" 2>/dev/null || echo "  [erro lendo config]"
}

# Recommended parallelism for a model tier.
didio_recommend_parallel() {
  local model="${1:-sonnet}"
  case "$model" in
    opus*)  echo "3-4 (modelo pesado, alto custo)" ;;
    sonnet*) echo "5-8 (equilibrio custo/qualidade)" ;;
    haiku*) echo "8-12 (leve e rapido)" ;;
    *)      echo "5-8 (padrao)" ;;
  esac
}
