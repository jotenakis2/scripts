#!/usr/bin/env bash
# Usage : backup | restore
set -euo pipefail
SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
DATE=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${HOME}/.local/log"
LOG_FILE="${LOG_DIR}/private-data_backup-${DATE}.log"
NAS_MOUNT="/media/NAS/backup/data2restore"
mkdir -p "${NAS_MOUNT}" "${LOG_DIR}"

# dossiers à sauvegarder
PROFILES=(
   "FIREFOX"
   "BRAVE"
   "SSH"
   "IPTVNATOR"
   "SSHMANAGER"
)
declare -A SOURCES=(
   ["FIREFOX"]=".mozilla/firefox/"
   ["BRAVE"]=".config/BraveSoftware/Brave-Browser/"
   ["SSH"]=".ssh/"
   ["IPTVNATOR"]=".config/iptvnator/"
   ["SSHMANAGER"]=".local/share/sshmanager"
)
declare -A TARGETS=(
   ["FIREFOX"]="${NAS_MOUNT}/FIREFOX_${DATE}.tar.gz"
   ["BRAVE"]="${NAS_MOUNT}/BRAVE_${DATE}.tar.gz"
   ["SSH"]="${NAS_MOUNT}/SSH_${DATE}.tar.gz"
   ["IPTVNATOR"]="${NAS_MOUNT}/IPTVNATOR_${DATE}.tar.gz"
   ["SSHMANAGER"]="${NAS_MOUNT}/SSHMANAGER_${DATE}.tar.gz"
)
declare -A COMMANDS=(
   ["FIREFOX"]="firefox"
   ["BRAVE"]="brave"
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
    for profil in "${PROFILES[@]}"; do
		source=${SOURCES["${profil}"]}
		target=${TARGETS["${profil}"]}
		cmd=${COMMANDS["${profil}"]}
		if [[ -n "${cmd}" ]] && pgrep -x "${cmd}" >/dev/null; then
			_ERR "Ferme ${cmd} d'abord."
		else
			_RUN "Sauvegarde du profil ${profil} en cours..." tar -cvzf "${target}" -C "${HOME}" "${source}"
		fi
    done
}

####################################################################################################################

restore() {
    local profil file
    for profil in "${PROFILES[@]}"; do
    	cmd=${COMMANDS["${profil}"]}
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

case "${1:-}" in
    backup)  backup  ;;
    restore) restore ;;
    *) echo "Usage: $0 backup|restore" ;;
esac
####################################################################################################################
