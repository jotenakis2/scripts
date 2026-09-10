#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo "Ce script doit être exécuté en root." >&2
    exit 1
fi

BOOT_DIR="/boot"
if ! [[ -d "${BOOT_DIR}" ]]; then
    echo "Répertoire ${BOOT_DIR} introuvable." >&2
    exit 1
fi

# VERROU : kernel actuellement en cours d'utilisation
current_kernel="$(uname -r)"
readonly current_kernel

# Extraire les versions de kernels depuis /boot
# shellcheck disable=SC2312
mapfile -t kernels < <(
    find "${BOOT_DIR}" -maxdepth 1 -type f -name 'vmlinuz-*' -printf '%f\n' \
        | sed -E 's/^vmlinuz-//' \
        | sort -V
)

if [[ ${#kernels[@]} -eq 0 ]]; then
    echo "Aucun kernel trouvé dans ${BOOT_DIR}."
    exit 0
fi

echo "Kernels trouvés dans ${BOOT_DIR} :"
printf '%s\n' "${kernels[@]}"
echo "🔒 en cours d'utilisation : ${current_kernel}"
echo

for k in "${kernels[@]}"; do
    # VERROU FORT : on saute immédiatement si c'est le kernel actuel ou le rescue
    if [[ "${k}" == "${current_kernel}" ]] || [[ "${k}" == *rescue* ]]; then
        echo "🔒 Protégé : ${k}"
        echo
        continue
    fi

    while true; do
        read -rp "Supprimer le kernel ${k} ? [Y/N] : " response
        case "${response}" in
            [Yy]* )
                echo "Suppression de ${k} via dnf..."
                
                # Déterminer le type de kernel (cachyos ou standard)
                if [[ "${k}" == *cachyos* ]]; then
                    pkg_prefix="kernel-cachyos"
                else
                    pkg_prefix="kernel"
                fi

                # Supprimer proprement avec dnf
                if dnf remove -y \
                    "${pkg_prefix}-${k}" \
                    "${pkg_prefix}-core-${k}" \
                    "${pkg_prefix}-modules-${k}" \
                    "${pkg_prefix}-modules-extra-${k}" \
                    "${pkg_prefix}-devel-${k}" \
                    "${pkg_prefix}-devel-matched-${k}" \
                    2>/dev/null; then
                    echo "✓ ${k} supprimé avec succès."
                    echo
                else
                    echo "⚠️  dnf n'a pas trouvé de paquet pour ${k}, suppression manuelle des fichiers..."
                    find "${BOOT_DIR}" -maxdepth 1 -type f \( \
                        -name "vmlinuz-${k}" -o \
                        -name "initramfs-${k}*.img" -o \
                        -name "initrd-${k}*.img" -o \
                        -name "System.map-${k}" -o \
                        -name "config-${k}" \
                    \) -exec rm -v {} \;
                    echo
                fi
                break
                ;;
            [Nn]* )
                echo "✓ Kernel ${k} conservé."
                echo
                break
                ;;
            * )
                echo "Réponse invalide. Veuillez répondre Y ou N."
                echo
                ;;
        esac
    done
done

echo "✅ Opération terminée."
