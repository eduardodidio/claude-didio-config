#!/usr/bin/env bash
# didio-archive-feature.sh — move QA-passed features to archive/
# Usage:
#   didio-archive-feature.sh <FXX>              archive a single feature
#   didio-archive-feature.sh --list             list eligible features
#   didio-archive-feature.sh --dry-run <FXX>   print actions, don't write
#   didio-archive-feature.sh --force <FXX>     bypass eligibility (interactive)
#   didio-archive-feature.sh --help            show this help

set -euo pipefail
DIDIO_HOME="${DIDIO_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$DIDIO_HOME"

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
# Helpers
# ---------------------------------------------------------------------------

# Resolve "F01" to "tasks/features/F01-dashboard" (or empty string if not found).
# Prints "AMBIGUOUS:<dir1> <dir2>" if multiple matches.
feature_dir() {
  local fxx="${1^^}"
  local real=()
  local m
  for m in tasks/features/"${fxx}"-*/; do
    [[ -d "$m" ]] && real+=("${m%/}")
  done
  if [[ ${#real[@]} -eq 0 ]]; then
    echo ""
    return 0
  fi
  if [[ ${#real[@]} -gt 1 ]]; then
    echo "AMBIGUOUS:${real[*]}"
    return 0
  fi
  echo "${real[0]}"
}

# Returns 0 if any qa-report-*.md in dir has "verdict: PASSED" (case-insensitive).
# Accepts: "verdict: PASSED", "> verdict: passed", "**Verdict:** Passed", etc.
has_passed_qa() {
  local dir="$1"
  local qa_file
  for qa_file in "$dir"/qa-report-*.md; do
    [[ -f "$qa_file" ]] || continue
    if LC_ALL=C grep -aiE '^[[:space:]>*-]*verdict[[:space:]]*:[*[:space:]]*passed' \
        "$qa_file" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# Returns age in days of the most recent commit touching dir. 99999 if no commits.
last_commit_age_days() {
  local dir="$1"
  local ts
  ts="$(git log -1 --format="%ct" -- "$dir" 2>/dev/null || true)"
  if [[ -z "$ts" ]]; then
    echo "99999"
    return 0
  fi
  local now
  now="$(date +%s)"
  echo $(( (now - ts) / 86400 ))
}

# Returns 0 if archive/features/<FXX>-* already exists.
already_archived() {
  local fxx="${1^^}"
  local m
  for m in archive/features/"${fxx}"-*/; do
    [[ -d "$m" ]] && return 0
  done
  return 1
}

# Prints the archive path for fxx (empty if not archived).
archive_dir_for() {
  local fxx="${1^^}"
  local m
  for m in archive/features/"${fxx}"-*/; do
    [[ -d "$m" ]] && echo "${m%/}" && return 0
  done
  echo ""
}

# Copies retrospective.md → memory/retrospectives/<FXX>.md.
# If absent, writes a minimal stub with a reference to the qa-report.
copy_retro() {
  local dir="$1"
  local fxx="${2^^}"
  local dry_run="${3:-0}"
  local dest="memory/retrospectives/${fxx}.md"

  if [[ -f "$dir/retrospective.md" ]]; then
    if [[ "$dry_run" == "1" ]]; then
      echo -e "  ${CYAN}[DRY_RUN]${RESET} cp $dir/retrospective.md → $dest"
    else
      cp "$dir/retrospective.md" "$dest"
      echo -e "  ${GREEN}[COPIED]${RESET} retrospective → $dest"
    fi
  else
    local qa_ref=""
    local qa_file
    for qa_file in "$dir"/qa-report-*.md; do
      [[ -f "$qa_file" ]] && qa_ref="$qa_file"
    done
    if [[ "$dry_run" == "1" ]]; then
      echo -e "  ${CYAN}[DRY_RUN]${RESET} create stub $dest (no retrospective.md found)"
    else
      {
        printf "# %s — retrospective\n" "$fxx"
        printf "(Archived without explicit retrospective; see qa-report)\n"
        [[ -n "$qa_ref" ]] && printf "Reference: %s\n" "$qa_ref"
      } > "$dest"
      echo -e "  ${YELLOW}[STUB]${RESET} created $dest (no retrospective.md found)"
    fi
  fi
}

# Moves dir to archive/features/ using git mv if tracked, mv otherwise.
move_to_archive() {
  local dir="$1"
  local dry_run="${2:-0}"
  local dest
  dest="archive/features/$(basename "$dir")"

  if [[ "$dry_run" == "1" ]]; then
    echo -e "  ${CYAN}[DRY_RUN]${RESET} move $dir → $dest"
    return 0
  fi

  if git ls-files "$dir" | head -1 | LC_ALL=C grep -q .; then
    git mv "$dir" "$dest"
    echo -e "  ${GREEN}[GIT_MV]${RESET} $dir → $dest"
  else
    mv "$dir" "$dest"
    echo -e "  ${GREEN}[MV]${RESET} $dir → $dest"
  fi
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

usage() {
  echo -e "${BOLD}didio-archive-feature.sh${RESET} — move QA-passed features to archive/"
  echo ""
  echo "Usage:"
  echo "  $(basename "$0") <FXX>              archive a single feature"
  echo "  $(basename "$0") --list             list eligible features"
  echo "  $(basename "$0") --dry-run <FXX>   print actions, don't write"
  echo "  $(basename "$0") --force <FXX>     bypass eligibility check (interactive)"
  echo "  $(basename "$0") --help            show this help"
  echo ""
  echo "Eligibility:"
  echo "  A feature is archivable when:"
  echo "    1. tasks/features/<FXX>-*/ contains at least one qa-report-*.md"
  echo "       with 'verdict: PASSED' (case-insensitive)"
  echo "    2. The last git commit touching the feature dir is >=30 days ago"
  echo ""
  echo "See also: archive/README.md"
}

do_list() {
  local found=0
  local dir name fxx age
  for dir in tasks/features/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    fxx="${name%%-*}"
    fxx="${fxx^^}"

    already_archived "$fxx" && continue

    if has_passed_qa "$dir"; then
      age="$(last_commit_age_days "$dir")"
      if [[ "$age" -ge 30 ]]; then
        echo -e "${GREEN}ELIGIBLE${RESET}  $name  (last commit ${age}d ago)"
        found=$((found + 1))
      fi
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    echo -e "${YELLOW}No eligible features found.${RESET}"
  fi
}

do_archive() {
  local fxx="${1^^}"
  local dry_run="${2:-0}"
  local force="${3:-0}"

  # Idempotence: already in archive → exit 0
  if already_archived "$fxx"; then
    local arch
    arch="$(archive_dir_for "$fxx")"
    echo -e "${CYAN}NO_CHANGE:${RESET} ${fxx} already in $arch"
    exit 0
  fi

  # Resolve feature directory
  local dir_result
  dir_result="$(feature_dir "$fxx")"

  if [[ -z "$dir_result" ]]; then
    echo -e "${RED}ERROR:${RESET} ${fxx} not found in tasks/features/" >&2
    exit 1
  fi

  if [[ "$dir_result" == AMBIGUOUS:* ]]; then
    local dirs="${dir_result#AMBIGUOUS:}"
    echo -e "${RED}ERROR:${RESET} ${fxx} matches multiple directories: $dirs. Be more specific." >&2
    exit 1
  fi

  local dir="$dir_result"

  # Eligibility checks (skipped when --force)
  if [[ "$force" != "1" ]]; then
    if ! has_passed_qa "$dir"; then
      echo -e "${RED}INELIGIBLE:${RESET} ${fxx} — no qa-report with PASSED verdict"
      echo -e "  Use ${BOLD}--force${RESET} to bypass eligibility check."
      exit 1
    fi
    local age
    age="$(last_commit_age_days "$dir")"
    if [[ "$age" -lt 30 ]]; then
      echo -e "${RED}INELIGIBLE:${RESET} ${fxx} — last commit ${age} days ago (need >=30)"
      echo -e "  Use ${BOLD}--force${RESET} to bypass eligibility check."
      exit 1
    fi
  else
    # --force: require interactive confirmation or DIDIO_FORCE_YES=1
    if [[ -t 0 ]]; then
      read -r -p "Force-archive ${fxx} (no eligibility check)? [y/N] " ans
      [[ "$ans" =~ ^[Yy] ]] || { echo "Aborted."; exit 1; }
    else
      if [[ "${DIDIO_FORCE_YES:-0}" != "1" ]]; then
        echo "ERROR: --force in non-tty mode requires DIDIO_FORCE_YES=1" >&2
        exit 2
      fi
    fi
  fi

  local name
  name="$(basename "$dir")"
  local file_count
  file_count="$(find "$dir" -type f | wc -l | tr -d ' ')"

  if [[ "$dry_run" == "1" ]]; then
    echo -e "${CYAN}[DRY_RUN]${RESET} Would archive ${BOLD}${name}${RESET} (${file_count} files):"
  else
    echo -e "${BOLD}Archiving${RESET} ${name} (${file_count} files):"
  fi

  copy_retro "$dir" "$fxx" "$dry_run"
  move_to_archive "$dir" "$dry_run"

  if [[ "$dry_run" == "1" ]]; then
    echo -e "${CYAN}[DRY_RUN]${RESET} No changes written."
  else
    echo -e "${GREEN}Done.${RESET} Archived ${name} (${file_count} files)."
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

MODE="archive"
FXX=""
DRY_RUN="0"
FORCE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --list)
      MODE="list"
      shift
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      if [[ $# -gt 0 && "$1" != --* ]]; then
        FXX="$1"
        shift
      fi
      ;;
    --force)
      FORCE="1"
      shift
      if [[ $# -gt 0 && "$1" != --* ]]; then
        FXX="$1"
        shift
      fi
      ;;
    F[0-9]*)
      FXX="$1"
      shift
      ;;
    *)
      echo -e "${RED}ERROR:${RESET} Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$MODE" in
  list)
    do_list
    ;;
  archive)
    if [[ -z "$FXX" ]]; then
      echo -e "${RED}ERROR:${RESET} Feature ID required (e.g. F01)" >&2
      usage >&2
      exit 1
    fi
    do_archive "$FXX" "$DRY_RUN" "$FORCE"
    ;;
esac
