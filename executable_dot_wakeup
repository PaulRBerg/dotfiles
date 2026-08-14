#!/usr/bin/env bash
# Wakeup script for sleepwatcher
# Runs when Mac wakes from sleep

# Sleepwatcher runs with a minimal PATH; ensure user and Homebrew binaries are available
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

_wakeup_commit_and_push() {
  local repo="$1"
  local message="$2"
  local prepare_output transaction_id
  shift 2

  if ! command -v ai-commit >/dev/null 2>&1; then
    echo "Skipping commit and push for $repo (ai-commit is unavailable)"
    return 1
  fi
  if ! prepare_output="$(cd "$repo" && ai-commit prepare --no-auto-baseline --porcelain "$@")"; then
    echo "Skipping commit and push for $repo (preparation failed)"
    return 1
  fi
  transaction_id="$(awk -F '\t' '$1 == "PREPARED" { print $2; exit }' <<<"$prepare_output")"
  if [[ -z "$transaction_id" ]]; then
    echo "Skipping commit and push for $repo (preparation returned no transaction)"
    return 1
  fi

  (cd "$repo" && ai-commit commit "$transaction_id" -m "$message" --push)
}

# ------------------------------
# SSH key
# ------------------------------
# Safety net behind the local.ssh-load-keychain LaunchAgent, for the case where
# the agent lost the key while asleep. `ssh-add -l` prints fingerprints and
# comments, never paths, so the guard has to match on the fingerprint. The
# passphrase comes from the login keychain, so this never prompts.
SSH_KEY_PUB="$HOME/.ssh/github/key.pub"
if [[ -f "$SSH_KEY_PUB" ]]; then
  ssh_fingerprint="$(/usr/bin/ssh-keygen -lf "$SSH_KEY_PUB" | awk '{print $2}')"
  if ! /usr/bin/ssh-add -l 2>/dev/null | grep -qF "$ssh_fingerprint"; then
    echo "Loading SSH key into the agent"
    /usr/bin/ssh-add --apple-load-keychain 2>&1 || true
  fi
fi

# ------------------------------
# Pull repos
# ------------------------------
PULL_REPOS=(
  "$HOME/.claude"
  "$HOME/.agents"
  "$HOME/.local/share/chezmoi"
  "$HOME/projects/agent-skills"
)

for repo in "${PULL_REPOS[@]}"; do
  if [[ ! -d "$repo/.git" ]]; then
    continue
  fi
  if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
    echo "Skipping $repo (dirty worktree)"
    continue
  fi
  echo "Pulling $repo"
  git -C "$repo" pull --ff-only 2>&1 || true
done

# ------------------------------
# Refresh CLI-backed agent skills
# ------------------------------
REFRESH_CLI_SKILLS="$HOME/.config/prb/wakeup/refresh_cli_skills.sh"
if [[ -x "$REFRESH_CLI_SKILLS" ]]; then
  "$REFRESH_CLI_SKILLS" 2>&1 || true
else
  echo "Skipping CLI-backed skill refresh (missing $REFRESH_CLI_SKILLS)"
fi

# ------------------------------
# Effect: pin to latest npm release
# ------------------------------
# The Effect monorepo ships breaking changes on main between releases. Keep the
# local checkout pinned to the most recent published release instead of main,
# exposed as a local `release` branch built from the newest effect@* tag
# reachable on origin/main (every package in a release shares that commit).
EFFECT_DIR="$HOME/.effect"
if [[ -d "$EFFECT_DIR/.git" ]] && [[ -z "$(git -C "$EFFECT_DIR" status --porcelain 2>/dev/null)" ]]; then
  echo "Fetching Effect"
  git -C "$EFFECT_DIR" fetch --tags --prune origin 2>&1 || true
  latest_tag="$(git -C "$EFFECT_DIR" describe --tags --match 'effect@*' --abbrev=0 origin/main 2>/dev/null)"
  if [[ -n "$latest_tag" ]]; then
    release_commit="$(git -C "$EFFECT_DIR" rev-list -n1 "$latest_tag")"
    if [[ "$release_commit" != "$(git -C "$EFFECT_DIR" rev-parse HEAD)" ]]; then
      echo "Pinning Effect to $latest_tag"
      git -C "$EFFECT_DIR" checkout -B release "$release_commit" 2>&1 || true
    else
      echo "Effect already on $latest_tag"
    fi
  fi
fi

# ------------------------------
# Merge Claude settings
# ------------------------------
CLAUDE_DIR="$HOME/.claude"
if [[ -d "$CLAUDE_DIR/.git" ]] && [[ -z "$(git -C "$CLAUDE_DIR" status --porcelain 2>/dev/null)" ]]; then
  echo "Merging Claude settings"
  (cd "$CLAUDE_DIR" && just merge-settings 2>&1) || true
