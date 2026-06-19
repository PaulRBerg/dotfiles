#!/usr/bin/env bash
# shellcheck disable=SC2139 - expand CODEX_MODEL at define time

###############################################################################
# CONSTANTS                                                                   #
###############################################################################

CODEX_MODEL="gpt-5.5"

###############################################################################
# ALIASES                                                                     #
###############################################################################

alias c="codex"
alias cl="claude --dangerously-skip-permissions"
alias c5l="codex -m $CODEX_MODEL -c model_reasoning_effort=low"
alias c5m="codex -m $CODEX_MODEL -c model_reasoning_effort=medium"
alias c5h="codex -m $CODEX_MODEL -c model_reasoning_effort=high"
alias c5x="codex -m $CODEX_MODEL -c model_reasoning_effort=xhigh"
alias cda="cd ~/.agents"
alias cd_agents="cd ~/.agents"
alias cd_claude="cd ~/.claude"
alias cd_codex="cd ~/.codex"
alias cd_sk="cd ~/projects/agent-skills"
alias edit_claude="code ~/.claude"
alias edit_codex="code ~/.codex"

###############################################################################
# FUNCTIONS                                                                   #
###############################################################################

# Claude Code commit
function ccc() {
  _require_gum || return 1

  if ! git rev-parse --git-dir &>/dev/null; then
    echo "❌ Error: Not in a git repository"
    return 1
  fi

  if [[ -z "$(git status --porcelain)" ]]; then
    echo "No changes to commit (working tree clean)"
    return 0
  fi

  [[ $# -eq 0 ]] && set -- --all

  # Hard timeout so a stall can never become an unbounded hang (coreutils
  # ships `gtimeout` on macOS, `timeout` on Linux). Override with CCC_TIMEOUT.
  local timeout_cmd=""
  if command -v timeout &>/dev/null; then
    timeout_cmd="timeout ${CCC_TIMEOUT:-300}"
  elif command -v gtimeout &>/dev/null; then
    timeout_cmd="gtimeout ${CCC_TIMEOUT:-300}"
  fi

  # Redirect Claude's JSON to a file instead of capturing it through gum's
  # pipe. Claude spawns background workers (prefetch/keychain reads) that can
  # inherit the capture pipe and hold it open after the commit already landed,
  # wedging `$(...)`/gum forever. Writing to a file breaks that fd inheritance.
  # The commit skill runs helper scripts; this wrapper is noninteractive, so
  # Claude needs bypass mode instead of a permission prompt it cannot surface.
  # GIT_TERMINAL_PROMPT=0 turns a hidden credential prompt (e.g. cccp/--push)
  # into a fast failure instead of an invisible hang behind the spinner.
  local out err rc
  out=$(mktemp) || return 1
  err=$(mktemp) || return 1

  gum spin --spinner dot --title "Claude is git committing..." -- \
    sh -c "GIT_TERMINAL_PROMPT=0 ${timeout_cmd} \
      claude \
        --no-session-persistence \
        --output-format json \
        --strict-mcp-config \
        --tools \"Bash,Read\" \
        --permission-mode bypassPermissions \
        --print \"/commit \$1\" \
        >\"\$2\" \
        2>\"\$3\"" \
    _ "$*" "$out" "$err"
  rc=$?

  if ((rc != 0)) || [[ ! -s "$out" ]]; then
    echo "❌ ccc failed (exit ${rc}; 124 = timed out)" >&2
    [[ -s "$err" ]] && sed 's/^/   /' "$err" >&2
    rm -f "$out" "$err"
    return 1
  fi

  jq -r '.result' "$out"
  rm -f "$out" "$err"
}

# Claude Code commit and push
# Best suited for feature branches with upstream configured
function cccp() {
  ccc --all --push
}

# Claude Code bump release
function ccbump() {
  _require_gum || return 1
  gum spin --spinner dot --title "Claude is bumping release..." -- \
    claude --no-session-persistence --output-format json \
    --print "/bump-release $*"
}

# Add skills globally for the agents that support global installs.
function add_skill() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: add_skill <repo> [--skill <skill> ...]" >&2
    return 2
  fi

  local repo="$1"
  shift

  npx skills add "$repo" --global --yes --agent codex claude-code "$@"
}

###############################################################################
# PRIVATE                                                                     #
###############################################################################

# Helper to ensure gum is installed (used for spinners)
function _require_gum() {
  if ! command -v gum &>/dev/null; then
    echo "❌ Error: gum is required for this command"
    echo "Install: brew install gum (macOS) or sudo apt install gum (Ubuntu)"
    return 1
  fi
}
