#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
}

write_executable() {
  local destination="$1"
  shift

  printf '%s\n' "$@" >"$destination"
  chmod +x "$destination"
}

render_symlinks_for_macos() {
  awk '
    BEGIN { include = 1 }
    /{{- if eq \.chezmoi\.os "darwin" }}/ { include = 1; next }
    /{{- else if eq \.chezmoi\.os "linux" }}/ { include = 0; next }
    /{{- end }}/ { include = 1; next }
    include { print }
  ' "$REPO_ROOT/dot_config/prb/functions/symlinks.sh.tmpl" >"$BATS_TEST_TMPDIR/symlinks.sh"
}

setup_agent_skills_remote() {
  AGENT_SKILLS_REMOTE="$BATS_TEST_TMPDIR/agent-skills.git"
  AGENT_SKILLS_PRIMARY="$BATS_TEST_TMPDIR/agent-skills-primary"
  local seed="$BATS_TEST_TMPDIR/agent-skills-seed"

  git init -q --bare "$AGENT_SKILLS_REMOTE"
  git init -q -b main "$seed"
  git -C "$seed" config user.name Test
  git -C "$seed" config user.email test@example.com
  mkdir -p "$seed/skills/cli-fake/references"
  printf '1.0.0\n' >"$seed/skills/cli-fake/references/version.txt"
  git -C "$seed" add skills/cli-fake/references/version.txt
  git -C "$seed" commit -qm initial
  git -C "$seed" remote add origin "$AGENT_SKILLS_REMOTE"
  git -C "$seed" push -q -u origin main
  git clone -q --branch main "$AGENT_SKILLS_REMOTE" "$AGENT_SKILLS_PRIMARY"
  printf 'primary worktree must remain dirty\n' >"$AGENT_SKILLS_PRIMARY/local-only"
}

install_fake_refresh_tools() {
  write_executable "$BATS_TEST_TMPDIR/bin/fake" \
    '#!/usr/bin/env bash' \
    "printf '%s\\n' 'fake 2.0.0'"

  write_executable "$BATS_TEST_TMPDIR/bin/claude" \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$PWD" >>"$CLAUDE_CWD_LOG"' \
    'printf "refresh\n" >>"$CLAUDE_CALL_LOG"' \
    'printf "2.0.0\n" >skills/cli-fake/references/version.txt' \
    'if [[ -n "${ADVANCE_REMOTE_DURING_REFRESH:-}" ]]; then' \
    '  base="$(git --git-dir="$AGENT_SKILLS_REMOTE" rev-parse refs/heads/main)"' \
    '  tree="$(git --git-dir="$AGENT_SKILLS_REMOTE" rev-parse "${base}^{tree}")"' \
    '  advanced="$(printf "advance\n" | GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com git --git-dir="$AGENT_SKILLS_REMOTE" commit-tree "$tree" -p "$base")"' \
    '  git --git-dir="$AGENT_SKILLS_REMOTE" update-ref refs/heads/main "$advanced" "$base"' \
    'fi' \
    "printf '%s\\n' '{\"result\":\"ok\"}'"

  write_executable "$BATS_TEST_TMPDIR/bin/ai-commit" \
    '#!/usr/bin/env bash' \
    'case "$1" in' \
    '  prepare)' \
    '    git add -A' \
    '    printf "PREPARED\\tfake-transaction\\n"' \
    '    ;;' \
    '  commit)' \
    '    [[ "$2" == fake-transaction ]] || exit 2' \
    '    shift 2' \
    '    while (($#)); do' \
    '      case "$1" in' \
    '        -m) message="$2"; shift 2 ;;' \
    '        --push) push=1; shift ;;' \
    '        *) exit 2 ;;' \
    '      esac' \
    '    done' \
    '    git commit -qm "$message"' \
    '    [[ -z "${push:-}" ]] || git push -q origin HEAD:main' \
    '    ;;' \
    '  *) exit 2 ;;' \
    'esac'
}

