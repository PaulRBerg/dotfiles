#!/usr/bin/env bash
# Install command-line tools using Homebrew.
# shellcheck disable=SC2034

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/packages.sh"

log_info "Installing Homebrew packages..."
echo ""

brew_refresh

# Install required taps before formulae that depend on them.
for tap in "${MACOS_TAPS[@]}"; do
  brew tap "$tap"
done

# Install all formulae
for formula in "${MACOS_FORMULAE[@]}"; do
  brew install "$formula"
done

# Install all casks
for cask in "${MACOS_CASKS[@]}"; do
  brew install --cask "$cask"
done

# Create symlink for sha256sum
BREW_PREFIX=$(brew --prefix)
ln -sf "${BREW_PREFIX}/bin/gsha256sum" "${BREW_PREFIX}/bin/sha256sum"

# Use fnm for installing Node.Js
if brew list --formula | grep -q "^node$"; then
  brew uninstall --ignore-dependencies node
fi

# Remove outdated versions from the cellar
brew cleanup

echo ""
echo "🎉 Homebrew installation complete!" >&2
