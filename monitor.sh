#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<USAGE
Usage: $0 [--print] [--no-send]

Creates the regular weekly server snapshot report.

Environment variables are loaded from:
  ${ENV_FILE}
USAGE
}

PRINT_ONLY=0
SEND_MAIL=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --print)
      PRINT_ONLY=1
      ;;
    --no-send)
      SEND_MAIL=0
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

REPORT_FILE="${REPORT_FILE:-/tmp/server-monitor-${HOSTNAME_FQDN}.md}"
SUBJECT="${SUBJECT:-[Server Snapshot] ${HOST_DISPLAY_NAME} $(now_string)}"

write_snapshot_report "$REPORT_FILE"

if [[ "$PRINT_ONLY" -eq 1 ]]; then
  cat "$REPORT_FILE"
fi

if [[ "$SEND_MAIL" -eq 1 ]]; then
  send_report_file "$REPORT_FILE" "$SUBJECT"
fi
