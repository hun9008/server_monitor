#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER="# server_monitoring user_storage_alert"

if [[ "$(id -u)" -ne 0 ]]; then
  printf 'Run this installer as root so all home directories can be measured: sudo %s\n' "$0" >&2
  exit 1
fi

for command in crontab flock python3 du df; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
  printf 'Missing %s/.env; copy .env.example and configure mail first.\n' "$SCRIPT_DIR" >&2
  exit 1
fi

cron_file="$(mktemp)"
trap 'rm -f "$cron_file"' EXIT
crontab -l 2>/dev/null | grep -Fv "$MARKER" >"$cron_file" || true
printf '0 * * * * %q >>/tmp/user_storage_alert.log 2>&1 %s\n' \
  "${SCRIPT_DIR}/user_storage_alert.sh" "$MARKER" >>"$cron_file"
crontab "$cron_file"

printf 'Installed hourly storage monitoring cron entry.\n'
printf 'Per-user cooldown: USER_STORAGE_COOLDOWN_HOURS (default: 9 hours).\n'
printf 'Log: /tmp/user_storage_alert.log\n'
