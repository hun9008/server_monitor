#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<USAGE
Usage: $0 [--print] [--no-send] [--force]

Checks memory/storage thresholds and sends an urgent alert when:
  memory, total storage, or home storage >= ALERT_THRESHOLD

Cooldown:
  same target is suppressed for ALERT_COOLDOWN_HOURS after an alert.
USAGE
}

PRINT_ONLY=0
SEND_MAIL=1
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --print)
      PRINT_ONLY=1
      ;;
    --no-send)
      SEND_MAIL=0
      ;;
    --force)
      FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

memory_pct="$(memory_used_percent)"
total_storage_pct="$(total_storage_used_percent)"
home_storage_pct="$(home_storage_used_percent)"

targets=()
if is_percent_at_least "$memory_pct" "$ALERT_THRESHOLD"; then
  targets+=("memory")
fi
if is_percent_at_least "$total_storage_pct" "$ALERT_THRESHOLD"; then
  targets+=("total_storage")
fi
if [[ -n "$home_storage_pct" ]] && is_percent_at_least "$home_storage_pct" "$ALERT_THRESHOLD"; then
  targets+=("home_storage")
fi

eligible_targets=()
for target in "${targets[@]}"; do
  if [[ "$FORCE" -eq 1 ]] || ! alert_is_in_cooldown "$target"; then
    eligible_targets+=("$target")
  fi
done

if [[ "${#targets[@]}" -eq 0 ]]; then
  printf 'No alert targets. memory=%s total_storage=%s home_storage=%s threshold=%s%%\n' \
    "$memory_pct" "$total_storage_pct" "${home_storage_pct:-N/A}" "$ALERT_THRESHOLD"
  exit 0
fi

if [[ "${#eligible_targets[@]}" -eq 0 ]]; then
  printf 'Alert condition exists, but all targets are in cooldown. targets=%s cooldown=%sh\n' \
    "${targets[*]}" "$ALERT_COOLDOWN_HOURS"
  exit 0
fi

ALERT_REPORT_FILE="${ALERT_REPORT_FILE:-/tmp/server-alert-${HOSTNAME_FQDN}.md}"
ALERT_SUBJECT="${ALERT_SUBJECT:-[Server Alert] ${HOSTNAME_FQDN} memory/storage threshold exceeded}"

write_alert_report "$ALERT_REPORT_FILE" "${eligible_targets[@]}"

if [[ "$PRINT_ONLY" -eq 1 ]]; then
  cat "$ALERT_REPORT_FILE"
fi

if [[ "$SEND_MAIL" -eq 1 ]]; then
  send_report_file "$ALERT_REPORT_FILE" "$ALERT_SUBJECT"
  for target in "${eligible_targets[@]}"; do
    mark_alert_sent "$target"
  done
fi
