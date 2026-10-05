#!/usr/bin/env bash

###############################################################################
# MACOS CLEANUP                                                               #
###############################################################################

function _mac_cleanup_require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "mac cleanup helpers are macOS-only" >&2
    return 1
  fi
}

function _mac_cleanup_tool() {
  if command -v mac-cleanup >/dev/null 2>&1; then
    echo mac-cleanup
  elif command -v mac-cleanup-go >/dev/null 2>&1; then
    echo mac-cleanup-go
  else
    return 1
  fi
}

function _mac_cleanup_limit_lines() {
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

function _mac_cleanup_du_kib() {
  local du_path="$1"
  local timeout_seconds="${MAC_CLEANUP_DU_TIMEOUT_SECONDS:-20}"

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_seconds" du -sk "$du_path"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" du -sk "$du_path"
  else
    du -sk "$du_path"
  fi
}

function _mac_cleanup_format_kib() {
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

function _mac_cleanup_du_root() {
  local root="$1"
  local limit="${2:-12}"
  local max_kib="${MAC_CLEANUP_TOP_CHILDREN_MAX_KIB:-52428800}"
  local root_kib

  echo
  echo "== ${root} =="
  if [[ ! -d "$root" ]]; then
    echo "missing"
    return 0
  fi

  root_kib=$(_mac_cleanup_du_kib "$root" 2>/dev/null | awk '{ print $1 }')
  if [[ -z "$root_kib" ]]; then
    echo "timed out or unreadable"
    return 0
  fi

  printf '%s\t%s\n' "$root_kib" "$root" | _mac_cleanup_format_kib

  if ((root_kib > max_kib)); then
    echo "top children skipped: root exceeds $((max_kib / 1048576))G"
    return 0
  fi

  find "$root" -mindepth 1 -maxdepth 1 -exec du -sk {} + 2>/dev/null |
    sort -rn |
    head -n "$limit" |
    _mac_cleanup_format_kib
}

function _mac_cleanup_list_dir() {
  local dir="$1"

  if command -v fd >/dev/null 2>&1; then
    fd -H -d 1 . "$dir" -x basename {} | sort
  else
    find "$dir" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort
  fi
}

# Review macOS cache pressure, cleanup previews, Homebrew stale downloads,
# background items, and launch registrations without deleting anything.
function mac_cleanup_review() {
  _mac_cleanup_require_macos || return

  echo "## Cache size summary"
  _mac_cleanup_du_root "$HOME/Library/Caches"
  _mac_cleanup_du_root "${XDG_CACHE_HOME:-$HOME/.cache}"
  _mac_cleanup_du_root "$HOME/Library/Logs"
  _mac_cleanup_du_root "$HOME/Library/Developer/Xcode/DerivedData"
  _mac_cleanup_du_root "$HOME/Library/Caches/Homebrew"

  echo
  echo "## mac-cleanup preview"
  local cleaner
  if cleaner=$(_mac_cleanup_tool); then
    "$cleaner" --clean --dry-run | _mac_cleanup_limit_lines
  else
    echo "skip: install mac-cleanup-go"
  fi

  echo
  echo "## Homebrew cleanup dry run"
  if command -v brew >/dev/null 2>&1; then
    brew cleanup --dry-run --prune="${HOMEBREW_CLEANUP_MAX_AGE_DAYS:-30}" | _mac_cleanup_limit_lines 120
  else
    echo "skip: brew not found"
  fi

  echo
  echo "## Brew services"
  if command -v brew >/dev/null 2>&1; then
    brew services list
  else
    echo "skip: brew not found"
  fi

  echo
  echo "## Background items"
  if command -v sfltool >/dev/null 2>&1; then
    sfltool dumpbtm | _mac_cleanup_limit_lines 150
  else
    echo "skip: sfltool not found"
  fi

  echo
  echo "## Launch registrations"
  local dir
  for dir in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
    echo
    echo "== ${dir} =="
    if [[ -d "$dir" ]]; then
      _mac_cleanup_list_dir "$dir"
    else
      echo "missing"
    fi
  done
}

# Prune low-risk regenerated developer caches, then delete project node_modules
# folders under the given roots (default: $HOME). Cache pruning requires an
# exact typed confirmation; node_modules deletion lists the folders with sizes
# and asks again. Declining the first step still continues to the second.
#
# The node_modules scan keeps global installs by never descending into
# ~/Library or hidden top-level home dirs (~/.local, ~/.cache, ~/.bun, …),
# which hold the fnm/npm, pnpm, bun, and yarn globals plus tool-managed
# runtimes, nor into system prefixes, .app bundles, or browser profiles
# (Chromium-family profiles unpack extensions under Extensions/). Roots
# themselves are never pruned, so an explicit root inside one of those trees
# (e.g. ~/.claude) is still scanned.
# Usage: clean_dev_caches [root...]
function clean_dev_caches() {
  _mac_cleanup_require_macos || return

  local roots=() root dirs dir found=() tilde='~' tab=$'\t'
  for root in "${@:-$HOME}"; do
    # find matches -path against the root's spelling, so make roots absolute.
    root=$(cd -- "$root" && pwd) || return 1
    roots+=("$root")
  done

  echo "This will run:"
  echo "  uv cache prune"
  echo "  pnpm store prune"
  echo "  go clean -cache -testcache"
  echo
  echo "It will not clear browser profiles, Helium cache, editor state, model stores, wallets, chat history, or app data."
  echo
  printf 'Type "clean dev caches" to continue: '

  local confirm
  read -r confirm
  if [[ "$confirm" == "clean dev caches" ]]; then
    if command -v uv >/dev/null 2>&1; then
      uv cache prune
    else
      echo "skip: uv not found"
    fi

    if command -v pnpm >/dev/null 2>&1; then
      pnpm store prune
    else
      echo "skip: pnpm not found"
    fi

    if command -v go >/dev/null 2>&1; then
      go clean -cache -testcache
    else
      echo "skip: go not found"
    fi
  else
    echo "Skipped cache pruning."
  fi

  echo
  local shown=("${roots[@]/#"$HOME"/$tilde}")
  # gum spin passes the child's stderr through, so silence find's permission
  # errors inside sh; `|| true` drops the nonzero status they cause.
  dirs=$(gum spin --show-stdout --title "Scanning ${shown[*]} for node_modules..." -- \
    sh -c 'find "$@" 2>/dev/null || true' sh "${roots[@]}" -mindepth 1 \
    \( -path "$HOME/.*" ! -path "$HOME/.*/*" -o -path "$HOME/Library" -o -path /opt/homebrew -o -path /usr -o -name '*.app' -o -name Extensions \) -prune \
    -o -type d -name node_modules -print -prune) || return 1

  while IFS= read -r dir; do
    [[ -n "$dir" ]] && found+=("$dir")
  done <<<"$dirs"

  local count=${#found[@]}
  if ((count == 0)); then
    echo "No node_modules folders found."
    return 0
  fi

  local sizes total
  sizes=$(gum spin --show-stdout --title "Measuring $count node_modules folders..." -- du -shc -- "${found[@]}") || return 1
  total=$(tail -n 1 <<<"$sizes" | cut -f 1)
  # Show paths under $HOME as ~/...
  printf '%s\n' "${sizes//"$tab$HOME"/$tab$tilde}"

  gum confirm "Delete these $count node_modules folders ($total)?" || return 0

  local i=0 failed=0
  for dir in "${found[@]}"; do
    ((++i))
    gum spin --title "Deleting [$i/$count] ${dir/#"$HOME"/$tilde}" -- rm -rf -- "$dir" || ((++failed))
  done

  if ((failed > 0)); then
    echo "Deleted $((count - failed))/$count node_modules folders; $failed failed." >&2
    return 1
  fi
  echo "Deleted $count node_modules folders, freeing $total."
}
