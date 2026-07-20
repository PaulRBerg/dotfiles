#!/usr/bin/env bash

set -euo pipefail

readonly DATA_UNIT_BYTES=512000
readonly SECONDS_PER_DAY=86400
readonly MIN_SAMPLE_SECONDS=3600
readonly WARNING_BYTES_PER_DAY=500000000000
readonly CRITICAL_BYTES_PER_DAY=1000000000000
readonly HISTORY_LIMIT=400
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ssd-write-monitor"
readonly STATE_FILE="$STATE_DIR/state.json"
readonly HISTORY_FILE="$STATE_DIR/history.tsv"
readonly HISTORY_HEADER=$'timestamp_utc\tdevice\tdata_units_written\tdelta_data_units\telapsed_seconds\tbytes_per_day\tpercentage_used\tavailable_spare\tcritical_warning\tmedia_errors\terror_log_entries\tpower_on_hours\tcodex_db_bytes\tcodex_wal_bytes\tcodex_shm_bytes\tstatus'

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

notify() {
  local title="$1"
  local message="$2"
  local osascript_bin

  if ! osascript_bin="$(command -v osascript)"; then
    log "notification unavailable: osascript not found"
    return 0
  fi

  if ! "$osascript_bin" - "$title" "$message" >/dev/null <<'APPLESCRIPT'; then
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
    log "notification failed: $title"
  fi
}

fail() {
  local message="$1"
  log "$message"
  notify "SSD write monitor failed" "$message"
  exit 1
}

