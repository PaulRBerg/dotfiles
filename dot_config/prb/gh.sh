#!/usr/bin/env bash

# Purge all GitHub Actions caches for a repository
function gh_cache_purge() {
  local repo="${1:-}"
  local gh_env=()
  local gh_host=""
  local gh_repo="$repo"

  if [[ -n "$repo" ]]; then
    if [[ "$repo" == */*/* ]]; then
      gh_host="${repo%%/*}"
      gh_repo="${repo#*/}"
    fi

    gh_env=(GH_REPO="$gh_repo")
    [[ -n "$gh_host" ]] && gh_env+=("GH_HOST=$gh_host")
  fi

  echo "Fetching cache list (all pages)..."

  local cache_ids
  if ! cache_ids=$(
    env "${gh_env[@]}" gh api --paginate "/repos/{owner}/{repo}/actions/caches?per_page=100" \
      --jq '.actions_caches[].id' 2>&1
  ); then
    echo "Error fetching caches: $cache_ids"
    return 1
  fi

  if [[ -z "$cache_ids" ]]; then
    echo "No caches found"
    return 0
  fi

  local cache_count
  cache_count=$(echo "$cache_ids" | wc -l | tr -d ' ')

  echo "Found $cache_count cache(s) to delete"
  [[ -n "$repo" ]] && echo "Repository: $repo"

  echo -n "Continue? [y/N] "
  read -r response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Aborted"
    return 1
  fi

  local count=0
  local failed=0

  while IFS= read -r cache_id; do
    ((count++))
    echo "[$count/$cache_count] Deleting cache $cache_id"

    env "${gh_env[@]}" gh api -X DELETE "/repos/{owner}/{repo}/actions/caches/$cache_id" >/dev/null 2>&1 || ((failed++))
  done <<<"$cache_ids"

  if [[ $failed -eq 0 ]]; then
    local remaining
    if ! remaining=$(
      env "${gh_env[@]}" gh api "/repos/{owner}/{repo}/actions/caches?per_page=1" --jq '.total_count' 2>&1
    ); then
      echo "Error verifying caches: $remaining"
      return 1
    fi

    if [[ "$remaining" -ne 0 ]]; then
      echo "Deleted $cache_count cache(s), but $remaining remain. Active workflows may have recreated caches."
      return 1
    fi

    echo "Successfully deleted $cache_count cache(s)"
  else
    echo "Failed to delete $failed cache(s)"
    return 1
  fi
}
