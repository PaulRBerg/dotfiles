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
  local quiet="${BUN_GLOBALS_QUIET:-0}"

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

  if [[ "$quiet" != "1" ]]; then
    echo "🚀 Installing global packages with bun..." >&2
    echo "" >&2
  fi

  # Install packages one by one so a single failure doesn't abort the rest.
  local package install_output
  for package in "${BUN_GLOBAL_PACKAGES[@]}"; do
    if [[ "$quiet" != "1" ]]; then
      echo "📦 Installing $package..." >&2
    fi
    if install_output="$(bun add --global --no-progress --no-summary "$package" 2>&1)"; then
      if [[ "$quiet" != "1" ]]; then
        echo "✅ $package installed successfully" >&2
      fi
    else
      echo "❌ $package installation failed" >&2
      printf '%s\n' "$install_output" >&2
    fi
    if [[ "$quiet" != "1" ]]; then
      echo "" >&2
    fi
  done

  local untrusted_packages packages_to_trust=()
  untrusted_packages="$(
    { bun pm untrusted -g 2>/dev/null || true; } | awk '
      /^\.\/node_modules\// {
        package_path = $1
        sub(/^.*\/node_modules\//, "", package_path)
        split(package_path, parts, "/")

        if (parts[1] ~ /^@/ && parts[2] != "") {
          print parts[1] "/" parts[2]
        } else {
          print parts[1]
        }
      }
    ' | sort -u
  )"

  for package in "${BUN_TRUSTED_PACKAGES[@]}"; do
    if grep -Fxq -- "$package" <<<"$untrusted_packages"; then
      packages_to_trust+=("$package")
    fi
  done

  if ((${#packages_to_trust[@]} > 0)); then
    if [[ "$quiet" == "1" ]]; then
      local trust_output
      if ! trust_output="$(bun pm trust -g "${packages_to_trust[@]}" 2>&1)"; then
        echo "❌ Failed to trust lifecycle scripts: ${packages_to_trust[*]}" >&2
        printf '%s\n' "$trust_output" >&2
      fi
    else
      echo "🔏 Trusting lifecycle scripts: ${packages_to_trust[*]}" >&2
      bun pm trust -g "${packages_to_trust[@]}"
    fi
  else
    if [[ "$quiet" != "1" ]]; then
      echo "✅ No configured lifecycle scripts need trusting" >&2
    fi
  fi

  if [[ "$quiet" != "1" ]]; then
    echo "🎉 All global packages installed!" >&2
  fi
}
