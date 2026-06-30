#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${1:-${SCRIPT_DIR}/alert_test.md}"
HTML_FILE="${OUTPUT_FILE%.md}.html"

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env"
  set +a
fi

FORCE_MEMORY_PCT=76.8% \
FORCE_TOTAL_STORAGE_PCT=68.5% \
FORCE_HOME_STORAGE_PCT=92.4% \
ALERT_REPORT_FILE="$OUTPUT_FILE" \
"${SCRIPT_DIR}/alert_check.sh" --no-send --force >/tmp/server_monitoring_alert_test.log 2>&1

python3 - "$OUTPUT_FILE" "$HTML_FILE" <<'PY'
import os
import sys
from pathlib import Path

body_file = Path(sys.argv[1])
html_file = Path(sys.argv[2])
sys.path.insert(0, str(body_file.parent))
import send_smtp

logo_path = Path(os.environ.get("LOGO_PATH", body_file.parent / "dilab_logo.png"))
logo_mode = os.environ.get("LOGO_MODE", "cid").lower()
logo_src = None
if logo_mode != "none":
    logo_src = os.environ.get("LOGO_URL") or send_smtp.logo_data_uri(logo_path)
html_file.write_text(
    send_smtp.render_html_report(
        body_file.read_text(encoding="utf-8"),
        logo_src=logo_src,
    ),
    encoding="utf-8",
)
PY

printf 'Saved alert email body to %s\n' "$OUTPUT_FILE"
printf 'Saved HTML preview to %s\n' "$HTML_FILE"
