#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/case"
  export MOCK_BIN="$TEST_ROOT/bin"
  export MOCK_LOG="$TEST_ROOT/commands.log"
  export REPO_ROOT="$BATS_TEST_DIRNAME/.."
  mkdir -p "$MOCK_BIN"
}

@test "ensure_symlink accepts correct links and reports mutation failures" {
  run bash -c '
    source "$1/dot_setup/lib/common.sh"
    tmpdir="$2/links"
    mkdir -p "$tmpdir"
    ln -s source-a "$tmpdir/link"
    ensure_symlink "$tmpdir/link" source-a
    ensure_symlink "$tmpdir/link" source-b
    [[ "$(readlink "$tmpdir/link")" == source-b ]]
    mkdir "$tmpdir/directory"
    ! ensure_symlink "$tmpdir/directory" source-c
  ' _ "$REPO_ROOT" "$TEST_ROOT"

  [[ "$status" -eq 0 ]]
}

@test "install_bun_globals attempts later packages and trust after failures" {
  cat >"$MOCK_BIN/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
add)
  printf 'add %s\n' "${*: -1}" >>"$MOCK_LOG"
  [[ "${*: -1}" != "tsx" ]]
  ;;
pm)
  if [[ "$2" == "untrusted" ]]; then
    printf './node_modules/yarn\n'
  else
    printf 'trust %s\n' "${*: -1}" >>"$MOCK_LOG"
    exit 1
  fi
  ;;
*) exit 1 ;;
esac
EOF
  chmod +x "$MOCK_BIN/bun"

  run bash -c 'BUN_INSTALL="$1"; PATH="$1:$PATH"; source "$2/dot_setup/lib/node_packages.sh"; install_bun_globals' _ "$MOCK_BIN" "$REPO_ROOT"

  [[ "$status" -ne 0 ]]
  grep -Fxq 'add yarn' "$MOCK_LOG"
  grep -Fxq 'trust yarn' "$MOCK_LOG"
  [[ "$output" != *'All global packages installed!'* ]]
}

@test "cleanup-safe attempts every cleanup after failures and exits nonzero" {
  cat >"$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
  cat >"$MOCK_BIN/brew" <<'EOF'
#!/usr/bin/env bash
printf 'brew\n' >>"$MOCK_LOG"
exit 1
EOF
  cat >"$MOCK_BIN/uv" <<'EOF'
#!/usr/bin/env bash
printf 'uv\n' >>"$MOCK_LOG"
EOF
  cat >"$MOCK_BIN/pnpm" <<'EOF'
#!/usr/bin/env bash
printf 'pnpm\n' >>"$MOCK_LOG"
exit 1
EOF
  cat >"$MOCK_BIN/go" <<'EOF'
#!/usr/bin/env bash
printf 'go\n' >>"$MOCK_LOG"
EOF
  chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/brew" "$MOCK_BIN/uv" "$MOCK_BIN/pnpm" "$MOCK_BIN/go"

  run bash -c 'printf "clean safe caches\n" | PATH="$1:$PATH" "$2/.agents/skills/mac-efficiency-cleanup/scripts/cleanup-safe.sh" --execute' _ "$MOCK_BIN" "$REPO_ROOT"

  [[ "$status" -ne 0 ]]
  [[ "$(sort "$MOCK_LOG")" == $'brew\ngo\npnpm\nuv' ]]
  [[ "$output" == *'One or more safe cleanup actions failed.'* ]]
}
