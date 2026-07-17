[![한국어](https://img.shields.io/badge/README-한국어-2563eb)](README.md)

# Server Monitoring

A collection of scripts that monitors Ubuntu server resources and sends email reports.

It provides two types of automation:

1. Server-wide CPU, memory, GPU, and storage snapshots and threshold alerts
2. Per-user home-directory usage checks and storage cleanup notifications

## Main Files

| File | Description |
|---|---|
| `monitor.sh` | Sends a server-wide snapshot email |
| `alert_check.sh` | Checks memory and server-wide storage thresholds |
| `common.sh` | Shared configuration, metric collection, and email helpers |
| `send_smtp.py` | SMTP delivery and HTML email rendering |
| `install_cron.sh` | Installs server-wide monitoring cron jobs |
| `user_storage_alert.py` | Checks per-user home usage and sends cleanup notices |
| `user_storage_alert.sh` | Entry point that loads configuration and prevents overlapping runs |
| `users.json` | User names, email addresses, and Linux usernames |
| `install_user_storage_cron.sh` | Installs the per-user storage cron job |
| `save_storage_alert_test_report.sh` | Generates an HTML preview of the storage notice |
| `check_requirements.sh` | Checks Ubuntu runtime dependencies |
| `.env.example` | Example per-server configuration |

## Installation on Ubuntu

Clone the repository:

```bash
git clone https://github.com/hun9008/server_monitor.git
cd server_monitor
```

Create the per-server environment file. `.env` can contain SMTP credentials and must not be committed to Git.

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Example Gmail SMTP configuration:

```bash
MAIL_FROM=younghune135@gmail.com
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=younghune135@gmail.com
SMTP_PASS="Gmail app password"
SMTP_TLS=1
SMTP_HTML=1
LOGO_MODE=cid
```

Use a Gmail app password, not the regular password for the account.

Check required commands:

```bash
./check_requirements.sh
```

To install missing packages automatically on Ubuntu:

```bash
sudo ./check_requirements.sh --install
```

## Per-User Storage Alerts

### Configure Monitored Users

Only entries in `users.json` with all three fields are monitored:

- `name`: Name displayed in the email
- `email`: Notification recipient
- `username`: Linux account name on the server

Use `null`, rather than an empty string, when a value is unknown.

```json
{
  "name": "정용훈",
  "email": "younghune135@unist.ac.kr",
  "username": "hun"
}
```

If N entries contain all three values, the alert threshold is `100/N%`. There are currently four eligible users, so the threshold is 25%.

Usage is calculated by dividing the account's home-directory usage by the total capacity of the filesystem that contains that home directory.

```text
percentage = home directory usage / home filesystem capacity × 100
```

### Preview the HTML Email

Generate a sample HTML email without sending it:

```bash
./save_storage_alert_test_report.sh
```

Generated files:

```text
alert_storage_test.md
alert_storage_test.html
```

### Check Real Usage Without Sending

Run as root so the script can read every monitored home directory:

```bash
sudo ./user_storage_alert.sh --no-send
```

This command prints actual usage and percentages. It does not send email or update cooldown timestamps.

### Send a Test Email

```bash
sudo ./user_storage_alert.sh --test
```

Test mode generates one email regardless of the current threshold. Its recipient is hard-coded to the following address, so no other user can receive a test message:

```text
younghune135@unist.ac.kr
```

### Install the Production Cron Job

Install the cron job only after checking the preview, dry run, and test email:

```bash
sudo ./install_user_storage_cron.sh
sudo crontab -l
```

Installed entry:

```cron
0 * * * * /installation/path/user_storage_alert.sh >>/tmp/user_storage_alert.log 2>&1 # server_monitoring user_storage_alert
```

Cron runs once per hour. After a successful email, only that user enters a nine-hour cooldown. Other users are evaluated and notified independently.

Default settings:

```bash
USER_STORAGE_COOLDOWN_HOURS=9
USER_STORAGE_STATE_DIR=/installation/path/user_storage_alert_state
USER_STORAGE_LOCK_FILE=/tmp/user-storage-alert.lock
```

These values can be overridden in `.env`. A failed delivery does not update the cooldown, so the next cron run will retry it.

To ignore cooldown timestamps and immediately evaluate the production condition again, use `--force`. This can send email to real users who currently exceed the threshold.

```bash
sudo ./user_storage_alert.sh --force
```

View the cron log:

```bash
tail -n 100 /tmp/user_storage_alert.log
```

## Server-Wide Monitoring

Generate a snapshot preview:

```bash
sudo ./save_test_report.sh
```

Generate a threshold-alert preview:

```bash
sudo ./save_alert_test_report.sh
```

Install server-wide monitoring cron jobs:

```bash
sudo ./install_cron.sh
sudo crontab -l
```

Default schedule:

```cron
0 9 * * 1 /installation/path/monitor.sh >/tmp/server_monitoring_snapshot.log 2>&1
0 * * * * /installation/path/alert_check.sh >/tmp/server_monitoring_alert.log 2>&1
```

- Server snapshot: Monday at 09:00
- Memory and storage threshold check: every hour
- Default server-wide alert cooldown: 12 hours

Server-wide alert settings can be changed in `.env`:

```bash
ALERT_THRESHOLD=70
ALERT_CRITICAL_THRESHOLD=90
ALERT_COOLDOWN_HOURS=12
```

## Deployment Checklist for Another Ubuntu Server

Run these checks on each server before installing cron:

```bash
git clone https://github.com/hun9008/server_monitor.git
cd server_monitor

cp .env.example .env
chmod 600 .env
nano .env

./check_requirements.sh
getent passwd parkdw00 heek psm hun
python3 -m json.tool users.json >/dev/null
sudo ./user_storage_alert.sh --no-send
./save_storage_alert_test_report.sh
sudo ./user_storage_alert.sh --test
sudo ./install_user_storage_cron.sh
sudo crontab -l
```

Verify the following on every server:

- Every account in `users.json` exists on that server
- Each home directory is mounted on the intended filesystem
- Root can read every monitored home directory
- SMTP connectivity and the Gmail app password work
- The server timezone matches the intended cron schedule

## Tests

Run the unit tests:

```bash
python3 -m unittest -v test_user_storage_alert.py
```

Covered behavior:

- Only entries with a name, email, and username count toward N
- Home storage percentage calculation
- Fixed test recipient
- Per-user nine-hour cooldown

## Notes

- Per-user usage collection scans the full home directory with `du`, so it can take time on large datasets.
- If the previous check is still running when cron starts again, `flock` skips the overlapping run.
- A missing account or unreadable home directory is skipped individually and logged as `SKIP`.
- `nvidia-smi` is optional. Other monitoring features continue to work without an NVIDIA GPU.
- `LOGO_MODE=cid` provides the best Gmail and Outlook compatibility, although some clients may display the logo like an attachment.
- `LOGO_MODE=url` uses an external image URL without an attachment.
- `.env`, delivery state, and generated HTML previews are excluded from Git.
