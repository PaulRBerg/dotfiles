#!/usr/bin/env bats
# Child scripts expand variables; -f keeps Zsh startup from replacing test stubs.
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/capture"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export TMPDIR="$BATS_TEST_TMPDIR/capture"
}

fake_claude() {
  printf '%s\n' '#!/usr/bin/env bash' "$@" >"$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
}

@test "headless skills print the final response without terminal controls in Bash and Zsh" {
  fake_claude 'printf '\''%s\n'\'' '\''{"result":"Committed and pushed."}'\'''

  for shell in bash zsh; do
    run --separate-stderr "$shell" -efc 'source "$1"; _run_claude_skill "Working..." "/commit --all --push"' _ \
      "$REPO_ROOT/dot_config/prb/agents.sh"

    [[ "$status" -eq 0 ]]
    [[ "$output" == 'Committed and pushed.' ]]
    [[ "$stderr" == 'Working...' ]]
    [[ -z "$(ls -A "$TMPDIR")" ]]
  done
}

@test "headless skills give Claude EOF instead of consuming caller input" {
  fake_claude \
    'if IFS= read -r line; then echo "unexpected stdin" >&2; exit 9; fi' \
    'printf '\''%s\n'\'' '\''{"result":"Complete."}'\'''

  for shell in bash zsh; do
    run --separate-stderr "$shell" -efc 'source "$1"; printf "caller input\n" | _run_claude_skill "Working..." "/commit"' _ \
      "$REPO_ROOT/dot_config/prb/agents.sh"

    [[ "$status" -eq 0 ]]
    [[ "$output" == 'Complete.' ]]
  done
}

@test "headless skills surface failure diagnostics and clean their capture files" {
  fake_claude \
    'echo "push failed" >&2' \
    'printf '\''%s\n'\'' '\''{"is_error":true,"errors":["Could not finish."]}'\''' \
    'exit 7'

  for shell in bash zsh; do
    run --separate-stderr "$shell" -efc 'source "$1"; _run_claude_skill "Working..." "/commit"' _ \
      "$REPO_ROOT/dot_config/prb/agents.sh"

    [[ "$status" -ne 0 ]]
    [[ "$stderr" == *'exit 7'* ]]
    [[ "$stderr" == *'Could not finish.'* ]]
    [[ "$stderr" == *'push failed'* ]]
    [[ -z "$(ls -A "$TMPDIR")" ]]
  done
}

@test "headless skills reject empty, malformed, missing, and failed results" {
  fake_claude 'printf "%s" "$CLAUDE_RESPONSE"'

  for shell in bash zsh; do
    for response in '' 'not json' '{}' '{"result":""}' '{"is_error":true,"result":"Failed."}'; do
      run --separate-stderr env CLAUDE_RESPONSE="$response" "$shell" -efc \
        'source "$1"; _run_claude_skill "Working..." "/commit"' _ "$REPO_ROOT/dot_config/prb/agents.sh"

      [[ "$status" -ne 0 ]]
      [[ "$stderr" == *'claude skill failed'* ]]
      [[ -z "$output" ]]
      [[ -z "$(ls -A "$TMPDIR")" ]]
    done
  done
}

@test "headless skills report timeout failures" {
  command -v timeout >/dev/null || command -v gtimeout >/dev/null || skip 'coreutils timeout is not installed'
  fake_claude 'exec sleep 5'

  for shell in bash zsh; do
    run --separate-stderr env CCC_TIMEOUT=0.1 "$shell" -efc \
      'source "$1"; _run_claude_skill "Working..." "/commit"' _ "$REPO_ROOT/dot_config/prb/agents.sh"

    [[ "$status" -ne 0 ]]
    [[ "$stderr" == *'exit 124'* ]]
    [[ -z "$(ls -A "$TMPDIR")" ]]
  done
}
