#!/usr/bin/env bash

PRB_CONFIG_DIR="${PRB_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/prb}"

source "$PRB_CONFIG_DIR/aliases/basics.sh"
source "$PRB_CONFIG_DIR/aliases/locations.sh"

source "$PRB_CONFIG_DIR/aliases/macos.sh"
