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

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
  fi
}

apt_refresh() {
  export NEEDRESTART_MODE=a
  export DEBIAN_FRONTEND=noninteractive

  log_info "Updating package lists..."
  apt-get update

  log_info "Upgrading installed packages..."
  apt-get upgrade -y
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
    return 1
  fi

  mkdir -p "$(dirname "$target")"
  rm -f "$target"
  ln -s "$source" "$target"
  printf "↪ %s → %s\n" "$target" "$source"
  return 0
}
