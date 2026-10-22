#!/usr/bin/env bash
# Sync Cursor configuration to VSCode (VSCode is source of truth).
# shellcheck disable=SC2034

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# run_onchange_ scripts execute from a temp dir, so source from the installed path
source "$HOME/.setup/lib/common.sh"

# Base paths
VSCODE_USER="$HOME/Library/Application Support/Code/User"
CURSOR_USER="$HOME/Library/Application Support/Cursor/User"

# Config files to sync
CONFIG_FILES=(keybindings.json settings.json tasks.json)

needs_setup=false
for file in "${CONFIG_FILES[@]}"; do
  link="$CURSOR_USER/$file"
  target="$VSCODE_USER/$file"
  [[ ! -L "$link" || "$(readlink "$link")" != "$target" ]] && needs_setup=true
done

if [[ $needs_setup == true ]]; then
  echo "🔗 Syncing Cursor → VSCode..." >&2
  echo ""
  for file in "${CONFIG_FILES[@]}"; do
    ensure_symlink "$CURSOR_USER/$file" "$VSCODE_USER/$file"
  done
  echo ""
  echo "✓ Sync complete!" >&2
fi

exit 0