@test "agents-layout shell-quotes a directory containing quotes and metacharacters" {
  local target="$BATS_TEST_TMPDIR/repo ' ; touch injected ; #"
  local pwd_log="$BATS_TEST_TMPDIR/it2-pwd"
  mkdir -p "$target"
  write_executable "$BATS_TEST_TMPDIR/bin/it2" \
    '#!/usr/bin/env bash' \
    'if [[ "$1" == session && "$2" == run ]]; then' \
    '  bash -c "$3; printf '\''%s\\n'\'' \"\$PWD\" >\"\$IT2_PWD_LOG\""' \
    'fi'

  cd "$BATS_TEST_TMPDIR"
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" IT2_PWD_LOG="$pwd_log" TERM=xterm \
    bash "$REPO_ROOT/dot_config/prb/bin/executable_agents-layout" -n 1 "$target"

  [[ "$status" -eq 0 ]]
  [[ "$(<"$pwd_log")" == "$target" ]]
  [[ ! -e "$BATS_TEST_TMPDIR/injected" ]]
}

@test "deref moves a relative file target and creates the reverse symlink" {
  render_symlinks_for_macos
  mkdir -p "$BATS_TEST_TMPDIR/links" "$BATS_TEST_TMPDIR/data"
  printf 'payload\n' >"$BATS_TEST_TMPDIR/data/target.txt"
  ln -s ../data/target.txt "$BATS_TEST_TMPDIR/links/item"

  run bash -c 'source "$1"; deref "$2"' _ "$BATS_TEST_TMPDIR/symlinks.sh" "$BATS_TEST_TMPDIR/links/item"

  [[ "$status" -eq 0 ]]
  [[ ! -L "$BATS_TEST_TMPDIR/links/item" ]]
  [[ "$(<"$BATS_TEST_TMPDIR/links/item")" == payload ]]
  [[ -L "$BATS_TEST_TMPDIR/data/target.txt" ]]
  [[ "$(readlink "$BATS_TEST_TMPDIR/data/target.txt")" == "$(grealpath "$BATS_TEST_TMPDIR/links/item")" ]]
}

@test "deref supports directory targets" {
  render_symlinks_for_macos
  mkdir -p "$BATS_TEST_TMPDIR/links" "$BATS_TEST_TMPDIR/data/target"
  printf 'payload\n' >"$BATS_TEST_TMPDIR/data/target/file"
  ln -s ../data/target "$BATS_TEST_TMPDIR/links/item"

  run bash -c 'source "$1"; deref "$2"' _ "$BATS_TEST_TMPDIR/symlinks.sh" "$BATS_TEST_TMPDIR/links/item"

  [[ "$status" -eq 0 ]]
  [[ -d "$BATS_TEST_TMPDIR/links/item" && ! -L "$BATS_TEST_TMPDIR/links/item" ]]
  [[ "$(<"$BATS_TEST_TMPDIR/links/item/file")" == payload ]]
  [[ -L "$BATS_TEST_TMPDIR/data/target" ]]
}

@test "deref restores the original state when reverse-link creation fails" {
  render_symlinks_for_macos
  mkdir -p "$BATS_TEST_TMPDIR/links" "$BATS_TEST_TMPDIR/data"
  printf 'payload\n' >"$BATS_TEST_TMPDIR/data/target.txt"
  ln -s ../data/target.txt "$BATS_TEST_TMPDIR/links/item"
  write_executable "$BATS_TEST_TMPDIR/bin/ln" '#!/usr/bin/env bash' 'exit 1'

  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c 'source "$1"; deref "$2"' _ \
    "$BATS_TEST_TMPDIR/symlinks.sh" "$BATS_TEST_TMPDIR/links/item"

  [[ "$status" -ne 0 ]]
  [[ -L "$BATS_TEST_TMPDIR/links/item" ]]
  [[ "$(readlink "$BATS_TEST_TMPDIR/links/item")" == ../data/target.txt ]]
  [[ ! -L "$BATS_TEST_TMPDIR/data/target.txt" ]]
  [[ "$(<"$BATS_TEST_TMPDIR/data/target.txt")" == payload ]]
  [[ -z "$(find "$BATS_TEST_TMPDIR/links" -maxdepth 1 -name '.deref.*' -print -quit)" ]]
}

