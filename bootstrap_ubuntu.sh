#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2154

# Bootstrap script for initializing a new Ubuntu machine
# This should be run first on a fresh Ubuntu installation

# Strict mode: https://gist.github.com/vncsna/64825d5609c146e80de8b1fd623011ca
set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/dot_setup/lib/common.sh"

if [[ $EUID -ne 0 ]]; then
  log_error "This script must be run with sudo"
  exit 1
fi

invoking_uid="$(id -u "${SUDO_USER:-}" 2>/dev/null || true)"
if [[ -z "${SUDO_USER:-}" || "$SUDO_USER" == "root" || "$invoking_uid" == "0" || ! "$invoking_uid" =~ ^[0-9]+$ ]]; then
  log_error "Run this script through sudo from a non-root user"
  exit 1
fi

if ! invoking_home="$(getent passwd "$SUDO_USER" | awk -F: 'NR == 1 { print $6 }')"; then
  log_error "Cannot look up the home directory for $SUDO_USER"
  exit 1
fi
if [[ -z "$invoking_home" || ! -d "$invoking_home" ]]; then
  log_error "Cannot determine a valid home directory for $SUDO_USER"
  exit 1
fi

readonly INVOKING_USER="$SUDO_USER"
readonly INVOKING_HOME="$(cd "$invoking_home" && pwd -P)"

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
  local omz_dir="$1"
  local plugin_name="$2"
  local repo_url="$3"

  local plugin_dir="${omz_dir}/custom/plugins/${plugin_name}"

  if [[ -d "$plugin_dir/.git" ]]; then
    log_info "Oh My Zsh plugin already installed: ${plugin_name}"
    return 0
  fi
  if [[ -e "$plugin_dir" ]]; then
    log_error "Cannot install ${plugin_name}; ${plugin_dir} exists and is not a Git checkout"
    return 1
  fi

  if ! sudo -H -u "$INVOKING_USER" git clone --depth=1 "$repo_url" "$plugin_dir"; then
    log_error "Failed to clone Oh My Zsh plugin ${plugin_name} from ${repo_url}"
    return 1
  fi
}

install_zsh() {
  log_info "Installing Zsh..."

  apt-get install -y zsh

  log_success "Zsh installed"
}

install_ohmyzsh() {
  log_info "Installing Oh My Zsh..."

  if [[ -n "${INVOKING_USER:-}" ]]; then
    local user_home="$INVOKING_HOME"
    # The applied .zshrc sources Oh My Zsh from ZSH=$XDG_DATA_HOME/oh-my-zsh
    # (set in env_core.sh), not the installer default ~/.oh-my-zsh.
    local omz_dir="${user_home}/.local/share/oh-my-zsh"

    if [[ ! -d "${omz_dir}" ]]; then
      # Install Oh My Zsh for the regular user (not root)
      sudo -H -u "$INVOKING_USER" env ZSH="$omz_dir" sh -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'

      # Set Zsh as default shell for the user
      chsh -s "$(command -v zsh)" "$INVOKING_USER"

      log_success "Oh My Zsh installed for user ${INVOKING_USER}"
    else
      log_info "Oh My Zsh already installed"
    fi

    # Install Oh My Zsh plugins
    log_info "Installing Oh My Zsh plugins..."

    install_omz_plugin "${omz_dir}" "fzf-tab" "https://github.com/Aloxaf/fzf-tab"
    install_omz_plugin "${omz_dir}" "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions"
    install_omz_plugin "${omz_dir}" "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting"

    log_success "Oh My Zsh plugins installed"
  else
    log_error "Cannot determine regular user for Oh My Zsh installation"
    log_error "Please install manually: ZSH=\"\$HOME/.local/share/oh-my-zsh\" sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
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
  local user_home="$INVOKING_HOME"
  mkdir -p "${user_home}/.ssh"
  ssh-keyscan github.com >>"${user_home}/.ssh/known_hosts" 2>/dev/null
  chown -R "${INVOKING_USER}:${INVOKING_USER}" "${user_home}/.ssh"

  sudo -H -u "$INVOKING_USER" /snap/bin/chezmoi init git@github.com:PaulRBerg/dotfiles.git
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
    sudo -H -u "$INVOKING_USER" mkdir -p "$(dirname "$target_dir")"
    sudo -H -u "$INVOKING_USER" git clone "$repo_url" "$target_dir"
    log_success "Cloned $repo_url -> $target_dir"
  fi
}

setup_directories_and_repos() {
  local user_home="$INVOKING_HOME"

  log_info "Setting up directories and repositories..."

  # Create bare directories
  for dir in "$user_home/projects" "$user_home/sablier" "$user_home/work"; do
    sudo -H -u "$INVOKING_USER" mkdir -p "$dir"
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
