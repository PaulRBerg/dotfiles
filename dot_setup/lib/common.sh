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

# ensure_symlink <link> <target>: make <link> a symlink to <target>.
ensure_symlink() {
  local link="$1"
  local target="$2"

  if [[ -L "$link" ]] && [[ "$(readlink "$link")" == "$target" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$link")" || return 1
  rm -f "$link" || return 1
  ln -s "$target" "$link" || return 1
  printf "↪ %s → %s\n" "$link" "$target"
}
