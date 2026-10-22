#!/usr/bin/env bash

USER_DIR="${USER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/prb}"

# Compatibility wrapper for manual sourcing.
[[ -r "$USER_DIR/env_core.sh" ]] && source "$USER_DIR/env_core.sh"
[[ -r "$USER_DIR/env_session.sh" ]] && source "$USER_DIR/env_session.sh"