require_commands() {
  local command_name
  local missing=()

  for command_name in date diskutil jq mktemp mv plutil smartctl stat tail; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing+=("$command_name")
    fi
  done

  if ((${#missing[@]} > 0)); then
    fail "missing required commands: ${missing[*]}"
  fi
}

raise_alert() {
  local requested_severity="$1"
  local message="$2"

  if [[ "$requested_severity" == "critical" || "$severity" == "normal" ]]; then
    severity="$requested_severity"
  fi
  alert_messages+=("$message")
}

join_alerts() {
  local result=""
  local message

  for message in "${alert_messages[@]}"; do
    if [[ -n "$result" ]]; then
      result+="; "
    fi
    result+="$message"
  done
  printf '%s\n' "$result"
}

file_size() {
  local file="$1"
  local size

  if [[ -f "$file" ]] && size="$(stat -f '%z' "$file" 2>/dev/null)"; then
    printf '%s\n' "$size"
  else
    printf '0\n'
  fi
}

require_commands
umask 077
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

tmp_dir="$(mktemp -d "$STATE_DIR/.tmp.XXXXXX")"
readonly tmp_dir
trap 'rm -rf -- "$tmp_dir"' EXIT

if ! diskutil info -plist / >"$tmp_dir/root.plist" 2>"$tmp_dir/diskutil.err"; then
  fail "could not inspect the boot volume"
fi
if ! plutil -convert json -o "$tmp_dir/root.json" "$tmp_dir/root.plist" 2>>"$tmp_dir/diskutil.err"; then
  fail "could not parse boot-volume metadata"
fi
if ! physical_store="$(jq -er '.APFSPhysicalStores | select(type == "array" and length == 1) | .[0].APFSPhysicalStore | select(type == "string" and length > 0)' "$tmp_dir/root.json")"; then
  fail "expected exactly one APFS physical store for the boot volume"
fi

if ! diskutil info -plist "$physical_store" >"$tmp_dir/store.plist" 2>>"$tmp_dir/diskutil.err"; then
  fail "could not inspect APFS physical store $physical_store"
fi
if ! plutil -convert json -o "$tmp_dir/store.json" "$tmp_dir/store.plist" 2>>"$tmp_dir/diskutil.err"; then
  fail "could not parse physical-store metadata"
fi
if ! whole_disk="$(jq -er 'select(.SolidState == true) | .ParentWholeDisk | select(type == "string" and length > 0)' "$tmp_dir/store.json")"; then
  fail "the boot volume is not backed by one identifiable solid-state disk"
fi
readonly device="/dev/$whole_disk"

smartctl_rc=0
smartctl -Aj "$device" >"$tmp_dir/smart.json" 2>"$tmp_dir/smart.err" || smartctl_rc=$?
if ! jq -e '
  .nvme_smart_health_information_log as $health
  | [
      $health.data_units_written,
      $health.percentage_used,
      $health.available_spare,
      $health.available_spare_threshold,
      $health.critical_warning,
      $health.media_errors,
      $health.num_err_log_entries,
      $health.power_on_hours
    ]
  | all(.[]; type == "number" and . >= 0)
' "$tmp_dir/smart.json" >/dev/null 2>&1; then
  fail "SMART collection failed for $device (smartctl exit $smartctl_rc)"
fi
if ((smartctl_rc != 0)); then
  log "smartctl returned $smartctl_rc but provided a complete NVMe health record"
fi

metrics="$(jq -er '
  .nvme_smart_health_information_log
  | [
      .data_units_written,
      .percentage_used,
      .available_spare,
      .available_spare_threshold,
      .critical_warning,
      .media_errors,
      .num_err_log_entries,
      .power_on_hours
    ]
  | @tsv
' "$tmp_dir/smart.json")"
IFS=$'\t' read -r data_units_written percentage_used available_spare available_spare_threshold critical_warning media_errors error_log_entries power_on_hours <<<"$metrics"
readonly data_units_written percentage_used available_spare available_spare_threshold critical_warning media_errors error_log_entries power_on_hours

readonly timestamp_epoch="$(date '+%s')"
readonly timestamp_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
readonly codex_db_bytes="$(file_size "$HOME/.codex/logs_2.sqlite")"
readonly codex_wal_bytes="$(file_size "$HOME/.codex/logs_2.sqlite-wal")"
readonly codex_shm_bytes="$(file_size "$HOME/.codex/logs_2.sqlite-shm")"

have_previous=false
previous_device=""
previous_timestamp=0
previous_data_units=0
previous_percentage_used=0
previous_media_errors=0
previous_error_log_entries=0

if [[ -f "$STATE_FILE" ]]; then
  if ! previous="$(jq -er '
    select(.schema_version == 1)
    | [
        .device,
        .timestamp_epoch,
        .data_units_written,
        .percentage_used,
        .media_errors,
        .error_log_entries
      ]
    | @tsv
  ' "$STATE_FILE")"; then
    fail "invalid monitor state: $STATE_FILE"
  fi
  IFS=$'\t' read -r previous_device previous_timestamp previous_data_units previous_percentage_used previous_media_errors previous_error_log_entries <<<"$previous"
  have_previous=true
fi

severity="normal"
alert_messages=()
sample_status="baseline"
delta_data_units=""
elapsed_seconds=""
bytes_per_day=""
compatible_previous=false

if [[ "$have_previous" == true && "$previous_device" == "$device" && "$timestamp_epoch" -gt "$previous_timestamp" && "$data_units_written" -ge "$previous_data_units" ]]; then
  compatible_previous=true
  elapsed_seconds=$((timestamp_epoch - previous_timestamp))
  delta_data_units=$((data_units_written - previous_data_units))

  if ((elapsed_seconds >= MIN_SAMPLE_SECONDS)); then
    bytes_per_day="$(jq -nr \
      --argjson units "$delta_data_units" \
      --argjson data_unit_bytes "$DATA_UNIT_BYTES" \
      --argjson seconds_per_day "$SECONDS_PER_DAY" \
      --argjson elapsed "$elapsed_seconds" \
      '($units * $data_unit_bytes * $seconds_per_day / $elapsed) | floor')"
    sample_status="ok"

    if ((bytes_per_day >= CRITICAL_BYTES_PER_DAY)); then
      raise_alert critical "host writes $((bytes_per_day / 1000000000)) GB/day"
    elif ((bytes_per_day >= WARNING_BYTES_PER_DAY)); then
      raise_alert warning "host writes $((bytes_per_day / 1000000000)) GB/day"
    fi
  else
    sample_status="short_interval"
  fi
elif [[ "$have_previous" == true ]]; then
  sample_status="reset"
fi

if ((critical_warning != 0)); then
  raise_alert critical "SMART critical warning is $critical_warning"
fi
if ((available_spare <= available_spare_threshold)); then
  raise_alert critical "available spare ${available_spare}% is at or below its ${available_spare_threshold}% threshold"
fi

if [[ "$compatible_previous" == true ]]; then
  if ((media_errors > previous_media_errors)); then
    raise_alert critical "media errors increased from $previous_media_errors to $media_errors"
  fi
  if ((percentage_used > previous_percentage_used)); then
    raise_alert warning "SMART percentage used increased from ${previous_percentage_used}% to ${percentage_used}%"
  fi
  if ((error_log_entries > previous_error_log_entries)); then
    raise_alert warning "error-log entries increased from $previous_error_log_entries to $error_log_entries"
  fi
elif ((media_errors > 0)); then
  raise_alert critical "SMART reports $media_errors existing media errors"
fi

if [[ "$severity" != "normal" ]]; then
  sample_status="$severity"
fi

if [[ -f "$HISTORY_FILE" ]]; then
  IFS= read -r existing_header <"$HISTORY_FILE" || true
  if [[ "$existing_header" != "$HISTORY_HEADER" ]]; then
    fail "invalid history header: $HISTORY_FILE"
  fi
fi

{
  printf '%s\n' "$HISTORY_HEADER"
  if [[ -f "$HISTORY_FILE" ]]; then
    tail -n +2 "$HISTORY_FILE" | tail -n "$((HISTORY_LIMIT - 1))"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$timestamp_utc" \
    "$device" \
    "$data_units_written" \
    "$delta_data_units" \
    "$elapsed_seconds" \
    "$bytes_per_day" \
    "$percentage_used" \
    "$available_spare" \
    "$critical_warning" \
    "$media_errors" \
    "$error_log_entries" \
    "$power_on_hours" \
    "$codex_db_bytes" \
    "$codex_wal_bytes" \
    "$codex_shm_bytes" \
    "$sample_status"
} >"$tmp_dir/history.tsv"
chmod 600 "$tmp_dir/history.tsv"
mv "$tmp_dir/history.tsv" "$HISTORY_FILE"

jq -n \
  --argjson schema_version 1 \
  --arg timestamp_utc "$timestamp_utc" \
  --argjson timestamp_epoch "$timestamp_epoch" \
  --arg device "$device" \
  --argjson data_units_written "$data_units_written" \
  --argjson percentage_used "$percentage_used" \
  --argjson available_spare "$available_spare" \
  --argjson available_spare_threshold "$available_spare_threshold" \
  --argjson critical_warning "$critical_warning" \
  --argjson media_errors "$media_errors" \
  --argjson error_log_entries "$error_log_entries" \
  --argjson power_on_hours "$power_on_hours" \
  --arg last_status "$sample_status" \
  '{
    schema_version: $schema_version,
    timestamp_utc: $timestamp_utc,
    timestamp_epoch: $timestamp_epoch,
    device: $device,
    data_units_written: $data_units_written,
    percentage_used: $percentage_used,
    available_spare: $available_spare,
    available_spare_threshold: $available_spare_threshold,
    critical_warning: $critical_warning,
    media_errors: $media_errors,
    error_log_entries: $error_log_entries,
    power_on_hours: $power_on_hours,
    last_status: $last_status
  }' >"$tmp_dir/state.json"
chmod 600 "$tmp_dir/state.json"
mv "$tmp_dir/state.json" "$STATE_FILE"

if [[ "$severity" != "normal" ]]; then
  notify "SSD write monitor $severity" "$(join_alerts)"
fi

rate_summary="n/a"
if [[ -n "$bytes_per_day" ]]; then
  rate_summary="$((bytes_per_day / 1000000000)) GB/day"
fi
log "status=$sample_status device=$device data_units_written=$data_units_written rate=$rate_summary"
