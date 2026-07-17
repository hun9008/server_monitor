#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Reuse the existing .env SMTP settings without changing cron configuration.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

LOCK_FILE="${USER_STORAGE_LOCK_FILE:-/tmp/user-storage-alert.lock}"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  printf 'Another user storage check is already running; skipping.\n' >&2
  exit 0
fi

exec python3 "${SCRIPT_DIR}/user_storage_alert.py" "$@"
