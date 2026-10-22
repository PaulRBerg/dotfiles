#!/usr/bin/env bash

USER_DIR="${USER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/prb}"
PRB_SETUP_DIR="${PRB_SETUP_DIR:-$HOME/.setup}"

# Keep the first PATH entry when duplicates appear. In zsh, PATH and path are
# tied, so fnm and other late startup hooks keep their prepended priority.
if [[ -n "${ZSH_VERSION:-}" ]]; then
  # shellcheck disable=SC2034 # zsh ties path/PATH; assigning path mutates PATH.
  typeset -gU path PATH
fi

# Helper to add path only if it exists.
add_path() {
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
add_path "$USER_DIR/bin"
add_path "$PRB_SETUP_DIR"

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
  add_path "$HOMEBREW_PREFIX/sbin"
  add_path "$HOMEBREW_PREFIX/bin"
fi

# LM Studio
add_path "$HOME/.lmstudio/bin"

# OpenSSL
if [[ -n "${HOMEBREW_PREFIX:-}" && -d "$HOMEBREW_PREFIX/opt/openssl" ]]; then
  export PKG_CONFIG_PATH="$HOMEBREW_PREFIX/opt/openssl/lib/pkgconfig"
  add_path "$HOMEBREW_PREFIX/opt/openssl/bin"
fi

# Google Cloud SDK
if [[ -d "$HOME/.local/share/google-cloud-sdk" ]]; then
  add_path "$HOME/.local/share/google-cloud-sdk/bin"
fi

# iTerm2 shell integration utilities
add_path "$HOME/.iterm2"

# Solana
add_path "$HOME/.local/share/solana/install/active_release/bin"
add_path "$HOME/.avm/bin"

###############################################################################
# Cross-Machine                                                               #
###############################################################################

# Codex helpers
add_path "$HOME/.codex/helpers"

# User-local binaries
add_path "$HOME/.local/bin"

# Deno
add_path "$HOME/.deno/bin"

# Bun
add_path "${BUN_INSTALL:-$XDG_DATA_HOME/bun}/bin"

# Cargo/Rust (CARGO_HOME set in env_core.sh)
add_path "${CARGO_HOME:-$XDG_DATA_HOME/cargo}/bin"

# PNPM
add_path "${PNPM_HOME:-$XDG_DATA_HOME/pnpm}"

# Foundry
add_path "${FOUNDRY_DIR:-$XDG_DATA_HOME/foundry}/bin"

# Go
add_path "${GOBIN:-${GOPATH:-$HOME/go}/bin}"

# OpenCode
add_path "$HOME/.opencode/bin"

# Rindexer
add_path "${XDG_CONFIG_HOME:-$HOME/.config}/.rindexer/bin"
