#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/.env}"

load_config() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi

  MAIL_TO="${MAIL_TO:-younghune135@gmail.com,younghune135@unist.ac.kr}"
  MAIL_FROM="${MAIL_FROM:-younghune135@gmail.com}"
  ALERT_THRESHOLD="${ALERT_THRESHOLD:-70}"
  ALERT_CRITICAL_THRESHOLD="${ALERT_CRITICAL_THRESHOLD:-90}"
  ALERT_COOLDOWN_HOURS="${ALERT_COOLDOWN_HOURS:-12}"
  ALERT_STATE_DIR="${ALERT_STATE_DIR:-${SCRIPT_DIR}/alert_state}"
  SMTP_HTML="${SMTP_HTML:-1}"

  HOST_SHORT="$(hostname -s 2>/dev/null || hostname)"
  HOSTNAME_FQDN="$(hostname -f 2>/dev/null || true)"
  if [[ -z "$HOSTNAME_FQDN" ]]; then
    HOSTNAME_FQDN="${HOST_SHORT}.localdomain"
  elif [[ "$HOSTNAME_FQDN" != *.* ]]; then
    HOSTNAME_FQDN="${HOSTNAME_FQDN}.localdomain"
  fi

  case "$HOST_SHORT" in
    dilab-sc|dilab-sc-01) HOST_DISPLAY_NAME="TIGER" ;;
    dilab-sc2|dilab-sc-02) HOST_DISPLAY_NAME="NEXT" ;;
    oem-MD72-HB3-00) HOST_DISPLAY_NAME="POSEIDON H" ;;
    oem-MD72-HB1-000) HOST_DISPLAY_NAME="POSEIDON B" ;;
    *) HOST_DISPLAY_NAME="$HOST_SHORT" ;;
  esac
}

now_string() {
  date '+%Y-%m-%d %H:%M:%S %Z'
}

percent_number() {
  printf '%s' "$1" | tr -d '%'
}

status_for_percent() {
  awk -v pct="$(percent_number "$1")" -v warn="$ALERT_THRESHOLD" -v crit="$ALERT_CRITICAL_THRESHOLD" 'BEGIN {
    if (pct >= crit) print "CRITICAL";
    else if (pct >= warn) print "WARNING";
    else print "OK";
  }'
}

resource_bar() {
  awk -v pct="$(percent_number "$1")" 'BEGIN {
    filled = int((pct / 5) + 0.5);
    if (filled < 0) filled = 0;
    if (filled > 20) filled = 20;
    printf "[";
    for (i = 1; i <= 20; i++) printf "%s", i <= filled ? "#" : "-";
    printf "]";
  }'
}

metric_bar_line() {
  local label="$1"
  local pct="$2"

  printf '%-14s %s %6s\n' "$label" "$(resource_bar "$pct")" "$pct"
}

cpu_usage_percent() {
  local a b idle_a total_a idle_b total_b diff_idle diff_total
  a="$(grep '^cpu ' /proc/stat)"
  sleep 1
  b="$(grep '^cpu ' /proc/stat)"

  read -r _ user nice system idle iowait irq softirq steal guest guest_nice <<< "$a"
  idle_a=$((idle + iowait))
  total_a=$((user + nice + system + idle + iowait + irq + softirq + steal + guest + guest_nice))

  read -r _ user nice system idle iowait irq softirq steal guest guest_nice <<< "$b"
  idle_b=$((idle + iowait))
  total_b=$((user + nice + system + idle + iowait + irq + softirq + steal + guest + guest_nice))

  diff_idle=$((idle_b - idle_a))
  diff_total=$((total_b - total_a))

  if [[ "$diff_total" -le 0 ]]; then
    printf 'N/A\n'
  else
    awk -v idle="$diff_idle" -v total="$diff_total" 'BEGIN { printf "%.1f%%\n", (1 - idle / total) * 100 }'
  fi
}

memory_used_percent() {
  if [[ -n "${FORCE_MEMORY_PCT:-}" ]]; then
    printf '%s\n' "$FORCE_MEMORY_PCT"
    return 0
  fi
  free -b | awk '/^Mem:/ { printf "%.1f%%\n", ($3 / $2) * 100 }'
}