@test "_git_confirm accepts input in Bash and Zsh" {
  run bash -c 'source "$1"; printf "y\n" | _git_confirm "Continue?"' _ \
    "$REPO_ROOT/dot_config/prb/functions/git.sh"
  [[ "$status" -eq 0 ]]

  run zsh -c 'source "$1"; printf "y\n" | _git_confirm "Continue?"' _ \
    "$REPO_ROOT/dot_config/prb/functions/git.sh"
  [[ "$status" -eq 0 ]]
}

@test "gsf cancellation is a successful no-op and gstf rejects an ordinal shift" {
  run bash -c '
    source "$1"
    git() {
      case "$1 $2" in
        "for-each-ref refs/heads/") printf "main\n" ;;
        "stash list") printf "stash@{0}\told-oid\tsubject\n" ;;
        "rev-parse --verify") printf "new-oid\n" ;;
        "stash pop") touch "$2" ;;
      esac
    }
    fzf() { return 130; }
    gsf || exit 1
    fzf() { cat; }
    gstf && exit 1
    [[ ! -e stash@{0} ]]
  ' _ "$REPO_ROOT/dot_config/prb/functions/git.sh"

  [[ "$status" -eq 0 ]]
}

@test "git dm preserves main, the current branch, and unmerged branches while rb cancellation is a no-op" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local aliases="$BATS_TEST_TMPDIR/aliases.config"
  local dm rb
  sed -n '1,/^\[apply\]/p' "$REPO_ROOT/dot_config/git/gitconfig.tmpl" >"$aliases"
  dm="$(git config --file "$aliases" --get alias.dm)"
  rb="$(git config --file "$aliases" --get alias.rb)"

  git init -q -b main "$repo"
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.com
  printf 'base\n' >"$repo/file"
  git -C "$repo" add file
  git -C "$repo" commit -qm base
  git -C "$repo" branch merged
  git -C "$repo" switch -qc unmerged
  printf 'unmerged\n' >>"$repo/file"
  git -C "$repo" commit -qam unmerged
  git -C "$repo" switch -qc current main
  git -C "$repo" config alias.dm "$dm"
  git -C "$repo" config alias.rb "$rb"

  run git -C "$repo" dm
  [[ "$status" -eq 0 ]]
  run git -C "$repo" show-ref --verify --quiet refs/heads/merged
  [[ "$status" -ne 0 ]]
  git -C "$repo" show-ref --verify --quiet refs/heads/main
  git -C "$repo" show-ref --verify --quiet refs/heads/current
  git -C "$repo" show-ref --verify --quiet refs/heads/unmerged

  write_executable "$BATS_TEST_TMPDIR/bin/fzf" '#!/usr/bin/env bash' 'exit 130'
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" git -C "$repo" rb
  [[ "$status" -eq 0 ]]
  [[ "$(git -C "$repo" branch --show-current)" == current ]]
}

@test "Codex build autosync refuses unexpected output paths" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex="$home/.codex"
  local block="$BATS_TEST_TMPDIR/codex-build.sh"
  mkdir -p "$codex"
  git init -q -b main "$codex"
  git -C "$codex" config user.name Test
  git -C "$codex" config user.email test@example.com
  printf 'old\n' >"$codex/AGENTS.md"
  git -C "$codex" add AGENTS.md
  git -C "$codex" commit -qm initial
  write_executable "$BATS_TEST_TMPDIR/bin/just" \
    '#!/usr/bin/env bash' \
    'printf "new\n" >AGENTS.md' \
    'printf "unexpected\n" >other-file'
  awk '
    /# Build Codex AGENTS.md/ { include = 1; next }
    /# Update package managers/ { include = 0 }
    include { print }
  ' "$REPO_ROOT/executable_dot_wakeup" >"$block"

  run env HOME="$home" PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$block"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Skipping Codex commit and push"* ]]
  [[ "$(git -C "$codex" rev-list --count HEAD)" == 1 ]]
  [[ -z "$(git -C "$codex" diff --cached --name-only)" ]]
  [[ "$(git -C "$codex" status --short)" == $' M AGENTS.md\n?? other-file' ]]
}

