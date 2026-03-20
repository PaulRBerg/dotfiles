#!/usr/bin/env bash

# Homebrew (must be first - use shellenv for proper PATH ordering)
if [[ -z "${HOMEBREW_PREFIX:-}" ]] && [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# LM Studio
add_path "$HOME/.lmstudio/bin"

# OpenSSL
if [[ -d "/opt/homebrew/opt/openssl" ]]; then
  export PKG_CONFIG_PATH="/opt/homebrew/opt/openssl/lib/pkgconfig"
  add_path "/opt/homebrew/opt/openssl/bin"
fi

# Solana
add_path "$HOME/.local/share/solana/install/active_release/bin"
add_path "$HOME/.avm/bin"
