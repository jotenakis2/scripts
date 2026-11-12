#!/usr/bin/env bash
# shellcheck enable=all
#
# Suppression interactive d'anciens noyaux de /boot.
# - Fedora : utilise dnf quand les paquets kernel-* existent.
# - Arch   : supprime uniquement les fichiers de /boot non possédés par un paquet.
# Le noyau courant et les entrées "rescue" sont toujours protégés.

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    printf 'Ce script doit être exécuté en root.\n' >&2
    exit 1
fi

BOOT_DIR='/boot'
if [[ ! -d "${BOOT_DIR}" ]]; then
    printf 'Répertoire %s introuvable.\n' "${BOOT_DIR}" >&2
    exit 1
fi

current_kernel="$(uname -r)"
readonly current_kernel

mapfile -t kernels < <(
    find "${BOOT_DIR}" -maxdepth 1 -type f -name 'vmlinuz-*' -printf '%f\n' \
        | sed -E 's/^vmlinuz-//' \
        | sort -V || true
)

if [[ ${#kernels[@]} -eq 0 ]]; then
    printf 'Aucun kernel trouvé dans %s.\n' "${BOOT_DIR}"
    exit 0
fi

printf 'Kernels trouvés dans %s :\n' "${BOOT_DIR}"
printf '%s\n' "${kernels[@]}"
printf '🔒 en cours d'\''utilisation : %s\n\n' "${current_kernel}"

remove_boot_files() {
    local kernel="${1}"
    find "${BOOT_DIR}" -maxdepth 1 -type f \( \
        -name "vmlinuz-${kernel}" -o \
        -name "initramfs-${kernel}*.img" -o \
        -name "initrd-${kernel}*.img" -o \
        -name "System.map-${kernel}" -o \
        -name "config-${kernel}" \
    \) -exec rm -v {} +
}

package_owner() {
    local kernel="${1}"
    pacman -Qo "${BOOT_DIR}/vmlinuz-${kernel}" 2>/dev/null \
        | sed -n 's/.* is owned by \([^ ]*\) .*/\1/p' || true
}

for kernel in "${kernels[@]}"; do
    if [[ "${kernel}" == "${current_kernel}" ]] || [[ "${kernel}" == *rescue* ]]; then
        printf '🔒 Protégé : %s\n\n' "${kernel}"
        continue
    fi

    response=''
    read -rp "Supprimer le kernel ${kernel} ? [Y/N] : " response || {
        printf '\nEntrée terminée, arrêt.\n'
        break
    }

    case "${response}" in
        [Yy]*)
            if command -v dnf >/dev/null 2>&1; then
                if [[ "${kernel}" == *cachyos* ]]; then
                    pkg_prefix='kernel-cachyos'
                else
                    pkg_prefix='kernel'
                fi

                if dnf remove -y \
                    "${pkg_prefix}-${kernel}" \
                    "${pkg_prefix}-core-${kernel}" \
                    "${pkg_prefix}-modules-${kernel}" \
                    "${pkg_prefix}-modules-extra-${kernel}" \
                    "${pkg_prefix}-devel-${kernel}" \
                    "${pkg_prefix}-devel-matched-${kernel}" \
                    2>/dev/null; then
                    printf '✓ %s supprimé avec succès.\n\n' "${kernel}"
                else
                    printf '⚠️  dnf n'\''a pas trouvé de paquet pour %s, suppression des fichiers de /boot...\n' "${kernel}"
                    remove_boot_files "${kernel}"
                    printf '\n'
                fi
            elif command -v pacman >/dev/null 2>&1; then
                owner="$(package_owner "${kernel}")"
                if [[ -n "${owner}" ]]; then
                    printf '⚠️  %s est géré par le paquet %s.\n' "${kernel}" "${owner}"
                    printf '    Suppression refusée : utilisez pacman -Rns %s si nécessaire.\n\n' "${owner}"
                else
                    printf 'Fichiers de /boot non possédés par un paquet : suppression...\n'
                    remove_boot_files "${kernel}"
                    printf '\n'
                fi
            else
                printf 'Ni dnf ni pacman détecté : suppression manuelle des fichiers de /boot...\n'
                remove_boot_files "${kernel}"
                printf '\n'
            fi
            ;;
        [Nn]*)
            printf '✓ Kernel %s conservé.\n\n' "${kernel}"
            ;;
        *)
            printf 'Réponse invalide, kernel %s conservé.\n\n' "${kernel}"
            ;;
    esac
done

printf '✅ Opération terminée.\n'
