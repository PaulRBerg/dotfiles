#!/usr/bin/env bash

###############################################################################
# DEVELOPMENT TOOLS                                                           #
###############################################################################

# See https://github.com/oven-sh/bun/issues/10341
function pm_update() {
  # --maturity-period skips versions published within the last N days to mitigate supply-chain attacks
  nlx taze --group --interactive --recursive --maturity-period 3
}

# Upgrade global bun packages to their latest versions.
# `bun update -g` only moves within each package's saved semver range (and has
# been unreliable for globals — oven-sh/bun#10341), so reinstall each global at
# `latest`, which reliably crosses majors. The 7-day cooldown in ~/.bunfig.toml
# still applies. No-op when nothing is installed.
function bun_update() {
  local manifest names
  manifest="${BUN_INSTALL:-${XDG_DATA_HOME:-$HOME/.local/share}/bun}/install/global/package.json"

  if [[ ! -f "$manifest" ]]; then
    echo "No global bun packages installed."
    return 0
  fi

  # bun is guaranteed on PATH here; let it read its own manifest (no jq needed).
  names=$(bun --print "Object.keys(require('$manifest').dependencies ?? {}).join('\n')")

  if [[ -z "$names" ]]; then
    echo "No global bun packages installed."
    return 0
  fi

  echo "Upgrading global bun packages:"
  echo "  ${names//$'\n'/$'\n'  }"

  # Build an explicit arg array; zsh does not word-split scalars by default.
  local specs=() name
  while IFS= read -r name; do
    [[ -n "$name" ]] && specs+=("$name@latest")
  done <<<"$names"

  bun add --global "${specs[@]}"
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

# Interactive live grep: ripgrep re-runs on every keystroke and streams matches
# into fzf, with a syntax-highlighted bat preview centered on the hit. Hidden
# files are searched too (.git excluded, .gitignore still honored). CTRL-T
# toggles fzf mode, which fuzzy-filters the current rg results (matched chars
# underlined); each mode remembers its own query. Enter opens the match in
# Cursor at the exact line/column, or in ${EDITOR:-vim} at the line when
# cursor is not on PATH. An optional argument seeds the initial query. Empty
# query shows nothing (no full-repo dump on launch).
# Requires fzf >= 0.45 (transform action with $FZF_PROMPT).
# Usage: rgf [query]
function rgf() {
  local rg_prefix="rg --column --line-number --no-heading --color=always --smart-case --hidden --glob '!.git'"
  # Resolve the Enter action up front: with $EDITOR baked into the command
  # text, a multi-word value (e.g. "code -w") still word-splits in fzf's
  # child shell; an unquoted runtime $EDITOR would not under zsh.
  local opener='cursor -g {1}:{2}:{3}'
  command -v cursor >/dev/null 2>&1 || opener="${EDITOR:-vim} {1} +{2}"
  local tmp
  tmp=$(mktemp -d) || return 1
  # Per-mode query stashes; pre-created so the first toggle's `cat` is quiet.
  local rq="$tmp/rg-query" fq="$tmp/fzf-query" ret
  : >"$rq"
  : >"$fq"
  # Stash queries with `printf %s`, not `echo`: fzf runs binds via $SHELL -c,
  # and zsh's echo would expand regex escapes like \b in the stashed query.
  : | fzf --ansi --disabled --query "${*:-}" \
    --prompt 'rg> ' \
    --header 'CTRL-T: toggle ripgrep <-> fuzzy filtering' \
    --color 'hl:-1:underline,hl+:-1:underline:reverse' \
    --bind "start:reload:[ -n {q} ] && $rg_prefix -- {q} || :" \
    --bind "change:reload:sleep 0.1; [ -n {q} ] && $rg_prefix -- {q} || :" \
    --bind "ctrl-t:transform:[ \"\$FZF_PROMPT\" = 'rg> ' ] &&
      printf %s \"unbind(change)+change-prompt(fzf> )+enable-search+transform-query:printf %s \\{q} >'$rq'; cat '$fq'\" ||
      printf %s \"rebind(change)+change-prompt(rg> )+disable-search+transform-query:printf %s \\{q} >'$fq'; cat '$rq'\"" \
    --delimiter : \
    --preview 'bat --color=always --style=numbers --highlight-line {2} -- {1}' \
    --preview-window 'right,60%,border-left,+{2}+3/3' \
    --bind "enter:become($opener)"
  ret=$?
  rm -rf -- "$tmp"
  return "$ret"
}
