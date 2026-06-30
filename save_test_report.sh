#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${1:-${SCRIPT_DIR}/test.md}"

"${SCRIPT_DIR}/monitor.sh" --print --no-send > "$OUTPUT_FILE"

printf 'Saved monitoring email body to %s\n' "$OUTPUT_FILE"