total_storage_used_percent() {
  if [[ -n "${FORCE_TOTAL_STORAGE_PCT:-}" ]]; then
    printf '%s\n' "$FORCE_TOTAL_STORAGE_PCT"
    return 0
  fi
  df -B1 -x tmpfs -x devtmpfs -x squashfs --total | awk '$1 == "total" { printf "%.1f%%\n", ($3 / $2) * 100 }'
}

home_storage_used_percent() {
  if [[ -n "${FORCE_HOME_STORAGE_PCT:-}" ]]; then
    printf '%s\n' "$FORCE_HOME_STORAGE_PCT"
    return 0
  fi
  df -B1 /home 2>/dev/null | awk '$NF == "/home" { printf "%.1f%%\n", ($3 / $2) * 100 }'
}

quick_read_row() {
  local metric="$1"
  local value="$2"
  local status="$3"

  printf '| %s | %s | %s |\n' "$metric" "$value" "$status"
}

failed_services_count() {
  systemctl --failed --no-pager 2>/dev/null | awk '/loaded units listed/ {print $1}' || printf 'N/A'
}

gpu_quick_read() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    quick_read_row "GPU" "nvidia-smi not found" "WARNING"
    return 0
  fi

  nvidia-smi --query-gpu=index,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | awk -F', ' -v warn="$ALERT_THRESHOLD" -v crit="$ALERT_CRITICAL_THRESHOLD" '
    {
      status = $2 >= crit ? "CRITICAL" : ($2 >= warn ? "WARNING" : "OK")
      printf "| GPU %s utilization | %s%% | %s |\n", $1, $2, status
    }' || quick_read_row "GPU" "nvidia-smi failed" "WARNING"
}

gpu_bar_lines() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    printf '%-14s %s\n' 'GPU' 'nvidia-smi not found'
    return 0
  fi

  nvidia-smi --query-gpu=index,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | awk -F', ' '
    function bar(pct) {
      filled = int((pct / 5) + 0.5)
      if (filled < 0) filled = 0
      if (filled > 20) filled = 20
      out = "["
      for (i = 1; i <= 20; i++) out = out (i <= filled ? "#" : "-")
      return out "]"
    }
    {
      printf "%-14s %s %6.1f%%\n", "GPU " $1, bar($2), $2
    }' || printf '%-14s %s\n' 'GPU' 'nvidia-smi failed'
}

memory_capacity_table() {
  free -h | awk '
    /^Mem:/ { mem_total=$2; mem_used=$3; mem_free=$4; mem_cache=$6; mem_avail=$7 }
    /^Swap:/ { swap_total=$2; swap_used=$3; swap_free=$4 }
    END {
      print "| Resource | Total | Used | Free | Buff/Cache | Available |"
      print "|---|---:|---:|---:|---:|---:|"
      printf "| Memory | %s | %s | %s | %s | %s |\n", mem_total, mem_used, mem_free, mem_cache, mem_avail
      printf "| Swap | %s | %s | %s | - | - |\n", swap_total, swap_used, swap_free
    }'
}

storage_table() {
  df -h -x tmpfs -x devtmpfs -x squashfs | awk '
    BEGIN {
      print "| Mount | Size | Used | Available | Use |"
      print "|---|---:|---:|---:|---:|"
    }
    NR > 1 {
      printf "| `%s` | %s | %s | %s | %s |\n", $NF, $2, $3, $4, $5
    }'
}

