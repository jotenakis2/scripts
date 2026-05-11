#!/usr/bin/env bash
# Usage : ./private-data_backup.sh backup | restore [PROFIL] | delete_old | show 
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
   ["MOK"]="mok-cachyos"
   ["DISCORD"]=".config/vesktop"
   # ajouter ici sur le modèle ["NOM-DU-PROFIL-DE-SAUVEGARDE"]="Dossier" où Dossier est un répertoire dans $HOME
)

# binaire à surveiller avant la sauvegarde 
# (par exemple pour les profils navigateurs il est recommandé de fermer le navigateur avant sauvegarde/restauration
declare -A COMMANDS=(
   ["FIREFOX"]="firefox" 			# ici grace à cette entrée si firefox est lancé, le script refusera de faire la sauvegarde et le signalera
   ["BRAVE"]="brave"
   ["HELIUM"]="helium"
   ["IPTVNATOR"]="iptvnator.bin"
   ["DISCORD"]="vesktop"
   # ajouter ici sur le modèle ["NOM-DU-PROFIL-DE-SAUVEGARDE"]="nom-du-binaire"
)











####################################################################################################################
####################################################################################################################
####################################################################################################################
####################################################################################################################
####################################################################################################################
set -euo pipefail
VER=1.1
SCRIPTNAME="${0##*/}"
SCRIPTNAME="${SCRIPTNAME%.sh}"
readonly VER SCRIPTNAME

trap '_CLEANUP' ERR
trap '_INTERRUPT' INT
trap '_DO_CLEAN' EXIT




########################################################################################################################
# shellcheck disable=SC2034
_ENABLE_COLORS() {
    if [[ -t 1 ]] && command -v tput &>/dev/null && [[ -z "${NO_COLOR:-}" ]]; then
        # texte
        C_BLACK=$(tput setaf 0)
        C_RED=$(tput setaf 1)
        C_GREEN=$(tput setaf 2)
        C_YELLOW=$(tput setaf 3)
        C_BLUE=$(tput setaf 4)
        C_MAGENTA=$(tput setaf 5)
        C_CYAN=$(tput setaf 6)
        C_WHITE=$(tput setaf 7)

        # attribut
        C_BOLD=$(tput bold)
        C_DIM=$(tput dim)
        C_RESET=$(tput sgr0)
        C_UNDERLINE=$(tput smul)
        C_RESET_UNDERLINE=$(tput rmul)

        # background
        BKGND_BLACK=$(tput setab 0)
        BKGND_RED=$(tput setab 1)
        BKGND_GREEN=$(tput setab 2)
        BKGND_YELLOW=$(tput setab 3)
        BKGND_BLUE=$(tput setab 4)
        BKGND_MAGENTA=$(tput setab 5)
        BKGND_CYAN=$(tput setab 6)
        BKGND_WHITE=$(tput setab 7)
    else
        # texte
        C_BLACK=''
        C_RED=''
        C_GREEN=''
        C_YELLOW=''
        C_BLUE=''
        C_MAGENTA=''
        C_CYAN=''
        C_WHITE=''

        # attribut
        C_BOLD=''
        C_DIM=''
        C_RESET=''
        C_UNDERLINE=''
        C_RESET_UNDERLINE=''

        # background
        BKGND_BLACK=''
        BKGND_RED=''
        BKGND_GREEN=''
        BKGND_YELLOW=''
        BKGND_BLUE=''
        BKGND_MAGENTA=''
        BKGND_CYAN=''
        BKGND_WHITE=''
    fi
    local vars=(
        C_BLACK C_RED C_GREEN C_YELLOW C_BLUE C_MAGENTA C_CYAN C_WHITE
        C_BOLD C_DIM C_RESET C_UNDERLINE C_RESET_UNDERLINE
        BKGND_BLACK BKGND_RED BKGND_GREEN BKGND_YELLOW
        BKGND_BLUE BKGND_MAGENTA BKGND_CYAN BKGND_WHITE
    )
    export "${vars[@]}"
}

########################################################################################################################

_DO_CLEAN(){
	echo ""
	if [[ -e "${LOG_FILE}" ]]; then
		echo "Log : ${LOG_FILE}"
	fi
}

########################################################################################################################

_DO_LOG(){
    if [[ -s "${LOG_FILE:-}" ]]; then
        _OK "Extrait du Log :"
        echo "--------------------------------------------------------------------------"
        tail -5 "${LOG_FILE:-}" 2>/dev/null
        echo "--------------------------------------------------------------------------"
        _DIE "Log complet : ${LOG_FILE:-}"
    fi
    echo -e "${C_RESET}"
}

########################################################################################################################

_CLEANUP() {
    echo -e "${C_BOLD}${C_RED} Plantage !${C_RESET}"
    _DO_CLEAN
    echo -e "${C_BOLD}${C_RED}"
    _DO_LOG
}


####################################################################################################################

backup() {
    local profil cmd source target selected
    selected=${1:-}
    for profil in "${!SOURCES[@]}"; do
    	if [[ -n "${selected}" ]]; then
            selected="${selected^^}"
            if [[ -z "${SOURCES["${selected}"]:-}" ]]; then
                _DIE "Profil inconnu : ${selected}. Utilisez 'show' pour lister les profils."
            else
				if [[ "${profil}" != "${selected}" ]]; then continue ;fi
			fi
    	fi
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
        echo -e "${C_GREEN}✓ ${C_RESET}Conservation de ${files[0]##*/}"
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
_ENABLE_COLORS
SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
DATE=$(date +%d_%m_%Y-%H.%M.%S)
LOG_DIR="${HOME}/.local/share/${SCRIPTNAME}"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/${SCRIPTNAME}-${DATE}.log"
mkdir -p "${NAS_MOUNT}"
echo -e "\n${C_CYAN}${SCRIPTNAME}${C_RESET} ${C_YELLOW}v${VER}${C_RESET}\n"
case "${1:-}" in
    backup)      backup "${2:-}"  ;;
    restore)     restore "${2:-}" ;;
    delete_old)  delete_old       ;;
    show)        show             ;;
    *)           echo -e "Usage :${C_GREEN} $0 backup | restore [PROFIL] | delete_old | show${C_RESET}" ;;
esac
####################################################################################################################
