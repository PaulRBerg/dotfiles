#!/usr/bin/env bash
# Setup Biome configuration symlinks for VS Code and Cursor
# shellcheck disable=SC2034

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# run_onchange_ scripts execute from a temp dir, so source from the installed path
source "$HOME/.setup/lib/common.sh"

# shared config
BIOME_CONFIG="$HOME/.biome/biome.jsonc"

# symlinks pointing at the shared config
VSCODE_LINK="$HOME/Library/Application Support/Code/User/biome.jsonc"
CURSOR_LINK="$HOME/Library/Application Support/Cursor/User/biome.jsonc"

needs_setup=false
[[ ! -L "$VSCODE_LINK" || "$(readlink "$VSCODE_LINK")" != "$BIOME_CONFIG" ]] && needs_setup=true
[[ ! -L "$CURSOR_LINK" || "$(readlink "$CURSOR_LINK")" != "$BIOME_CONFIG" ]] && needs_setup=true

if [[ $needs_setup == true ]]; then
  echo "🔗 Setting up Biome symlinks..." >&2
  echo ""
  ensure_symlink "$VSCODE_LINK" "$BIOME_CONFIG"
  ensure_symlink "$CURSOR_LINK" "$BIOME_CONFIG"
  echo ""
  echo "✓ Biome setup complete!" >&2
fi

exit 0
