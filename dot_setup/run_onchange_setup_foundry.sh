#!/usr/bin/env bash
# Install foundryup (Foundry's installer/version manager) and the Foundry
# toolchain (forge, cast, anvil, chisel). PATH is wired centrally in
# ~/.config/prb/path.sh, so we pre-add the bin dir to PATH to stop the upstream
# installer from appending a PATH export to the shell rc files.
# run_onchange_: re-runs whenever this file changes.
# shellcheck disable=SC2034

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# run_onchange_ scripts execute from a temp dir, so source from the installed path
source "$HOME/.setup/lib/common.sh"

if ! command -v curl &>/dev/null; then
  log_error "curl not found on PATH; skipping Foundry provisioning"
  exit 0
fi

# Match FOUNDRY_DIR from env_core.sh (defaults to $XDG_DATA_HOME/foundry).
FOUNDRY_DIR="${FOUNDRY_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/foundry}"
export FOUNDRY_DIR
foundry_bin="$FOUNDRY_DIR/bin"
changed=0

# Pre-seed PATH so the upstream installer detects the bin dir and skips rc edits.
case ":$PATH:" in
*":$foundry_bin:"*) ;;
*) export PATH="$foundry_bin:$PATH" ;;
esac

if ! command -v foundryup &>/dev/null; then
  log_info "Installing foundryup..."
  curl -L https://foundry.paradigm.xyz | bash
  changed=1
fi

# Bootstrap the toolchain on first install. To update later, run: foundryup
if ! command -v forge &>/dev/null; then
  log_info "Installing the Foundry toolchain (forge, cast, anvil, chisel)..."
  foundryup
  changed=1
fi

if ((changed)); then
  log_success "Foundry toolchain ready"
fi
