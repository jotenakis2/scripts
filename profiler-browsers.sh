#!/usr/bin/env bash
# Usage : backup | restore
set -euo pipefail

# dossier de sauvegarde
NAS_MOUNT="/media/NAS/backup/browser"

# dossiers à sauvegarder
MOZILLA=".mozilla/firefox/"
BRAVE=".config/BraveSoftware/Brave-Browser/"


####################################################################################################################
trap '_ERR "Interruption ligne ${LINENO}"; _DIE "Log : ${LOG_FILE}"' ERR

C_RESET='' C_RED='' C_GREEN=''
if [[ -t 1 ]]; then
    C_RESET='\e[0m'
    C_RED='\e[1;31m'
    C_GREEN='\e[1;32m'
fi
SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
DATE=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${HOME}/.local/log"
LOG_FILE="${LOG_DIR}/profilers-browsers-${DATE}.log"
FIREFOX_FILE="${NAS_MOUNT}/firefox_${DATE}.tar.gz"
BRAVE_FILE="${NAS_MOUNT}/brave_${DATE}.tar.gz"
mkdir -p "${NAS_MOUNT}" "${LOG_DIR}"

####################################################################################################################
backup() {
    FIREFOX_OK=0
    BRAVE_OK=0
    if pgrep -x firefox >/dev/null; then
        _ERR "Ferme Firefox d'abord."
    else
        _RUN "Sauvegarde du profil Firefox en cours..." tar -cvzf "${FIREFOX_FILE}" -C "${HOME}" "${MOZILLA}"
        FIREFOX_OK=1
    fi
    echo ""
    if pgrep -x brave   >/dev/null; then
        _ERR "Ferme Brave d'abord."
        exit 1
    else
        _RUN "Sauvegarde du profil Brave en cours..." tar -cvzf "${BRAVE_FILE}"   -C "${HOME}" "${BRAVE}"
        BRAVE_OK=1
    fi
    echo ""
    show_backup_info
}
####################################################################################################################

restore() {
	local ff_list brave_list ff_sorted brave_sorted ff_arc brave_arc
   
    if pgrep -x firefox >/dev/null; then
        _ERR "Ferme Firefox d'abord."
    else
		ff_list=$(find "${NAS_MOUNT}" -maxdepth 1 -name 'firefox_*.tar.gz' -printf '%T@ %p\n' || true)
		ff_sorted=$(echo "${ff_list}"    | sort -rn || true)
		ff_arc=$(echo "${ff_sorted}"    | head -1 | cut -d' ' -f2- || true)		
	    if [[ -n "${ff_arc}" ]]; then
	    	_RUN "Restauration du profil Firefox en cours..." tar -xzf "${ff_arc}" -C "${HOME}"
	    	echo "Firefox restauré depuis ${ff_arc}."
    	fi
    fi

	if pgrep -x brave >/dev/null; then
        _ERR "Ferme Brave d'abord."
    else
		brave_list=$(find "${NAS_MOUNT}" -maxdepth 1 -name 'brave_*.tar.gz' -printf '%T@ %p\n' || true)
   		brave_sorted=$(echo "${brave_list}" | sort -rn || true)
    	brave_arc=$(echo "${brave_sorted}" | head -1 | cut -d' ' -f2- || true)
    	if [[ -n "${brave_arc}" ]]; then
    		_RUN "Restauration du profil Brave en cours..." tar -xzf "${brave_arc}" -C "${HOME}" 
    		echo "=> Brave restauré depuis ${brave_arc}."
    	fi
    fi
    
}
####################################################################################################################

show_backup_info() {
    local firefox_size_bytes=""
    local brave_size_bytes=""
    local firefox_size_mb=""
    local brave_size_mb=""

    if [[ ${FIREFOX_OK} -eq 1 ]]; then
        firefox_size_bytes=$(stat -c %s "${FIREFOX_FILE}" 2>/dev/null || true)
        if [[ -n "${firefox_size_bytes}" ]]; then
            firefox_size_mb=$(awk -v size="${firefox_size_bytes}" 'BEGIN { printf "%.1f", size / 1024 / 1024 }')
            printf 'Firefox: %s (%s Mo)\n' "$(basename "${FIREFOX_FILE}")" "${firefox_size_mb}"
        else
            printf 'Firefox: %s\n' "$(basename "${FIREFOX_FILE}")"
        fi
    fi

    if [[ ${BRAVE_OK} -eq 1 ]]; then
        brave_size_bytes=$(stat -c %s "${BRAVE_FILE}" 2>/dev/null || true)
        if [[ -n "${brave_size_bytes}" ]]; then
            brave_size_mb=$(awk -v size="${brave_size_bytes}" 'BEGIN { printf "%.1f", size / 1024 / 1024 }')
            printf 'Brave:   %s (%s Mo)\n' "$(basename "${BRAVE_FILE}")" "${brave_size_mb}"
        else
            printf 'Brave:   %s\n' "$(basename "${BRAVE_FILE}")"
        fi
    fi
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