@test "Vim starts without the optional Amix runtime and loads the custom config" {
  mkdir -p "$BATS_TEST_TMPDIR/home"

  run env HOME="$BATS_TEST_TMPDIR/home" vim -Nu "$REPO_ROOT/dot_vimrc" -n -es '+qa!'
  [[ "$status" -eq 0 ]]

  run vim -Nu NONE -n -es -S "$REPO_ROOT/dot_vim_runtime/my_configs.vim" '+qa!'
  [[ "$status" -eq 0 ]]
}

@test "CLI skill refresh commits from a temporary clone and never touches the primary worktree" {
  setup_agent_skills_remote
  install_fake_refresh_tools
  mkdir -p "$BATS_TEST_TMPDIR/clones" "$BATS_TEST_TMPDIR/home"
  local primary_before
  primary_before="$(git -C "$AGENT_SKILLS_PRIMARY" status --short)"

  run env \
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
    HOME="$BATS_TEST_TMPDIR/home" \
    TMPDIR="$BATS_TEST_TMPDIR/clones" \
    AGENT_SKILLS_DIR="$AGENT_SKILLS_PRIMARY" \
    AGENT_SKILLS_REMOTE="$AGENT_SKILLS_REMOTE" \
    GIT_AUTHOR_NAME=Test \
    GIT_AUTHOR_EMAIL=test@example.com \
    GIT_COMMITTER_NAME=Test \
    GIT_COMMITTER_EMAIL=test@example.com \
    CHEZMOI_SOURCE_DIR="$REPO_ROOT" \
    CLAUDE_CWD_LOG="$BATS_TEST_TMPDIR/claude-cwd" \
    CLAUDE_CALL_LOG="$BATS_TEST_TMPDIR/claude-calls" \
    bash "$REPO_ROOT/dot_config/prb/wakeup/executable_refresh_cli_skills.sh"

  [[ "$status" -eq 0 ]]
  [[ "$(git -C "$AGENT_SKILLS_PRIMARY" status --short)" == "$primary_before" ]]
  [[ "$(<"$AGENT_SKILLS_PRIMARY/skills/cli-fake/references/version.txt")" == 1.0.0 ]]
  [[ "$(git --git-dir="$AGENT_SKILLS_REMOTE" show main:skills/cli-fake/references/version.txt)" == 2.0.0 ]]
  [[ "$(<"$BATS_TEST_TMPDIR/claude-calls")" == refresh ]]
  run rg -Fx "$AGENT_SKILLS_PRIMARY" "$BATS_TEST_TMPDIR/claude-cwd"
  [[ "$status" -eq 1 ]]
  [[ -z "$(find "$BATS_TEST_TMPDIR/clones" -mindepth 1 -print -quit)" ]]
}

@test "CLI skill refresh aborts before commit when the remote branch advances" {
  setup_agent_skills_remote
  install_fake_refresh_tools
  mkdir -p "$BATS_TEST_TMPDIR/clones" "$BATS_TEST_TMPDIR/home"

  run env \
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
    HOME="$BATS_TEST_TMPDIR/home" \
    TMPDIR="$BATS_TEST_TMPDIR/clones" \
    AGENT_SKILLS_DIR="$AGENT_SKILLS_PRIMARY" \
    AGENT_SKILLS_REMOTE="$AGENT_SKILLS_REMOTE" \
    ADVANCE_REMOTE_DURING_REFRESH=1 \
    CHEZMOI_SOURCE_DIR="$REPO_ROOT" \
    CLAUDE_CWD_LOG="$BATS_TEST_TMPDIR/claude-cwd" \
    CLAUDE_CALL_LOG="$BATS_TEST_TMPDIR/claude-calls" \
    bash "$REPO_ROOT/dot_config/prb/wakeup/executable_refresh_cli_skills.sh"

  [[ "$status" -ne 0 ]]
  [[ "$(<"$BATS_TEST_TMPDIR/claude-calls")" == refresh ]]
  [[ "$(git --git-dir="$AGENT_SKILLS_REMOTE" show main:skills/cli-fake/references/version.txt)" == 1.0.0 ]]
  [[ -z "$(find "$BATS_TEST_TMPDIR/clones" -mindepth 1 -print -quit)" ]]
}