fi

# ------------------------------
# Build Codex AGENTS.md
# ------------------------------
CODEX_DIR="$HOME/.codex"
if [[ -d "$CODEX_DIR/.git" ]] && [[ -z "$(git -C "$CODEX_DIR" status --porcelain 2>/dev/null)" ]]; then
  echo "Building Codex AGENTS.md"
  if (cd "$CODEX_DIR" && just build 2>&1); then
    if ! unexpected_codex_changes="$(git -C "$CODEX_DIR" status --porcelain -- . ':(top,exclude)AGENTS.md' 2>/dev/null)"; then
      echo "Skipping Codex commit and push (could not inspect build output)"
    elif [[ -n "$unexpected_codex_changes" ]]; then
      echo "Skipping Codex commit and push (just build changed paths other than AGENTS.md)"
    elif [[ -n "$(git -C "$CODEX_DIR" status --porcelain -- AGENTS.md 2>/dev/null)" ]]; then
      echo "Committing and pushing Codex AGENTS.md"
      _wakeup_commit_and_push "$CODEX_DIR" "Build AGENTS.md $(date -u +%Y-%m-%d@%H-%M-%S)" -- AGENTS.md || true
    else
      echo "Codex AGENTS.md is already current"
    fi
  else
    echo "Skipping Codex commit and push (build failed)"
  fi
fi

# ------------------------------
# Update package managers
# ------------------------------
# bun and Cargo live in their own install dirs, npm comes from fnm, and Go may
# use its default GOPATH bin dir; none are guaranteed on sleepwatcher's PATH.
export PATH="$HOME/.local/share/bun/bin:${CARGO_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/cargo}/bin:${GOBIN:-${GOPATH:-$HOME/go}/bin}:$HOME/Library/Application Support/fnm/aliases/default/bin:$PATH"

DEV_HELPERS_SOURCE="${XDG_CONFIG_HOME:-$HOME/.config}/prb/functions/dev.sh"
if [[ -r "$DEV_HELPERS_SOURCE" ]]; then
  # shellcheck source=dot_config/prb/functions/dev.sh
  source "$DEV_HELPERS_SOURCE"
fi

if command -v bun >/dev/null; then
  echo "Updating bun"
  bun upgrade 2>&1 || true
  if declare -F upgrade_bun_globals >/dev/null; then
    echo "Updating global bun packages"
    upgrade_bun_globals 2>&1 || true
  fi
fi

# pnpm comes from Homebrew; upgrade only when a newer bottle is already known
# locally, without triggering brew's network auto-update on every wake.
if command -v brew >/dev/null; then
  echo "Updating pnpm"
  HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade pnpm 2>&1 || true
fi

if command -v npm >/dev/null; then
  echo "Updating npm"
  npm install -g npm 2>&1 || true
fi

# ------------------------------
# Update Rust and Cargo packages
# ------------------------------
if command -v rustup >/dev/null; then
  echo "Updating Rust toolchains"
  rustup update 2>&1 || true
fi

if command -v cargo >/dev/null && declare -F upgrade_cargo_globals >/dev/null; then
  echo "Updating global Cargo packages"
  upgrade_cargo_globals 2>&1 || true
fi

# ------------------------------
# Update Go binaries
# ------------------------------
if command -v go >/dev/null && declare -F upgrade_go_globals >/dev/null; then
  echo "Updating global Go binaries"
  upgrade_go_globals 2>&1 || true
fi

# ------------------------------
# Update uv and its tools
# ------------------------------
# Standalone install; not on sleepwatcher's PATH
UV="$HOME/.local/bin/uv"
if [[ -x "$UV" ]]; then
  echo "Updating uv"
  "$UV" self update 2>&1 || true
  echo "Updating uv tools"
  "$UV" tool upgrade --all 2>&1 || true
fi

# ------------------------------
# Commit and push dictionary
# ------------------------------
DICTIONARY_DIR="$HOME/work/dictionary"
if [[ -d "$DICTIONARY_DIR/.git" ]]; then
  if [[ -n "$(git -C "$DICTIONARY_DIR" status --porcelain 2>/dev/null)" ]]; then
    echo "Committing and pushing dictionary changes"
    _wakeup_commit_and_push "$DICTIONARY_DIR" "Update words $(date -u +%Y-%m-%d@%H-%M-%S)" --all || true
  elif command -v ai-commit >/dev/null 2>&1; then
    echo "Pushing dictionary"
    (cd "$DICTIONARY_DIR" && ai-commit push) || true
  else
    echo "Skipping dictionary push (ai-commit is unavailable)"
  fi
fi
