#!/usr/bin/env bats
# Bats isolates each test process, so their mocked clock mutations cannot leak.
# shellcheck disable=SC2030,SC2031

bats_require_minimum_version 1.5.0

setup() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/case"
  export HOME="$TEST_ROOT/home"
  export XDG_STATE_HOME="$TEST_ROOT/state"
  export MOCK_BIN="$TEST_ROOT/bin"
  export MOCK_SMART_JSON="$TEST_ROOT/smart.json"
  export MOCK_NOTIFICATION_LOG="$TEST_ROOT/notifications.tsv"
  export MOCK_EPOCH=1784505600
  export MOCK_TIMESTAMP="2026-07-20T00:00:00Z"
  export PATH="$MOCK_BIN:/opt/homebrew/bin:/usr/bin:/bin"
  export MONITOR="$BATS_TEST_DIRNAME/../dot_config/prb/bin/executable_ssd_write_monitor_macos.sh"

  mkdir -p "$HOME/.codex" "$MOCK_BIN"
  write_mocks
  write_smart 1000 0 100 99 0 0 0 100
}

write_mocks() {
  cat >"$MOCK_BIN/diskutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target="${*: -1}"
if [[ "$target" == "/" ]]; then
  printf '%s\n' '{"APFSPhysicalStores":[{"APFSPhysicalStore":"disk0s2"}]}'
else
  printf '%s\n' '{"ParentWholeDisk":"disk0","SolidState":true}'
fi
EOF

  cat >"$MOCK_BIN/plutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
input="${*: -1}"
output=""
while (($# > 0)); do
  if [[ "$1" == "-o" ]]; then
    output="$2"
    break
  fi
  shift
done
cp "$input" "$output"
EOF

  cat >"$MOCK_BIN/smartctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat "$MOCK_SMART_JSON"
exit "${MOCK_SMART_EXIT:-0}"
EOF

  cat >"$MOCK_BIN/osascript" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf '%s\t%s\n' "${2:-}" "${3:-}" >>"$MOCK_NOTIFICATION_LOG"
EOF

  cat >"$MOCK_BIN/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "+%s" ]]; then
  printf '%s\n' "$MOCK_EPOCH"
else
  printf '%s\n' "$MOCK_TIMESTAMP"
fi
EOF

  chmod +x "$MOCK_BIN/diskutil" "$MOCK_BIN/plutil" "$MOCK_BIN/smartctl" "$MOCK_BIN/osascript" "$MOCK_BIN/date"
}

write_smart() {
  local data_units_written="$1"
  local percentage_used="$2"
  local available_spare="$3"
  local available_spare_threshold="$4"
  local critical_warning="$5"
  local media_errors="$6"
  local error_log_entries="$7"
  local power_on_hours="$8"

  jq -n \
    --argjson data_units_written "$data_units_written" \
    --argjson percentage_used "$percentage_used" \
    --argjson available_spare "$available_spare" \
    --argjson available_spare_threshold "$available_spare_threshold" \
    --argjson critical_warning "$critical_warning" \
    --argjson media_errors "$media_errors" \
    --argjson error_log_entries "$error_log_entries" \
    --argjson power_on_hours "$power_on_hours" \
    '{
      smartctl: {exit_status: 0},
      nvme_smart_health_information_log: {
        data_units_written: $data_units_written,
        percentage_used: $percentage_used,
        available_spare: $available_spare,
        available_spare_threshold: $available_spare_threshold,
        critical_warning: $critical_warning,
        media_errors: $media_errors,
        num_err_log_entries: $error_log_entries,
        power_on_hours: $power_on_hours
      }
    }' >"$MOCK_SMART_JSON"
}

run_monitor() {
  run bash "$MONITOR"
}

advance_day() {
  export MOCK_EPOCH=$((MOCK_EPOCH + 86400))
  export MOCK_TIMESTAMP="2026-07-21T00:00:00Z"
}

@test "creates a baseline and records Codex file sizes" {
  printf 'abc' >"$HOME/.codex/logs_2.sqlite"
  printf '12345' >"$HOME/.codex/logs_2.sqlite-wal"

  run_monitor

  [[ "$status" -eq 0 ]]
  jq -e '.data_units_written == 1000 and .last_status == "baseline"' "$XDG_STATE_HOME/ssd-write-monitor/state.json"
  [[ "$(wc -l <"$XDG_STATE_HOME/ssd-write-monitor/history.tsv" | tr -d ' ')" -eq 2 ]]
  run awk -F '\t' 'END { print $13, $14, $15, $16 }' "$XDG_STATE_HOME/ssd-write-monitor/history.tsv"
  [[ "$output" = "3 5 0 baseline" ]]
  [[ ! -e "$MOCK_NOTIFICATION_LOG" ]]
}

@test "keeps a normal daily write rate silent" {
  run_monitor
  [[ "$status" -eq 0 ]]

  advance_day
  write_smart 782250 0 100 99 0 0 0 124
  run_monitor

  [[ "$status" -eq 0 ]]
  jq -e '.last_status == "ok"' "$XDG_STATE_HOME/ssd-write-monitor/state.json"
  [[ ! -e "$MOCK_NOTIFICATION_LOG" ]]
}

@test "warns above 500 GB per day" {
  run_monitor
  [[ "$status" -eq 0 ]]

  advance_day
  write_smart 1172875 0 100 99 0 0 0 124
  run_monitor

  [[ "$status" -eq 0 ]]
  jq -e '.last_status == "warning"' "$XDG_STATE_HOME/ssd-write-monitor/state.json"
  grep -q $'SSD write monitor warning\thost writes 600 GB/day' "$MOCK_NOTIFICATION_LOG"
}

@test "raises a critical alert above 1 TB per day" {
  run_monitor
  [[ "$status" -eq 0 ]]

  advance_day
  write_smart 2344750 0 100 99 0 0 0 124
  run_monitor

  [[ "$status" -eq 0 ]]
  jq -e '.last_status == "critical"' "$XDG_STATE_HOME/ssd-write-monitor/state.json"
  grep -q $'SSD write monitor critical\thost writes 1200 GB/day' "$MOCK_NOTIFICATION_LOG"
}

@test "aggregates worsening SMART health into one critical alert" {
  run_monitor
  [[ "$status" -eq 0 ]]

  advance_day
  write_smart 1010 1 100 99 0 1 2 124
  run_monitor

  [[ "$status" -eq 0 ]]
  jq -e '.last_status == "critical"' "$XDG_STATE_HOME/ssd-write-monitor/state.json"
  [[ "$(wc -l <"$MOCK_NOTIFICATION_LOG" | tr -d ' ')" -eq 1 ]]
  grep -q 'media errors increased from 0 to 1' "$MOCK_NOTIFICATION_LOG"
  grep -q 'SMART percentage used increased from 0% to 1%' "$MOCK_NOTIFICATION_LOG"
  grep -q 'error-log entries increased from 0 to 2' "$MOCK_NOTIFICATION_LOG"
}

@test "does not extrapolate short intervals and rebaselines counter resets" {
  run_monitor
  [[ "$status" -eq 0 ]]

  export MOCK_EPOCH=$((MOCK_EPOCH + 30))
  write_smart 1000000 0 100 99 0 0 0 100
  run_monitor
  [[ "$status" -eq 0 ]]
  jq -e '.last_status == "short_interval" and .rate_data_units_written == 1000' "$XDG_STATE_HOME/ssd-write-monitor/state.json"

  advance_day
  write_smart 10 0 100 99 0 0 0 124
  run_monitor
  [[ "$status" -eq 0 ]]
  jq -e '.last_status == "reset"' "$XDG_STATE_HOME/ssd-write-monitor/state.json"
  [[ ! -e "$MOCK_NOTIFICATION_LOG" ]]
}

@test "retains the rate baseline across short intervals" {
  run_monitor
  [[ "$status" -eq 0 ]]
  state="$XDG_STATE_HOME/ssd-write-monitor/state.json"
  jq 'del(.rate_timestamp_epoch, .rate_data_units_written)' "$state" >"$TEST_ROOT/legacy-state.json"
  mv "$TEST_ROOT/legacy-state.json" "$state"

  export MOCK_EPOCH=$((MOCK_EPOCH + 30))
  write_smart 1172875 0 100 99 0 0 0 100
  run_monitor
  [[ "$status" -eq 0 ]]
  jq -e '.last_status == "short_interval" and .rate_data_units_written == 1000' "$XDG_STATE_HOME/ssd-write-monitor/state.json"
  [[ ! -e "$MOCK_NOTIFICATION_LOG" ]]

  export MOCK_EPOCH=$((MOCK_EPOCH + 3570))
  write_smart 1172875 0 100 99 0 0 0 101
  run_monitor

  [[ "$status" -eq 0 ]]
  jq -e '.last_status == "critical" and .rate_data_units_written == 1172875' "$XDG_STATE_HOME/ssd-write-monitor/state.json"
  grep -q $'SSD write monitor critical\thost writes 14400 GB/day' "$MOCK_NOTIFICATION_LOG"
}

@test "preserves state and notifies when SMART output is invalid" {
  run_monitor
  [[ "$status" -eq 0 ]]
  cp "$XDG_STATE_HOME/ssd-write-monitor/state.json" "$TEST_ROOT/state.before.json"

  printf '{' >"$MOCK_SMART_JSON"
  run_monitor

  [[ "$status" -ne 0 ]]
  cmp -s "$TEST_ROOT/state.before.json" "$XDG_STATE_HOME/ssd-write-monitor/state.json"
  grep -q 'SSD write monitor failed' "$MOCK_NOTIFICATION_LOG"
}

@test "rejects non-integer SMART counters" {
  run_monitor
  [[ "$status" -eq 0 ]]
  cp "$XDG_STATE_HOME/ssd-write-monitor/state.json" "$TEST_ROOT/state.before.json"
  jq '.nvme_smart_health_information_log.data_units_written = "1001"' "$MOCK_SMART_JSON" >"$TEST_ROOT/smart.invalid.json"
  mv "$TEST_ROOT/smart.invalid.json" "$MOCK_SMART_JSON"

  run_monitor

  [[ "$status" -ne 0 ]]
  cmp -s "$TEST_ROOT/state.before.json" "$XDG_STATE_HOME/ssd-write-monitor/state.json"
  grep -q 'SMART collection failed' "$MOCK_NOTIFICATION_LOG"
}

@test "rejects corrupt state before arithmetic" {
  run_monitor
  [[ "$status" -eq 0 ]]
  state="$XDG_STATE_HOME/ssd-write-monitor/state.json"
  jq '.timestamp_epoch = "1 + 1"' "$state" >"$TEST_ROOT/state.invalid.json"
  mv "$TEST_ROOT/state.invalid.json" "$state"

  run_monitor

  [[ "$status" -ne 0 ]]
  grep -q 'invalid monitor state' "$MOCK_NOTIFICATION_LOG"
  [[ "$(wc -l <"$XDG_STATE_HOME/ssd-write-monitor/history.tsv" | tr -d ' ')" -eq 2 ]]
}

@test "retains the newest 400 history samples" {
  run_monitor
  [[ "$status" -eq 0 ]]

  history="$XDG_STATE_HOME/ssd-write-monitor/history.tsv"
  header="$(head -n 1 "$history")"
  {
    printf '%s\n' "$header"
    for index in $(seq 1 400); do
      printf 'old-%s\n' "$index"
    done
  } >"$history"

  advance_day
  write_smart 1010 0 100 99 0 0 0 124
  run_monitor

  [[ "$status" -eq 0 ]]
  [[ "$(wc -l <"$history" | tr -d ' ')" -eq 401 ]]
  run ! grep -q '^old-1$' "$history"
  grep -q '^old-2$' "$history"
  [[ "$(head -n 1 "$history")" = "$header" ]]
}
