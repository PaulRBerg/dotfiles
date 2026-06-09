#!/usr/bin/env bash

###############################################################################
# GIT                                                                         #
###############################################################################

# Use Git's colored diff when available
if hash git &>/dev/null; then
  function diff() {
    git diff --no-index --color-words "$@"
  }
fi

function _git_require_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "❌ Not a git repository" >&2
    return 1
  fi
}

function _git_require_clean_worktree() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "❌ Working tree is dirty - commit or stash changes first" >&2
    return 1
  fi
}

function _git_current_branch() {
  git branch --show-current
}

function _git_is_protected_branch() {
  case "$1" in
  main | master | staging | production | release | release/*)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

function _git_require_unprotected_branch() {
  local branch="$1"

  if _git_is_protected_branch "$branch"; then
    echo "❌ Refusing to modify protected branch '$branch'" >&2
    return 1
  fi
}

function _git_default_branch() {
  if git show-ref --verify --quiet refs/heads/main; then
    echo "main"
  elif git show-ref --verify --quiet refs/heads/master; then
    echo "master"
  else
    return 1
  fi
}

function _git_confirm() {
  local prompt="$1"

  read -r "REPLY?$prompt [y/N] "
  [[ "$REPLY" =~ ^[Yy]$ ]]
}

# Flatten current branch commits into a single commit.
# On feature branches: flattens commits since diverging from main/master.
# On main/master: flattens entire history to root commit.
# Usage: flatten_branch [commit_message]
function flatten_branch() {
  _git_require_repo || return 1

  local current_branch
  current_branch=$(_git_current_branch)
  if [[ -z "$current_branch" ]]; then
    echo "❌ Cannot flatten in detached HEAD state" >&2
    return 1
  fi

  _git_require_unprotected_branch "$current_branch" || return 1
  _git_require_clean_worktree || return 1

  local message="${1:-Initial commit}"

  # Detect base branch
  local base_branch
  if ! base_branch=$(_git_default_branch); then
    echo "❌ No main or master branch found" >&2
    return 1
  fi

  local reset_target commit_count
  if [[ "$current_branch" == "$base_branch" ]]; then
    # On main/master: flatten entire history (take first root if multiple exist)
    reset_target=$(git rev-list --max-parents=0 HEAD 2>/dev/null | head -n1)
    if [[ -z "$reset_target" ]]; then
      echo "❌ No commits found" >&2
      return 1
    fi
    commit_count=$(git rev-list --count HEAD)
  else
    # On feature branch: flatten since base
    reset_target="$base_branch"
    commit_count=$(git rev-list --count "${base_branch}..HEAD")
  fi

  if [[ "$commit_count" -eq 0 ]]; then
    echo "ℹ️  No commits to flatten"
    return 0
  fi
  if [[ "$commit_count" -eq 1 ]]; then
    echo "ℹ️  Already a single commit"
    return 0
  fi

  echo "⚠️  This will flatten $commit_count commits on '$current_branch' into one"
  _git_confirm "Continue?" || return 0

  echo "🔄 Flattening branch..."
  git reset --soft "$reset_target" || {
    echo "❌ Reset failed" >&2
    return 1
  }

  if [[ "$current_branch" == "$base_branch" ]]; then
    git commit --amend -m "$message" || {
      echo "❌ Commit failed" >&2
      return 1
    }
  else
    git commit -m "$message" || {
      echo "❌ Commit failed" >&2
      return 1
    }
  fi

  echo "✅ Branch flattened to single commit: $message"
}

function gocp() {
  go_cherry_pick "$@"
}

# Checkout a temporary branch `tmp`, cherry pick the provided commit(s), and
# finally replace the provided branch name
# Usage: go_cherry_pick <branch_name> [start_commit] [end_commit]
#   If start_commit is omitted, uses the first commit of the current branch (after main)
function go_cherry_pick() {
  _git_require_repo || return 1
  _git_require_clean_worktree || return 1

  local branch_name="$1"
  local start_commit="$2" # optional: defaults to first commit of branch
  local end_commit="$3"   # optional

  if [[ -z "$branch_name" ]]; then
    echo "Branch name not provided, aborting"
    return 1
  fi

  _git_require_unprotected_branch "$branch_name" || return 1

  if [[ "$branch_name" = tmp* ]]; then
    echo "The branch name cannot start with tmp"
    return 1
  fi

  local original_branch
  original_branch=$(_git_current_branch)
  if [[ -z "$original_branch" ]]; then
    echo "Cannot cherry-pick in detached HEAD state, aborting"
    return 1
  fi

  # Detect base branch (main or master)
  local base_branch
  if ! base_branch=$(_git_default_branch); then
    echo "No main or master branch found, aborting"
    return 1
  fi

  # If start_commit not provided, use the first commit of the branch
  if [[ -z "$start_commit" ]]; then
    start_commit=$(git rev-list --ancestry-path "${base_branch}..HEAD" | tail -1)
    if [[ -z "$start_commit" ]]; then
      echo "No commits found on branch after ${base_branch}, aborting"
      return 1
    fi
    echo "Using first commit of branch: $(git log --oneline -1 "$start_commit")"
  fi

  local tmp_branch backup_branch
  tmp_branch="tmp-go-cherry-pick-$$"
  backup_branch="${branch_name}.backup.$$"

  git switch -c "$tmp_branch" "$base_branch" || return 1

  if [[ -z "$end_commit" ]]; then
    git cherry-pick "$start_commit" || {
      echo "Cherry-pick failed; leaving '$tmp_branch' for inspection" >&2
      return 1
    }
  else
    git cherry-pick "$start_commit"^.."$end_commit" || {
      echo "Cherry-pick failed; leaving '$tmp_branch' for inspection" >&2
      return 1
    }
  fi

  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    git branch -m "$branch_name" "$backup_branch" || return 1
    if git branch -m "$tmp_branch" "$branch_name"; then
      git branch -D "$backup_branch"
    else
      git branch -m "$backup_branch" "$branch_name"
      echo "Failed to rename '$tmp_branch' to '$branch_name'; restored original branch" >&2
      return 1
    fi
  else
    git branch -m "$tmp_branch" "$branch_name" || return 1
  fi

  git switch "$branch_name"
}

# Fuzzy branch switch with commit preview
function gsf() {
  git for-each-ref refs/heads/ --sort=-committerdate --format='%(refname:short)' |
    fzf --height 40% --reverse \
      --preview 'git log --oneline --graph --color=always -10 {}' |
    xargs git switch
}

# Fuzzy stash browser
function gstf() {
  git stash list |
    fzf --height 40% --reverse \
      --preview 'git stash show -p {1}' |
    cut -d: -f1 |
    xargs git stash pop
}

# Replace history with a fresh root commit pushed to GitHub main branch.
# Preserves the existing origin remote URL from the current git configuration.
# Note: This function only works with the main branch (not master or other branches).
function nuke_git_main() {
  _git_require_repo || return 1
  _git_require_clean_worktree || return 1

  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null)
  if [[ -z "$remote_url" ]]; then
    echo "❌ No origin remote found" >&2
    return 1
  fi

  local current_branch
  current_branch=$(_git_current_branch)
  if [[ "$current_branch" != "main" ]]; then
    echo "❌ Refusing to reset history from '$current_branch'; switch to main first" >&2
    return 1
  fi

  echo "⚠️  This will destroy all git history and force push to origin/main"
  echo "   Repo: $remote_url"
  read -r "REPLY?Type 'nuke origin/main' to continue: "
  [[ "$REPLY" != "nuke origin/main" ]] && return 0

  local tmp_branch
  tmp_branch="tmp-nuke-main-$$"

  echo "🔧 Creating fresh root commit..."
  git switch --orphan "$tmp_branch" || return 1
  git add -A || return 1

  git commit -q -m "Initial commit" || {
    echo "❌ Failed to commit" >&2
    git switch main >/dev/null 2>&1
    git branch -D "$tmp_branch" >/dev/null 2>&1
    return 1
  }

  echo "🚀 Force pushing to origin/main..."
  git push -ufq origin "$tmp_branch:main" || {
    echo "❌ Failed to push" >&2
    git switch main >/dev/null 2>&1
    git branch -D "$tmp_branch" >/dev/null 2>&1
    return 1
  }

  git branch -M main || {
    echo "❌ Failed to rename fresh branch to main" >&2
    return 1
  }

  echo "✅ Repository history reset successfully"
}

# Reinitialize git submodules when switching between branches
function reinit() {
  _git_require_repo || return 1

  if ! git config --file .gitmodules --get-regexp path >/dev/null 2>&1; then
    echo "ℹ️  No submodules configured"
    return 0
  fi

  # shellcheck disable=SC2016
  if ! git submodule foreach --quiet 'test -z "$(git status --porcelain)"'; then
    echo "❌ Submodule working tree is dirty - commit or stash changes first" >&2
    return 1
  fi

  _git_confirm "Reinitialize all submodules?" || return 0

  git submodule deinit --force .
  git submodule update --init --recursive
}
