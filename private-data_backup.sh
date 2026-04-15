#!/usr/bin/env bash
# Usage : backup | restore
set -euo pipefail

# Dossier de stockage des sauvegardes
NAS_MOUNT="/media/NAS/backup/data2restore"

# dossiers à sauvegarder
declare -A SOURCES=(
   ["FIREFOX"]=".mozilla/firefox/"
   ["BRAVE"]=".config/BraveSoftware/Brave-Browser/"
   ["HELIUM"]=".config/net.imput.helium/"
   ["SSH"]=".ssh/"
   ["IPTVNATOR"]=".config/iptvnator/"
   ["SSHMANAGER"]=".local/share/sshmanager"
)

# binaire à surveiller avant la sauvegarde (par exemple pour les profils navigateurs il est recommandé de fermer le navigateur avant sauvegarde/restauration - si on met "" on ne surveille rien)
declare -A COMMANDS=(
   ["FIREFOX"]="firefox"
   ["BRAVE"]="brave"
   ["HELIUM"]="helium"
   ["SSH"]=""
   ["IPTVNATOR"]="iptvnator.bin"
   ["SSHMANAGER"]=""
)


####################################################################################################################

trap '_ERR "Interruption ligne ${LINENO}"; _DIE "Log : ${LOG_FILE}"' ERR

C_RESET='' C_RED='' C_GREEN=''
if [[ -t 1 ]]; then
    C_RESET='\e[0m'
    C_RED='\e[1;31m'
    C_GREEN='\e[1;32m'
fi

####################################################################################################################

backup() {
    local profil cmd source target 
    for profil in "${!SOURCES[@]}"; do
        source=${SOURCES["${profil}"]}
        target="${NAS_MOUNT}/${profil}_${DATE}.tar.gz"
        cmd=${COMMANDS["${profil}"]:-}
		if [[ -n "${cmd}" ]] && pgrep -x "${cmd}" >/dev/null; then
			_ERR "Ferme ${cmd} d'abord."
		else
			_RUN "Sauvegarde du profil ${profil} en cours..." tar -cvzf "${target}" -C "${HOME}" "${source}"
		fi
    done
    echo
    find "${NAS_MOUNT}" -maxdepth 1 -type f -printf '%f\t%s\n' | awk -F '\t' '{ printf "%s (%d Mo)\n", $1, ($2/1024/1024)+1.0 }' | sort | grep "${DATE}" | column -t

}

####################################################################################################################

restore() {
    local profil file
    for profil in "${!SOURCES[@]}"; do
    	cmd=${COMMANDS["${profil}"]:-}
		file=$(find "${NAS_MOUNT}" -maxdepth 1 -name "${profil}_*.tar.gz" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2- || true)
		if [[ -n "${cmd}" ]] && pgrep -x "${cmd}" >/dev/null; then
			_ERR "Ferme ${cmd} d'abord."
		else
			if [[ -n "${file}" ]]; then
				_RUN "Restauration du profil ${profil} (${file} vers ${HOME}) en cours..." tar -xzf "${file}" -C "${HOME}"/temp
			fi
		fi
	done
}

####################################################################################################################

# HELPERS ----------------------------------------------------------------------------------------------------------
_OK()       { printf " %b✓%b %s\n" "${C_GREEN}"  "${C_RESET}" "$*" | tee -a "${LOG_FILE}"; }
_ERR()      { printf " %b✗%b %s\n" "${C_RED}"    "${C_RESET}" "$*" | tee -a "${LOG_FILE}" >&2; }
_DIE()      { _ERR "$*"; exit 1; }
_RUN() {
    local msg="$1"; shift

    spin() {
        local pid="$1" msg="$2" i=0
        while kill -0 "${pid}" 2>/dev/null; do
            printf "\r %b%s%b %s" "${C_RED}" "${SPIN_FRAMES[$((i % 10))]}" "${C_RESET}" "${msg}"
            sleep 0.05
            (( i++ )) || true
        done
        printf '\r\033[2K'
    }

    "$@" >> "${LOG_FILE}" 2>&1 &
    local pid=$!
    spin "${pid}" "${msg}"
    if wait "${pid}"; then
        _OK "${msg}"
    else
        _ERR "${msg}"
        _DIE "Échec — détails : ${LOG_FILE}"
    fi
}
####################################################################################################################
# shellcheck disable=SC2312
show() {
    local profil
    local -i w=0

    for profil in "${!SOURCES[@]}"; do
        (( ${#profil} > w )) && w=${#profil}
    done

    printf '%-*s | %-40s | %s\n' \
        "${w}" "Profil" \
        "Dossier" \
        "Binaire de contrôle"
    printf '%-*s-+-%-40s-+-%s\n' \
        "${w}" "$(printf '%*s' "${w}" '' | tr ' ' '-')" \
        "$(printf '%*s' 40 '' | tr ' ' '-')" \
        "$(printf '%*s' 20 '' | tr ' ' '-')"

    for profil in "${!SOURCES[@]}"; do
        printf '%-*s | %-40s | %s\n' \
            "${w}" "${profil}" \
            "${SOURCES[${profil}]}" \
            "${COMMANDS[${profil}]:-}"
    done
    echo -e "\nContenu de la sauvegarde :"
    find "${NAS_MOUNT}" -maxdepth 1 -type f -printf '%f\t%s\n' | awk -F '\t' '{ printf "%s (%d Mo)\n", $1, ($2/1024/1024)+1.0 }' | sort | column -t
}
####################################################################################################################
SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
DATE=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${HOME}/.local/log"
LOG_FILE="${LOG_DIR}/private-data_backup-${DATE}.log"
mkdir -p "${NAS_MOUNT}" "${LOG_DIR}"

case "${1:-}" in
    backup)  echo "Log : ${LOG_FILE}"; backup  ;;
    restore) echo "Log : ${LOG_FILE}"; restore ;;
    show)    show ;;
    *) echo "Usage: $0 backup|restore|show" ;;
esac
####################################################################################################################
