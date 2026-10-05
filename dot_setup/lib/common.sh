#!/usr/bin/env bash

LOG_PREFIX="[${SCRIPT_NAME:-$(basename "${BASH_SOURCE[0]}")}]"

log_info() {
  echo "${LOG_PREFIX} 📦 $*" >&2
}

log_error() {
  echo "${LOG_PREFIX} ❌ $*" >&2
}

log_success() {
  echo "${LOG_PREFIX} ✓ $*" >&2
}

brew_refresh() {
  log_info "Updating Homebrew..."
  brew update

  log_info "Upgrading installed formulae..."
  brew upgrade
}

ensure_symlink() {
  local target="$1"
  local source="$2"

  if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$source" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$target")" || return 1
  rm -f "$target" || return 1
  ln -s "$source" "$target" || return 1
  printf "↪ %s → %s\n" "$target" "$source"
}
