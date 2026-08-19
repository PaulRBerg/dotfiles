#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/case"
  export HOME="$TEST_ROOT/home"
  export XDG_STATE_HOME="$TEST_ROOT/state"
  export CLEANSHOT_SCREENSHOT_DIR="$TEST_ROOT/screenshots"
  export CLEANSHOT_RENAMER_STATE_DIR="$XDG_STATE_HOME/cleanshot-screenshot-renamer"
  export CLEANSHOT_RENAMER_SETTLE_SECONDS=0
  export MOCK_BIN="$TEST_ROOT/bin"
  export MOCK_CODEX_RESULT="$TEST_ROOT/codex-result.json"
  export MOCK_CODEX_LOG="$TEST_ROOT/codex-args.log"
  export MOCK_CODEX_COUNT="$TEST_ROOT/codex-count"
  export MOCK_CLIPBOARD_LOG="$TEST_ROOT/clipboard.tsv"
  export MOCK_CLIPBOARD_TOKEN_FILE="$TEST_ROOT/clipboard-token"
  export MOCK_NOTIFICATION_LOG="$TEST_ROOT/notifications.tsv"
  export MOCK_BIRTH_EPOCH=1001
  export MOCK_NOW_EPOCH=1000
  export PATH="$MOCK_BIN:/opt/homebrew/bin:/usr/bin:/bin"
  export RENAMER="$BATS_TEST_DIRNAME/../dot_config/prb/bin/executable_cleanshot_screenshot_renamer_macos.sh"
  export CLEANSHOT_RENAMER_CLIPBOARD_HELPER="$MOCK_BIN/cleanshot_clipboard_macos.sh"

  mkdir -p "$CLEANSHOT_SCREENSHOT_DIR" "$CLEANSHOT_RENAMER_STATE_DIR" "$MOCK_BIN"
  printf '%s\n' '1000' >"$CLEANSHOT_RENAMER_STATE_DIR/enabled-at"
  write_mocks
  write_result 'code' 'oauth-callback-error' '0.95'
}

write_mocks() {
  cat >"$MOCK_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=0
[[ ! -f "$MOCK_CODEX_COUNT" ]] || count="$(<"$MOCK_CODEX_COUNT")"
count=$((count + 1))
printf '%s\n' "$count" >"$MOCK_CODEX_COUNT"
printf '%q ' "$@" >>"$MOCK_CODEX_LOG"
printf '\n' >>"$MOCK_CODEX_LOG"

if [[ "${MOCK_CLIPBOARD_BUMP_DURING_NAMING:-0}" == "1" && -f "$MOCK_CLIPBOARD_TOKEN_FILE" ]]; then
  printf '%s\n' "$(($(<"$MOCK_CLIPBOARD_TOKEN_FILE") + 10))" >"$MOCK_CLIPBOARD_TOKEN_FILE"
fi

if ((count <= ${MOCK_CODEX_FAILURES:-0})); then
  exit 1
fi

output=""
while (($# > 0)); do
  if [[ "$1" == "--output-last-message" ]]; then
    output="$2"
    break
  fi
  shift
done
cp "$MOCK_CODEX_RESULT" "$output"
EOF

  cat >"$MOCK_BIN/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "+%s" ]]; then
  printf '%s\n' "$MOCK_NOW_EPOCH"
else
  printf '%s\n' '2026-08-14T12:00:00Z'
fi
EOF

  cat >"$MOCK_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  cat >"$MOCK_BIN/stat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
format="$2"
file="$3"
case "$format" in
'%B') printf '%s\n' "$MOCK_BIRTH_EPOCH" ;;
'%z:%m')
  if [[ "${MOCK_UNSTABLE:-0}" == "1" ]]; then
    counter_file="$TEST_ROOT/stat-count"
    count=0
    [[ ! -f "$counter_file" ]] || count="$(<"$counter_file")"
    count=$((count + 1))
    printf '%s\n' "$count" >"$counter_file"
    printf '%s:%s\n' "$(wc -c <"$file" | tr -d ' ')" "$count"
  else
    /usr/bin/stat -f '%z:%m' "$file"
  fi
  ;;
*) exit 1 ;;
esac
EOF

  cat >"$MOCK_BIN/osascript" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf '%s\t%s\n' "${2:-}" "${3:-}" >>"$MOCK_NOTIFICATION_LOG"
EOF

  cat >"$MOCK_BIN/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source="${@: -2:1}"
target="${@: -1}"
if [[ "${MOCK_MV_RACE:-0}" == "1" && "$source" == *'/CleanShot '* && ! -e "$TEST_ROOT/mv-race-created" ]]; then
  printf '%s\n' 'rival file' >"$target"
  : >"$TEST_ROOT/mv-race-created"
