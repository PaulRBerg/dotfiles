#!/usr/bin/env bash

set -uo pipefail

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

du_kib() {
  local path="$1"
  local timeout_seconds="${MAC_CLEANUP_DU_TIMEOUT_SECONDS:-20}"

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_seconds" du -sk "$path"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" du -sk "$path"
  else
    du -sk "$path"
  fi
}

section() {
  printf '\n## %s\n' "$1"
}

format_kib_stream() {
  awk '{
    size = $1
    $1 = ""
    sub(/^ /, "")
    if (size >= 1048576) {
      printf "%8.1fG  %s\n", size / 1048576, $0
    } else if (size >= 1024) {
      printf "%8.1fM  %s\n", size / 1024, $0
    } else {
      printf "%8dK  %s\n", size, $0
    }
  }'
}

cache_root() {
  local root="$1"
  local limit="${2:-20}"
  local max_kib="${MAC_CLEANUP_TOP_CHILDREN_MAX_KIB:-52428800}"
  local root_kib

  printf '\n== %s ==\n' "$root"
  if [[ ! -d "$root" ]]; then
    echo "missing"
    return 0
  fi

  root_kib=$(du_kib "$root" 2>/dev/null | awk '{ print $1 }')
  if [[ -z "$root_kib" ]]; then
    echo "timed out or unreadable"
    return 0
  fi

  printf '%s\t%s\n' "$root_kib" "$root" | format_kib_stream

  if ((root_kib > max_kib)); then
    echo "top children skipped: root exceeds $((max_kib / 1048576))G"
    return 0
  fi

  find "$root" -mindepth 1 -maxdepth 1 -exec du -sk {} + 2>/dev/null |
    sort -rn |
    head -n "$limit" |
    format_kib_stream
}

list_dir_entries() {
  local dir="$1"

  if command -v fd >/dev/null 2>&1; then
    fd -H -d 1 . "$dir" -x basename {} | sort
  else
    find "$dir" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort
  fi
}

run_if_present() {
  local command_name="$1"
  shift

  if command -v "$command_name" >/dev/null 2>&1; then
    "$@"
  else
    printf 'skip: %s not found\n' "$command_name"
  fi
}

cleanup_tool() {
  if command -v mac-cleanup >/dev/null 2>&1; then
    echo mac-cleanup
  elif command -v mac-cleanup-go >/dev/null 2>&1; then
    echo mac-cleanup-go
  else
    return 1
  fi
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "mac-efficiency-cleanup audit is macOS-only" >&2
  exit 1
fi

section "System"
run_if_present sw_vers sw_vers
uptime
df -h / /System/Volumes/Data 2>/dev/null || df -h /

section "Cache Sizes"
cache_root "$HOME/Library/Caches"
cache_root "${XDG_CACHE_HOME:-$HOME/.cache}"
cache_root "$HOME/Library/Logs"
cache_root "$HOME/Library/Developer/Xcode/DerivedData"
cache_root "$HOME/Library/Developer/CoreSimulator/Caches"
cache_root "$HOME/Library/Caches/Homebrew"

section "Homebrew Cleanup Preview"
if command -v brew >/dev/null 2>&1; then
  brew cleanup --dry-run --prune="${HOMEBREW_CLEANUP_MAX_AGE_DAYS:-30}" | limit_lines 120
else
  echo "skip: brew not found"
fi

section "mac-cleanup-go Preview"
if cleaner=$(cleanup_tool); then
  "$cleaner" --clean --dry-run | limit_lines 250
else
  echo "skip: install mac-cleanup-go"
fi

section "Brew Services"
if command -v brew >/dev/null 2>&1; then
  brew services list
else
  echo "skip: brew not found"
fi

section "Launch Registrations"
for dir in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
  printf '\n== %s ==\n' "$dir"
  if [[ -d "$dir" ]]; then
    list_dir_entries "$dir" | limit_lines
  else
    echo "missing"
  fi
done

section "Login And Background Items"
if command -v sfltool >/dev/null 2>&1; then
  sfltool dumpbtm 2>/dev/null | limit_lines 150
else
  echo "skip: sfltool not found"
fi

section "Memory Pressure"
run_if_present memory_pressure memory_pressure

section "Top CPU Processes"
ps -axo pid=,pcpu=,pmem=,rss=,comm= |
  sort -k2 -rn |
  head -n 15 |
  awk '{ printf "%7s %6s %6s %9s  %s\n", $1, $2, $3, $4, $5 }' ||
  true

section "Top RSS Processes"
ps -axo pid=,pcpu=,pmem=,rss=,comm= |
  sort -k4 -rn |
  head -n 15 |
  awk '{ printf "%7s %6s %6s %9s  %s\n", $1, $2, $3, $4, $5 }' ||
  true
