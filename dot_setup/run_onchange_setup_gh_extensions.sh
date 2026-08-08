#!/usr/bin/env bash
# Provision GitHub CLI extensions.
# run_onchange_: re-runs whenever this file changes (e.g. when EXTENSIONS is edited).
# shellcheck disable=SC2034

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# run_onchange_ scripts execute from a temp dir, so source from the installed path
source "$HOME/.setup/lib/common.sh"

if ! command -v gh &>/dev/null; then
  log_error "gh not found on PATH; skipping gh extension provisioning"
  exit 0
fi

if ! gh auth status &>/dev/null; then
  log_info "gh is not authenticated; skipping gh extension provisioning"
  exit 0
fi

# gh extensions to install. Editing this list re-triggers the script.
readonly EXTENSIONS=(
  dlvhdr/gh-dash
  seachicken/gh-poi
)

installed="$(gh extension list 2>/dev/null || true)"

for extension in "${EXTENSIONS[@]}"; do
  name="${extension#*/}"
  if grep -q "/${name}\b" <<<"$installed"; then
    log_info "Upgrading ${extension}..."
    gh extension upgrade "$name"
  else
    log_info "Installing ${extension}..."
    gh extension install "$extension"
  fi
done

log_success "gh extensions ready"
