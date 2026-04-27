#!/usr/bin/env bash
# didio-sync-project.sh — idempotent framework sync for a downstream project
# Usage: didio-sync-project.sh <target-project-path>
#
# Syncs templates from DIDIO_HOME/templates/ into the target project.
# Safe: never deletes files, never overwrites files with real content.
#
# Operations (in order):
#   1.  Validate target is a git repo
#   2.  Create rollback git tag pre-didio-sync-YYYYMMDD
#   3.  Sync .claude/agents/
#   4.  Sync .claude/commands/
#   5.  Merge .claude/settings.json allow arrays
#   6.  Sync root agents/
#   7.  Sync docs/adr/
#   8.  Sync docs/diagrams/templates/
#   9.  Sync docs/prd/template.md
#   10. Sync memory/agent-learnings/ (preserve real content)
#   11. Create logs/agents/.gitkeep
#   12. Sync tasks/features/FXX-template/
#   12b. Merge didio.config.json top-level blocks (session_guard, etc.)
#   13. Append .gitignore entries
#   14. Section-level CLAUDE.md sync
#   15. Print colored summary

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
DIDIO_HOME="${DIDIO_HOME:-/Users/eduardodidio/claude-didio-config}"
TEMPLATES="$DIDIO_HOME/templates"

# ---------------------------------------------------------------------------
# --dry-run flag (F09-T05 gap, implemented in T08)
# ---------------------------------------------------------------------------
DRY_RUN=0
REAL_ARGS=()
for _arg in "$@"; do
  if [[ "$_arg" == "--dry-run" ]]; then
    DRY_RUN=1
  else
    REAL_ARGS+=("$_arg")
  fi
done
TARGET="${REAL_ARGS[0]:-}"

# ---------------------------------------------------------------------------
# Counters and action log
# ---------------------------------------------------------------------------
COUNT_ADDED=0
COUNT_MERGED=0
COUNT_APPENDED=0
COUNT_SKIPPED=0
COUNT_NOCHANGE=0
declare -a SUMMARY_LINES=()

log_action() {
  local label="$1"
  local detail="$2"
  SUMMARY_LINES+=("$label|$detail")
  case "$label" in
    ADDED)     COUNT_ADDED=$((COUNT_ADDED + 1)) ;;
    MERGED)    COUNT_MERGED=$((COUNT_MERGED + 1)) ;;
    APPENDED)  COUNT_APPENDED=$((COUNT_APPENDED + 1)) ;;
    SKIPPED)   COUNT_SKIPPED=$((COUNT_SKIPPED + 1)) ;;
    NO_CHANGE) COUNT_NOCHANGE=$((COUNT_NOCHANGE + 1)) ;;
  esac
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# copy_if_missing <src> <dst> [display-label]
copy_if_missing() {
  local src="$1"
  local dst="$2"
  local label="${3:-${dst#$TARGET/}}"

  if [[ ! -f "$src" ]]; then
    echo -e "${YELLOW}[WARN]${RESET} Template source missing: $src — skipping" >&2
    return 0
  fi

  if [[ -f "$dst" ]]; then
    log_action "NO_CHANGE" "$label (already exists)"
  else
    if [[ $DRY_RUN -eq 0 ]]; then
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
    fi
    log_action "ADDED" "$label"
  fi
}

# sync_dir <src_dir> <dst_dir> — copy-if-missing for every file in src_dir
sync_dir() {
  local src_dir="$1"
  local dst_dir="$2"

  if [[ ! -d "$src_dir" ]]; then
    echo -e "${YELLOW}[WARN]${RESET} Template dir missing: $src_dir — skipping" >&2
    return 0
  fi

  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$dst_dir"
  fi
  while IFS= read -r -d '' src_file; do
    local rel="${src_file#$src_dir/}"
    local dst_file="$dst_dir/$rel"
    copy_if_missing "$src_file" "$dst_file" "${dst_file#$TARGET/}"
  done < <(find "$src_dir" -type f -print0 | sort -z)
}

