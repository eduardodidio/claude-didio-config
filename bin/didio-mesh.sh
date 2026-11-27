#!/usr/bin/env bash
# didio-mesh.sh — Knowledge Mesh CLI for cross-project learnings.
#
# Usage:
#   didio mesh register <path>       Register a project in the mesh
#   didio mesh unregister <name>     Remove a project from the mesh
#   didio mesh list [--json]         Show all registered projects
#   didio mesh sync [--dry-run]      Export local + import from all siblings
#   didio mesh query <keywords>      Search learnings across all projects
#
# Registry location: ~/.didio/mesh-registry.json

set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
REGISTRY_FILE="${DIDIO_MESH_REGISTRY:-$HOME/.didio/mesh-registry.json}"
REGISTRY_DIR="$(dirname "$REGISTRY_FILE")"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_mesh_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_mesh_native_path() {
  # Convert POSIX path to native for python3 on MINGW/MSYS
  if command -v cygpath &>/dev/null; then
    cygpath -m "$1"
  else
    echo "$1"
  fi
}

_mesh_ensure_registry() {
  mkdir -p "$REGISTRY_DIR"
  if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo '{"version":1,"projects":[]}' > "$REGISTRY_FILE"
  fi
}

# Native path for python3 (MINGW compatibility)
REGISTRY_FILE_PY="$(_mesh_native_path "$REGISTRY_FILE")"

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_register() {
  local project_path="${1:?Usage: didio mesh register <path>}"

  # Resolve to absolute path
  project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
    echo "[mesh] Error: path '$1' does not exist or is not a directory" >&2
    exit 1
  }

  # Validate it's a didio project
  if [[ ! -f "$project_path/didio.config.json" ]]; then
    echo "[mesh] Error: '$project_path' does not contain didio.config.json" >&2
    exit 1
  fi

  # Read project name
  local name
  name="$(python3 -c "
import json, sys, os
try:
    with open(os.path.join(sys.argv[1], 'didio.config.json'), 'r') as f:
        d = json.load(f)
    print(d.get('project_name', os.path.basename(sys.argv[1])))
except Exception:
    print(os.path.basename(sys.argv[1]))
" "$project_path")"

  _mesh_ensure_registry

  # Check for duplicate
  local exists
  exists="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    d = json.load(f)
for p in d.get('projects', []):
    if p['name'] == sys.argv[2]:
        print('yes')
        sys.exit(0)
print('no')
" "$REGISTRY_FILE_PY" "$name")"

  if [[ "$exists" == "yes" ]]; then
    echo "[mesh] Error: project '$name' is already registered" >&2
    exit 1
  fi

  # Add to registry
  local now
  now="$(_mesh_now_iso)"

  python3 -c "
import json, sys
registry_file = sys.argv[1]
name = sys.argv[2]
path = sys.argv[3]
now = sys.argv[4]

with open(registry_file, 'r') as f:
    d = json.load(f)

d['projects'].append({
    'name': name,
    'path': path,
    'registered_at': now,
    'last_sync': None,
    'learnings_count': 0
})

with open(registry_file, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$REGISTRY_FILE_PY" "$name" "$project_path" "$now"

  echo "[mesh] Registered '$name' at $project_path"
}

