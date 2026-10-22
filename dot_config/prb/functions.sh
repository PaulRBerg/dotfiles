#!/usr/bin/env bash

PRB_CONFIG_DIR="${PRB_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/prb}"

source "$PRB_CONFIG_DIR/functions/clipboard.sh"
source "$PRB_CONFIG_DIR/functions/dev.sh"
source "$PRB_CONFIG_DIR/functions/fs.sh"
source "$PRB_CONFIG_DIR/functions/git.sh"
[[ -r "$PRB_CONFIG_DIR/functions/macos.sh" ]] && source "$PRB_CONFIG_DIR/functions/macos.sh"
source "$PRB_CONFIG_DIR/functions/network.sh"
source "$PRB_CONFIG_DIR/functions/shell.sh"
source "$PRB_CONFIG_DIR/functions/symlinks.sh"
source "$PRB_CONFIG_DIR/functions/text.sh"
