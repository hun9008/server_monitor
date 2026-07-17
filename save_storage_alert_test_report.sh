#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKDOWN_FILE="${1:-${SCRIPT_DIR}/alert_storage_test.md}"
HTML_FILE="${MARKDOWN_FILE%.md}.html"

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env"
  set +a
fi

python3 - "$SCRIPT_DIR" "$MARKDOWN_FILE" "$HTML_FILE" <<'PY'
import os
import sys
from pathlib import Path

script_dir = Path(sys.argv[1])
markdown_file = Path(sys.argv[2])
html_file = Path(sys.argv[3])
sys.path.insert(0, str(script_dir))

import send_smtp
import user_storage_alert

user = {
    "name": "정용훈",
    "email": user_storage_alert.TEST_RECIPIENT,
    "username": "hun",
}
body = user_storage_alert.message_body(
    user=user,
    home="/home/hun",
    used=1024 ** 4,
    total=4 * 1024 ** 4,
    percent=25.0,
    n=4,
    test=True,
)
markdown_file.write_text(body, encoding="utf-8")

logo_path = Path(os.environ.get("LOGO_PATH", script_dir / "dilab_logo.png"))
logo_mode = os.environ.get("LOGO_MODE", "cid").lower()
logo_src = None
if logo_mode != "none":
    logo_src = os.environ.get("LOGO_URL") or send_smtp.logo_data_uri(logo_path)

html_file.write_text(
    send_smtp.render_html_report(body, logo_src=logo_src),
    encoding="utf-8",
)
PY

printf 'Saved storage alert email body to %s\n' "$MARKDOWN_FILE"
printf 'Saved HTML preview to %s\n' "$HTML_FILE"
