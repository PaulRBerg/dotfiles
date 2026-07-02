#!/usr/bin/env bash
# Global bun packages installed on top of Node.js.
#
# Sourced by dot_setup/executable_node.sh (manual / fnm_bump_node) and
# dot_setup/run_onchange_setup_node.sh.tmpl (automatic, on `chezmoi apply`) so
# both entry points install the same set without duplicating the list.
# shellcheck disable=SC2034

BUN_GLOBAL_PACKAGES=(
  @antfu/ni
  @biomejs/biome
  @mariozechner/claude-trace
  @mariozechner/pi-coding-agent
  @steipete/summarize
  @typescript/native-preview
  ccstatusline
  chrome-devtools-mcp
  jscpd
  next
  playwright
  prettier
  skills
  taze
  ts-node
  tsx
  typescript
  vercel
  vitest
  yarn
)

# Deps whose lifecycle scripts bun blocks by default but that need them for
# preinstall/native prebuild setup. bunfig.toml has no trust option — bun
# records trust only in the global package.json — so re-assert it here to keep
# fresh-machine provisioning reproducible.
BUN_TRUSTED_PACKAGES=(
  @google/genai
  koffi
  protobufjs
  yarn
)

# bun honors $BUN_INSTALL (set in env_core.sh) for its location. Prepend its
# bin dir so a freshly bootstrapped bun is callable within this process.
# Mirror the canonical default used by env_core.sh / path.sh.tmpl so the
# install prefix and the PATH entry stay in sync even under a customized
# $XDG_DATA_HOME.
install_bun_globals() {
  export BUN_INSTALL="${BUN_INSTALL:-${XDG_DATA_HOME:-$HOME/.local/share}/bun}"
  export PATH="$BUN_INSTALL/bin:$PATH"

  # Bootstrap bun via the native installer if it is missing (no-op when
  # present, so repeated calls don't re-fetch it).
  if ! command -v bun >/dev/null 2>&1; then
    echo "📦 Installing bun (native installer)..." >&2
    curl -fsSL https://bun.com/install | bash
  fi

  if ! command -v bun >/dev/null 2>&1; then
    echo "❌ bun unavailable after install; aborting." >&2
    return 1
  fi

  echo "🚀 Installing global packages with bun..." >&2
  echo "" >&2

  # Install packages one by one so a single failure doesn't abort the rest.
  local package
  for package in "${BUN_GLOBAL_PACKAGES[@]}"; do
    echo "📦 Installing $package..." >&2
    if bun add --global "$package"; then
      echo "✅ $package installed successfully" >&2
    else
      echo "❌ $package installation failed" >&2
    fi
    echo "" >&2
  done

  # NB: exits 1 when everything is already trusted (and its error output
  # echoes the subcommand name as if it were a package — bun quirk), hence
  # the guard.
  echo "🔏 Trusting lifecycle scripts: ${BUN_TRUSTED_PACKAGES[*]}" >&2
  bun pm -g trust "${BUN_TRUSTED_PACKAGES[@]}" || echo "⚠️ bun pm trust: nothing untrusted (or a package is missing)" >&2

  echo "🎉 All global packages installed!" >&2
}
