#!/usr/bin/env bash

###############################################################################
# CLIPBOARD                                                                   #
###############################################################################

# copy_rg_paths
# -------------------------------
# Uses ripgrep (rg) to search for a pattern and copies all file paths
# that contain at least one match to the clipboard via pbcopy.
# Each file path is placed on its own line (newline-separated).
# Examples:
#   copy_rg_paths "Sentry\.init" .
#   copy_rg_paths "TODO"
function copy_rg_paths() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: copy_rg_paths <pattern> [path...]" >&2
    return 1
  fi

  local pattern=$1
  shift

  # rg -l => one file per line; sort -u removes duplicates
  rg -l --color=never "$pattern" "${@:-.}" | sort -u | pbcopy
}

# Yank working directory to clipboard (escapes special chars for shell use)
function ywd() {
  local target="$(pwd)"
  [[ -n "$1" ]] && target="$target/$1"
  if [[ ! -e "$target" ]]; then
    echo "❌ Path does not exist: $target" >&2
    return 1
  fi
  local display_path="${target/#$HOME/~}"
  local escaped_path="${display_path// /\\ }"
  escaped_path="${escaped_path//\(/\\(}"
  escaped_path="${escaped_path//)/\\)}"
  echo -n "$escaped_path" | pbcopy
  printf "📋 Copied: \e[36m%s\e[0m\n" "$escaped_path"
}
