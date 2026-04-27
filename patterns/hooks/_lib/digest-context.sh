#!/usr/bin/env bash
# patterns/hooks/_lib/digest-context.sh
# Sourced by patterns/hooks/feature-end-digest/hook.sh and
# _bootstrap/scripts/digest-pending.sh. Collects learnings, skills,
# patterns, and QA anomalies from a downstream project root and emits
# an ADR-0010-compliant drop payload (frontmatter + 4 sections).
# Zero-dependency (bash/grep/sed/awk/git/find/head/tail). Fail-soft:
# every public function returns 0 and echoes empty string on any error.
# Silent helper: stderr is never written to. Only function definitions — sourcing
# this file produces no output and no side effects.

set -u

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_DIGEST_MAX_BYTES=32768
_DIGEST_MAX_BULLETS=50
# All 9 ADR-0010 §8 canonical token patterns + xoxb (Slack) as bonus.
# Uses @ as sed delimiter so patterns with / (Discord URLs) work safely.
_DIGEST_TOKEN_PATTERNS=(
  "-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"
  "sk-ant-[A-Za-z0-9_-]{20,}"
  "sk-[A-Za-z0-9]{20,}"
  "ghp_[A-Za-z0-9]{36}"
  "glpat-[A-Za-z0-9_-]{20,}"
  "AKIA[0-9A-Z]{16}"
  "eyJ[A-Za-z0-9_-]+[.][A-Za-z0-9_-]+[.][A-Za-z0-9_-]+"
  "https://discord(app)?[.]com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+"
  "Bearer [A-Za-z0-9._-]{20,}"
  "[A-Z_]{5,}=[A-Za-z0-9_/+=\\-]{32,}"
  "xoxb-[0-9-]+"
)

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

_dc_now_iso() {
  date -u +%FT%TZ
  return 0
}

_dc_seven_days_ago_iso() {
  local result=""
  result="$(date -u -v-7d +%FT%TZ 2>/dev/null)" \
    && { echo "$result"; return 0; }
  result="$(date -u -d '7 days ago' +%FT%TZ 2>/dev/null)" \
    && { echo "$result"; return 0; }
  date -u +%FT%TZ
  return 0
}

_dc_redact_tokens() {
  # Reads stdin, writes redacted output to stdout.
  # Uses @ as delimiter so patterns containing / (e.g. Discord URLs) are safe.
  local expr=""
  local pat
  for pat in "${_DIGEST_TOKEN_PATTERNS[@]}"; do
    expr="${expr}s@${pat}@[REDACTED-TOKEN]@g;"
  done
  sed -E "$expr"
  return 0
}

# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------

collect_new_learnings() {
  local project_root="${1:-$(pwd)}"
  local feature_id="${2:-}"
  [ -n "$feature_id" ] || { echo ""; return 0; }
  [ -d "$project_root" ] || { echo ""; return 0; }

  # Locate the commit that first added the feature task files.
  local start_commit=""
  start_commit="$(git -C "$project_root" log --diff-filter=A \
    --format="%H" -- "tasks/features/${feature_id}-*" 2>/dev/null \
    | tail -1)"

  # List learning files touched since feature start.
  local touched_files=""
  if [ -n "$start_commit" ]; then
    touched_files="$(git -C "$project_root" log \
      "${start_commit}..HEAD" --pretty=format: --name-only \
      -- 'memory/agent-learnings/*.md' 2>/dev/null \
      | grep -v '^[[:space:]]*$' | sort -u)"
  else
    local since_ts
    since_ts="$(_dc_seven_days_ago_iso)"
    touched_files="$(git -C "$project_root" log \
      --since="$since_ts" --pretty=format: --name-only \
      -- 'memory/agent-learnings/*.md' 2>/dev/null \
      | grep -v '^[[:space:]]*$' | sort -u)"
  fi
  [ -n "$touched_files" ] || { echo ""; return 0; }

  local bullet_count=0
  local file diff_out in_block line content

  while IFS= read -r file; do
    [ -n "$file" ] || continue

    if [ -n "$start_commit" ]; then
      diff_out="$(git -C "$project_root" diff \
        "${start_commit}" HEAD --unified=0 -- "$file" 2>/dev/null)"
    else
      diff_out="$(git -C "$project_root" diff \
        HEAD~1 HEAD --unified=0 -- "$file" 2>/dev/null)"
    fi
    [ -n "$diff_out" ] || continue

    # Extract added lines that belong to the ## FXX section block.
    in_block=0
    while IFS= read -r line; do
      if echo "$line" | grep -q "^+## ${feature_id}"; then
        in_block=1
        continue
      fi
      if [ "$in_block" -eq 1 ] && echo "$line" | grep -q "^+## "; then
        in_block=0
        continue
      fi
      if [ "$in_block" -eq 1 ] \
          && echo "$line" | grep -q "^+" \
          && ! echo "$line" | grep -q "^+++"; then
        content="${line:1}"
        [ -n "${content// /}" ] || continue
        echo "- ${content}"
        bullet_count=$((bullet_count + 1))
        [ "$bullet_count" -lt "$_DIGEST_MAX_BULLETS" ] || break 2
      fi
    done <<< "$diff_out"
  done <<< "$touched_files"

  return 0
}

