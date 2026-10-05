#!/usr/bin/env bash
# Sleep script for sleepwatcher
# Runs when Mac enters sleep mode

# Sleepwatcher runs with a minimal PATH; ensure Homebrew binaries are available
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Sleepwatcher discards hook output, so log each run for the launchd dashboard,
# which splits runs on these marker lines (see dot_config/launchd-dashboard/server.ts).
HOOK_LOG="$HOME/Library/Logs/sleepwatcher-sleep.log"
if [[ -f "$HOOK_LOG" ]] && (($(wc -c <"$HOOK_LOG") > 2097152)); then
  mv -f "$HOOK_LOG" "$HOOK_LOG.1"
fi
exec >>"$HOOK_LOG" 2>&1
echo "=== sleepwatcher sleep start $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
trap 'rc=$?; echo "=== sleepwatcher sleep end $(date -u +%Y-%m-%dT%H:%M:%SZ) exit=$rc ==="' EXIT

# ------------------------------
# Stop Next.js dev servers
# ------------------------------
ports=(4001 4003 5001 5003 6100)

for p in "${ports[@]}"; do
  # Check if something is listening on the port
  if lsof -i tcp:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Killing server on port $p"
    killport "$p"
  fi
done
