#!/usr/bin/env bash
# Install Oh My Zsh custom plugins used by dot_zshrc.tmpl.

set -euo pipefail

# shellcheck disable=SC2034 # common.sh reads SCRIPT_NAME for LOG_PREFIX.
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# run_onchange_ scripts execute from a temp dir, so source from the installed path.
source "$HOME/.setup/lib/common.sh"

plugin_root="${ZSH_CUSTOM:-${ZSH:-${XDG_DATA_HOME:-$HOME/.local/share}/oh-my-zsh}/custom}/plugins"
mkdir -p "$plugin_root"

install_plugin() {
  local name="$1"
  local repo="$2"
  local dir="${plugin_root}/${name}"

  if [[ -d "${dir}/.git" ]]; then
    log_info "Updating ${name}..."
    if ! git -C "$dir" pull --ff-only --depth=1; then
      log_info "Leaving ${name} unchanged; checkout is not fast-forwardable"
    fi
  elif [[ -e "$dir" ]]; then
    log_info "Skipping ${name}; ${dir} exists and is not a git checkout"
  else
    log_info "Installing ${name}..."
    git clone --depth=1 "$repo" "$dir"
  fi
}

install_plugin fzf-tab https://github.com/Aloxaf/fzf-tab.git
install_plugin zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git
install_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git

log_success "Oh My Zsh custom plugins are installed"
