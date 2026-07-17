#!/usr/bin/env bash
set -euo pipefail

AUTO_INSTALL=0

usage() {
  cat <<USAGE
Usage: $0 [--install]

Checks runtime dependencies for server_monitoring.

Options:
  --install   Install missing Ubuntu packages with apt.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      AUTO_INSTALL=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
else
  ID="unknown"
fi

if [[ "${ID:-unknown}" != "ubuntu" && "$AUTO_INSTALL" -eq 1 ]]; then
  printf 'Automatic install is supported only on Ubuntu. Detected: %s\n' "${ID:-unknown}" >&2
  exit 1
fi

declare -A PACKAGE_FOR_CMD=(
  [awk]=mawk
  [bash]=bash
  [crontab]=cron
  [cut]=coreutils
  [date]=coreutils
  [df]=coreutils
  [du]=coreutils
  [free]=procps
  [flock]=util-linux
  [grep]=grep
  [head]=coreutils
  [hostname]=hostname
  [mktemp]=coreutils
  [nproc]=coreutils
  [ps]=procps
  [python3]=python3
  [sed]=sed
  [sort]=coreutils
  [systemctl]=systemd
  [tail]=coreutils
  [tr]=coreutils
  [uptime]=procps
  [who]=coreutils
)

REQUIRED_COMMANDS=(
  awk
  bash
  crontab
  cut
  date
  df
  du
  free
  flock
  grep
  head
  hostname
  mktemp
  nproc
  ps
  python3
  sed
  sort
  systemctl
  tail
  tr
  uptime
  who
)

OPTIONAL_COMMANDS=(
  nvidia-smi
)

missing_packages=()
missing_commands=()

printf 'Checking required commands...\n'
for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  OK      %s\n' "$cmd"
  else
    printf '  MISSING %s\n' "$cmd"
    missing_commands+=("$cmd")
    missing_packages+=("${PACKAGE_FOR_CMD[$cmd]}")
  fi
done

printf '\nChecking optional commands...\n'
for cmd in "${OPTIONAL_COMMANDS[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  OK      %s\n' "$cmd"
  else
    printf '  SKIP    %s (GPU section will degrade gracefully)\n' "$cmd"
  fi
done

printf '\nChecking Python standard-library imports...\n'
python3 - <<'PY'
import argparse
import email.message
import html
import os
import re
import smtplib
import sys

print(f"  OK      python {sys.version.split()[0]}")
print("  OK      argparse email html os re smtplib")
PY

if [[ "${#missing_commands[@]}" -eq 0 ]]; then
  printf '\nAll required dependencies are available.\n'
  exit 0
fi

printf '\nMissing required commands: %s\n' "${missing_commands[*]}"

if [[ "$AUTO_INSTALL" -ne 1 ]]; then
  printf 'Run with --install to install missing Ubuntu packages.\n'
  exit 1
fi

printf '\nInstalling missing packages...\n'
mapfile -t unique_packages < <(printf '%s\n' "${missing_packages[@]}" | sort -u)

if [[ "${#unique_packages[@]}" -eq 0 ]]; then
  printf 'No package mapping found for missing commands.\n' >&2
  exit 1
fi

apt update
DEBIAN_FRONTEND=noninteractive apt install -y "${unique_packages[@]}"

printf '\nRe-running dependency check...\n'
exec "$0"
