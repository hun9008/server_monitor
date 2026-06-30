#!/usr/bin/env python3
import argparse
import html
import os
import re
import smtplib
from email.message import EmailMessage


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
    urgent_mode = body.startswith("# Urgent")

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


def render_html_report(body: str) -> str:
    rendered_body = render_markdown_report(body)
    wrap_class = "wrap urgent-wrap" if body.startswith("# Urgent") else "wrap"
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
      {rendered_body}
    </div>
  </body>
</html>
"""


def main() -> None:
    args = parse_args()

    smtp_host = os.environ["SMTP_HOST"]
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    smtp_user = os.environ.get("SMTP_USER")
    smtp_pass = os.environ.get("SMTP_PASS")
    smtp_tls = env_bool("SMTP_TLS", True)
    smtp_html = env_bool("SMTP_HTML", True)
    smtp_timeout = int(os.environ.get("SMTP_TIMEOUT", "30"))

    msg = EmailMessage()
    msg["From"] = args.mail_from
    msg["To"] = args.mail_to
    msg["Subject"] = args.subject

    with open(args.body_file, "r", encoding="utf-8", errors="replace") as report:
        body = report.read()

    msg.set_content(body)
    if smtp_html:
        msg.add_alternative(render_html_report(body), subtype="html")

    with smtplib.SMTP(smtp_host, smtp_port, timeout=smtp_timeout) as smtp:
        if smtp_tls:
            smtp.starttls()
        if smtp_user and smtp_pass:
            smtp.login(smtp_user, smtp_pass)
        smtp.send_message(msg, from_addr=args.mail_from, to_addrs=parse_recipients(args.mail_to))


if __name__ == "__main__":
    main()
