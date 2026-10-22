#!/usr/bin/env bash

PRB_CONFIG_DIR="${PRB_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/prb}"

# Compatibility wrapper for manual sourcing.
[[ -r "$PRB_CONFIG_DIR/env_core.sh" ]] && source "$PRB_CONFIG_DIR/env_core.sh"
[[ -r "$PRB_CONFIG_DIR/env_session.sh" ]] && source "$PRB_CONFIG_DIR/env_session.sh"
