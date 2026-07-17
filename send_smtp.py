#!/usr/bin/env python3
import argparse
import base64
import html
import os
import re
import smtplib
from email.message import EmailMessage
from email.utils import make_msgid
from pathlib import Path


def env_bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.lower() not in {"0", "false", "no", "off"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send a server monitoring report via SMTP.")
    parser.add_argument("--from", dest="mail_from", required=True)
    parser.add_argument("--to", dest="mail_to", required=True)
    parser.add_argument("--subject", required=True)
    parser.add_argument("--body-file", required=True)
    return parser.parse_args()


def parse_recipients(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(",") if item.strip()]


def percent_color(value: float) -> str:
    if value >= 90:
        return "#dc2626"
    if value >= 70:
        return "#ca8a04"
    return "#15803d"


def render_inline(text: str) -> str:
    escaped = html.escape(text)

    def bold_repl(match: re.Match[str]) -> str:
        return f"<strong>{match.group(1)}</strong>"

    escaped = re.sub(r"\*\*([^*]+)\*\*", bold_repl, escaped)

    def code_repl(match: re.Match[str]) -> str:
        return f"<code>{match.group(1)}</code>"

    escaped = re.sub(r"`([^`]+)`", code_repl, escaped)

    def percent_repl(match: re.Match[str]) -> str:
        value = float(match.group(1))
        color = percent_color(value)
        return f'<span style="color:{color}; font-weight:700;">{match.group(0)}</span>'

    escaped = re.sub(r"\b(\d+(?:\.\d+)?)%", percent_repl, escaped)

    badges = {
        "OK": ("#dcfce7", "#166534"),
        "WARNING": ("#fef3c7", "#92400e"),
        "CRITICAL": ("#fee2e2", "#991b1b"),
    }
    if text in badges:
        bg, fg = badges[text]
        return (
            f'<span style="display:inline-block; padding:2px 8px; border-radius:999px; '
            f'background:{bg}; color:{fg}; font-weight:700; font-size:12px;">{text}</span>'
        )

    return escaped


def render_table(lines: list[str]) -> str:
    rows = []
    for line in lines:
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if cells and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells):
            continue
        rows.append(cells)

    if not rows:
        return ""

    header = rows[0]
    body = rows[1:]

    out = ['<table class="metric-table">', "<thead><tr>"]
    for cell in header:
        out.append(f"<th>{render_inline(cell)}</th>")
    out.append("</tr></thead><tbody>")

    for row in body:
        out.append("<tr>")
        for cell in row:
            out.append(f"<td>{render_inline(cell)}</td>")
        out.append("</tr>")

    out.append("</tbody></table>")
    return "".join(out)


def render_markdown_report(body: str) -> str:
    lines = body.splitlines()
    rendered = []
    i = 0
    urgent_mode = body.startswith("# Urgent") or body.startswith("# [Urgent]")

    while i < len(lines):
        line = lines[i]

        if line.startswith("```"):
            i += 1
            block = []
            while i < len(lines) and not lines[i].startswith("```"):
                block.append(lines[i])
                i += 1
            rendered.append(f'<pre class="code-block">{html.escape(chr(10).join(block))}</pre>')
            i += 1
            continue

        if line.startswith("|"):
            table_lines = []
            while i < len(lines) and lines[i].startswith("|"):
                table_lines.append(lines[i])
                i += 1
            rendered.append(render_table(table_lines))
            continue

        if line.startswith("# "):
            class_name = ' class="urgent-title"' if urgent_mode else ""
            rendered.append(f"<h1{class_name}>{render_inline(line[2:].strip())}</h1>")
        elif line.startswith("## "):
            rendered.append(f"<h2>{render_inline(line[3:].strip())}</h2>")
        elif line.strip():
            rendered.append(f"<p>{render_inline(line.strip())}</p>")

        i += 1

    return "\n".join(rendered)


def split_report_header(body: str) -> tuple[str | None, str | None, str]:
    lines = body.splitlines()
    if not lines or not lines[0].startswith("# "):
        return None, None, body

    title = lines[0][2:].strip()
    index = 1
    while index < len(lines) and not lines[index].strip():
        index += 1

    meta = None
    if index < len(lines) and not lines[index].startswith("#"):
      meta = lines[index].strip()
      index += 1

    while index < len(lines) and not lines[index].strip():
        index += 1

    return title, meta, "\n".join(lines[index:])


