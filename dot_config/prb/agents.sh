#!/usr/bin/env bash
# shellcheck disable=SC2139 - expand CODEX_MODEL at define time

###############################################################################
# CONSTANTS                                                                   #
###############################################################################

CODEX_MODEL="gpt-5.6-sol"

# Lite headless Claude: skip hooks, CLAUDE.md, bundled skills, auto-memory, and
# nonessential network traffic (~3.5x faster one-shot skill runs). Keep
# --setting-sources user: user settings are what make /commit et al. resolve.
# --bare would be faster still but refuses OAuth/keychain auth (needs an API key).
CLAUDE_LITE_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 \
CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1 \
CLAUDE_CODE_DISABLE_AUTO_MEMORY=1"
CLAUDE_LITE_FLAGS="--no-session-persistence \
--output-format json \
--permission-mode bypassPermissions \
--strict-mcp-config \
--setting-sources user \
--settings '{\"disableAllHooks\":true}'"

###############################################################################
# ALIASES                                                                     #
###############################################################################

alias c="codex"
alias c_s="codex -m gpt-5.6-sol"
alias c_t="codex -m gpt-5.6-terra"
alias c_l="codex -m gpt-5.6-luna"
alias cda="cd ~/.agents"
alias cd_agents="cd ~/.agents"
alias cd_claude="cd ~/.claude"
alias cd_codex="cd ~/.codex"
alias cd_omp="cd ~/.omp"
alias cd_sk="cd ~/projects/agent-skills"
alias cl="claude --dangerously-skip-permissions"
alias edit_claude="code ~/.claude"
alias edit_codex="code ~/.codex"

###############################################################################
# FUNCTIONS                                                                   #
###############################################################################

# Claude Code commit
function ccc() {
  _require_gum || return 1
  _require_ai_commit || return 1

  if ! git rev-parse --git-dir &>/dev/null; then
    echo "❌ Error: Not in a git repository"
    return 1
  fi

  if [[ -z "$(git status --porcelain)" ]]; then
    echo "No changes to commit (working tree clean)"
    return 0
  fi

  [[ $# -eq 0 ]] && set -- --all

  _run_claude_skill "Claude is git committing..." "/commit $*" \
    --effort medium \
    --model sonnet \
    --tools Bash,Read
}

# Claude Code commit and push
# Best suited for feature branches with upstream configured
function cccp() {
  ccc --all --push
}

# Claude Code commit staged
# Commits only the currently staged index (git add your specific changes first)
function ccs() {
  ccc --staged "$@"
}

# Claude Code commit staged and push
function ccsp() {
  ccc --staged --push "$@"
}

# Claude Code bump release
function ccbump() {
  _require_gum || return 1
  _run_claude_skill "Claude is bumping release..." "/release-bumper $*"
}

# Claude Code todo archive
function ccta() {
  _require_gum || return 1

  local prompt='/todo-archive'
  [[ $# -gt 0 ]] && prompt+=" $*"

  _run_claude_skill "Claude is archiving TODOs..." "$prompt" \
    --effort medium \
    --model sonnet \
    --tools Bash,Read
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

# Helper to ensure ai-commit is installed (used by Claude's /commit skill).
function _require_ai_commit() {
  if ! command -v ai-commit &>/dev/null; then
    echo "❌ Error: ai-commit is required for this command" >&2
    echo 'Install: cargo install --git https://github.com/PaulRBerg/agent-toolkit ai-commit --locked --root "$HOME/.local"' >&2
    return 1
  fi
}

# _run_claude_skill <spinner-title> <prompt> [extra claude flags...]
# Runs a headless Claude skill in lite mode (see CLAUDE_LITE_ENV/CLAUDE_LITE_FLAGS).
function _run_claude_skill() {
  local title="$1" prompt="$2"
  shift 2

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
  # inherit the capture pipe and hold it open after the run already landed,
  # wedging `$(...)`/gum forever. Writing to a file breaks that fd inheritance.
  # The skills this runs invoke helper scripts; this wrapper is noninteractive,
  # so Claude needs bypass mode instead of a permission prompt it cannot
  # surface. GIT_TERMINAL_PROMPT=0 turns a hidden credential prompt (e.g.
  # cccp/--push) into a fast failure instead of an invisible hang behind the
  # spinner.
  local out err rc
  out=$(mktemp) || return 1
  err=$(mktemp) || return 1

  gum spin --spinner dot --title "$title" -- \
    sh -c "GIT_TERMINAL_PROMPT=0 ${CLAUDE_LITE_ENV} ${timeout_cmd} \
      claude ${CLAUDE_LITE_FLAGS} $* \
        --print \"\$1\" \
        >\"\$2\" \
        2>\"\$3\"" \
    _ "$prompt" "$out" "$err"
  rc=$?

  if ((rc != 0)) || [[ ! -s "$out" ]]; then
    echo "❌ claude skill failed (exit ${rc}; 124 = timed out)" >&2
    [[ -s "$err" ]] && sed 's/^/   /' "$err" >&2
    rm -f "$out" "$err"
    return 1
  fi

  jq -r '.result' "$out"
  rm -f "$out" "$err"
}