# extract_section <header> <template_file>
# Prints from the header line to the next ## header (exclusive) or EOF.
extract_section() {
  local header="$1"
  local template="$2"
  awk -v h="$header" '
    found && /^## / { exit }
    $0 == h { found=1 }
    found { print }
  ' "$template"
}

# ---------------------------------------------------------------------------
# 1. Validate target
# ---------------------------------------------------------------------------
if [[ -z "$TARGET" ]]; then
  echo -e "${RED}ERROR:${RESET} Usage: didio-sync-project.sh <target-project-path>" >&2
  exit 1
fi

if [[ ! -d "$TARGET" ]]; then
  echo -e "${RED}ERROR:${RESET} $TARGET is not a directory. Aborting." >&2
  exit 1
fi

if ! git -C "$TARGET" rev-parse --git-dir &>/dev/null; then
  echo -e "${RED}ERROR:${RESET} $TARGET is not a git repository. Aborting." >&2
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"  # resolve absolute path
PROJECT_NAME="$(basename "$TARGET")"

echo -e "${BOLD}=== didio-sync-project: $PROJECT_NAME ===${RESET}"
echo -e "Source : $TEMPLATES"
echo -e "Target : $TARGET"
if [[ $DRY_RUN -eq 1 ]]; then
  echo -e "${YELLOW}DRY-RUN MODE — no files will be written${RESET}"
fi
echo

# ---------------------------------------------------------------------------
# 2. Create rollback git tag
# ---------------------------------------------------------------------------
TAG="pre-didio-sync-$(date +%Y%m%d)"
if [[ $DRY_RUN -eq 1 ]]; then
  echo -e "${GREEN}[TAG]${RESET} DRY-RUN: would create rollback tag: $TAG"
elif git -C "$TARGET" tag "$TAG" 2>/dev/null; then
  echo -e "${GREEN}[TAG]${RESET} Created rollback tag: $TAG"
else
  echo -e "${CYAN}[TAG]${RESET} Rollback tag already exists (preserved): $TAG"
fi

# ---------------------------------------------------------------------------
# 3. Sync .claude/agents/
# ---------------------------------------------------------------------------
sync_dir "$TEMPLATES/.claude/agents" "$TARGET/.claude/agents"

# ---------------------------------------------------------------------------
# 4. Sync .claude/commands/
# ---------------------------------------------------------------------------
sync_dir "$TEMPLATES/.claude/commands" "$TARGET/.claude/commands"

# ---------------------------------------------------------------------------
# 5. Sync .claude/settings.json
# ---------------------------------------------------------------------------
SRC_SETTINGS="$TEMPLATES/.claude/settings.json"
DST_SETTINGS="$TARGET/.claude/settings.json"

if [[ ! -f "$SRC_SETTINGS" ]]; then
  echo -e "${YELLOW}[WARN]${RESET} Template settings.json missing — skipping" >&2
