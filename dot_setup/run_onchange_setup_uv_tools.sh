#!/usr/bin/env bash
# Provision uv-managed CPython and the global Python CLI tools.
# run_onchange_: re-runs whenever this file changes (e.g. when TOOLS is edited).
# shellcheck disable=SC2034

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# run_onchange_ scripts execute from a temp dir, so source from the installed path
source "$HOME/.setup/lib/common.sh"

if ! command -v uv &>/dev/null; then
  log_error "uv not found on PATH; skipping Python tool provisioning"
  exit 0
fi

# Keep in sync with the global default pinned in ~/.config/uv/.python-version
# and the only-managed preference in ~/.config/uv/uv.toml.
readonly PYTHON_VERSION="3.14"

# Global CLI tools, each installed into its own uv-managed venv on
# PYTHON_VERSION. Editing this list re-triggers the script via run_onchange.
readonly TOOLS=(
  cfn-lint
  claude-code-transcripts
  extract-msg
  gita
  it2
  mdformat
  pynvim
  pytest
  python-lsp-server
  ruff
  sqlfluff
)

# Extra packages injected into a tool's venv via --with (plugins, extensions).
# mdformat: without these plugins it corrupts YAML frontmatter and lacks GFM
# support (tables, strikethrough, autolinks, task lists).
declare -rA TOOL_PLUGINS=(
  [mdformat]="mdformat-frontmatter mdformat-gfm"
)

log_info "Installing uv-managed CPython ${PYTHON_VERSION}..."
uv python install "${PYTHON_VERSION}"

log_info "Installing ${#TOOLS[@]} uv tools on CPython ${PYTHON_VERSION}..."
for tool in "${TOOLS[@]}"; do
  install_args=("${tool}" --python "${PYTHON_VERSION}")
  for plugin in ${TOOL_PLUGINS[$tool]:-}; do
    install_args+=(--with "${plugin}")
  done
  uv tool install "${install_args[@]}"
done

# Repair drift if an interpreter was ever removed:
#   uv tool upgrade --all --reinstall
log_success "uv Python toolchain ready"
