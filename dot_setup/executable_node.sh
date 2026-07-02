#!/usr/bin/env bash
# Install global command-line packages with bun.
#
# Invoked by `fnm_bump_node` (dot_config/prb/functions/dev.sh) and runnable
# directly as `~/.setup/node.sh`. Also auto-invoked by `chezmoi apply` via
# run_onchange_setup_node.sh.tmpl whenever lib/node_packages.sh changes — both
# entry points share that file so the package list lives in one place.
#
# Unlike npm globals — which are scoped to the active fnm Node version and
# wiped on every Node bump — bun installs these into its own global prefix
# ($BUN_INSTALL/bin, on PATH via path.sh.tmpl), so they persist across Node
# versions and only need (re)linking, not reinstalling.

# Fail on unset vars and masked pipe failures. `-e` is intentionally omitted:
# install_bun_globals continues past individual package failures by design.
set -uo pipefail

source "$HOME/.setup/lib/node_packages.sh"
install_bun_globals