cmd_unregister() {
  local name="${1:?Usage: didio mesh unregister <name>}"

  _mesh_ensure_registry

  local found
  found="$(python3 -c "
import json, sys
registry_file = sys.argv[1]
name = sys.argv[2]

with open(registry_file, 'r') as f:
    d = json.load(f)

original = len(d['projects'])
d['projects'] = [p for p in d['projects'] if p['name'] != name]

if len(d['projects']) == original:
    print('not_found')
else:
    with open(registry_file, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    print('removed')
" "$REGISTRY_FILE_PY" "$name")"

  if [[ "$found" == "not_found" ]]; then
    echo "[mesh] Error: project '$name' not found in registry" >&2
    exit 1
  fi

  echo "[mesh] Unregistered '$name'"
}

cmd_list() {
  _mesh_ensure_registry

  local json_mode=0
  [[ "${1:-}" == "--json" ]] && json_mode=1

  if [[ $json_mode -eq 1 ]]; then
    python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    d = json.load(f)
print(json.dumps(d['projects'], indent=2))
" "$REGISTRY_FILE_PY"
  else
    python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    d = json.load(f)

projects = d.get('projects', [])
if not projects:
    print('No projects registered. Use: didio mesh register <path>')
    sys.exit(0)

# Header
print(f\"{'Name':<25} {'Path':<45} {'Last Sync':<22} {'Learnings':>9}\")
print('-' * 105)

for p in projects:
    name = p.get('name', '?')[:24]
    path = p.get('path', '?')[:44]
    last_sync = p.get('last_sync', 'never') or 'never'
    if last_sync != 'never':
        last_sync = last_sync[:19].replace('T', ' ')
    count = p.get('learnings_count', 0)
    print(f'{name:<25} {path:<45} {last_sync:<22} {count:>9}')
" "$REGISTRY_FILE_PY"
  fi
}

cmd_sync() {
  local dry_run=0
  local target_project=""

  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=1 ;;
      --project=*) target_project="${arg#--project=}" ;;
    esac
  done

  _mesh_ensure_registry

  python3 -c "
import json, sys, os, subprocess, glob
from datetime import datetime, timezone

registry_file = sys.argv[1]
dry_run = sys.argv[2] == '1'
target = sys.argv[3]
didio_home = sys.argv[4]

with open(registry_file, 'r') as f:
    reg = json.load(f)

projects = reg.get('projects', [])
if not projects:
    print('[mesh] No projects registered. Nothing to sync.')
    sys.exit(0)

# Filter to target if specified
if target:
    projects = [p for p in projects if p['name'] == target]
    if not projects:
        print(f'[mesh] Error: project \"{target}\" not found in registry', file=sys.stderr)
        sys.exit(1)

# Phase 1: Export from each project
exports = {}
for p in projects:
    path = p['path']
    name = p['name']
    if not os.path.isdir(path):
        print(f'[mesh] WARN: {name} path not found: {path}', file=sys.stderr)
        continue

    export_file = os.path.join(path, 'logs', 'agents', 'shared-learnings-export.json')
    export_script = os.path.join(didio_home, 'bin', 'didio-learnings-export.sh')

    if not os.path.isfile(export_script):
        # Try project-local
        export_script = os.path.join(path, 'bin', 'didio-learnings-export.sh')

    if os.path.isfile(export_script):
        if dry_run:
            print(f'[mesh] DRY RUN: would export from {name}')
        else:
            try:
                subprocess.run(['bash', export_script], cwd=path, capture_output=True, timeout=30)
            except Exception as e:
                print(f'[mesh] WARN: export failed for {name}: {e}', file=sys.stderr)
                continue

    # Count learnings from local files
    learnings_dir = os.path.join(path, 'memory', 'agent-learnings')
    count = 0
    if os.path.isdir(learnings_dir):
        for md in glob.glob(os.path.join(learnings_dir, '*.md')):
            with open(md, 'r', errors='replace') as f:
                count += sum(1 for line in f if line.startswith('## F'))

    if os.path.isfile(export_file):
        exports[name] = export_file

    # Update registry entry
    for rp in reg['projects']:
        if rp['name'] == name:
            rp['learnings_count'] = count
            if not dry_run:
                rp['last_sync'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

# Phase 2: Import to each project from siblings
import_script_base = os.path.join(didio_home, 'bin', 'didio-learnings-import.sh')
for p in projects:
    name = p['name']
    path = p['path']
    if not os.path.isdir(path):
        continue

    import_script = import_script_base
    if not os.path.isfile(import_script):
        import_script = os.path.join(path, 'bin', 'didio-learnings-import.sh')

    for src_name, src_file in exports.items():
        if src_name == name:
            continue  # skip self

        if dry_run:
            print(f'[mesh] DRY RUN: would import {src_name} -> {name}')
        else:
            if os.path.isfile(import_script) and os.path.isfile(src_file):
                try:
                    subprocess.run(['bash', import_script, src_file], cwd=path, capture_output=True, timeout=30)
                except Exception as e:
                    print(f'[mesh] WARN: import {src_name} -> {name} failed: {e}', file=sys.stderr)

# Save updated registry
if not dry_run:
    with open(registry_file, 'w') as f:
        json.dump(reg, f, indent=2)
        f.write('\n')

# Summary
total_exports = len(exports)
total_imports = sum(1 for _ in ((s, t) for s in exports for t in projects if t['name'] != s and os.path.isdir(t['path'])))
mode = 'DRY RUN' if dry_run else 'Sync'
print(f'[mesh] {mode} complete: {len(projects)} projects, {total_exports} exported, {total_imports} import pairs')
" "$REGISTRY_FILE_PY" "$((dry_run))" "${target_project}" "$DIDIO_HOME"
}

cmd_query() {
  local keywords=""
  local role_filter=""
  local project_filter=""
  local json_mode=0
  local limit=20

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --role) shift; role_filter="${1:-}" ;;
      --project) shift; project_filter="${1:-}" ;;
      --json) json_mode=1 ;;
      --limit) shift; limit="${1:-20}" ;;
      --*) ;; # ignore unknown flags
      *) keywords="$keywords $1" ;;
    esac
    shift
  done

  keywords="$(echo "$keywords" | sed 's/^ //')"

  if [[ -z "$keywords" ]]; then
    echo "Usage: didio mesh query <keywords> [--role <role>] [--project <name>] [--json] [--limit N]" >&2
    exit 1
  fi

  _mesh_ensure_registry

  python3 -c "
