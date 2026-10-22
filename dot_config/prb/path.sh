#!/usr/bin/env bash

PRB_CONFIG_DIR="${PRB_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/prb}"
PRB_SETUP_DIR="${PRB_SETUP_DIR:-$HOME/.setup}"

# Keep the first PATH entry when duplicates appear. In zsh, PATH and path are
# tied, so fnm and other late startup hooks keep their prepended priority.
if [[ -n "${ZSH_VERSION:-}" ]]; then
  # shellcheck disable=SC2034 # zsh ties path/PATH; assigning path mutates PATH.
  typeset -gU path PATH
fi

# Prepend a directory to PATH only if it exists.
prepend_path() {
  [[ -d "$1" ]] || return 0

  if [[ -n "${ZSH_VERSION:-}" ]]; then
    path=("$1" "${path[@]}")
    export PATH
  else
    case ":$PATH:" in
    *":$1:"*) ;;
    *) export PATH="$1:$PATH" ;;
    esac
  fi
}

###############################################################################
# Dotfiles                                                                    #
###############################################################################
prepend_path "$PRB_CONFIG_DIR/bin"
prepend_path "$PRB_SETUP_DIR"

###############################################################################
# Homebrew and macOS apps                                                     #
###############################################################################

# Homebrew (keep ahead of macOS system binaries even if HOMEBREW_PREFIX is inherited)
if [[ -z "${HOMEBREW_PREFIX:-}" ]]; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
if [[ -n "${HOMEBREW_PREFIX:-}" ]]; then
  prepend_path "$HOMEBREW_PREFIX/sbin"
  prepend_path "$HOMEBREW_PREFIX/bin"
fi

# LM Studio
prepend_path "$HOME/.lmstudio/bin"

# OpenSSL
if [[ -n "${HOMEBREW_PREFIX:-}" && -d "$HOMEBREW_PREFIX/opt/openssl" ]]; then
  export PKG_CONFIG_PATH="$HOMEBREW_PREFIX/opt/openssl/lib/pkgconfig"
  prepend_path "$HOMEBREW_PREFIX/opt/openssl/bin"
fi

# Google Cloud SDK
if [[ -d "$HOME/.local/share/google-cloud-sdk" ]]; then
  prepend_path "$HOME/.local/share/google-cloud-sdk/bin"
fi

# iTerm2 shell integration utilities
prepend_path "$HOME/.iterm2"

# Solana
prepend_path "$HOME/.local/share/solana/install/active_release/bin"
prepend_path "$HOME/.avm/bin"

###############################################################################
# Cross-Machine                                                               #
###############################################################################

# Codex helpers
prepend_path "$HOME/.codex/helpers"

# User-local binaries
prepend_path "$HOME/.local/bin"

# Deno
prepend_path "$HOME/.deno/bin"

# Bun
prepend_path "${BUN_INSTALL:-$XDG_DATA_HOME/bun}/bin"

# Cargo/Rust (CARGO_HOME set in env_core.sh)
prepend_path "${CARGO_HOME:-$XDG_DATA_HOME/cargo}/bin"

# PNPM
prepend_path "${PNPM_HOME:-$XDG_DATA_HOME/pnpm}"

# Foundry
prepend_path "${FOUNDRY_DIR:-$XDG_DATA_HOME/foundry}/bin"

# Go
prepend_path "${GOBIN:-${GOPATH:-$HOME/go}/bin}"

# OpenCode
prepend_path "$HOME/.opencode/bin"

# Rindexer
prepend_path "${XDG_CONFIG_HOME:-$HOME/.config}/.rindexer/bin"
