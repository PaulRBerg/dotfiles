#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2154

# Bootstrap script for initializing a new Ubuntu machine
# This should be run first on a fresh Ubuntu installation

# Strict mode: https://gist.github.com/vncsna/64825d5609c146e80de8b1fd623011ca
set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/dot_setup/lib/common.sh"

# ==============================================================================
# Update and Upgrade System
# ==============================================================================

update_system() {
  apt_refresh
  log_success "System updated and upgraded"
}

# ==============================================================================
# Install Snap
# ==============================================================================

install_snap() {
  log_info "Installing snapd..."

  if ! command -v snap &>/dev/null; then
    apt-get install -y snapd
    systemctl enable --now snapd.socket
    log_success "Snap installed"
  else
    log_info "Snap already installed"
  fi
}

# ==============================================================================
# Install Zsh and Oh My Zsh
# ==============================================================================

install_omz_plugin() {
  local plugin_name="$1"
  local repo_url="$2"

  su - "${SUDO_USER}" -c "git clone '${repo_url}' \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/${plugin_name} 2>/dev/null || true"
}

install_zsh() {
  log_info "Installing Zsh..."

  apt-get install -y zsh

  log_success "Zsh installed"
}

install_ohmyzsh() {
  log_info "Installing Oh My Zsh..."

  if [[ -n "${SUDO_USER:-}" ]]; then
    local user_home="/home/${SUDO_USER}"

    if [[ ! -d "${user_home}/.oh-my-zsh" ]]; then
      # Install Oh My Zsh for the regular user (not root)
      su - "${SUDO_USER}" -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'

      # Set Zsh as default shell for the user
      chsh -s "$(command -v zsh)" "${SUDO_USER}"

      log_success "Oh My Zsh installed for user ${SUDO_USER}"
    else
      log_info "Oh My Zsh already installed"
    fi

    # Install Oh My Zsh plugins
    log_info "Installing Oh My Zsh plugins..."

    install_omz_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions"
    install_omz_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting"

    log_success "Oh My Zsh plugins installed"
  else
    log_error "Cannot determine regular user for Oh My Zsh installation"
    log_error "Please install manually: sh -c \"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
  fi
}

# ==============================================================================
# Initialize Tailscale
# ==============================================================================

init_tailscale() {
  if [[ -z "${TAILSCALE_AUTHKEY:-}" ]]; then
    log_info "TAILSCALE_AUTHKEY not set, skipping Tailscale setup"
    return 0
  fi

  log_info "Installing Tailscale..."

  if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
    log_success "Tailscale installed"
  else
    log_info "Tailscale already installed"
  fi

  log_info "Connecting to Tailscale..."
  tailscale up --auth-key="$TAILSCALE_AUTHKEY" --hostname=prb-agents-aws
  log_success "Tailscale connected as prb-agents-aws"
}

# ==============================================================================
# Initialize Chezmoi
# ==============================================================================

init_chezmoi() {
  log_info "Installing Chezmoi..."

  if ! command -v chezmoi &>/dev/null; then
    snap install chezmoi --classic
    log_success "Chezmoi installed"
  else
    log_info "Chezmoi already installed"
  fi

  log_info "Initializing Chezmoi..."

  # Add GitHub to known_hosts to avoid SSH prompt
  local user_home="/home/${SUDO_USER}"
  mkdir -p "${user_home}/.ssh"
  ssh-keyscan github.com >>"${user_home}/.ssh/known_hosts" 2>/dev/null
  chown -R "${SUDO_USER}:${SUDO_USER}" "${user_home}/.ssh"

  sudo -u "$SUDO_USER" /snap/bin/chezmoi init git@github.com:PaulRBerg/dotfiles.git
  log_success "Chezmoi initialized"
}

# ==============================================================================
# Setup Directories and Repositories
# ==============================================================================

clone_repo() {
  local repo_url="$1"
  local target_dir="$2"

  if [[ -d "$target_dir" ]]; then
    log_info "Already exists: $target_dir"
  else
    mkdir -p "$(dirname "$target_dir")"
    sudo -u "$SUDO_USER" git clone "$repo_url" "$target_dir"
    log_success "Cloned $repo_url -> $target_dir"
  fi
}

setup_directories_and_repos() {
  local user_home="/home/${SUDO_USER}"

  log_info "Setting up directories and repositories..."

  # Create bare directories
  for dir in "$user_home/projects" "$user_home/sablier" "$user_home/work"; do
    sudo -u "$SUDO_USER" mkdir -p "$dir"
  done

  # Clone dotfile repos into home directories
  clone_repo "git@github.com:PaulRBerg/dot-claude.git" "$user_home/.claude"
  clone_repo "git@github.com:PaulRBerg/dot-agents.git" "$user_home/.agents"

  # Clone project repositories
  clone_repo "git@github.com:PaulRBerg/next-template.git" "$user_home/work/next-template"
  clone_repo "git@github.com:PaulRBerg/agent-skills.git" "$user_home/projects/agent-skills"
  clone_repo "git@github.com:sablier-labs/ui.git" "$user_home/sablier/new-ui"

  log_success "Directories and repositories set up"
}

# ==============================================================================
# Main
# ==============================================================================

main() {
  echo "🚀 Starting Ubuntu bootstrap process..." >&2
  echo ""

  check_root

  update_system
  install_snap
  install_zsh
  install_ohmyzsh

  init_chezmoi
  init_tailscale
  setup_directories_and_repos

  echo ""
  echo "🎉 Bootstrap complete!" >&2
  echo ""
  log_info "Next steps: log out and log back in for Zsh to take effect"
}

main "$@"
