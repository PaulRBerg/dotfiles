#!/usr/bin/env bash

###############################################################################
# NETWORK                                                                     #
###############################################################################

# Run `dig` and display the most useful info
function digga() {
  dig +nocmd "$1" any +multiline +noall +answer
}

# Print the primary local IP address.
function localip() {
  ipconfig getifaddr en0
}