elif [[ ! -f "$DST_SETTINGS" ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$TARGET/.claude"
    cp "$SRC_SETTINGS" "$DST_SETTINGS"
  fi
  log_action "ADDED" ".claude/settings.json"
else
  # Merge permissions.allow arrays (union, no duplicates) using python3
  if command -v python3 &>/dev/null; then
    MERGE_RESULT=$(python3 - "$SRC_SETTINGS" "$DST_SETTINGS" "$DRY_RUN" <<'PY'
import json, sys

src_path, dst_path = sys.argv[1], sys.argv[2]
dry_run = len(sys.argv) > 3 and sys.argv[3] == "1"
with open(src_path) as f:
    src = json.load(f)
with open(dst_path) as f:
    dst = json.load(f)

# Merge permissions.allow
src_allow = src.get("permissions", {}).get("allow", [])
dst_allow = dst.get("permissions", {}).get("allow", [])
new_entries = [e for e in src_allow if e not in dst_allow]

if new_entries:
    if "permissions" not in dst:
        dst["permissions"] = {}
    if "allow" not in dst["permissions"]:
        dst["permissions"]["allow"] = []
    dst["permissions"]["allow"].extend(new_entries)

# Merge hooks with dedupe by command
src_hooks = src.get("hooks", {})
dst_hooks = dst.get("hooks", {})
hooks_added = 0

for event, src_matchers in src_hooks.items():
    dst_matchers = dst_hooks.setdefault(event, [])
    existing_cmds = {
        h.get("command")
        for m in dst_matchers
        for h in m.get("hooks", [])
        if h.get("command")
    }
    for src_matcher in src_matchers:
        src_matcher_value = src_matcher.get("matcher", "*")
        src_hook_list = src_matcher.get("hooks", [])
        target = next(
            (m for m in dst_matchers if m.get("matcher") == src_matcher_value),
            None,
        )
        for hook in src_hook_list:
            cmd = hook.get("command")
            if not cmd or cmd in existing_cmds:
                continue
            if target is None:
                target = {"matcher": src_matcher_value, "hooks": []}
                dst_matchers.append(target)
            target.setdefault("hooks", []).append(hook)
            existing_cmds.add(cmd)
            hooks_added += 1

# Merge permissions.deny (F09 scan-exclusion)
src_deny = src.get("permissions", {}).get("deny", [])
dst_deny = dst.get("permissions", {}).get("deny", [])
new_deny = [e for e in src_deny if e not in dst_deny]
exclusion_added = 0
if new_deny:
    if "permissions" not in dst:
        dst["permissions"] = {}
    if "deny" not in dst["permissions"]:
        dst["permissions"]["deny"] = []
    dst["permissions"]["deny"].extend(new_deny)
    exclusion_added = len(new_deny)

if new_entries or hooks_added or new_deny:
    if not dry_run:
        if hooks_added:
            dst["hooks"] = dst_hooks
        with open(dst_path, "w") as f:
            json.dump(dst, f, indent=2)
            f.write("\n")
    print(f"MERGED:perms={len(new_entries)},hooks={hooks_added},excl={exclusion_added}")
else:
    print("NO_CHANGE")
PY
    )
    if [[ "$MERGE_RESULT" == "NO_CHANGE" ]]; then
      log_action "NO_CHANGE" ".claude/settings.json"
    elif [[ "$MERGE_RESULT" =~ ^MERGED:perms=([0-9]+),hooks=([0-9]+),excl=([0-9]+)$ ]]; then
      NP="${BASH_REMATCH[1]}"
      NH="${BASH_REMATCH[2]}"
      NE="${BASH_REMATCH[3]}"
      log_action "MERGED" ".claude/settings.json ($NP permissions + $NH hooks + $NE deny-exclusions added)"
    fi
  else
    echo -e "${YELLOW}[WARN]${RESET} python3 not available — skipping settings.json merge" >&2
    log_action "SKIPPED" ".claude/settings.json (python3 not available for merge)"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Sync root agents/
# ---------------------------------------------------------------------------
copy_if_missing "$TEMPLATES/agents/orchestrator.md" "$TARGET/agents/orchestrator.md"
sync_dir "$TEMPLATES/agents/prompts"    "$TARGET/agents/prompts"
sync_dir "$TEMPLATES/agents/workflows"  "$TARGET/agents/workflows"

# ---------------------------------------------------------------------------
# 7. Sync docs/adr/
# ---------------------------------------------------------------------------
# If docs/ADR/ (uppercase) exists, skip to avoid confusion — leave as-is.
# Use ls + grep -x for a case-sensitive check (macOS FS is case-insensitive
# but case-preserving, so this matches the actual stored directory name).
if [[ -d "$TARGET/docs" ]] && ls "$TARGET/docs/" 2>/dev/null | grep -qx "ADR"; then
  echo -e "${CYAN}[INFO]${RESET} docs/ADR/ (uppercase) exists — skipping docs/adr/ creation"
  log_action "SKIPPED" "docs/adr/ (docs/ADR/ already exists)"
else
  copy_if_missing "$TEMPLATES/docs/adr/0000-template.md" \
    "$TARGET/docs/adr/0000-template.md"
  copy_if_missing "$TEMPLATES/docs/adr/0001-adopt-claude-didio-framework.md" \
    "$TARGET/docs/adr/0001-adopt-claude-didio-framework.md"
fi

# ---------------------------------------------------------------------------
# 8. Sync docs/diagrams/templates/
# ---------------------------------------------------------------------------
sync_dir "$TEMPLATES/docs/diagrams/templates" "$TARGET/docs/diagrams/templates"

# ---------------------------------------------------------------------------
# 9. Sync docs/prd/ (templates: PRD output + elicit questions)
# ---------------------------------------------------------------------------
copy_if_missing "$TEMPLATES/docs/prd/template.md" "$TARGET/docs/prd/template.md"
copy_if_missing "$TEMPLATES/docs/prd/elicit-questions.md" "$TARGET/docs/prd/elicit-questions.md"

# ---------------------------------------------------------------------------
# 10. Sync memory/agent-learnings/ (preserve files with real content)
# ---------------------------------------------------------------------------
TEMPLATE_LEARNINGS="$TEMPLATES/memory/agent-learnings"
TARGET_LEARNINGS="$TARGET/memory/agent-learnings"
if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$TARGET_LEARNINGS"
fi

for role in architect developer techlead qa readiness tea; do
  src="$TEMPLATE_LEARNINGS/$role.md"
  dst="$TARGET_LEARNINGS/$role.md"

  if [[ ! -f "$src" ]]; then
    echo -e "${YELLOW}[WARN]${RESET} Template missing: $src" >&2
    continue
  fi

  if [[ ! -f "$dst" ]]; then
    if [[ $DRY_RUN -eq 0 ]]; then
      cp "$src" "$dst"
    fi
    log_action "ADDED" "memory/agent-learnings/$role.md"
  else
    # Placeholder detection: file has ≤ 5 non-empty lines
    lines=$(grep -c '\S' "$dst" 2>/dev/null || true)
    if [[ "$lines" -le 5 ]]; then
      if cmp -s "$src" "$dst"; then
        log_action "NO_CHANGE" "memory/agent-learnings/$role.md (placeholder, up to date)"
      else
        if [[ $DRY_RUN -eq 0 ]]; then
          cp "$src" "$dst"
        fi
        log_action "ADDED" "memory/agent-learnings/$role.md (placeholder replaced)"
      fi
    else
      log_action "SKIPPED" "memory/agent-learnings/$role.md (has content)"
    fi
  fi
done

# ---------------------------------------------------------------------------
# 11. Sync logs/agents/.gitkeep
# ---------------------------------------------------------------------------
# Guard: if logs/ exists as a plain file (not a directory), skip silently.
if [[ -e "$TARGET/logs" && ! -d "$TARGET/logs" ]]; then
  echo -e "${YELLOW}[WARN]${RESET} $TARGET/logs exists as a file, not a directory — skipping logs/agents/.gitkeep" >&2
  log_action "SKIPPED" "logs/agents/.gitkeep (logs is a file)"
else
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$TARGET/logs/agents"
  fi
  if [[ ! -f "$TARGET/logs/agents/.gitkeep" ]]; then
    if [[ $DRY_RUN -eq 0 ]]; then
      mkdir -p "$TARGET/logs/agents"
      touch "$TARGET/logs/agents/.gitkeep"
    fi
    log_action "ADDED" "logs/agents/.gitkeep"
  else
    log_action "NO_CHANGE" "logs/agents/.gitkeep (already exists)"
  fi
fi

# ---------------------------------------------------------------------------
# 12. Sync tasks/features/FXX-template/
# ---------------------------------------------------------------------------
SRC_TASK_TPL="$TEMPLATES/tasks/features/FXX-template"
DST_TASK_TPL="$TARGET/tasks/features/FXX-template"
if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$TARGET/tasks/features"
fi

if [[ ! -d "$DST_TASK_TPL" ]]; then
  if [[ -d "$SRC_TASK_TPL" ]]; then
    if [[ $DRY_RUN -eq 0 ]]; then
      mkdir -p "$TARGET/tasks/features"
      cp -r "$SRC_TASK_TPL" "$DST_TASK_TPL"
    fi
    log_action "ADDED" "tasks/features/FXX-template/"
  else
    echo -e "${YELLOW}[WARN]${RESET} Template tasks/features/FXX-template/ missing — skipping" >&2
  fi
else
  log_action "NO_CHANGE" "tasks/features/FXX-template/ (already exists)"
fi

# ---------------------------------------------------------------------------
# 12b. Merge didio.config.json — add missing top-level blocks (idempotent).
#      Preserves any keys the user has customized; only adds new ones
#      (e.g. session_guard from F07) when the block is absent.
# ---------------------------------------------------------------------------
SRC_CFG="$TEMPLATES/didio.config.json"
DST_CFG="$TARGET/didio.config.json"

if [[ ! -f "$SRC_CFG" ]]; then
  echo -e "${YELLOW}[WARN]${RESET} Template didio.config.json missing — skipping" >&2
elif [[ ! -f "$DST_CFG" ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    cp "$SRC_CFG" "$DST_CFG"
  fi
  log_action "ADDED" "didio.config.json"
else
  MERGE_CFG_RESULT=$(python3 - "$SRC_CFG" "$DST_CFG" "$DRY_RUN" <<'PY'
import json, sys
src_path, dst_path = sys.argv[1], sys.argv[2]
dry_run = len(sys.argv) > 3 and sys.argv[3] == "1"
with open(src_path) as f:
    src = json.load(f)
with open(dst_path) as f:
    dst = json.load(f)
added = []
# Top-level block merge: only add keys that don't already exist at the root.
# We do NOT recurse — users may have nested customizations, and we must
# not stomp them. The F07 session_guard block is the typical case here.
for k, v in src.items():
    if k not in dst:
        dst[k] = v
        added.append(k)
if added:
    if not dry_run:
        with open(dst_path, "w") as f:
            json.dump(dst, f, indent=2)
            f.write("\n")
    print("MERGED:" + ",".join(added))
else:
    print("NO_CHANGE")
PY
  )
  if [[ "$MERGE_CFG_RESULT" == "NO_CHANGE" ]]; then
    log_action "NO_CHANGE" "didio.config.json"
  elif [[ "$MERGE_CFG_RESULT" =~ ^MERGED:(.+)$ ]]; then
    log_action "MERGED" "didio.config.json (added: ${BASH_REMATCH[1]})"
  fi
fi

# ---------------------------------------------------------------------------
# 13. Append .gitignore entries
# ---------------------------------------------------------------------------
GITIGNORE="$TARGET/.gitignore"
GITIGNORE_ENTRIES=(
  "logs/agents/*.jsonl"
  "logs/agents/*.meta.json"
  "logs/agents/state.json"
  "archive/"
  "claude-didio-out/"
)
APPENDED_GITIGNORE=0
declare -a NEW_GITIGNORE_ENTRIES=()

if [[ $DRY_RUN -eq 0 ]]; then
  [[ ! -f "$GITIGNORE" ]] && touch "$GITIGNORE"
fi

for entry in "${GITIGNORE_ENTRIES[@]}"; do
  if [[ ! -f "$GITIGNORE" ]] || ! grep -qF "$entry" "$GITIGNORE"; then
    if [[ $DRY_RUN -eq 0 ]]; then
      echo "$entry" >> "$GITIGNORE"
    else
      echo -e "  ${CYAN}[APPEND-PENDING]${RESET} .gitignore: $entry"
    fi
    NEW_GITIGNORE_ENTRIES+=("$entry")
    APPENDED_GITIGNORE=$((APPENDED_GITIGNORE + 1))
  fi
done

if [[ $APPENDED_GITIGNORE -gt 0 ]]; then
  log_action "APPENDED" ".gitignore ($APPENDED_GITIGNORE entries added: ${NEW_GITIGNORE_ENTRIES[*]})"
else
  log_action "NO_CHANGE" ".gitignore"
fi

# ---------------------------------------------------------------------------
# 14. CLAUDE.md — section-level sync
# ---------------------------------------------------------------------------
TARGET_CLAUDE="$TARGET/CLAUDE.md"
TEMPLATE_CLAUDE="$TEMPLATES/CLAUDE.md.tmpl"

if [[ ! -f "$TEMPLATE_CLAUDE" ]]; then
  echo -e "${YELLOW}[WARN]${RESET} CLAUDE.md.tmpl missing — skipping CLAUDE.md sync" >&2
elif [[ ! -f "$TARGET_CLAUDE" ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    cp "$TEMPLATE_CLAUDE" "$TARGET_CLAUDE"
  fi
  log_action "ADDED" "CLAUDE.md (full template)"
else
  SECTIONS=(
    "## Agent Workflow"
    "## Project Layout"
    "## Documentation Maintenance Rules"
    "## Agent Learnings (Retrospective)"
    "## Guardrails de Segurança"
  )

  for section_header in "${SECTIONS[@]}"; do
    if ! grep -qF "$section_header" "$TARGET_CLAUDE"; then
      if [[ $DRY_RUN -eq 0 ]]; then
        {
          echo ""
          extract_section "$section_header" "$TEMPLATE_CLAUDE"
        } >> "$TARGET_CLAUDE"
      fi
      log_action "APPENDED" "CLAUDE.md (section: $section_header)"
    else
      log_action "NO_CHANGE" "CLAUDE.md (section: $section_header already present)"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 16. Sync bin/didio-archive-feature.sh
# ---------------------------------------------------------------------------
SRC_ARCH="$TEMPLATES/bin/didio-archive-feature.sh"
DST_ARCH="$TARGET/bin/didio-archive-feature.sh"
if [[ -f "$SRC_ARCH" ]]; then
  if [[ ! -f "$DST_ARCH" ]]; then
    if [[ $DRY_RUN -eq 0 ]]; then
      mkdir -p "$(dirname "$DST_ARCH")"
      cp "$SRC_ARCH" "$DST_ARCH"
      chmod +x "$DST_ARCH"
    fi
    log_action "ADDED" "bin/didio-archive-feature.sh"
  else
    log_action "NO_CHANGE" "bin/didio-archive-feature.sh (already exists)"
  fi
else
  echo -e "${YELLOW}[WARN]${RESET} Template bin/didio-archive-feature.sh missing — skipping" >&2
fi

# ---------------------------------------------------------------------------
# 15. Print colored summary
# ---------------------------------------------------------------------------
echo
echo -e "${BOLD}=== didio-sync-project summary for $PROJECT_NAME ===${RESET}"

for entry in "${SUMMARY_LINES[@]}"; do
  label="${entry%%|*}"
  detail="${entry#*|}"
  case "$label" in
    ADDED)
      echo -e "  ${GREEN}[ADDED]${RESET}     $detail" ;;
    MERGED)
      echo -e "  ${CYAN}[MERGED]${RESET}    $detail" ;;
    APPENDED)
      echo -e "  ${CYAN}[APPENDED]${RESET}  $detail" ;;
    SKIPPED)
      echo -e "  ${YELLOW}[SKIPPED]${RESET}   $detail" ;;
    NO_CHANGE)
      echo -e "  [NO CHANGE] $detail" ;;
    *)
      echo -e "  [$label] $detail" ;;
  esac
done

echo
echo -e "Total: ${GREEN}$COUNT_ADDED added${RESET}, ${CYAN}$COUNT_MERGED merged${RESET}," \
  "${CYAN}$COUNT_APPENDED appended${RESET}, ${YELLOW}$COUNT_SKIPPED skipped${RESET}," \
  "$COUNT_NOCHANGE no-change"

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  echo "DRY-RUN ONLY. Real sync pending human approval."
fi
