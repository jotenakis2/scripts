#!/bin/bash
# shellcheck enable=all
#
# Verifie si le boost cpufreq d'apple-cpufreq est reellement utilisable et si
# power-profiles-daemon ne fait que basculer ce boost. A lancer en root.

set -euo pipefail

if (( EUID != 0 )); then
  printf 'Root requis : pkexec %s\n' "${BASH_SOURCE[0]}" >&2
  exit 1
fi

shopt -s nullglob
policies=(/sys/devices/system/cpu/cpufreq/policy*)
shopt -u nullglob

if (( ${#policies[@]} == 0 )); then
  printf 'Aucune politique cpufreq trouvee\n' >&2
  exit 1
fi

readonly BOOST=/sys/devices/system/cpu/cpufreq/boost
original_profile=$(powerprofilesctl get)
read -r ac_online < /sys/class/power_supply/macsmc-ac/online
read -r battery_status < /sys/class/power_supply/macsmc-battery/status

printf 'AC online : %s\n' "${ac_online}"
printf 'batterie  : %s\n' "${battery_status}"
printf 'profil    : %s\n' "${original_profile}"

# Le script modifie governors et profil : on les restaure même en cas d'erreur
# ou d'interruption, sinon la machine reste bloquée en performance.
restore() {
  local p
  for p in "${policies[@]}"; do
    printf 'schedutil\n' >"${p}/scaling_governor" 2>/dev/null || true
  done
  powerprofilesctl set "${original_profile}" >/dev/null 2>&1 || true
}
trap restore EXIT INT TERM

# Governor performance : il demande policy->max, contrairement a schedutil.
for p in "${policies[@]}"; do
  printf 'performance\n' > "${p}/scaling_governor"
done

for profile in performance power-saver; do
  powerprofilesctl set "${profile}" >/dev/null
  sleep 1
  read -r boost < "${BOOST}"
  printf '\nprofil=%-12s boost=%s\n' "${profile}" "${boost}"
  for p in "${policies[@]}"; do
    read -r cur < "${p}/scaling_cur_freq"
    read -r max < "${p}/scaling_max_freq"
    read -r min < "${p}/scaling_min_freq"
    printf '  %-8s cur=%-8s max=%-8s min=%-8s\n' \
      "$(basename "${p}")" "${cur}" "${max}" "${min}"
  done
done

# Restauration : faite par le trap (schedutil + profil d'origine).
printf '\nRestauration : governors=schedutil, profil=%s\n' "${original_profile}"