import json, sys, os, re, glob

registry_file = sys.argv[1]
keywords = sys.argv[2].lower()
role_filter = sys.argv[3]
project_filter = sys.argv[4]
json_mode = sys.argv[5] == '1'
limit = int(sys.argv[6])

with open(registry_file, 'r') as f:
    reg = json.load(f)

results = []

for p in reg.get('projects', []):
    name = p['name']
    path = p['path']

    if project_filter and name != project_filter:
        continue
    if not os.path.isdir(path):
        continue

    learnings_dir = os.path.join(path, 'memory', 'agent-learnings')
    if not os.path.isdir(learnings_dir):
        continue

    for md_file in sorted(glob.glob(os.path.join(learnings_dir, '*.md'))):
        role = os.path.basename(md_file).replace('.md', '')
        if role_filter and role != role_filter:
            continue

        try:
            with open(md_file, 'r', errors='replace') as f:
                content = f.read()
        except Exception:
            continue

        # Split by feature sections
        sections = re.split(r'^## (F\S+.*)', content, flags=re.MULTILINE)
        # sections[0] = header, then alternating: title, body, title, body...
        for i in range(1, len(sections) - 1, 2):
            feature_line = sections[i].strip()
            body = sections[i + 1].strip() if i + 1 < len(sections) else ''

            # Extract feature ID
            feature_match = re.match(r'(F\S+)', feature_line)
            feature = feature_match.group(1) if feature_match else feature_line

            # Search
            full_text = (feature_line + ' ' + body).lower()
            if all(kw in full_text for kw in keywords.split()):
                # Extract first meaningful line as context
                context_lines = [l.strip() for l in body.split('\n') if l.strip() and not l.strip().startswith('#')]
                context = context_lines[0][:120] if context_lines else body[:120]

                results.append({
                    'project': name,
                    'role': role,
                    'feature': feature,
                    'context': context
                })

                if len(results) >= limit:
                    break
        if len(results) >= limit:
            break
    if len(results) >= limit:
        break

if json_mode:
    print(json.dumps(results, indent=2))
else:
    if not results:
        print('No results found.')
    else:
        for r in results:
            print(f\"[{r['project']}] {r['role']} {r['feature']}: {r['context']}\")
" "$REGISTRY_FILE_PY" "$keywords" "$role_filter" "$project_filter" "$((json_mode))" "$limit"
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

cmd_help() {
  cat <<'EOF'
USAGE:
  didio mesh <subcommand> [args...]

SUBCOMMANDS:
  register <path>              Register a project in the knowledge mesh
  unregister <name>            Remove a project from the mesh
  list [--json]                Show all registered projects
  sync [--dry-run]             Export local learnings + import from all siblings
  query <keywords> [OPTIONS]   Search learnings across all registered projects

QUERY OPTIONS:
  --role <role>        Filter by agent role (architect, developer, etc.)
  --project <name>     Filter by project name
  --json               Output as JSON array
  --limit <N>          Max results (default: 20)

REGISTRY:
  Stored at ~/.didio/mesh-registry.json (user-level, shared across projects)

CONFIGURATION (didio.config.json):
  mesh.enabled                 Enable/disable mesh features
  mesh.registry_path           Override registry location
  mesh.auto_sync_on_retro      Auto-sync after retrospective ceremony
EOF
}

# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------

SUB="${1:-help}"
shift || true

case "$SUB" in
  register)    cmd_register "$@" ;;
  unregister)  cmd_unregister "$@" ;;
  list)        cmd_list "$@" ;;
  sync)        cmd_sync "$@" ;;
  query)       cmd_query "$@" ;;
  help|--help|-h) cmd_help ;;
  *)
    echo "[mesh] Unknown subcommand '$SUB'. Try 'didio mesh help'." >&2
    exit 1
    ;;
esac
