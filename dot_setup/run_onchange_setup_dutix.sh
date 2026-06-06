#!/usr/bin/env bash
# Set default applications for common file types.
#
# Uses dutix (https://github.com/jackchuka/dutix): it resolves each extension to
# its real UTI through the modern UniformTypeIdentifiers / NSWorkspace APIs and
# skips targets already pointing at the desired app. That idempotence keeps
# re-applies silent and sidesteps the macOS 26.4+ "confirm default app" prompt.
# It replaces duti, whose deprecated Carbon lookups synthesize bogus dynamic
# UTIs on current macOS and fail with "error -50" for types another app owns.

echo "📝 Configuring file type associations..." >&2
echo ""

# dutix is part of the managed macOS toolset.
if ! command -v dutix >/dev/null 2>&1; then
  echo "❌ dutix is required. Install it with ~/.setup/tools_macos.sh." >&2
  exit 1
fi

# Point an app at a comma-separated extension list, tolerating a missing app.
# A single unresolvable target aborts dutix's whole plan, so each list must stay
# clean. --yes skips dutix's own prompt; --quiet hides idempotent skips while
# still surfacing real failures.
set_default() {
  local app=$1 exts=$2
  if ! dutix set "$app" --extensions "$exts" --yes --quiet; then
    echo "⚠️  dutix could not set $app for: $exts (is $app installed?)" >&2
  fi
}

# Code editor — Cursor — extensions in alphabetical order.
#
# Single-segment names only: macOS derives an extension from the text after the
# LAST dot, so multi-dot names (e.g. env.local) have no UTI and dutix rejects
# the entire batch. Such files inherit the handler of their final segment.
CURSOR_EXTENSIONS=(
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

cursor_exts=$(
  IFS=,
  printf '%s' "${CURSOR_EXTENSIONS[*]}"
)

set_default "Cursor" "$cursor_exts"
set_default "Microsoft Word" "doc,docx"
set_default "Microsoft Excel" "xls,xlsx"

echo ""
echo "✓ File type associations configured!" >&2
