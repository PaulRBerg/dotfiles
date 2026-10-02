#!/bin/zsh
set -eu

# Launched by Codex and Claude from ~/.codex/config.toml and ~/.claude.json.
# Upstream: https://github.com/ChromeDevTools/chrome-devtools-mcp
# Connect only to the existing debugging browser. Do not fall back to launching
# Chromium: that lets concurrent agents create extra windows or fresh profiles.
port="${PRB_AGENT_CHROMIUM_PORT:-9222}"

# Use the globally installed executable directly. Package runners such as bunx
# share temporary install directories, so concurrent agent startups can race
# while linking the same package and close the MCP transport before initialize.
bun_install="${BUN_INSTALL:-${XDG_DATA_HOME:-$HOME/.local/share}/bun}"
server="$bun_install/bin/chrome-devtools-mcp"
if [[ ! -x "$server" ]]; then
  print -u2 "chrome-devtools-mcp is not installed at $server; run ~/.setup/node.sh"
  exit 127
fi

# Long browser sessions can retain large accessibility snapshots and exhaust
# Node's default V8 heap, which closes the MCP transport while Chromium stays
# healthy. Keep enough headroom for document-heavy workflows.
export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--max-old-space-size=8192"

# Per-process server log (namespace mcp:log; export DEBUG='*' for verbose CDP
# traffic) so transport drops are diagnosable after the fact. Each agent
# session spawns its own server process, hence the PID suffix.
log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/chrome-devtools-mcp/logs"
mkdir -p "$log_dir"
find "$log_dir" -name 'server-*.log' -mtime +7 -delete 2>/dev/null || true

# Screenshot flags only set response-side defaults (JPEG ~3-5x smaller than
# PNG, downscaled to vision-model resolution); tools can still request PNG or
# full size explicitly.
exec "$server" \
  "--browser-url=http://127.0.0.1:$port" \
  --experimental-page-id-routing \
  --experimental-memory \
  --experimental-vision \
  --experimental-structured-content \
  --experimental-screencast \
  --experimental-ffmpeg-path=/opt/homebrew/bin/ffmpeg \
  --redact-network-headers \
  --no-performance-crux \
  --no-usage-statistics \
  --allow-unrestricted-paths \
  --screenshot-format=jpeg \
  --screenshot-quality=80 \
  --screenshot-max-width=1600 \
  --screenshot-max-height=1600 \
  "--log-file=$log_dir/server-$$.log"
