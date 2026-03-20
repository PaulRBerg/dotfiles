#!/usr/bin/env bash

USER_DIR="${USER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/prb}"

source "$USER_DIR/functions/clipboard.sh"
source "$USER_DIR/functions/dev.sh"
source "$USER_DIR/functions/fs.sh"
source "$USER_DIR/functions/git.sh"
source "$USER_DIR/functions/shell.sh"
source "$USER_DIR/functions/symlinks.sh"
source "$USER_DIR/functions/utils.sh"
