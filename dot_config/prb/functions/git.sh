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

# Flatten current branch commits into a single commit.
# On feature branches: flattens commits since diverging from main/master.
# On main/master: flattens entire history to root commit.
# Usage: flatten_branch [commit_message]
function flatten_branch() {
  if [[ ! -d .git ]]; then
    echo "❌ Not a git repository" >&2
    return 1
  fi

  local current_branch
  current_branch=$(git branch --show-current)
  if [[ -z "$current_branch" ]]; then
    echo "❌ Cannot flatten in detached HEAD state" >&2
    return 1
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "❌ Working tree is dirty - commit or stash changes first" >&2
    return 1
  fi

  local message="${1:-Initial commit}"

  # Detect base branch
  local base_branch
  if git show-ref --verify --quiet refs/heads/main; then
    base_branch="main"
  elif git show-ref --verify --quiet refs/heads/master; then
    base_branch="master"
  else
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
  read -r "REPLY?Continue? [y/N] "
  [[ ! "$REPLY" =~ ^[Yy]$ ]] && return 0

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
  local branch_name="$1"
  local start_commit="$2" # optional: defaults to first commit of branch
  local end_commit="$3"   # optional

  if [[ -z "$branch_name" ]]; then
    echo "Branch name not provided, aborting"
    return 1
  fi

  if [[ "$branch_name" = "tmp" ]]; then
    echo "The branch name cannot be tmp"
    return 1
  fi

  # Detect base branch (main or master)
  local base_branch
  if git show-ref --verify --quiet refs/heads/main; then
    base_branch="main"
  elif git show-ref --verify --quiet refs/heads/master; then
    base_branch="master"
  else
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

  git checkout -b tmp
  if [[ -z "$end_commit" ]]; then
    git cherry-pick "$start_commit"
  else
    git cherry-pick "$start_commit"^.."$end_commit"
  fi

  git branch -D "$branch_name"
  git branch -m "$branch_name"
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

# Nuke .git and reinitialize with fresh history pushed to GitHub main branch.
# Preserves the existing origin remote URL from the current git configuration.
# Note: This function only works with the main branch (not master or other branches).
function nuke_git_main() {
  if [[ ! -d .git ]]; then
    echo "❌ Not a git repository" >&2
    return 1
  fi

  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null)
  if [[ -z "$remote_url" ]]; then
    echo "❌ No origin remote found" >&2
    return 1
  fi

  echo "⚠️  This will destroy all git history and force push to origin/main"
  echo "   Repo: $remote_url"
  read -r "REPLY?Continue? [y/N] "
  [[ ! "$REPLY" =~ ^[Yy]$ ]] && return 0

  echo "🗑️  Removing .git directory..."
  rm -rf .git || {
    echo "❌ Failed to remove .git" >&2
    return 1
  }

  echo "🔧 Initializing fresh git repository..."
  git init -q || {
    echo "❌ Failed to git init" >&2
    return 1
  }

  echo "🔗 Adding remote: $remote_url"
  git remote add origin "$remote_url" || {
    echo "❌ Failed to add remote" >&2
    return 1
  }

  echo "📦 Staging all files..."
  git add -A || {
    echo "❌ Failed to stage files" >&2
    return 1
  }

  echo "💾 Creating initial commit..."
  git commit -q -m "Initial commit" || {
    echo "❌ Failed to commit" >&2
    return 1
  }

  echo "🚀 Force pushing to origin/main..."
  git push -ufq origin main || {
    echo "❌ Failed to push" >&2
    return 1
  }

  echo "✅ Repository history reset successfully"
}

# Reinitialize git submodules when switching between branches
function reinit() {
  git submodule deinit --force .
  git submodule update --init --recursive
}
