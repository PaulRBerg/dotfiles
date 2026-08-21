#!/usr/bin/env bash
# Refresh CLI-backed agent skills when local CLI versions outpace docs.

export PATH="$HOME/.local/bin:$HOME/.local/share/foundry/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

CHEZMOI_SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"
AGENT_SKILLS_DIR="${AGENT_SKILLS_DIR:-$HOME/projects/agent-skills}"
WAKEUP_CLAUDE_PID=""
WAKEUP_REFRESH_TEMP_DIR=""

function _wakeup_cleanup_isolated_refresh() {
  if [[ -n "$WAKEUP_CLAUDE_PID" ]] && kill -0 "$WAKEUP_CLAUDE_PID" 2>/dev/null; then
    kill "$WAKEUP_CLAUDE_PID" 2>/dev/null || true
    if kill -0 "$WAKEUP_CLAUDE_PID" 2>/dev/null; then
      kill -9 "$WAKEUP_CLAUDE_PID" 2>/dev/null || true
    fi
    wait "$WAKEUP_CLAUDE_PID" 2>/dev/null || true
  fi
  WAKEUP_CLAUDE_PID=""

  if [[ -n "$WAKEUP_REFRESH_TEMP_DIR" && -d "$WAKEUP_REFRESH_TEMP_DIR" &&
    "${WAKEUP_REFRESH_TEMP_DIR##*/}" == wakeup-agent-skills.* ]]; then
    rm -rf -- "$WAKEUP_REFRESH_TEMP_DIR"
  fi
  WAKEUP_REFRESH_TEMP_DIR=""
}

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
  local work_dir="$3"
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

  out="$(mktemp "${WAKEUP_REFRESH_TEMP_DIR:-${TMPDIR:-/tmp}}/wakeup-claude-out.XXXXXX")" || return 1
  err="$(mktemp "${WAKEUP_REFRESH_TEMP_DIR:-${TMPDIR:-/tmp}}/wakeup-claude-err.XXXXXX")" || {
    rm -f "$out"
    return 1
  }

  echo "$label"
  (
    cd "$work_dir" || exit 1
    GIT_TERMINAL_PROMPT=0 claude \
      --no-session-persistence \
      --output-format json \
      --permission-mode bypassPermissions \
      --allow-dangerously-skip-permissions \
      --plugin-dir "$plugin_dir" \
      --print "$prompt"
  ) >"$out" 2>"$err" &
  pid=$!
  WAKEUP_CLAUDE_PID="$pid"

  _wakeup_wait_with_timeout "$pid" "$timeout_seconds" "$label"
  rc=$?
  WAKEUP_CLAUDE_PID=""

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

function refresh_cli_backed_agent_skills() (
  local skill_dir skill_name binary version_file installed_raw installed recorded comparison
  local stale_args=()
  local stale_count=0
  local prompt skills_dir remote_url branch temp_dir clone_dir starting_oid remote_oid
  local prepare_output transaction_id

  if ! git -C "$AGENT_SKILLS_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Skipping CLI-backed skill refresh (missing $AGENT_SKILLS_DIR)"
    return 0
  fi
  if [[ -n "${WAKEUP_REFRESH_CLI_SKILLS_DRY_RUN:-}" &&
    -n "$(git -C "$AGENT_SKILLS_DIR" status --porcelain 2>/dev/null)" ]]; then
    echo "Skipping CLI-backed skill refresh (dirty worktree)"
    return 0
  fi

  skills_dir="$AGENT_SKILLS_DIR"
  if [[ -z "${WAKEUP_REFRESH_CLI_SKILLS_DRY_RUN:-}" ]]; then
    remote_url="$(git -C "$AGENT_SKILLS_DIR" remote get-url origin 2>/dev/null)"
    branch="$(git -C "$AGENT_SKILLS_DIR" branch --show-current 2>/dev/null)"
    if [[ -z "$remote_url" || -z "$branch" ]]; then
      echo "Skipping CLI-backed skill refresh (origin or current branch unavailable)"
      return 0
    fi

    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/wakeup-agent-skills.XXXXXX")" || return 1
    WAKEUP_REFRESH_TEMP_DIR="$temp_dir"
    trap '_wakeup_cleanup_isolated_refresh' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    clone_dir="$temp_dir/repo"
    if ! GIT_TERMINAL_PROMPT=0 git clone --quiet --single-branch --branch "$branch" "$remote_url" "$clone_dir"; then
      echo "CLI-backed skill refresh failed (could not clone origin/$branch)" >&2
      return 1
    fi
    skills_dir="$clone_dir"
    starting_oid="$(git -C "$clone_dir" rev-parse HEAD)" || return 1
  fi

  for skill_dir in "$skills_dir"/skills/cli-*; do
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

  if ! _wakeup_run_claude_in_agent_skills "Refreshing CLI-backed agent skills" "$prompt" "$clone_dir"; then
    echo "CLI-backed skill refresh failed; skipping commit"
    return 1
  fi

  if [[ "$(git -C "$clone_dir" rev-parse HEAD)" != "$starting_oid" ]]; then
    echo "CLI-backed skill refresh changed Git history; refusing to push" >&2
    return 1
  fi

  if [[ -z "$(git -C "$clone_dir" status --porcelain 2>/dev/null)" ]]; then
    echo "No CLI-backed skill changes to commit"
    return 0
  fi

  remote_oid="$(
    GIT_TERMINAL_PROMPT=0 git -C "$clone_dir" ls-remote --exit-code origin "refs/heads/$branch" |
      awk 'NR == 1 { print $1 }'
  )" || {
    echo "CLI-backed skill refresh failed (could not verify origin/$branch)" >&2
    return 1
  }
  if [[ "$remote_oid" != "$starting_oid" ]]; then
    echo "CLI-backed skill refresh aborted (origin/$branch advanced during refresh)" >&2
    return 1
  fi

  if ! command -v ai-commit >/dev/null 2>&1; then
    echo "CLI-backed skill refresh failed (ai-commit is unavailable)" >&2
    return 1
  fi

  if ! prepare_output="$(
    cd "$clone_dir" && ai-commit prepare --all --no-auto-baseline --porcelain
  )"; then
    echo "CLI-backed skill commit preparation failed" >&2
    return 1
  fi
  transaction_id="$(awk -F '\t' '$1 == "PREPARED" { print $2; exit }' <<<"$prepare_output")"
  if [[ -z "$transaction_id" ]]; then
    echo "CLI-backed skill commit preparation returned no transaction" >&2
    return 1
  fi

  if ! (cd "$clone_dir" && ai-commit commit "$transaction_id" -m "Refresh CLI-backed agent skills" --push); then
    echo "CLI-backed skill commit or push failed" >&2
    return 1
  fi
)

refresh_cli_backed_agent_skills "$@"
