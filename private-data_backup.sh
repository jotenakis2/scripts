#!/usr/bin/env bash
# Usage : ./private-data_backup.sh backup | restore | show 

# Dossier de stockage des sauvegardes (par exemple un point de montage d'un NAS ou d'un disque externe)
NAS_MOUNT="/media/NAS/backup/data2restore"

# dossiers à sauvegarder
declare -A SOURCES=(
   ["FIREFOX"]=".mozilla/firefox/"
   ["BRAVE"]=".config/BraveSoftware/Brave-Browser/"
   ["HELIUM"]=".config/net.imput.helium/"
   ["SSH"]=".ssh/"
   ["IPTVNATOR"]=".config/iptvnator/"
   ["SSHMANAGER"]=".local/share/sshmanager"
   ["MSMTP"]=".config/msmtp"
   ["IMAGES"]="Pictures"
   ["DOCUMENTS"]="Documents"
   # ajouter ici sur le modèle ["NOM-DU-PROFIL-DE-SAUVEGARDE"]="Dossier" où Dossier est un répertoire dans $HOME
)

# binaire à surveiller avant la sauvegarde 
# (par exemple pour les profils navigateurs il est recommandé de fermer le navigateur avant sauvegarde/restauration
declare -A COMMANDS=(
   ["FIREFOX"]="firefox" 			# ici grace à cette entrée si firefox est lancé, le script refusera de faire la sauvegarde et le signalera
   ["BRAVE"]="brave"
   ["HELIUM"]="helium"
   ["IPTVNATOR"]="iptvnator.bin"
   # ajouter ici sur le modèle ["NOM-DU-PROFIL-DE-SAUVEGARDE"]="nom-du-binaire"
)











####################################################################################################################
####################################################################################################################
####################################################################################################################
####################################################################################################################
####################################################################################################################
set -euo pipefail
readonly SCRIPTNAME="${0##*/}"
readonly VER=1.0

trap '_ERR "Interruption ligne ${LINENO}"; _DIE "Log : ${LOG_FILE}"' ERR

C_RESET='' C_RED='' C_GREEN=''
if [[ -t 1 ]]; then
    C_RESET='\e[0m'
    C_RED='\e[1;31m'
    C_GREEN='\e[1;32m'
    C_YELLOW='\e[1;33m'
    C_CYAN='\e[1;36m'
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

# restore() {
#     local profil file
#     for profil in "${!SOURCES[@]}"; do
#     	cmd=${COMMANDS["${profil}"]:-}
# 		file=$(find "${NAS_MOUNT}" -maxdepth 1 -name "${profil}_*.tar.gz" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2- || true)
# 		if [[ -n "${cmd}" ]] && pgrep -x "${cmd}" >/dev/null; then
# 			_ERR "Ferme ${cmd} d'abord."
# 		else
# 			if [[ -n "${file}" ]]; then
# 				_RUN "Restauration du profil ${profil} (${file} vers ${HOME}) en cours..." tar -xzf "${file}" -C "${HOME}"
# 			fi
# 		fi
# 	done
# }

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

delete_old() {
    local profil file
    local -i deleted=0

    echo -e "${C_CYAN}Suppression des anciennes sauvegardes (on ne garde que la plus récente)...${C_RESET}"

    for profil in "${!SOURCES[@]}"; do
        # Liste tous les fichiers du profil triés du plus récent au plus ancien
        local -a files=()
        mapfile -t files < <(
            find "${NAS_MOUNT}" -maxdepth 1 -name "${profil}_*.tar.gz" -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2- || true
        )

        if (( ${#files[@]} <= 1 )); then
            continue  # 0 ou 1 fichier : rien à supprimer
        fi

        # On garde le premier (le plus récent), on supprime les suivants
        echo "Profil ${profil} : "
        echo ""
        echo -e "${C_GREEN}✓${C_RESET}Conservation de ${files[0]##*/}"
        for file in "${files[@]:1}"; do
            _RUN "Suppression de ${file##*/}" rm -vf "${file}"
            (( deleted++ )) || true
        done
        echo
    done

    if (( deleted == 0 )); then
        printf " Rien à supprimer.\n"
    else
        printf "\n%b%d archive(s) supprimée(s).%b\n" "${C_GREEN}" "${deleted}" "${C_RESET}"
        show
    fi
}

####################################################################################################################

restore() {
    local profil cmd
    local target_profil="${1:-}"
	show 
    if [[ -n "${target_profil}" ]]; then
        target_profil="${target_profil^^}"
        if [[ -z "${SOURCES["${target_profil}"]:-}" ]]; then
            _DIE "Profil inconnu : ${target_profil}. Utilisez 'show' pour lister les profils."
        fi
        _restore_one "${target_profil}"
        return
    fi

    local -a profils
    mapfile -t profils < <(printf '%s\n' "${!SOURCES[@]}" | sort)

    printf "\n%bChoisissez un profil à restaurer :%b\n\n" "${C_CYAN}" "${C_RESET}"
    local -i i=1
    for profil in "${profils[@]}"; do
        printf "  %b%2d)%b %s\n" "${C_GREEN}" "${i}" "${C_RESET}" "${profil}"
        (( i++ )) || true
    done
    printf "  %b%2d)%b TOUS\n"    "${C_GREEN}" "${i}" "${C_RESET}"; local all_idx=${i}; (( i++ )) || true
    printf "  %b%2d)%b Annuler\n" "${C_GREEN}" "${i}" "${C_RESET}"; local cancel_idx=${i}

    local choice
    printf "\n%b#?%b " "${C_CYAN}" "${C_RESET}"
    read -r choice

    if [[ ! "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > cancel_idx )); then
        echo "Choix invalide."; return
    fi

    if (( choice == cancel_idx )); then
        echo "Annulé."; return
    elif (( choice == all_idx )); then
        for profil in "${profils[@]}"; do
            _restore_one "${profil}"
        done
    else
        _restore_one "${profils[$(( choice - 1 ))]}"
    fi
}
####################################################################################################################

_restore_one() {
    local profil="$1" file cmd
    cmd=${COMMANDS["${profil}"]:-}
    file=$(find "${NAS_MOUNT}" -maxdepth 1 -name "${profil}_*.tar.gz" -printf '%T@ %p\n' \
        | sort -rn | head -1 | cut -d' ' -f2- || true)

    if [[ -n "${cmd}" ]] && pgrep -x "${cmd}" >/dev/null; then
        _ERR "Ferme ${cmd} d'abord."
        return
    fi
    if [[ -z "${file}" ]]; then
        _ERR "Aucune sauvegarde trouvée pour le profil ${profil}."
        return
    fi
    _RUN "Restauration du profil ${profil} (${file##*/} → ${HOME}) en cours..." \
        tar -xzf "${file}" -C "${HOME}"
}

####################################################################################################################
SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
DATE=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${HOME}/.local/log"
LOG_FILE="${LOG_DIR}/private-data_backup-${DATE}.log"
mkdir -p "${NAS_MOUNT}" "${LOG_DIR}"
echo -e "\n${C_CYAN}${SCRIPTNAME}${C_RESET} ${C_YELLOW}v${VER}${C_RESET}\n"
case "${1:-}" in
    backup)      echo "Log : ${LOG_FILE}"; echo; backup ;;
    restore)     echo "Log : ${LOG_FILE}"; echo; restore "${2:-}" ;;
    delete_old)  echo "Log : ${LOG_FILE}"; echo; delete_old ;;
    show)        show ;;
    *)           echo -e "Usage :${C_GREEN} $0 backup | restore [PROFIL] | delete_old | show${C_RESET}" ;;
esac
####################################################################################################################
