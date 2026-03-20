#!/usr/bin/env bash
# Set up the default application for file types.

echo "📝 Configuring file type associations..." >&2
echo ""

CURSOR_BUNDLE_ID=$(osascript -e 'id of app "Cursor"')
FINDER_BUNDLE_ID="com.apple.finder"

# Extensions in alphabetical order
EXTENSIONS=(
  astro
  bash
  bats
  c
  cc
  conf
  cpp
  css
  csv
  cxx
  dockerfile
  dockerignore
  editorconfig
  env
  env.development
  env.example
  env.local
  env.production
  env.staging
  eslintrc
  gitignore
  go
  gql
  graphql
  gs
  h
  hpp
  ini
  java
  js
  json
  jsonc
  jsx
  just
  lock
  log
  md
  mdc
  mdx
  mjs
  mts
  php
  prisma
  proto
  py
  rb
  rs
  sass
  sh
  snap
  sol
  sql
  svg
  tmpl
  toml
  ts
  tsv
  tsx
  txt
  vim
  xml
  yaml
  yml
  zsh
)

# duti is part of the managed macOS toolset.
if ! command -v duti >/dev/null 2>&1; then
  echo "❌ duti is required. Install it with ~/.setup/tools_macos.sh." >&2
  exit 1
fi

# Generate the duti configuration file
{
  # Loop through each file extension
  for ext in "${EXTENSIONS[@]}"; do
    printf "%s\t.%s\tall\n" "$CURSOR_BUNDLE_ID" "$ext"
  done

  # Configure Finder to handle directories
  printf "%s\tpublic.folder\tall\n" "$FINDER_BUNDLE_ID"
} >~/.duti

# Apply the new defaults
duti ~/.duti

echo ""
echo "✓ File and folder associations configured!" >&2
