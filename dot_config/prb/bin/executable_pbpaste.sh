#!/usr/bin/env bash
# Linux shim for macOS pbpaste (clipboard → stdout).

set -euo pipefail

if command -v xsel >/dev/null 2>&1; then
  # This replaces the shell with xsel; the script does not continue after a successful exec
  exec xsel --clipboard --output "$@"
fi

# echo alone would exit 0; fail explicitly when xsel is missing.
echo "pbpaste requires xsel on Linux" >&2
exit 1
