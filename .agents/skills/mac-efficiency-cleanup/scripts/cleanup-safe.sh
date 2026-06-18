#!/usr/bin/env bash

set -uo pipefail

mode="dry-run"

usage() {
  echo "Usage: cleanup-safe.sh [--dry-run|--execute]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    mode="dry-run"
    ;;
  --execute)
    mode="execute"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
  esac
  shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "mac-efficiency-cleanup cleanup is macOS-only" >&2
  exit 1
fi

run_or_skip() {
  local command_name="$1"
  shift

  if command -v "$command_name" >/dev/null 2>&1; then
    "$@"
  else
    printf 'skip: %s not found\n' "$command_name"
  fi
}

limit_lines() {
  local max="${1:-250}"
  local max_chars="${2:-1200}"
  awk -v max="$max" -v max_chars="$max_chars" '
    function emit(line) {
      if (length(line) > max_chars) {
        print substr(line, 1, max_chars) "... line truncated ..."
      } else {
        print line
      }
    }
    NR <= max { emit($0) }
    /would free approximately/ { summary = $0 }
    END {
      if (NR > max) {
        print "... output truncated ..."
        if (summary != "") {
          print summary
        }
      }
    }'
}

print_plan() {
  echo "Safe cleanup set:"
  echo "  brew cleanup --prune=\"\${HOMEBREW_CLEANUP_MAX_AGE_DAYS:-30}\""
  echo "  uv cache prune"
  echo "  pnpm store prune"
  echo "  go clean -cache -testcache"
  echo
  echo "Excluded: Helium cache, browser profiles, editor state/history, 1Password, Google Drive, wallets, chat histories, model stores, Docker, CoreSimulator, npm, and Bun."
}

if [[ "$mode" == "dry-run" ]]; then
  print_plan
  echo
  echo "Dry-run previews:"
  if command -v brew >/dev/null 2>&1; then
    brew cleanup --dry-run --prune="${HOMEBREW_CLEANUP_MAX_AGE_DAYS:-30}" | limit_lines 80
  else
    echo "skip: brew not found"
  fi
  if command -v go >/dev/null 2>&1; then
    go clean -n -cache -testcache | limit_lines 5 1000
  else
    echo "skip: go not found"
  fi
  echo "+ uv cache prune    # dry-run unavailable; not executed"
  echo "+ pnpm store prune  # dry-run unavailable; not executed"
  exit 0
fi

print_plan
echo
printf 'Type "clean safe caches" to execute: '
read -r confirm
if [[ "$confirm" != "clean safe caches" ]]; then
  echo "Aborted."
  exit 1
fi

if command -v brew >/dev/null 2>&1; then
  brew cleanup --prune="${HOMEBREW_CLEANUP_MAX_AGE_DAYS:-30}"
else
  echo "skip: brew not found"
fi

run_or_skip uv uv cache prune
run_or_skip pnpm pnpm store prune
run_or_skip go go clean -cache -testcache
