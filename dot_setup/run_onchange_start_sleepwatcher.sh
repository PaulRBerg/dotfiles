#!/usr/bin/env bash
# Ensure sleepwatcher service is running via brew services

if ! command -v brew &>/dev/null; then
  exit 0 # Homebrew not installed, skip
fi

if ! brew list sleepwatcher &>/dev/null; then
  exit 0 # sleepwatcher not installed, skip
fi

if ! brew services list | grep -q "sleepwatcher.*started"; then
  echo "Starting sleepwatcher service..." >&2
  brew services start sleepwatcher
  echo "Sleepwatcher started" >&2
fi
