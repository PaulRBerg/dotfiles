#!/usr/bin/env bash

###############################################################################
# DEVELOPMENT TOOLS                                                           #
###############################################################################

# See https://github.com/oven-sh/bun/issues/10341
function pm_update() {
  nlx taze --group --interactive --recursive
}

# Copy Chromium browser profile while excluding files specific to one browser or system
function copy_browser_profile() {
  rsync --archive \
    --exclude='Cache' \
    --exclude='GPUCache' \
    --exclude='Local Storage' \
    --exclude='Sessions' \
    --exclude='ShaderCache' \
    --exclude='Service Worker' \
    --exclude='IndexedDB' \
    "$1/" "$2/"
}

# Prettier wrapper that includes global ignore patterns
function prettier() {
  local args=()
  local global_ignore="${XDG_CONFIG_HOME:-$HOME/.config}/prettier/ignore"
  local git_global_ignore

  # Add global prettier ignore if it exists
  [[ -f "$global_ignore" ]] && args+=(--ignore-path "$global_ignore")

  # Add global gitignore if configured and exists
  git_global_ignore=$(git config --global core.excludesFile 2>/dev/null)
  [[ -n "$git_global_ignore" && -f "${git_global_ignore/#\~/$HOME}" ]] &&
    args+=(--ignore-path "${git_global_ignore/#\~/$HOME}")

  # Add local .prettierignore if it exists
  [[ -f .prettierignore ]] && args+=(--ignore-path .prettierignore)

  # Add local .gitignore if it exists
  [[ -f .gitignore ]] && args+=(--ignore-path .gitignore)

  command prettier "${args[@]}" "$@"
}

# Download a VSCode extension (.vsix) from the marketplace
# Usage: vscode_download <publisher.extension>
# Example: vscode_download ms-python.python
function vscode_download() {
  if [[ -z "$1" ]]; then
    echo "Usage: vscode_download <publisher.extension>" >&2
    echo "Example: vscode_download ms-python.python" >&2
    return 1
  fi

  local full_name="$1"
  local publisher="${full_name%%.*}"
  local extension="${full_name#*.}"

  if [[ "$publisher" == "$extension" || -z "$publisher" || -z "$extension" ]]; then
    echo "Invalid extension format. Expected: publisher.extension" >&2
    return 1
  fi

  local url="https://${publisher}.gallery.vsassets.io/_apis/public/gallery/publisher/${publisher}/extension/${extension}/latest/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"
  local download_dir="$HOME/work/extensions/vscode"
  [[ -d "$download_dir" ]] || download_dir="$HOME/Downloads"
  local output="${download_dir}/${publisher}.${extension}.vsix"

  echo "Downloading ${full_name}..."
  if curl -fSL "$url" -o "$output"; then
    echo "Downloaded: $output"
  else
    echo "Failed to download ${full_name}" >&2
    return 1
  fi
}

# Upgrade to a new Node.js version, port global npm packages, and set as default
# Usage: fnm_bump_node [version]
# Example: fnm_bump_node 24
# Example: fnm_bump_node        # installs latest
function fnm_bump_node() {
  local version
  if [[ -n "$1" ]]; then
    version="$1"
  else
    version=$(fnm ls-remote | tail -1)
  fi

  fnm install "$version" || return 1
  fnm use "$version" || return 1

  ~/.setup/node.sh

  fnm default "$version"

  echo "Node.js $(node -v) is now the default"
}