def render_html_report(body: str, logo_src: str | None = None) -> str:
    title, meta, body_without_header = split_report_header(body)
    rendered_body = render_markdown_report(body_without_header)
    wrap_class = "wrap urgent-wrap" if body.startswith("# Urgent") else "wrap"
    brand_html = ""
    if title:
        logo_html = ""
        if logo_src:
            logo_html = f'<img src="{logo_src}" alt="DILAB" class="brand-logo">'
        brand_html = f"""\
      <div class="brand">
        <div class="brand-copy">
          <h1 class="brand-title">{render_inline(title)}</h1>
          <div class="brand-meta">{render_inline(meta or "")}</div>
        </div>
        {logo_html}
      </div>
"""
    return f"""\
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <style>
      body {{
        margin: 0;
        padding: 24px;
        background: #f6f8fb;
        color: #111827;
        font-family: Arial, Helvetica, sans-serif;
      }}
      .wrap {{
        max-width: 920px;
        margin: 0 auto;
        background: #ffffff;
        border: 1px solid #e5e7eb;
        border-radius: 8px;
        padding: 22px 24px;
      }}
      .urgent-wrap {{
        border-color: #fecaca;
      }}
      .brand {{
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 18px;
        margin: 0 0 20px;
        padding-bottom: 18px;
        border-bottom: 1px solid #e5e7eb;
      }}
      .brand-copy {{
        min-width: 0;
      }}
      .brand-title {{
        margin: 0;
        font-size: 24px;
        line-height: 1.25;
      }}
      .brand-meta {{
        margin-top: 6px;
        color: #4b5563;
        font-size: 13px;
      }}
      .urgent-wrap .brand-meta {{
        color: #111827;
      }}
      .brand-logo {{
        display: block;
        width: 168px;
        max-width: 32%;
        height: auto;
      }}
      h1 {{
        margin: 0 0 8px;
        font-size: 24px;
        line-height: 1.25;
      }}
      .urgent-title {{
        color: #b91c1c;
      }}
      h2 {{
        margin: 26px 0 10px;
        padding-top: 18px;
        border-top: 1px solid #e5e7eb;
        font-size: 16px;
      }}
      p {{
        margin: 6px 0 12px;
        color: #4b5563;
      }}
      code {{
        padding: 1px 5px;
        border-radius: 4px;
        background: #f3f4f6;
        font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
        font-size: 12px;
      }}
      .metric-table {{
        width: 100%;
        border-collapse: collapse;
        margin: 8px 0 14px;
        font-size: 13px;
      }}
      .metric-table th {{
        text-align: left;
        background: #f9fafb;
        color: #374151;
        border: 1px solid #e5e7eb;
        padding: 8px 10px;
      }}
      .metric-table td {{
        border: 1px solid #e5e7eb;
        padding: 8px 10px;
        vertical-align: top;
      }}
      .metric-table td:not(:first-child),
      .metric-table th:not(:first-child) {{
        text-align: right;
      }}
      .code-block {{
        margin: 8px 0 14px;
        padding: 12px 14px;
        border-radius: 8px;
        background: #111827;
        color: #e5e7eb;
        overflow-x: auto;
        font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
        font-size: 13px;
        line-height: 1.45;
        white-space: pre;
      }}
    </style>
  </head>
  <body>
    <div class="{wrap_class}">
{brand_html}
      {rendered_body}
    </div>
  </body>
</html>
"""


def logo_data_uri(logo_path: Path) -> str | None:
    if not logo_path.is_file():
        return None
    encoded = base64.b64encode(logo_path.read_bytes()).decode("ascii")
    return f"data:image/png;base64,{encoded}"


def logo_mode() -> str:
    mode = os.environ.get("LOGO_MODE", "cid").lower()
    if mode not in {"cid", "url", "data", "none"}:
        return "cid"
    return mode


def main() -> None:
    args = parse_args()

    smtp_host = os.environ["SMTP_HOST"]
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    smtp_user = os.environ.get("SMTP_USER")
    smtp_pass = os.environ.get("SMTP_PASS")
    smtp_tls = env_bool("SMTP_TLS", True)
    smtp_html = env_bool("SMTP_HTML", True)
    smtp_timeout = int(os.environ.get("SMTP_TIMEOUT", "30"))
    logo_path = Path(os.environ.get("LOGO_PATH", Path(__file__).with_name("dilab_logo.png")))
    logo_url = os.environ.get("LOGO_URL")
    logo_src = None
    logo_cid = None
    mode = logo_mode()

    if smtp_html:
        if logo_url:
            logo_src = logo_url
        elif mode == "data":
            logo_src = logo_data_uri(logo_path)
        elif mode == "cid" and logo_path.is_file():
            logo_cid = make_msgid(domain="server-monitoring.local")[1:-1]
            logo_src = f"cid:{logo_cid}"

    msg = EmailMessage()
    msg["From"] = args.mail_from
    msg["To"] = args.mail_to
    msg["Subject"] = args.subject

    with open(args.body_file, "r", encoding="utf-8", errors="replace") as report:
        body = report.read()

    msg.set_content(body)
    if smtp_html:
        msg.add_alternative(render_html_report(body, logo_src=logo_src), subtype="html")
        if logo_cid:
            html_part = msg.get_payload()[-1]
            html_part.add_related(
                logo_path.read_bytes(),
                maintype="image",
                subtype="png",
                cid=f"<{logo_cid}>",
                disposition="inline",
            )

    with smtplib.SMTP(smtp_host, smtp_port, timeout=smtp_timeout) as smtp:
        if smtp_tls:
            smtp.starttls()
        if smtp_user and smtp_pass:
            smtp.login(smtp_user, smtp_pass)
        smtp.send_message(msg, from_addr=args.mail_from, to_addrs=parse_recipients(args.mail_to))


if __name__ == "__main__":
    main()
