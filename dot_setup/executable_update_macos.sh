#!/usr/bin/env bash
# Update Homebrew and upgrade installed formulae.
# shellcheck disable=SC2034

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh"

log_info "Updating Homebrew packages..."
echo ""

brew_refresh

# Remove outdated versions from the cellar
brew cleanup

echo ""
echo "✅ Homebrew update complete!" >&2