fi
exec /bin/mv "$@"
EOF

  cat >"$MOCK_BIN/cleanshot_clipboard_macos.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command="$1"
printf '%s' "$command" >>"$MOCK_CLIPBOARD_LOG"
shift
for argument in "$@"; do
  printf '\t%s' "$argument" >>"$MOCK_CLIPBOARD_LOG"
done
printf '\n' >>"$MOCK_CLIPBOARD_LOG"

case "$command" in
observe)
  [[ "${MOCK_CLIPBOARD_OBSERVE_FAILURE:-0}" != "1" ]] || exit 1
  token="${MOCK_CLIPBOARD_INITIAL_TOKEN:-40}"
  printf '%s\n' "$token" >"$MOCK_CLIPBOARD_TOKEN_FILE"
  printf '%s\n' "$token"
  ;;
copy-if-current)
  [[ "${MOCK_CLIPBOARD_COPY_FAILURE:-0}" != "1" ]] || exit 1
  expected="$1"
  current="$(<"$MOCK_CLIPBOARD_TOKEN_FILE")"
  if [[ "${MOCK_CLIPBOARD_CHANGED:-0}" == "1" || "$expected" != "$current" ]]; then
    printf '%s\n' 'changed'
    exit 0
  fi
  current=$((current + 1))
  printf '%s\n' "$current" >"$MOCK_CLIPBOARD_TOKEN_FILE"
  printf 'copied %s\n' "$current"
  ;;
*) exit 2 ;;
esac
EOF

  chmod +x \
    "$MOCK_BIN/codex" \
    "$MOCK_BIN/date" \
    "$MOCK_BIN/sleep" \
    "$MOCK_BIN/stat" \
    "$MOCK_BIN/osascript" \
    "$MOCK_BIN/mv" \
    "$MOCK_BIN/cleanshot_clipboard_macos.sh"
}

write_result() {
  local category="$1"
  local title_slug="$2"
  local confidence="$3"

  jq -n \
    --arg category "$category" \
    --arg title_slug "$title_slug" \
    --argjson confidence "$confidence" \
    '{category: $category, title_slug: $title_slug, confidence: $confidence}' >"$MOCK_CODEX_RESULT"
}

write_screenshot() {
  local name="$1"
  printf '%s\n' 'fake screenshot' >"$CLEANSHOT_SCREENSHOT_DIR/$name"
}

run_renamer() {
  run bash "$RENAMER"
}

@test "first run records the cutoff and leaves existing screenshots unchanged" {
  rm "$CLEANSHOT_RENAMER_STATE_DIR/enabled-at"
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_RENAMER_STATE_DIR/enabled-at" ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/CleanShot 2026-08-14 at 13.58.40.jpg" ]]
  [[ ! -e "$MOCK_CODEX_COUNT" ]]
}

@test "ignores screenshots created before the cutoff" {
  export MOCK_BIRTH_EPOCH=999
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/CleanShot 2026-08-14 at 13.58.40.jpg" ]]
  [[ ! -e "$MOCK_CODEX_COUNT" ]]
}

@test "renames with a fixed category and exact Luna medium arguments" {
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error.jpg" ]]
  grep -q -- '--model gpt-5.6-luna' "$MOCK_CODEX_LOG"
  grep -q -- 'model_reasoning_effort=\\"medium\\"' "$MOCK_CODEX_LOG"
  grep -q -- '--sandbox read-only' "$MOCK_CODEX_LOG"
  grep -q -- '--ephemeral' "$MOCK_CODEX_LOG"
  grep -q -- '--ignore-user-config' "$MOCK_CODEX_LOG"
  grep -q -- '--ignore-rules' "$MOCK_CODEX_LOG"
  grep -q -- '--image' "$MOCK_CODEX_LOG"
  grep -q -- '--output-schema' "$MOCK_CODEX_LOG"
  grep -Fq $'observe' "$MOCK_CLIPBOARD_LOG"
  ! grep -Fq -- 'CleanShot 2026-08-14 at 13.58.40.jpg' "$MOCK_CLIPBOARD_LOG"
  grep -Fq $'copy-if-current\t40\t'"$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error.jpg" "$MOCK_CLIPBOARD_LOG"
}

@test "accepts a short custom category" {
  write_result 'product-research' 'compact-travel-keyboards' '0.88'
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.png'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--product-research--compact-travel-keyboards.png" ]]
}

@test "forces low-confidence classifications into other" {
  write_result 'code' 'unfamiliar-dashboard' '0.4'
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--other--unfamiliar-dashboard.jpg" ]]
}

