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
  [[ -n "$pattern" ]] && entries=$(grep -iF -- "$pattern" <<<"$entries")

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
  [[ -n "$pattern" ]] && entries=$(grep -iF -- "$pattern" <<<"$entries")

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
  entries=$(
    env | LC_ALL=C sort | awk -F= '
      function is_secret(key) {
        key = toupper(key)
        return key ~ /(^|_)(API_)?KEY($|_)|TOKEN|SECRET|PASS(WORD)?|PRIVATE|SESSION|COOKIE|CREDENTIAL|AUTH|MNEMONIC|SEED/
      }
      {
        key = $1
        if (is_secret(key)) {
          print key "=<redacted>"
        } else {
          print
        }
      }
    '
  )

  # Apply pattern filter if provided
  [[ -n "$pattern" ]] && entries=$(grep -iF -- "$pattern" <<<"$entries")

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

###############################################################################
# TELEVISION WIDGETS                                                          #
###############################################################################

function _prb_shell_quote() {
  printf "%q" "$1"
}

function _prb_tv_insert_or_run() {
  local command_prefix="$1"
  local value="$2"
  local quoted

  [[ -n "$value" ]] || return 0
  quoted=$(_prb_shell_quote "$value")

  if ! command -v zle >/dev/null 2>&1 || ! zle -R 2>/dev/null; then
    printf "%s%s\n" "$command_prefix" "$quoted"
    return 0
  fi

  if [[ -z "$BUFFER" ]]; then
    BUFFER="${command_prefix}${quoted}"
    # shellcheck disable=SC2034 # zle uses CURSOR as the command-line cursor position.
    CURSOR=${#BUFFER}
    zle accept-line
  else
    LBUFFER+="$quoted"
    zle reset-prompt
  fi
}

function _prb_tv_select() {
  tv "$@"
}

function prb-tv-file-widget() {
  local file
  file=$(_prb_tv_select files "$PWD") || return 0
  _prb_tv_insert_or_run "${VISUAL:-${EDITOR:-nvim}} -- " "$file"
}

function prb-tv-dir-widget() {
  local dir
  dir=$(_prb_tv_select dirs) || return 0
  _prb_tv_insert_or_run "cd -- " "$dir"
}

function prb-tv-repo-widget() {
  local repo
  repo=$(_prb_tv_select git-repos) || return 0
  _prb_tv_insert_or_run "cd -- " "$repo"
}

function prb-tv-branch-widget() {
  local branch
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  branch=$(_prb_tv_select git-branch) || return 0
  _prb_tv_insert_or_run "git switch -- " "$branch"
}

function prb-tv-just-widget() {
  local recipe
  [[ -f justfile || -f .justfile ]] || return 0
  recipe=$(
    tv --source-command "just --summary | tr ' ' '\\n'" \
      --source-display "{}" \
      --source-output "{}" \
      --preview-command "just --show {}" \
      --input-header "just"
  ) || return 0
  _prb_tv_insert_or_run "just " "$recipe"
}
