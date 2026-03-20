#!/usr/bin/env bash
# Setup Biome configuration symlinks for VS Code and Cursor
# shellcheck disable=SC2034

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# run_onchange_ scripts execute from a temp dir, so source from the installed path
source "$HOME/.setup/lib/common.sh"

# shared config
BIOME_CONFIG="$HOME/.biome/biome.jsonc"

# targets
VSCODE_TARGET="$HOME/Library/Application Support/Code/User/biome.jsonc"
CURSOR_TARGET="$HOME/Library/Application Support/Cursor/User/biome.jsonc"

needs_setup=false
[[ ! -L "$VSCODE_TARGET" || "$(readlink "$VSCODE_TARGET")" != "$BIOME_CONFIG" ]] && needs_setup=true
[[ ! -L "$CURSOR_TARGET" || "$(readlink "$CURSOR_TARGET")" != "$BIOME_CONFIG" ]] && needs_setup=true

if [[ $needs_setup == true ]]; then
  echo "🔗 Setting up Biome symlinks..." >&2
  echo ""
  ensure_symlink "$VSCODE_TARGET" "$BIOME_CONFIG" || true
  ensure_symlink "$CURSOR_TARGET" "$BIOME_CONFIG" || true
  echo ""
  echo "✓ Biome setup complete!" >&2
fi

exit 0
