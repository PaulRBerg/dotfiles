#!/usr/bin/env bash

###############################################################################
# SHELL INTROSPECTION                                                         #
###############################################################################

# List shell aliases with fzf preview
# Usage: aliases [pattern]
function aliases() {
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/prb"
  local pattern="${1:-}"

  # Build list: "filename:aliasname: description"
  local entries
  entries=$(
    for f in "$config_dir"/aliases*.sh; do
      [[ -f "$f" ]] || continue
      awk -v file="$(basename "$f" .sh)" '
        /^alias [^ =]+/ {
          # Extract alias name (before =)
          name = $2
          sub(/=.*/, "", name)
          # Extract inline comment as description (after closing quote + " # ")
          desc = ""
          if (match($0, /["\047] # /)) {
            desc = substr($0, RSTART + 4)
          }
          if (desc) { print file ":" name ": " desc }
          else { print file ":" name ":" }
        }
      ' "$f"
    done | LC_ALL=C sort -t: -k2,2f -k1,1f
  )

  # Apply pattern filter if provided
  [[ -n "$pattern" ]] && entries=$(grep -i -- "$pattern" <<<"$entries")

  # Early exit if no aliases found
  if [[ -z "$entries" ]]; then
    echo "No aliases found" >&2
    return 1
  fi

  # fzf with preview showing alias definition
  # shellcheck disable=SC2016
  echo "$entries" | fzf --ansi \
    --delimiter=':' \
    --preview='
      alias_name={2}
      config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/prb"
      for f in "$config_dir"/aliases*.sh; do
        awk -v name="$alias_name" '\''
          index($0, "alias " name "=") == 1 { print; exit }
        '\'' "$f" 2>/dev/null
      done | bat --style=plain --language=bash --color=always 2>/dev/null \
           || batcat --style=plain --language=bash --color=always 2>/dev/null \
           || cat
    ' \
    --preview-window=right:60%:wrap
}

# List custom shell functions with fzf preview
# Usage: funcs [pattern]
function funcs() {
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/prb"
  local pattern="${1:-}"

  # Build list: "filename:funcname: description"
  local entries
  entries=$(
    for f in "$config_dir"/*.sh "$config_dir"/functions/*.sh; do
      [[ -f "$f" ]] || continue
      awk -v file="$(basename "$f" .sh)" '
        /^#[^!#]/ { desc = substr($0, 3) }
        /^[[:space:]]*function [a-zA-Z][a-zA-Z_]/ {
          name = $2
          gsub(/\(.*/, "", name)
          if (desc) { print file ":" name ": " desc; desc = "" }
          else { print file ":" name ":" }
        }
      ' "$f"
    done | LC_ALL=C sort -t: -k2,2f -k1,1f
  )

  # Apply pattern filter if provided
  [[ -n "$pattern" ]] && entries=$(grep -i -- "$pattern" <<<"$entries")

  # Early exit if no functions found
  if [[ -z "$entries" ]]; then
    echo "No functions found" >&2
    return 1
  fi

  # fzf with preview showing function body
  # shellcheck disable=SC2016
  echo "$entries" | fzf --ansi \
    --delimiter=':' \
    --preview='
      func={2}
      config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/prb"
      for f in "$config_dir"/*.sh "$config_dir"/functions/*.sh; do
        awk -v name="$func" '\''
          $0 ~ "^[[:space:]]*function " name "\\(" { found=1 }
          found { print; if (/^[[:space:]]*}[[:space:]]*$/) exit }
        '\'' "$f" 2>/dev/null
      done | bat --style=plain --language=bash --color=always 2>/dev/null \
           || batcat --style=plain --language=bash --color=always 2>/dev/null \
           || cat
    ' \
    --preview-window=right:60%:wrap
}

# List environment variables with fzf preview
# Usage: envs [pattern]
function envs() {
  local pattern="${1:-}"

  local entries
  entries=$(env | LC_ALL=C sort)

  # Apply pattern filter if provided
  [[ -n "$pattern" ]] && entries=$(grep -i -- "$pattern" <<<"$entries")

  # Early exit if no environment variables found
  if [[ -z "$entries" ]]; then
    echo "No environment variables found" >&2
    return 1
  fi

  # fzf with preview showing full KEY=VALUE entry
  # shellcheck disable=SC2016
  echo "$entries" | fzf --ansi \
    --delimiter='=' \
    --with-nth=1 \
    --preview='
      printf "%s\n" {} | bat --style=plain --language=sh --color=always 2>/dev/null \
           || printf "%s\n" {} | batcat --style=plain --language=sh --color=always 2>/dev/null \
           || printf "%s\n" {} | cat
    ' \
    --preview-window=right:60%:wrap
}
