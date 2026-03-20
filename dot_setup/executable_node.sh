#!/usr/bin/env bash
# Install Node.js packages globally.

echo "🚀 Installing global npm packages..." >&2
echo ""

packages=(
  @antfu/ni
  @biomejs/biome
  @google/gemini-cli
  @modelcontextprotocol/server-sequential-thinking
  @mariozechner/claude-trace
  @openai/codex
  @typescript/native-preview
  @upstash/context7-mcp
  add-skill
  bun
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

# Install packages one by one with npm's built-in progress display
for package in "${packages[@]}"; do
  echo "📦 Installing $package..." >&2
  if npm install --fund=false --location=global --progress=true "$package"; then
    echo "✅ $package installed successfully" >&2
  else
    echo "❌ $package installation failed" >&2
  fi
  echo "" >&2
done

echo "🎉 All npm packages installed!" >&2
