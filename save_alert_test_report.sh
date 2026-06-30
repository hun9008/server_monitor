#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${1:-${SCRIPT_DIR}/alert_test.md}"

FORCE_MEMORY_PCT=76.8% \
FORCE_TOTAL_STORAGE_PCT=68.5% \
FORCE_HOME_STORAGE_PCT=92.4% \
ALERT_REPORT_FILE="$OUTPUT_FILE" \
"${SCRIPT_DIR}/alert_check.sh" --no-send --force >/tmp/server_monitoring_alert_test.log 2>&1

printf 'Saved alert email body to %s\n' "$OUTPUT_FILE"