home_user_storage_usage() {
  local home_total home_size

  if [[ ! -d /home ]]; then
    printf '```text\n/home does not exist.\n```\n'
    return 0
  fi

  home_total="$(df -B1 --output=size /home | tail -n 1 | tr -d ' ')"
  home_size="$(df -h --output=size /home | tail -n 1 | tr -d ' ')"
  printf '```text\n'
  printf '/home capacity: %s\n\n' "$home_size"
  if [[ "$(id -u)" -ne 0 ]]; then
    printf 'WARNING: running as non-root; directories owned by other users may be undercounted.\n'
    printf 'Run the script with sudo or install cron as root for accurate /home usage.\n\n'
  fi
  du -sB1 /home/* 2>/dev/null | sort -nr | while read -r bytes path; do
    awk -v bytes="$bytes" -v total="$home_total" -v path="$path" '
      function bar(pct) {
        filled = int((pct / 5) + 0.5)
        if (filled < 0) filled = 0
        if (filled > 20) filled = 20
        out = "["
        for (i = 1; i <= 20; i++) out = out (i <= filled ? "#" : "-")
        return out "]"
      }
      function human(n) {
        split("B KiB MiB GiB TiB PiB", unit, " ")
        i = 1
        while (n >= 1024 && i < 6) {
          n /= 1024
          i++
        }
        if (n >= 10 || i == 1) {
          return sprintf("%.0f%s", n, unit[i])
        }
        return sprintf("%.1f%s", n, unit[i])
      }
      BEGIN {
        pct = total > 0 ? (bytes / total) * 100 : 0
        user = path
        sub("^/home/", "", user)
        printf "%-10s %-8s %6.2f%%  %s\n", user, human(bytes), pct, bar(pct)
      }'
  done
  printf '```\n'
}

gpu_detail_table() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    printf 'nvidia-smi not found.\n'
    return 0
  fi

  if ! nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit \
      --format=csv,noheader,nounits 2>/dev/null | awk -F', ' '
      BEGIN {
        print "| GPU | Model | Util | Memory | Temp | Power |"
        print "|---:|---|---:|---:|---:|---:|"
      }
      {
        printf "| %s | %s | %s%% | %s / %s MiB | %sC | %s / %s W |\n", $1, $2, $3, $4, $5, $6, $7, $8
      }'; then
    printf 'nvidia-smi failed.\n'
  fi
}

gpu_processes_block() {
  printf '```text\n'
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    printf 'nvidia-smi not found.\n'
  elif ! nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_memory --format=csv 2>/dev/null; then
    printf 'No active GPU processes or nvidia-smi failed.\n'
  fi
  printf '```\n'
}

logged_in_users_block() {
  printf '```text\n'
  who || true
  printf '```\n'
}

failed_units_block() {
  printf '```text\n'
  systemctl --failed --no-pager 2>/dev/null || true
  printf '```\n'
}

write_snapshot_report() {
  local output_file="$1"
  local cpu_sample memory_pct total_storage_pct home_storage_pct failed_count
  local now

  now="$(now_string)"
  cpu_sample="$(cpu_usage_percent)"
  memory_pct="$(memory_used_percent)"
  total_storage_pct="$(total_storage_used_percent)"
  home_storage_pct="$(home_storage_used_percent)"
  failed_count="$(failed_services_count)"

  : > "$output_file"
  {
    printf '# %s Server Snapshot\n\n' "$HOST_DISPLAY_NAME"
    printf '`%s` | `%s`\n\n' "$now" "$(uptime -p 2>/dev/null || uptime)"

    printf '\n## Resource Bars\n\n'
    printf '```text\n'
    metric_bar_line "CPU" "$cpu_sample"
    metric_bar_line "Memory" "$memory_pct"
    metric_bar_line "Total storage" "$total_storage_pct"
    metric_bar_line "Home storage" "${home_storage_pct:-0%}"
    gpu_bar_lines
    printf '```\n\n'

    printf '## Memory\n\n'
    memory_capacity_table

    printf '\n## Storage\n\n'
    storage_table

    printf '\n## Home Directory Usage\n\n'
    home_user_storage_usage

    printf '\n## GPU Detail\n\n'
    gpu_detail_table

    printf '\n## Active GPU Jobs\n\n'
    gpu_processes_block

    printf '\n## System\n\n'
    printf '```text\n'
    printf 'Host:          %s\n' "$HOSTNAME_FQDN"
    printf 'Kernel:        %s\n' "$(uname -srmo)"
    printf 'CPU cores:     %s\n' "$(nproc 2>/dev/null || printf 'N/A')"
    printf 'Load average:  %s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"
    printf 'CPU usage:     %s\n' "$cpu_sample"
    printf '```\n\n'

    printf '## Logged-In Users\n\n'
    logged_in_users_block

    printf '\n## Recent Failed Systemd Units\n\n'
    failed_units_block

    printf '\n## Quick Read\n\n'
    printf '| Metric | Value | Status |\n'
    printf '|---|---:|---|\n'
    quick_read_row "CPU usage" "$cpu_sample" "$(status_for_percent "$cpu_sample")"
    quick_read_row "Memory usage" "$memory_pct" "$(status_for_percent "$memory_pct")"
    quick_read_row "Total storage usage" "$total_storage_pct" "$(status_for_percent "$total_storage_pct")"
    quick_read_row "Home storage usage" "${home_storage_pct:-N/A}" "$(status_for_percent "${home_storage_pct:-0%}")"
    gpu_quick_read
    quick_read_row "Failed services" "$failed_count" "OK"
  } >> "$output_file"
}

alert_target_action() {
  case "$1" in
    memory) printf 'Check high-memory workloads; stop unnecessary processes if needed' ;;
    total_storage) printf 'Clean up unused files on mounted filesystems; archive old outputs if needed' ;;
    home_storage) printf 'Clean up large files under `/home`; archive or remove old experiment outputs' ;;
    *) printf 'Inspect the resource and reduce usage if needed' ;;
  esac
}

alert_target_label() {
  case "$1" in
    memory) printf 'Memory usage' ;;
    total_storage) printf 'Total storage usage' ;;
    home_storage) printf 'Home storage usage' ;;
    *) printf '%s' "$1" ;;
  esac
}

write_alert_report() {
  local output_file="$1"
  shift
  local targets=("$@")
  local cpu_sample memory_pct total_storage_pct home_storage_pct failed_count now target value status threshold

  now="$(now_string)"
  cpu_sample="$(cpu_usage_percent)"
  memory_pct="$(memory_used_percent)"
  total_storage_pct="$(total_storage_used_percent)"
  home_storage_pct="$(home_storage_used_percent)"
  failed_count="$(failed_services_count)"

  : > "$output_file"
  {
    printf '# Urgent Server Attention Required\n\n'
    printf '`%s` | `%s`\n\n' "$HOSTNAME_FQDN" "$now"

    printf '## Warning Targets\n\n'
    printf 'Immediate attention required: memory or storage usage has exceeded the %s%% warning threshold.  \n' "$ALERT_THRESHOLD"
    printf 'Review the high-usage targets first, then clean up unnecessary files or inspect running workloads as needed.\n\n'

    printf '| Priority | Target | Current | Threshold | Status | Recommended Action |\n'
    printf '|---:|---|---:|---:|---|---|\n'
    local priority=1
    for target in "${targets[@]}"; do
      case "$target" in
        memory) value="$memory_pct" ;;
        total_storage) value="$total_storage_pct" ;;
        home_storage) value="$home_storage_pct" ;;
        *) value="0%" ;;
      esac
      status="$(status_for_percent "$value")"
      threshold="${ALERT_THRESHOLD}% warning"
      if [[ "$status" == "CRITICAL" ]]; then
        threshold="${ALERT_CRITICAL_THRESHOLD}% critical"
      fi
      printf '| %s | %s | %s | %s | %s | %s |\n' "$priority" "$(alert_target_label "$target")" "$value" "$threshold" "$status" "$(alert_target_action "$target")"
      priority=$((priority + 1))
    done

    printf '\n## Critical Resource Bars\n\n'
    printf '```text\n'
    for target in "${targets[@]}"; do
      case "$target" in
        memory) metric_bar_line "Memory" "$memory_pct" ;;
        total_storage) metric_bar_line "Total storage" "$total_storage_pct" ;;
        home_storage) metric_bar_line "Home storage" "$home_storage_pct" ;;
      esac
    done
    printf '```\n\n'

    printf '## Snapshot\n\n'
    printf '| Metric | Value | Status |\n'
    printf '|---|---:|---|\n'
    quick_read_row "CPU usage" "$cpu_sample" "$(status_for_percent "$cpu_sample")"
    quick_read_row "Memory usage" "$memory_pct" "$(status_for_percent "$memory_pct")"
    quick_read_row "Total storage usage" "$total_storage_pct" "$(status_for_percent "$total_storage_pct")"
    quick_read_row "Home storage usage" "${home_storage_pct:-N/A}" "$(status_for_percent "${home_storage_pct:-0%}")"
    gpu_quick_read
    quick_read_row "Failed services" "$failed_count" "OK"

    printf '\n## Storage Detail\n\n'
    storage_table

    printf '\n## Home Directory Usage\n\n'
    home_user_storage_usage

    printf '\n## Memory Detail\n\n'
    memory_capacity_table

    printf '\n## System Snapshot\n\n'
    printf '```text\n'
    printf 'Host:          %s\n' "$HOSTNAME_FQDN"
    printf 'Kernel:        %s\n' "$(uname -srmo)"
    printf 'CPU cores:     %s\n' "$(nproc 2>/dev/null || printf 'N/A')"
    printf 'Load average:  %s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"
    printf 'CPU usage:     %s\n' "$cpu_sample"
    printf 'Uptime:        %s\n' "$(uptime -p 2>/dev/null || uptime)"
    printf '```\n\n'

    printf '## GPU Detail\n\n'
    gpu_detail_table
  } >> "$output_file"
}

send_report_file() {
  local report_file="$1"
  local subject="$2"

  if [[ -n "${SMTP_HOST:-}" ]]; then
    python3 "${SCRIPT_DIR}/send_smtp.py" \
      --from "$MAIL_FROM" \
      --to "$MAIL_TO" \
      --subject "$subject" \
      --body-file "$report_file"
  elif [[ "$MAIL_TO" == *@gmail.com* || "$MAIL_FROM" == *@gmail.com ]]; then
    printf 'Gmail delivery requires authenticated SMTP.\n' >&2
    printf 'Set SMTP_HOST=smtp.gmail.com, SMTP_USER, and SMTP_PASS in %s.\n' "$ENV_FILE" >&2
    printf 'Report was saved to %s\n' "$report_file" >&2
    return 1
  elif command -v sendmail >/dev/null 2>&1; then
    {
      printf 'From: %s\n' "$MAIL_FROM"
      printf 'To: %s\n' "$MAIL_TO"
      printf 'Subject: %s\n' "$subject"
      printf 'Content-Type: text/plain; charset=UTF-8\n'
      printf '\n'
      cat "$report_file"
    } | sendmail -f "$MAIL_FROM" -t
  elif command -v mail >/dev/null 2>&1; then
    mail -s "$subject" "$MAIL_TO" < "$report_file"
  elif command -v mailx >/dev/null 2>&1; then
    mailx -s "$subject" "$MAIL_TO" < "$report_file"
  elif command -v msmtp >/dev/null 2>&1; then
    {
      printf 'From: %s\n' "$MAIL_FROM"
      printf 'To: %s\n' "$MAIL_TO"
      printf 'Subject: %s\n' "$subject"
      printf 'Content-Type: text/plain; charset=UTF-8\n'
      printf '\n'
      cat "$report_file"
    } | msmtp "$MAIL_TO"
  else
    printf 'No mail sender found. Install mailutils/msmtp/sendmail, or set SMTP_HOST/SMTP_USER/SMTP_PASS.\n' >&2
    printf 'Report was saved to %s\n' "$report_file" >&2
    return 1
  fi
}

is_percent_at_least() {
  awk -v pct="$(percent_number "$1")" -v min="$2" 'BEGIN { exit !(pct >= min) }'
}

alert_state_file() {
  printf '%s/%s.last' "$ALERT_STATE_DIR" "$1"
}

alert_is_in_cooldown() {
  local target="$1"
  local state_file now last cooldown_seconds

  state_file="$(alert_state_file "$target")"
  [[ -f "$state_file" ]] || return 1

  now="$(date +%s)"
  last="$(cat "$state_file" 2>/dev/null || printf '0')"
  cooldown_seconds=$((ALERT_COOLDOWN_HOURS * 3600))

  [[ $((now - last)) -lt "$cooldown_seconds" ]]
}

mark_alert_sent() {
  local target="$1"

  mkdir -p "$ALERT_STATE_DIR"
  date +%s > "$(alert_state_file "$target")"
}

install_cron_entries() {
  local cron_file
  cron_file="$(mktemp)"

  crontab -l 2>/dev/null \
    | grep -v 'server_monitoring/monitor.sh' \
    | grep -v 'server_monitoring/alert_check.sh' \
    | grep -v 'server_monitoring/user_storage_alert.sh' \
    > "$cron_file" || true
  {
    printf '0 9 * * 1 %s/monitor.sh >/tmp/server_monitoring_snapshot.log 2>&1\n' "$SCRIPT_DIR"
  } >> "$cron_file"
  crontab "$cron_file"
  rm -f "$cron_file"
}

load_config
