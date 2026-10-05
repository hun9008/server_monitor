#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

install_cron_entries
printf 'Installed server monitoring cron entries:\n'
printf '  Snapshot: Monday 09:00\n'
printf '  Urgent alerts: disabled\n'
