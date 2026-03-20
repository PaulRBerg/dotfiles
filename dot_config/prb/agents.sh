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

# Helper to ensure gum is installed (used for spinners)
function _require_gum() {
  if ! command -v gum &>/dev/null; then
    echo "❌ Error: gum is required for this command"
    echo "Install: brew install gum (macOS) or sudo apt install gum (Ubuntu)"
    return 1
  fi
}

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
      claude --model "sonnet" --print "/commit $*" --output-format json
  )

  _claude_cleanup_session "$output"
  jq -r '.result' <<<"$output"
}

# Codex commit (message generated via Codex, commit performed locally)
function coc() {
  _require_gum || return 1

  if ! git rev-parse --git-dir &>/dev/null; then
    echo "❌ Error: Not in a git repository"
    return 1
  fi

  if [[ -z "$(git status --porcelain)" ]]; then
    echo "No changes to commit (working tree clean)"
    return 0
  fi

  local want_all=false
  local want_push=false
  local -a commit_args=()

  [[ $# -eq 0 ]] && want_all=true

  for arg in "$@"; do
    case "$arg" in
    --all) want_all=true ;;
    --push) want_push=true ;;
    -m | --message) echo "⚠️  Warning: Ignoring $arg (Codex generates the message)" ;;
    *) commit_args+=("$arg") ;;
    esac
  done

  [[ "$want_all" == true ]] && git add -A

  if git diff --cached --quiet; then
    echo "⚠️  Warning: No staged changes to commit"
    return 0
  fi

  local prompt_file="$HOME/.codex/prompts/commit.md"
  if [[ ! -f "$prompt_file" ]]; then
    echo "❌ Error: Missing $prompt_file"
    return 1
  fi

  local output
  output=$(
    {
      cat "$prompt_file"
      printf '\n'
      git diff --cached
    } |
      gum spin --spinner dot --title "Codex is drafting commit..." -- \
        command codex --dangerously-bypass-approvals-and-sandbox exec - \
        -m "$CODEX_MODEL" \
        -c model_reasoning_effort=low \
        --profile quiet \
        -s read-only \
        --skip-git-repo-check \
        2>/dev/null
  )

  local msg
  msg=$(printf '%s' "$output" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | head -n 1)
  [[ -z "$msg" ]] && {
    echo "❌ Error: Codex returned an empty commit message"
    return 1
  }
  if [[ "$msg" == *"approval_policy"* || "$msg" == *"sandbox"* || "$msg" == *"no session files"* ]]; then
    echo "❌ Error: Codex returned an error instead of a commit message"
    return 1
  fi

  git commit "${commit_args[@]}" -m "$msg"
  [[ "$want_push" == true ]] && git push
}

# Claude Code commit and push
# Best suited for feature branches with upstream configured
function cccp() {
  ccc --all --push
}

# Claude Code bump release
function ccbump() {
  _require_gum || return 1
  gum spin --spinner dot --title "Claude is bumping release..." -- claude --dangerously-skip-permissions --model "sonnet" --print "/bump-release $*"
}

# Helper function to resolve monorepo root when in app subdirectory
# Echoes the target directory (parent if in app subdir, otherwise PWD)
function _claude_get_monorepo_root() {
  if [[ "$PWD" =~ /sablier/new-ui/(portal|diff|landing)$ ]]; then
    echo "${PWD%/*}"
    return 0
  fi
  echo "$PWD"
  return 1
}

# Helper function to delete Claude conversation history from a JSON response
function _claude_cleanup_session() {
  local json_output="$1"

  # Extract session_id from JSON
  local session_id
  session_id=$(jq -r '.session_id' <<<"$json_output" 2>/dev/null)

  # Delete the .jsonl file if session_id exists
  if [[ -n "$session_id" && "$session_id" != "null" ]]; then
    local jsonl_file
    jsonl_file=$(find ~/.claude/projects -name "${session_id}.jsonl" 2>/dev/null | head -1)
    [[ -n "$jsonl_file" ]] && rm -f "$jsonl_file"
  fi
}
