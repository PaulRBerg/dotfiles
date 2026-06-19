#!/usr/bin/env bash

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
