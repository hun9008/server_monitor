# Server Monitoring

Server monitoring email scripts for Ubuntu servers.

## Files

| File | Purpose |
|---|---|
| `common.sh` | Shared config, metric collection, report generation, email helper, cron installer |
| `monitor.sh` | Weekly snapshot report entrypoint |
| `alert_check.sh` | Hourly memory/storage alert checker |
| `send_smtp.py` | SMTP sender and HTML email renderer |
| `save_test_report.sh` | Writes a snapshot preview to `test.md` |
| `save_alert_test_report.sh` | Writes an alert preview to `alert_test.md` |
| `install_cron.sh` | Installs cron entries for snapshot and alert automation |
| `.env.example` | Copy to `.env` and edit per server |

## Setup On Another Ubuntu Server

1. Copy this directory to the server:

```bash
scp -r server_monitoring user@server:/path/to/server_monitoring
```

2. Create `.env`:

```bash
cd /path/to/server_monitoring
cp .env.example .env
chmod 600 .env
```

3. Check dependencies:

```bash
./check_requirements.sh
```

If something is missing on Ubuntu:

```bash
./check_requirements.sh --install
```

4. Edit `.env` with SMTP credentials and recipients:

```bash
MAIL_TO=first@example.com,second@example.com
MAIL_FROM=younghune135@gmail.com
SMTP_HOST=smtp.gmail.com
SMTP_USER=younghune135@gmail.com
SMTP_PASS="gmail app password"
```

5. Test snapshot preview:

```bash
./save_test_report.sh
```

6. Test alert preview:

```bash
./save_alert_test_report.sh
```

7. Send a real snapshot email:

```bash
./monitor.sh
```

8. Install cron automation:

```bash
./install_cron.sh
```

## Automation

`install_cron.sh` installs:

```cron
0 9 * * 1 /path/to/server_monitoring/monitor.sh >/tmp/server_monitoring_snapshot.log 2>&1
0 * * * * /path/to/server_monitoring/alert_check.sh >/tmp/server_monitoring_alert.log 2>&1
```

Meaning:

- Snapshot email: every Monday at 09:00.
- Alert check: every hour.
- Alert cooldown: default 12 hours per target.

## Alert Rules

Alert targets:

- Memory usage
- Total storage usage
- `/home` storage usage

Defaults:

```bash
ALERT_THRESHOLD=70
ALERT_CRITICAL_THRESHOLD=90
ALERT_COOLDOWN_HOURS=12
```

If one or more targets exceed `ALERT_THRESHOLD`, `alert_check.sh` sends an urgent alert email unless all exceeded targets are still in cooldown.

## Manual Cron Registration

If you prefer manual cron editing:

```bash
crontab -e
```

Add:

```cron
0 9 * * 1 /path/to/server_monitoring/monitor.sh >/tmp/server_monitoring_snapshot.log 2>&1
0 * * * * /path/to/server_monitoring/alert_check.sh >/tmp/server_monitoring_alert.log 2>&1
```

## Notes

- `nvidia-smi` is optional. GPU sections degrade gracefully when NVIDIA tools are unavailable.
- Python 3 is required for SMTP/HTML email.
- Use a Gmail app password, not your normal Google account password.
