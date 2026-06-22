#!/usr/bin/env bash
# Refresh CLI-backed agent skills when local CLI versions outpace docs.

export PATH="$HOME/.local/bin:$HOME/.local/share/foundry/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

CHEZMOI_SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"
AGENT_SKILLS_DIR="${AGENT_SKILLS_DIR:-$HOME/projects/agent-skills}"

function _wakeup_semver() {
  local raw="$1"

  if [[ "$raw" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    printf '%s.%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    return 0
  fi

  return 1
}

function _wakeup_semver_compare() {
  local left="$1"
  local right="$2"
  local left_parts right_parts
  local IFS=.
  local i left_value right_value

  read -r -a left_parts <<<"$left"
  read -r -a right_parts <<<"$right"

  for i in 0 1 2; do
    left_value="${left_parts[$i]:-0}"
    right_value="${right_parts[$i]:-0}"
    if ((left_value > right_value)); then
      printf '1\n'
      return 0
    fi
    if ((left_value < right_value)); then
      printf -- '-1\n'
      return 0
    fi
  done

  printf '0\n'
}

function _wakeup_recorded_version() {
  local version_file="$1"

  awk '
    NR == 1 && $0 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/ {
      version = $0
      next
    }
    {
      invalid = 1
    }
    END {
      if (NR == 1 && !invalid) {
        print version
      } else {
        exit 1
      }
    }
  ' "$version_file"
}

function _wakeup_wait_with_timeout() {
  local pid="$1"
  local timeout_seconds="$2"
  local label="$3"
  local started_at="$SECONDS"
  local rc

  while kill -0 "$pid" 2>/dev/null; do
    if ((SECONDS - started_at >= timeout_seconds)); then
      echo "$label timed out after ${timeout_seconds}s"
      kill "$pid" 2>/dev/null || true
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
  done

  wait "$pid"
  rc=$?
  return "$rc"
}

function _wakeup_print_claude_output() {
  local out="$1"

  if [[ ! -s "$out" ]]; then
    return 0
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -r '.result // .' "$out" 2>/dev/null || cat "$out"
  else
    cat "$out"
  fi
}

function _wakeup_run_claude_in_agent_skills() {
  local label="$1"
  local prompt="$2"
  local timeout_seconds="${WAKEUP_CLAUDE_TIMEOUT_SECONDS:-900}"
  local plugin_dir="$CHEZMOI_SOURCE_DIR/.agents"
  local out err pid rc

  if ! command -v claude >/dev/null 2>&1; then
    echo "Skipping $label (claude unavailable)"
    return 1
  fi

  if [[ ! -d "$plugin_dir/skills/refresh-cli-skill" ]]; then
    echo "Skipping $label (missing refresh-cli-skill plugin at $plugin_dir)"
    return 1
  fi

  out="$(mktemp "${TMPDIR:-/tmp}/wakeup-claude-out.XXXXXX")" || return 1
  err="$(mktemp "${TMPDIR:-/tmp}/wakeup-claude-err.XXXXXX")" || {
    rm -f "$out"
    return 1
  }

  echo "$label"
  (
    cd "$AGENT_SKILLS_DIR" || exit 1
    GIT_TERMINAL_PROMPT=0 claude \
      --no-session-persistence \
      --output-format json \
      --permission-mode bypassPermissions \
      --plugin-dir "$plugin_dir" \
      --print "$prompt"
  ) >"$out" 2>"$err" &
  pid=$!

  _wakeup_wait_with_timeout "$pid" "$timeout_seconds" "$label"
  rc=$?

  _wakeup_print_claude_output "$out"

  if ((rc != 0)); then
    echo "$label failed (exit $rc; 124 = timed out)"
    if [[ -s "$err" ]]; then
      sed 's/^/  /' "$err"
    fi
  fi

  rm -f "$out" "$err"
  return "$rc"
}

function refresh_cli_backed_agent_skills() {
  local skill_dir skill_name binary version_file installed_raw installed recorded comparison
  local stale_args=()
  local stale_count=0
  local prompt

  if [[ ! -d "$AGENT_SKILLS_DIR/.git" ]]; then
    echo "Skipping CLI-backed skill refresh (missing $AGENT_SKILLS_DIR)"
    return 0
  fi

  if [[ -n "$(git -C "$AGENT_SKILLS_DIR" status --porcelain 2>/dev/null)" ]]; then
    echo "Skipping CLI-backed skill refresh (dirty worktree)"
    return 0
  fi

  for skill_dir in "$AGENT_SKILLS_DIR"/skills/cli-*; do
    if [[ ! -d "$skill_dir" ]]; then
      continue
    fi

    skill_name="${skill_dir##*/}"
    binary="${skill_name#cli-}"
    version_file="$skill_dir/references/version.txt"

    if ! command -v "$binary" >/dev/null 2>&1; then
      echo "Skipping $skill_name (missing $binary binary)"
      continue
    fi

    installed_raw="$("$binary" --version 2>/dev/null | head -n 1 || true)"
    if ! installed="$(_wakeup_semver "$installed_raw")"; then
      echo "Skipping $skill_name (could not parse $binary version: $installed_raw)"
      continue
    fi

    if [[ ! -f "$version_file" ]]; then
      echo "$skill_name is stale (missing references/version.txt; installed $installed)"
      stale_args+=("${skill_name}=${installed}")
      ((stale_count += 1))
      continue
    fi

    if ! recorded="$(_wakeup_recorded_version "$version_file")"; then
      echo "$skill_name is stale (invalid references/version.txt; installed $installed)"
      stale_args+=("${skill_name}=${installed}")
      ((stale_count += 1))
      continue
    fi

    comparison="$(_wakeup_semver_compare "$installed" "$recorded")"
    case "$comparison" in
    1)
      echo "$skill_name is stale ($recorded -> $installed)"
      stale_args+=("${skill_name}=${installed}")
      ((stale_count += 1))
      ;;
    0)
      ;;
    -1)
      echo "Skipping $skill_name (installed $installed is older than recorded $recorded)"
      ;;
    esac
  done

  if ((stale_count == 0)); then
    echo "No stale CLI-backed agent skills"
    return 0
  fi

  prompt="/refresh-cli-skill ${stale_args[*]}

Refresh only the listed CLI-backed skills. Use official upstream release docs, manuals, changelogs, or CLI help for the
installed versions. Update stale skill docs and set each references/version.txt to the requested semver. Run the repo
checks from AGENTS.md, then stop without committing."

  if [[ -n "${WAKEUP_REFRESH_CLI_SKILLS_DRY_RUN:-}" ]]; then
    echo "Dry run: would run Claude with prompt:"
    printf '%s\n' "$prompt"
    return 0
  fi

  if _wakeup_run_claude_in_agent_skills "Refreshing CLI-backed agent skills" "$prompt"; then
    if [[ -n "$(git -C "$AGENT_SKILLS_DIR" status --porcelain 2>/dev/null)" ]]; then
      # Worktree was clean before the refresh, so everything dirty now is the
      # refresh's output. Stage it and commit exactly that index with --staged
      # (deterministic; no reliance on a fresh session inferring what to stage).
      git -C "$AGENT_SKILLS_DIR" add -A
      _wakeup_run_claude_in_agent_skills "Committing CLI-backed skill refresh" "/commit --staged --push" || true
    else
      echo "No CLI-backed skill changes to commit"
    fi
  else
    echo "CLI-backed skill refresh failed; skipping commit"
  fi
}

refresh_cli_backed_agent_skills "$@"
