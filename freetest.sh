#!/usr/bin/env bash
# freetest.sh
# Compare les estimations de mémoire utilisée sous Linux :
#   1. htop (usedMem) : MemTotal - MemFree - Buffers - Cached - SReclaimable
#                       (champ usedMem de linux/LinuxMachine.c)
#   2. htop (barre)   : usedMem + Shmem, valeur affichée par la jauge Mem
#                       (la classe « shared » compte comme mémoire utilisée)
#   3. free           : MemTotal - MemAvailable (colonne « utilisé »)
#
# Cached contient déjà Shmem (mémoire partagée : tmpfs, SysV shm, memfd,
# mmap MAP_SHARED|MAP_ANONYMOUS…) : htop ne réintègre donc pas Shmem
# dans usedMem, il l'affiche comme classe « shared » séparée. Seule la jauge
# additionne usedMem et Shmem pour obtenir son total « utilisé ».
#
# Dépendances : awk, coreutils, util-linux (zramctl facultatif).

set -euo pipefail
IFS=$'\n\t'

readonly MEMINFO='/proc/meminfo'

if [[ ! -r "${MEMINFO}" ]]; then
    printf 'Erreur : %s illisible.\n' "${MEMINFO}" >&2
    exit 1
fi

# Lit /proc/meminfo.
# Sortie : htop_used_kib free_used_kib shmem_kib available_kib total_kib zswap_kib
#   htop_used_kib : usedMem d'htop (sans Shmem)
#   free_used_kib : « utilisé » de free (MemTotal - MemAvailable)
# Le code retour d'awk est ignoré : une lecture invalide est détectée via total_kib.
# shellcheck disable=SC2016
IFS=' ' read -r \
    htop_used_kib \
    free_used_kib \
    shmem_kib \
    available_kib \
    total_kib \
    zswap_kib < <(
        awk '
            $1 == "MemTotal:"     { total = $2 }
            $1 == "MemFree:"      { free = $2 }
            $1 == "MemAvailable:" { available = $2 }
            $1 == "Buffers:"      { buffers = $2 }
            $1 == "Cached:"       { cached = $2 }
            $1 == "SReclaimable:" { sreclaimable = $2 }
            $1 == "Shmem:"        { shmem = $2 }
            $1 == "Zswap:"        { zswap = $2 }

            END {
                if (total == "" || free == "") {
                    print "0 0 0 0 0 0"
                    exit 1
                }

                # Méthode htop, champ usedMem de linux/LinuxMachine.c :
                #   usedMem = MemTotal - (MemFree + Cached + SReclaimable + Buffers)
                # Cached inclut déjà Shmem : htop ne le rajoute pas ici.
                # Comme htop, si la somme dépasse MemTotal, on retombe sur
                #   usedMem = MemTotal - MemFree.
                used_diff = free + cached + sreclaimable + buffers
                if (total >= used_diff) {
                    htop_used = total - used_diff
                } else {
                    htop_used = total - free
                }

                # Méthode free, colonne « utilisé » de free(1) :
                #   utilisé = MemTotal - MemAvailable
                # MemAvailable existe depuis Linux 3.14. En son absence, htop
                # retombe sur MemFree (reproduit ici) ; free(1) estime alors
                # la valeur, cas non reproduit ici.
                if (available == "") {
                    free_used = total - free
                } else {
                    free_used = total - available
                }

                printf "%d %d %d %d %d %d\n",
                    htop_used,
                    free_used,
                    shmem,
                    available,
                    total,
                    zswap
            }
        ' "${MEMINFO}" || true
    )

if (( total_kib == 0 )); then
    printf 'Erreur : valeurs mémoire invalides dans %s.\n' "${MEMINFO}" >&2
    exit 1
fi

# Somme la RAM physique réellement occupée par tous les périphériques zram.
zram_kib=0
if command -v zramctl >/dev/null 2>&1; then
    zram_kib=$(
        zramctl \
            --bytes \
            --noheadings \
            --output TOTAL \
            2>/dev/null \
        | awk '{ sum += $1 } END { printf "%d", sum / 1024 }'
    )

    if [[ ! "${zram_kib}" =~ ^[0-9]+$ ]]; then
        zram_kib=0
    fi
fi


# Conversion KiB -> MiB avec une décimale, sans dépendre de bc.
format_mib() {
    local kib=${1}
    awk -v kib="${kib}" 'BEGIN { printf "%.1f", kib / 1024 }'
}

# printf compte les octets et non les caractères : ces deux aides calculent
# elles-mêmes le remplissage à partir de la longueur en caractères pour que
# les libellés accentués restent alignés en colonnes.
#
# Affiche "libellé : valeur MiB", libellé aligné sur 40 caractères.
# Un 3e argument "dim" atténue la ligne (SGR 2) si la sortie est un terminal.
mem_info() {
    local label=${1}
    local value=${2}
    local style=${3:-}
    local start=''
    local end=''
    if [[ ${style} == 'dim' && -t 1 ]]; then
        start=$'\e[2m'
        end=$'\e[0m'
    fi
    printf '%s%s%*s : %10s MiB%s\n' \
        "${start}" "${label}" "$(( 40 - ${#label} ))" '' "${value}" "${end}"
}

# Affiche une ligne du tableau de synthèse (libellé + valeur, suffixe facultatif).
mem_table_row() {
    local label=${1}
    local value=${2}
    local suffix=${3:-}
    printf '%s%*s %*s%s\n' \
        "${label}" "$(( 64 - ${#label} ))" '' \
        "$(( 16 - ${#value} - ${#suffix} ))" '' "${value}${suffix}"
}

total_mib=$(format_mib "${total_kib}")
available_mib=$(format_mib "${available_kib}")
shmem_mib=$(format_mib "${shmem_kib}")
zram_mib=$(format_mib "${zram_kib}")
zswap_mib=$(format_mib "${zswap_kib}")

htop_used_mib=$(format_mib "${htop_used_kib}")
free_used_mib=$(format_mib "${free_used_kib}")

# Valeur de la jauge « Mem » d'htop : elle additionne les classes qui comptent
# comme utilisées, soit usedMem + Shmem (classe « shared »). Les ajustements
# ZFS d'htop ne sont pas reproduits ici.
htop_bar_kib=$(( htop_used_kib + shmem_kib ))
htop_bar_mib=$(format_mib "${htop_bar_kib}")

mem_info 'Mémoire totale' "${total_mib}"
mem_info 'Mémoire disponible (MemAvailable)' "${available_mib}"
mem_info 'RAM physique réellement utilisée zram' "${zram_mib}"
mem_info 'RAM physique réellement utilisée zswap' "${zswap_mib}"
# Shmem est déjà compris dans Cached : ligne atténuée et placée en dernier.
mem_info 'Shmem (mémoire partagée)' "${shmem_mib}" dim
printf '\n'

# Tableau de synthèse :
#  - htop usedMem : formule exacte de linux/LinuxMachine.c, Shmem non réintégré
#    (il est déjà compris dans Cached) ;
#  - htop barre   : ce qu'affiche la jauge Mem d'htop = usedMem + Shmem ;
#  - free         : colonne « utilisé » de free(1).
mem_table_row 'Méthode' 'Mémoire utilisée'
printf '%s\n' '---------------------------------------------------------------------------------'
mem_table_row \
    'htop usedMem (total - free - buffers - Cache - SReclaimable)' \
    "${htop_used_mib}" ' MiB'
mem_table_row 'htop barre (usedMem + Shmem)' "${htop_bar_mib}" ' MiB'
mem_table_row 'free (total - MemAvailable)' "${free_used_mib}" ' MiB'
