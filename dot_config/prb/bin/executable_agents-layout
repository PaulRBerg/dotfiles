#!/usr/bin/env bash
# Open a new iTerm2 window with N split panes, each cd'd into a target directory.
# Handy for running several coding agents side by side against the same repo.

set -euo pipefail

usage() {
  echo "Usage: agents-layout [-n N] [dir]" >&2
  echo "  -n N   number of panes to open (default: 2)" >&2
  echo "  dir    directory to cd into in each pane (default: current directory)" >&2
}

panes=2
while getopts ":n:h" opt; do
  case "$opt" in
  n) panes="$OPTARG" ;;
  h)
    usage
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
  esac
done
shift $((OPTIND - 1))

if ! [[ "$panes" =~ ^[0-9]+$ ]] || ((panes < 1)); then
  echo "agents-layout: -n must be a positive integer" >&2
  exit 1
fi

target_dir="${1:-$PWD}"
if [[ ! -d "$target_dir" ]]; then
  echo "agents-layout: not a directory: $target_dir" >&2
  exit 1
fi
target_dir="$(cd "$target_dir" && pwd)"
printf -v target_dir_quoted '%q' "$target_dir"

if ! command -v it2 >/dev/null 2>&1; then
  echo "agents-layout: 'it2' CLI not found on PATH (requires the iTerm2 Python API)" >&2
  exit 1
fi

# `it2 session split`/`run` default to the active session, and a freshly created window or
# pane becomes active, so no explicit session IDs are needed here.
it2 window new >/dev/null
it2 session run "cd -- $target_dir_quoted && clear"

for ((i = 1; i < panes; i++)); do
  it2 session split --vertical >/dev/null
  it2 session run "cd -- $target_dir_quoted && clear"
done
