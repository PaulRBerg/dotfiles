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

copy_symlinks_functions() {
  cp "$REPO_ROOT/dot_config/prb/functions/symlinks.sh.tmpl" "$BATS_TEST_TMPDIR/symlinks.sh"
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
    bash "$REPO_ROOT/dot_config/prb/bin/executable_agents-layout.sh" -n 1 "$target"

  [[ "$status" -eq 0 ]]
  [[ "$(<"$pwd_log")" == "$target" ]]
  [[ ! -e "$BATS_TEST_TMPDIR/injected" ]]
}

@test "deref moves a relative file target and creates the reverse symlink" {
  copy_symlinks_functions
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
  copy_symlinks_functions
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
  copy_symlinks_functions
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

@test "Vim starts without the optional Amix runtime and loads the custom config" {
  mkdir -p "$BATS_TEST_TMPDIR/home"

  run env HOME="$BATS_TEST_TMPDIR/home" vim -Nu "$REPO_ROOT/dot_vimrc" -n -es '+qa!'
  [[ "$status" -eq 0 ]]

  run vim -Nu NONE -n -es -S "$REPO_ROOT/dot_vim_runtime/my_configs.vim" '+qa!'
  [[ "$status" -eq 0 ]]
}
