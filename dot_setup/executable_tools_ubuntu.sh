#!/usr/bin/env bash
# Install command-line tools (Ubuntu equivalent of .brew)
# shellcheck disable=SC2034

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prevent interactive prompts during package installation
export DEBIAN_FRONTEND=noninteractive

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/packages.sh"

# ==============================================================================
# APT Packages
# ==============================================================================

install_apt_packages() {
  log_info "Setting up APT packages..."

  apt_refresh
  local packages=("${UBUNTU_APT_PACKAGES[@]}")

  # Create keyrings directory
  mkdir -p /etc/apt/keyrings
  chmod 755 /etc/apt/keyrings

  # Install GitHub CLI repository first (not in default repos)
  if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
    log_info "Adding GitHub CLI repository..."
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    apt-get update
  fi

  # Install Eza repository (modern ls replacement)
  if [[ ! -f /etc/apt/sources.list.d/gierens.list ]]; then
    log_info "Adding Eza repository..."
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
    chmod 644 /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | tee /etc/apt/sources.list.d/gierens.list >/dev/null
    apt-get update
  fi

  # Add eza to package list
  packages+=(eza)

  # Install all packages
  log_info "Installing packages..."
  for package in "${packages[@]}"; do
    if ! dpkg -l | grep -q "^ii  ${package} "; then
      log_info "Installing ${package}..."
      apt-get install -y "$package"
    else
      log_info "${package} already installed"
    fi
  done

  # Create symlinks for fd and bat (Ubuntu uses different names)
  if [[ ! -f /usr/local/bin/fd ]] && [[ -f /usr/bin/fdfind ]]; then
    ln -sf /usr/bin/fdfind /usr/local/bin/fd
    log_info "Created symlink: fd -> fdfind"
  fi
  if [[ ! -f /usr/local/bin/bat ]] && [[ -f /usr/bin/batcat ]]; then
    ln -sf /usr/bin/batcat /usr/local/bin/bat
    log_info "Created symlink: bat -> batcat"
  fi

  log_success "APT packages installed"
}

# ==============================================================================
# Snap Packages
# ==============================================================================

install_snap_packages() {
  log_info "Setting up Snap packages..."

  # Install standard packages
  for package in "${UBUNTU_SNAP_PACKAGES[@]}"; do
    if ! command -v "$package" &>/dev/null; then
      log_info "Installing ${package}..."
      snap install "$package"
    else
      log_info "${package} already installed"
    fi
  done

  # Install classic packages
  for package in "${UBUNTU_CLASSIC_SNAP_PACKAGES[@]}"; do
    if ! command -v "$package" &>/dev/null; then
      log_info "Installing ${package}..."
      snap install "$package" --classic
    else
      log_info "${package} already installed"
    fi
  done

  log_success "Snap packages installed"
}

# ==============================================================================
# Additional Tools
# ==============================================================================

install_fnm() {
  log_info "Installing fnm (Fast Node Manager)..."

  if ! command -v fnm &>/dev/null; then
    curl -fsSL https://fnm.vercel.app/install | sh
    log_success "fnm installed"
  else
    log_info "fnm already installed"
  fi
}

install_uv() {
  log_info "Installing uv (Python package and project manager)..."

  if ! command -v uv &>/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    log_success "uv installed"
  else
    log_info "uv already installed"
  fi
}

install_vim_runtime() {
  log_info "Installing ultimate Vim configuration (amix/vimrc)..."

  # Run as the user who invoked sudo (not root)
  local actual_user="${SUDO_USER:-$USER}"
  local user_home=$(eval echo ~"$actual_user")

  if [[ -d "$user_home/.vim_runtime" ]]; then
    log_info "vim_runtime already installed"
  else
    log_info "Cloning vim_runtime repository..."
    sudo -u "$actual_user" git clone --depth=1 https://github.com/amix/vimrc.git "$user_home/.vim_runtime"
    sudo -u "$actual_user" sh "$user_home/.vim_runtime/install_awesome_vimrc.sh"
    log_success "vim_runtime installed"
  fi
}

install_tailscale() {
  log_info "Installing Tailscale..."

  if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
    log_success "Tailscale installed"
  else
    log_info "Tailscale already installed"
  fi
}

install_starship() {
  log_info "Installing Starship prompt..."

  if ! command -v starship &>/dev/null; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    log_success "Starship installed"
  else
    log_info "Starship already installed"
  fi
}

# ==============================================================================
# Main
# ==============================================================================

main() {
  echo "🚀 Starting Ubuntu package installation..." >&2
  echo ""

  check_root

  install_apt_packages
  install_snap_packages
  install_fnm
  install_uv
  install_vim_runtime
  install_tailscale
  install_starship

  # Remove outdated packages
  log_info "Cleaning up..."
  apt-get autoremove -y
  apt-get autoclean

  echo ""
  echo "🎉 Installation complete!" >&2
}

main "$@"