@test "adds a numeric suffix when the target already exists" {
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'
  printf '%s\n' 'existing' >"$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error.jpg"

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error--2.jpg" ]]
  grep -Fq -- '--code--oauth-callback-error--2.jpg' "$MOCK_CLIPBOARD_LOG"
}

@test "does not overwrite a target created during the rename" {
  export MOCK_MV_RACE=1
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  run cat "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error.jpg"
  [[ "$status" -eq 0 ]]
  [[ "$output" == 'rival file' ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error--2.jpg" ]]
}

@test "does not replace a dangling target symlink" {
  target="$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error.jpg"
  ln -s 'missing.jpg' "$target"
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -L "$target" ]]
  [[ "$(readlink "$target")" == 'missing.jpg' ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error--2.jpg" ]]
}

@test "retries transient failures and then uses the classification" {
  export MOCK_CODEX_FAILURES=2
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ "$(<"$MOCK_CODEX_COUNT")" -eq 3 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error.jpg" ]]
  [[ ! -e "$MOCK_NOTIFICATION_LOG" ]]
}

@test "falls back to an unclassified name and notifies after invalid output" {
  printf '%s\n' '{"category":"Code","title_slug":"unsafe title","confidence":2}' >"$MOCK_CODEX_RESULT"
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ "$(<"$MOCK_CODEX_COUNT")" -eq 3 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--other--unclassified.jpg" ]]
  grep -q 'CleanShot screenshot unclassified' "$MOCK_NOTIFICATION_LOG"
  grep -Fq -- '--other--unclassified.jpg' "$MOCK_CLIPBOARD_LOG"
}

@test "preserves clipboard content copied before the final copy" {
  export MOCK_CLIPBOARD_CHANGED=1
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error.jpg" ]]
  [[ "$(<"$MOCK_CLIPBOARD_TOKEN_FILE")" -eq 40 ]]
  [[ "$output" == *'clipboard changed; skipped copying 2026-08-14_13-58-40--code--oauth-callback-error.jpg'* ]]
  [[ "$(grep -c '^copy-if-current' "$MOCK_CLIPBOARD_LOG")" -eq 1 ]]
  [[ ! -e "$MOCK_NOTIFICATION_LOG" ]]
}

@test "preserves clipboard content copied while Luna is naming" {
  export MOCK_CLIPBOARD_BUMP_DURING_NAMING=1
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error.jpg" ]]
  ! grep -Fq -- 'CleanShot 2026-08-14 at 13.58.40.jpg' "$MOCK_CLIPBOARD_LOG"
  [[ "$output" == *'clipboard changed; skipped copying 2026-08-14_13-58-40--code--oauth-callback-error.jpg'* ]]
  [[ "$(<"$MOCK_CLIPBOARD_TOKEN_FILE")" -eq 50 ]]
  [[ ! -e "$MOCK_NOTIFICATION_LOG" ]]
}

@test "keeps a successful rename when clipboard copying fails" {
  export MOCK_CLIPBOARD_COPY_FAILURE=1
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error.jpg" ]]
  grep -q 'CleanShot screenshot clipboard failed' "$MOCK_NOTIFICATION_LOG"
}

@test "keeps naming when the clipboard cannot be observed" {
  export MOCK_CLIPBOARD_OBSERVE_FAILURE=1
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error.jpg" ]]
  [[ "$(grep -c '^copy-if-current' "$MOCK_CLIPBOARD_LOG" || true)" -eq 0 ]]
  grep -q 'CleanShot screenshot clipboard unavailable' "$MOCK_NOTIFICATION_LOG"
}

@test "leaves an unstable screenshot for a later event" {
  export MOCK_UNSTABLE=1
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/CleanShot 2026-08-14 at 13.58.40.jpg" ]]
  [[ ! -e "$MOCK_CODEX_COUNT" ]]
}

@test "processes multiple new screenshots chronologically" {
  write_screenshot 'CleanShot 2026-08-14 at 13.58.41.jpg'
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error.jpg" ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-41--code--oauth-callback-error.jpg" ]]
  [[ "$(<"$MOCK_CODEX_COUNT")" -eq 2 ]]
  first_image="$(head -n 1 "$MOCK_CODEX_LOG")"
  [[ "$first_image" == *'13.58.40.jpg'* ]]
  first_copy="$(sed -n '2p' "$MOCK_CLIPBOARD_LOG")"
  second_copy="$(sed -n '3p' "$MOCK_CLIPBOARD_LOG")"
  [[ "$first_copy" == $'copy-if-current\t40\t'*'13-58-40--code--oauth-callback-error.jpg' ]]
  [[ "$second_copy" == $'copy-if-current\t41\t'*'13-58-41--code--oauth-callback-error.jpg' ]]
}
