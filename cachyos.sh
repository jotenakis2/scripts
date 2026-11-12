#!/usr/bin/env bash
# shellcheck enable=all
#
# Définit le dernier noyau CachyOS comme noyau GRUB par défaut.
# Réservé à Fedora/CachyOS : utilise grubby et une entrée GRUB.

set -euo pipefail

if [[ ! -r /etc/fedora-release ]]; then
  printf 'Ce script est réservé à Fedora/CachyOS (GRUB + grubby).\n' >&2
  printf 'Il ne fonctionne pas sur Arch/Omarchy.\n' >&2
  exit 1
fi

if ! command -v grubby >/dev/null 2>&1; then
  printf 'grubby est introuvable : ce script nécessite Fedora/CachyOS avec GRUB.\n' >&2
  exit 1
fi

linux=''
while IFS= read -r -d '' candidate; do
  linux="${candidate}"
done < <(find /boot -maxdepth 1 -type f -name 'vmlinuz*cachy*' -print0 2>/dev/null | sort -z -V || true)

if [[ -z "${linux}" ]]; then
  printf 'Aucun noyau CachyOS détecté dans /boot.\n'
  exit 0
fi

printf 'Noyau CachyOS : %s\n' "${linux}"

if [[ "${EUID}" -eq 0 ]]; then
  grubby --set-default="${linux}"
else
  sudo grubby --set-default="${linux}"
fi