collect_new_skills() {
  local project_root="${1:-$(pwd)}"
  [ -d "$project_root" ] || { echo ""; return 0; }

  local skills_dir="${project_root}/.claude/skills"
  [ -d "$skills_dir" ] || { echo ""; return 0; }

  local project_name
  project_name="$(basename "$project_root")"

  local dir
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    [ "$dir" != "$skills_dir" ] || continue
    echo "- skill: $(basename "$dir") (em ${project_name})"
  done < <(find "$skills_dir" -maxdepth 2 -type d -mtime -7 2>/dev/null)

  return 0
}

collect_new_patterns() {
  local project_root="${1:-$(pwd)}"
  [ -d "$project_root" ] || { echo ""; return 0; }

  local patterns_dir="${project_root}/patterns"
  [ -d "$patterns_dir" ] || { echo ""; return 0; }

  local readme type_val slug
  while IFS= read -r readme; do
    [ -n "$readme" ] && [ -r "$readme" ] || continue
    type_val="$(grep -m1 -E '^type:' "$readme" 2>/dev/null \
      | sed -E "s/^type:[[:space:]]*//" | tr -d "\"'")"
    [ -n "$type_val" ] || type_val="unknown"
    slug="$(basename "$(dirname "$readme")")"
    echo "- pattern: ${type_val}/${slug}"
  done < <(find "$patterns_dir" -maxdepth 3 -name 'README.md' -mtime -7 2>/dev/null)

  return 0
}

collect_qa_anomalies() {
  local project_root="${1:-$(pwd)}"
  local feature_id="${2:-}"
  [ -n "$feature_id" ] || { echo ""; return 0; }
  [ -d "$project_root" ] || { echo ""; return 0; }

  local report=""
  report="$(ls -t "${project_root}"/tasks/features/"${feature_id}"-*/qa-report-*.md 2>/dev/null | head -1)"
  [ -n "$report" ] && [ -r "$report" ] || { echo ""; return 0; }

  local section=""
  local s
  for s in "Anomalies" "Issues" "Findings"; do
    if grep -q "^## ${s}" "$report" 2>/dev/null; then
      section="$s"
      break
    fi
  done
  [ -n "$section" ] || { echo ""; return 0; }

  local in_section=0 count=0 line
  while IFS= read -r line; do
    if echo "$line" | grep -q "^## ${section}"; then
      in_section=1
      continue
    fi
    if [ "$in_section" -eq 1 ] && echo "$line" | grep -q "^## "; then
      break
    fi
    if [ "$in_section" -eq 1 ] && echo "$line" | grep -q "^- "; then
      echo "$line"
      count=$((count + 1))
      [ "$count" -lt 10 ] || break
    fi
  done < "$report"

  return 0
}

emit_drop_payload() {
  local feature_id="${1:-}"
  local project_name="${2:-}"
  local project_root="${3:-$(pwd)}"
  [ -n "$feature_id" ] || { echo ""; return 0; }
  [ -n "$project_name" ] || { echo ""; return 0; }

  local now
  now="$(_dc_now_iso)"

  local start_commit=""
  start_commit="$(git -C "$project_root" log --diff-filter=A \
    --format="%H" -- "tasks/features/${feature_id}-*" 2>/dev/null \
    | tail -1)"

  local commits_yaml="  - (none)"$'\n'
  if [ -n "$start_commit" ]; then
    local tmp_commits="" sha
    while IFS= read -r sha; do
      [ -n "$sha" ] || continue
      tmp_commits="${tmp_commits}  - ${sha}"$'\n'
    done < <(git -C "$project_root" log \
      "${start_commit}..HEAD" --format="%H" --max-count=10 2>/dev/null)
    [ -n "$tmp_commits" ] && commits_yaml="$tmp_commits"
  fi

  local qa_report_path="null"
  local report=""
  report="$(ls -t "${project_root}"/tasks/features/"${feature_id}"-*/qa-report-*.md 2>/dev/null | head -1)"
  if [ -n "$report" ]; then
    qa_report_path="${report#"${project_root}/"}"
  fi

  local learnings skills patterns anomalies
  learnings="$(collect_new_learnings "$project_root" "$feature_id")"
  skills="$(collect_new_skills "$project_root")"
  patterns="$(collect_new_patterns "$project_root")"
  anomalies="$(collect_qa_anomalies "$project_root" "$feature_id")"

  local payload
  payload="---
feature: ${feature_id}
project: ${project_name}
created: ${now}
source_commits:
${commits_yaml}qa_report: ${qa_report_path}
digested: null
---

## Learnings

${learnings:-_(none)_}

## Skills

${skills:-_(none)_}

## Patterns

${patterns:-_(none)_}

## Anomalies

${anomalies:-_(none)_}
"

  # Redact tokens before emitting.
  payload="$(printf '%s' "$payload" | _dc_redact_tokens)"

  # Truncate drops that exceed the size limit.
  if [ "${#payload}" -gt "$_DIGEST_MAX_BYTES" ]; then
    payload="${payload:0:${_DIGEST_MAX_BYTES}}"$'\n[truncated]'
  fi

  echo "$payload"
  return 0
}
