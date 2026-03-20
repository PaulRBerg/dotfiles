#!/usr/bin/env bash
# Linux shim for macOS pbcopy (stdin → clipboard).

set -euo pipefail

if command -v xsel >/dev/null 2>&1; then
  # This replaces the shell with xsel; the script does not continue after a successful exec
  exec xsel --clipboard --input "$@"
fi

# echo alone would exit 0; fail explicitly when xsel is missing.
echo "pbcopy requires xsel on Linux" >&2
exit 1
