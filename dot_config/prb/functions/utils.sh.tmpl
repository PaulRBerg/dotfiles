#!/usr/bin/env bash

###############################################################################
# UTILITIES                                                                   #
###############################################################################

# Run `dig` and display the most useful info
function digga() {
  dig +nocmd "$1" any +multiline +noall +answer
}

# Print the primary local IP address.
function localip() {
  ipconfig getifaddr en0
}

# Get macOS marketing name + version (e.g., "macOS Tahoe 26.1")
function macos_version() {
  local name
  name=$(awk -F 'macOS ' '/SOFTWARE LICENSE AGREEMENT FOR macOS/{gsub(/[0-9]+\\.*/, "", $2); gsub(/\\.*/, "", $2); print $2; exit}' "/System/Library/CoreServices/Setup Assistant.app/Contents/Resources/en.lproj/OSXSoftwareLicense.rtf" | tr -d ' ')
  echo "macOS $name $(sw_vers -productVersion)"
}

# Return the length of the given string
function strlen() {
  echo -n "$@" | wc -c
}
