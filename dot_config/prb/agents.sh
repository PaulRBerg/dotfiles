#!/usr/bin/env bash
# shellcheck disable=SC2139 - expand CODEX_MODEL at define time

###############################################################################
# CONSTANTS                                                                   #
###############################################################################

CODEX_MODEL="gpt-5.4"

###############################################################################
# ALIASES                                                                     #
###############################################################################

alias c="claude --dangerously-skip-permissions"
alias cda="cd ~/.agents"
alias cd_agents="cd ~/.agents"
alias cd_claude="cd ~/.claude"
alias cd_codex="cd ~/.codex"
alias cd_gemini="cd ~/.gemini"
alias cd_sk="cd ~/projects/agent-skills"
alias codex="codex --dangerously-bypass-approvals-and-sandbox"
alias codex5l="codex -m $CODEX_MODEL -c model_reasoning_effort=low"
alias codex5m="codex -m $CODEX_MODEL -c model_reasoning_effort=medium"
alias codex5h="codex -m $CODEX_MODEL -c model_reasoning_effort=high"
alias codex5x="codex -m $CODEX_MODEL -c model_reasoning_effort=xhigh"
alias gemini="gemini --yolo"
alias edit_claude="code ~/.claude"
alias edit_codex="code ~/.codex"
alias edit_gemini="code ~/.gemini"

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

  local output
  output=$(
    gum spin --spinner dot --title "Claude is git committing..." -- \
      claude --model "sonnet" --no-session-persistence --output-format json \
      --print "/commit $*"
  )

  jq -r '.result' <<<"$output"
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
    claude --model "sonnet" --no-session-persistence --output-format json \
    --print "/bump-release $*"
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
