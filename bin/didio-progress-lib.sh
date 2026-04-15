#!/usr/bin/env bash
# didio-progress-lib.sh — thin bash wrapper around didio-progress.py.
# Source it to get didio_feature_progress, or run directly.

didio_feature_progress() {
  local feature="${1:?feature-id required}"
  local root="${DIDIO_PROGRESS_ROOT:-$(pwd)}"
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  python3 "$script_dir/didio-progress.py" --root "$root" --feature "$feature" --line
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  didio_feature_progress "${1:?feature-id required (e.g. F01)}"
fi
