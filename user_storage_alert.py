#!/usr/bin/env python3
"""Alert configured users whose home usage exceeds an equal storage share."""

from __future__ import annotations

import argparse
import json
import os
import pwd
import smtplib
import subprocess
import sys
import time
from email.message import EmailMessage
from email.utils import make_msgid
from pathlib import Path

import send_smtp

TEST_RECIPIENT = "younghune135@unist.ac.kr"


def parse_args() -> argparse.Namespace:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=here / "users.json")
    parser.add_argument("--test", action="store_true",
                        help=f"force one preview email to {TEST_RECIPIENT}")
    parser.add_argument("--no-send", action="store_true", help="print only")
    parser.add_argument("--force", action="store_true", help="ignore the per-user cooldown")
    return parser.parse_args()


def load_users(path: Path) -> list[dict[str, str]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    users = data.get("users")
    if not isinstance(users, list):
        raise ValueError("config must contain a 'users' array")
    return users


def eligible_users(users: list[dict[str, str]]) -> list[dict[str, str]]:
    required = ("name", "email", "username")
    return [u for u in users if all(isinstance(u.get(k), str) and u[k].strip() for k in required)]


def storage_usage(username: str) -> tuple[str, int, int, float]:
    home = pwd.getpwnam(username).pw_dir
    used_output = subprocess.check_output(
        ["du", "-sB1", home], text=True, stderr=subprocess.DEVNULL
    )
    total_output = subprocess.check_output(
        ["df", "-B1", "--output=size", home], text=True
    )
    used = int(used_output.split()[0])
    total = int(total_output.splitlines()[-1].strip())
    if total <= 0:
        raise ValueError(f"invalid filesystem capacity for {home}: {total}")
    return home, used, total, used / total * 100


def human_bytes(value: int) -> str:
    amount = float(value)
    units = ("B", "KiB", "MiB", "GiB", "TiB", "PiB")
    for unit in units:
        if amount < 1024 or unit == units[-1]:
            return f"{amount:.1f} {unit}" if amount < 10 else f"{amount:.0f} {unit}"
        amount /= 1024
    raise AssertionError("unreachable")


def state_file(username: str) -> Path:
    default_dir = Path(__file__).resolve().parent / "user_storage_alert_state"
    state_dir = Path(os.environ.get("USER_STORAGE_STATE_DIR", default_dir))
    return state_dir / f"{username}.last"


def cooldown_hours() -> float:
    value = float(os.environ.get("USER_STORAGE_COOLDOWN_HOURS", "9"))
    if value < 0:
        raise ValueError("USER_STORAGE_COOLDOWN_HOURS must be zero or greater")
    return value


def in_cooldown(username: str, now: float | None = None) -> bool:
    path = state_file(username)
    try:
        last_sent = float(path.read_text(encoding="ascii").strip())
    except (FileNotFoundError, ValueError):
        return False
    current = time.time() if now is None else now
    return current - last_sent < cooldown_hours() * 3600


def mark_sent(username: str, now: float | None = None) -> None:
    path = state_file(username)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(str(time.time() if now is None else now), encoding="ascii")
    temporary.replace(path)


def message_body(user: dict[str, str], home: str, used: int, total: int,
                 percent: float, n: int, test: bool) -> str:
    title = "# [Urgent] Server Storage Cleanup Required"
    return (
        f"{title}\n\n"
        f"{user['username']} | {user['name']}\n\n"
        f"안녕하세요, {user['name']}님.\n\n"
        "서버 담당 정용훈입니다.\n\n"
        "서버 저장 공간 모니터링 중 사용량 안내가 필요해 메일드립니다.\n\n"
        "현재 사용 중인 홈 디렉터리의 용량이 공동 사용 기준에 도달한 상태입니다.\n\n"
        "## 사용량 상세\n\n"
        "| 항목 | 현재 값 |\n"
        "|---|---:|\n"
        f"| 계정명 | `{user['username']}` |\n"
        f"| 홈 디렉터리 | `{home}` |\n"
        f"| 계정 사용량 | {human_bytes(used)} |\n"
        f"| 파일시스템 전체 용량 | {human_bytes(total)} |\n"
        f"| 현재 점유율 | {percent:.2f}% |\n"
        f"| 알림 기준 | 100/{n} = {100 / n:.2f}% |\n\n"
        "## 요청 사항\n\n"
        "번거로우시겠지만, 당장 사용하지 않는 데이터는 **하드디스크**로 옮기거나 **정리** 부탁드립니다.\n\n"
        "삭제나 이동할 위치 또는 방법이 필요하시면 편하게 문의해 주세요.\n\n"
        "협조해 주셔서 감사합니다.\n"
    )


def send_email(recipient: str, subject: str, body: str) -> None:
    sender = os.environ.get("MAIL_FROM", "younghune135@gmail.com")
    msg = EmailMessage()
    msg["From"] = sender
    msg["To"] = recipient
    msg["Subject"] = subject
    msg.set_content(body)

    logo_path = Path(os.environ.get("LOGO_PATH", Path(__file__).with_name("dilab_logo.png")))
    logo_url = os.environ.get("LOGO_URL")
    mode = send_smtp.logo_mode()
    logo_src = logo_url
    logo_cid = None
    if not logo_src and mode == "data":
        logo_src = send_smtp.logo_data_uri(logo_path)
    elif not logo_src and mode == "cid" and logo_path.is_file():
        logo_cid = make_msgid(domain="server-monitoring.local")[1:-1]
        logo_src = f"cid:{logo_cid}"
    if os.environ.get("SMTP_HTML", "1").lower() not in {"0", "false", "no"}:
        msg.add_alternative(send_smtp.render_html_report(body, logo_src=logo_src), subtype="html")
        if logo_cid:
            msg.get_payload()[-1].add_related(
                logo_path.read_bytes(), maintype="image", subtype="png",
                cid=f"<{logo_cid}>", disposition="inline"
            )

    smtp_host = os.environ.get("SMTP_HOST")
    if smtp_host:
        port = int(os.environ.get("SMTP_PORT", "587"))
        with smtplib.SMTP(smtp_host, port, timeout=int(os.environ.get("SMTP_TIMEOUT", "30"))) as smtp:
            if os.environ.get("SMTP_TLS", "1").lower() not in {"0", "false", "no"}:
                smtp.starttls()
            if os.environ.get("SMTP_USER"):
                smtp.login(os.environ["SMTP_USER"], os.environ["SMTP_PASS"])
            smtp.send_message(msg)
        return

    sendmail = next((p for p in ("/usr/sbin/sendmail", "/usr/lib/sendmail") if Path(p).exists()), None)
    if not sendmail:
        raise RuntimeError("SMTP_HOST is unset and sendmail was not found")
    subprocess.run([sendmail, "-f", sender, "-t"], input=msg.as_bytes(), check=True)


def main() -> int:
    args = parse_args()
    users = eligible_users(load_users(args.config))
    if not users:
        print("No users have all of name, email, and username.", file=sys.stderr)
        return 1

    threshold = 100 / len(users)
    print(f"Eligible users: {len(users)}; threshold: {threshold:.2f}%")
    alerts = []
    for user in users:
        try:
            result = storage_usage(user["username"])
        except (KeyError, subprocess.CalledProcessError, ValueError) as exc:
            print(f"SKIP {user['username']}: {exc}", file=sys.stderr)
            continue
        home, used, total, percent = result
        print(f"{user['username']:<12} {human_bytes(used):>10} / {human_bytes(total):>10}  {percent:6.2f}%")
        if percent >= threshold:
            alerts.append((user, result))

    if args.test:
        # A test always produces exactly one preview, and can never address a real user.
        sample_user = next((u for u in users if u["email"] == TEST_RECIPIENT), users[0])
        sample = next((item for item in alerts if item[0] == sample_user), None)
        if sample is None:
            try:
                sample = (sample_user, storage_usage(sample_user["username"]))
            except (KeyError, subprocess.CalledProcessError, ValueError) as exc:
                print(f"Cannot create test preview: {exc}", file=sys.stderr)
                return 1
        user, (home, used, total, percent) = sample
        body = message_body(user, home, used, total, percent, len(users), True)
        print(f"\nTEST recipient (forced): {TEST_RECIPIENT}\n\n{body}")
        if not args.no_send:
            send_email(TEST_RECIPIENT, "[Urgent] Server Storage Cleanup Required", body)
        return 0

    for user, (home, used, total, percent) in alerts:
        if not args.force and in_cooldown(user["username"]):
            print(f"COOLDOWN {user['username']}: already notified within {cooldown_hours():g} hours")
            continue
        body = message_body(user, home, used, total, percent, len(users), False)
        print(f"ALERT {user['username']} -> {user['email']}")
        if not args.no_send:
            send_email(user["email"], "[Urgent] Server Storage Cleanup Required", body)
            mark_sent(user["username"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
