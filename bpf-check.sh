#!/usr/bin/env bash
# shellcheck enable=all
#
# BPFDoor-like Suspicious Process Detector

set -euo pipefail

# Check for root permission
if [[ "${EUID}" -ne 0 ]]; then
  printf '[!] This script must be run as root.\n' >&2
  exit 1
fi

# Check required commands
for cmd in ps grep readlink ss; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf '[!] %s command is required. Please install it first.\n' "${cmd}" >&2
    exit 1
  fi
done

printf '[*] Starting focused BPFDoor-like process detection...\n'

found=0
shopt -s nullglob

# Iterate over all PIDs without parsing ls output.
for proc_dir in /proc/[0-9]*; do
  pid="${proc_dir#/proc/}"
  exe_path="$(readlink "${proc_dir}/exe" 2>/dev/null || true)"

  [[ "${exe_path}" == *"(deleted)" ]] || continue

  packet="${proc_dir}/net/packet"
  [[ -r "${packet}" && -s "${packet}" ]] || continue

  cmdline="$(ps -p "${pid}" -o cmd= 2>/dev/null || true)"
  if [[ "${cmdline}" =~ tcpdump|wireshark|dhclient ]]; then
    continue
  fi

  printf '[!] Suspicious process detected:\n'
  printf '    - PID: %s\n' "${pid}"
  printf '    - Command: %s\n' "${cmdline}"
  printf '    - Deleted executable: %s\n' "${exe_path}"
  printf '    - BPF socket is active\n'

  ss -p -n 2>/dev/null | grep -F "pid=${pid}," | awk '{ print "    - Network: " $0 }' || true
  printf '\n'

  found=1
done

if (( found == 0 )); then
  printf '[*] No suspicious processes found.\n'
fi

printf '[*] Detection completed.\n'
