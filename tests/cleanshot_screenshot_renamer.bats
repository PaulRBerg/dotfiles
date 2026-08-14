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
  export MOCK_NOTIFICATION_LOG="$TEST_ROOT/notifications.tsv"
  export MOCK_BIRTH_EPOCH=1001
  export MOCK_NOW_EPOCH=1000
  export PATH="$MOCK_BIN:/opt/homebrew/bin:/usr/bin:/bin"
  export RENAMER="$BATS_TEST_DIRNAME/../dot_config/prb/bin/executable_cleanshot_screenshot_renamer_macos.sh"

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

  chmod +x "$MOCK_BIN/codex" "$MOCK_BIN/date" "$MOCK_BIN/sleep" "$MOCK_BIN/stat" "$MOCK_BIN/osascript" "$MOCK_BIN/mv"
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

@test "renames with a fixed category and exact Luna xhigh arguments" {
  write_screenshot 'CleanShot 2026-08-14 at 13.58.40.jpg'

  run_renamer

  [[ "$status" -eq 0 ]]
  [[ -f "$CLEANSHOT_SCREENSHOT_DIR/2026-08-14_13-58-40--code--oauth-callback-error.jpg" ]]
  grep -q -- '--model gpt-5.6-luna' "$MOCK_CODEX_LOG"
  grep -q -- 'model_reasoning_effort=\\"xhigh\\"' "$MOCK_CODEX_LOG"
  grep -q -- '--sandbox read-only' "$MOCK_CODEX_LOG"
  grep -q -- '--ephemeral' "$MOCK_CODEX_LOG"
  grep -q -- '--ignore-user-config' "$MOCK_CODEX_LOG"
  grep -q -- '--ignore-rules' "$MOCK_CODEX_LOG"
  grep -q -- '--image' "$MOCK_CODEX_LOG"
  grep -q -- '--output-schema' "$MOCK_CODEX_LOG"
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
}
