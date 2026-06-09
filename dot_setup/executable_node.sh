#!/usr/bin/env bash
# Install global command-line packages with bun.
#
# Invoked by `fnm_bump_node` (dot_config/prb/functions/dev.sh) and runnable
# directly as `~/.setup/node.sh`. Unlike npm globals — which are scoped to the
# active fnm Node version and wiped on every Node bump — bun installs these into
# its own global prefix ($BUN_INSTALL/bin, on PATH via path.sh.tmpl), so they
# persist across Node versions and only need (re)linking, not reinstalling.

# Fail on unset vars and masked pipe failures. `-e` is intentionally omitted: the
# install loop below continues past individual package failures by design.
set -uo pipefail

# bun honors $BUN_INSTALL (set in env_core.sh) for its location. Prepend its bin
# dir so a freshly bootstrapped bun is callable within this script. Mirror the
# canonical default used by env_core.sh / path.sh.tmpl so the install prefix and
# the PATH entry stay in sync even under a customized $XDG_DATA_HOME.
export BUN_INSTALL="${BUN_INSTALL:-${XDG_DATA_HOME:-$HOME/.local/share}/bun}"
export PATH="$BUN_INSTALL/bin:$PATH"

# Bootstrap bun via the native installer if it is missing (no-op when present, so
# repeated fnm_bump_node runs don't re-fetch it).
if ! command -v bun >/dev/null 2>&1; then
  echo "📦 Installing bun (native installer)..." >&2
  curl -fsSL https://bun.com/install | bash
fi

if ! command -v bun >/dev/null 2>&1; then
  echo "❌ bun unavailable after install; aborting." >&2
  exit 1
fi

echo "🚀 Installing global packages with bun..." >&2
echo ""

packages=(
  @antfu/ni
  @biomejs/biome
  @google/gemini-cli
  @modelcontextprotocol/server-sequential-thinking
  @typescript/native-preview
  @upstash/context7-mcp
  add-skill
  ccstatusline
  github-label-sync
  jscpd
  next
  openclaw
  playwright
  pnpm
  prettier
  skills
  taze
  ts-node
  tsx
  typescript
  vercel
  yarn
)

# Install packages one by one so a single failure doesn't abort the rest.
for package in "${packages[@]}"; do
  echo "📦 Installing $package..." >&2
  if bun add --global "$package"; then
    echo "✅ $package installed successfully" >&2
  else
    echo "❌ $package installation failed" >&2
  fi
  echo "" >&2
done

echo "🎉 All global packages installed!" >&2
