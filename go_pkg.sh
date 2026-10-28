#!/usr/bin/env bash
version="0.5"
declare -ag pkg_url
pkg_url=(
			github.com/zi0p4tch0/radiogogo@latest
			github.com/ashish0kumar/stormy@latest
			github.com/programmersd21/zap/cmd/zap@latest
			github.com/xdagiz/xytz@latest
			github.com/renatoworks/oh-my-reddit@latest
			github.com/showwin/speedtest-go@latest
			github.com/Foxemsx/riptide/cmd/riptide@latest
			github.com/nolight132/nls/cmd/nls@latest
			github.com/0xjuanma/golazo@latest
			github.com/mr-karan/doggo/cmd/doggo@latest 
			github.com/heymaikol/network-doctor@latest
			github.com/yutat23/lsoff@latest
		)

################################################################################################################
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
################################################################################################################
START-SPINNER() {
	local msg=$1
    if [[ -t 1 ]]; then
        set +m
        tput civis || true # Hide cursor, ignore errors if unsupported
        echo -ne "${msg} en cours...  ${C_RED})"
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local index=""
        {
            while :; do
                for index in "${frames[@]}"; do
                    echo -en "\b${index}"
                    sleep 0.05
                done
            done &
        } 2>/dev/null
        spinner_pid=$!
        return 0
    fi
}
###############################################################################################################
STOP-SPINNER() {
    if [[ -t 1 ]]; then
        { kill -9 "${spinner_pid}" && wait "${spinner_pid}"; } 2>/dev/null || true # Kill spinner safely
        set -m
        echo -en "\b\b"
        tput cvvis || true # Show cursor, ignore errors if unsupported
        echo -ne "${C_RESET}"
        return 0
    fi
}
###############################################################################################################
INSTALL() {
	local pkg=$1
	local msg=$2
	if [[ -t 1 ]]; then
		{ echo ">>> ${msg^} de ${pkg}" ; go install "${pkg}" ; echo ; }  &>>"${LOG}"
	else
		echo "${msg^} de ${pkg}"
		go install "${pkg}" &>>"${LOG}"
	fi
}
###############################################################################################################
MAIN(){
	local msg
	# shellcheck disable=SC2312
	mapfile -t list < <(find "${GOBIN}" -maxdepth 1 -mindepth 1 -type f -printf '%f\n')
	if [[ -n "${list[*]}" ]]; then
		echo "${C_GREEN}Paquets GO installés dans ${C_BLUE}${GOBIN}${C_RESET} : ${list[*]}" ; echo "${C_YELLOW}"
		msg="mise à jour"
	else
		echo "${C_GREEN}Aucun paquet GO actuellement installé dans ${C_BLUE}${GOBIN}${C_RESET}" ; echo 
		msg="installation"
	fi

	local pkg
	echo "${C_GREEN}Paquets déclarés dans le script : ${C_RESET}"
	for pkg in "${pkg_url[@]}"; do
		echo "${pkg}"
	done
	echo "${C_YELLOW}"
	{ trap STOP-SPINNER EXIT && START-SPINNER "${msg^}"; }
	for pkg in "${pkg_url[@]}"; do
		INSTALL "${pkg}" "${msg}"
	done
	{ STOP-SPINNER && [[ -t 1 ]] && echo "${C_GREEN}terminée.${C_RESET}"; }

	# shellcheck disable=SC2312
    mapfile -t list < <(find "${GOBIN}" -maxdepth 1 -mindepth 1 -type f -printf '%f\n')
	if [[ -n "${list[*]}" ]]; then
		# symlink vers /usr/local/bin
		local link
		for link in "${list[@]}"; do
			sudo ln -svf "${GOBIN}/${link}" /usr/local/bin/"${link}" >>"${LOG}"
		done

		# listing
		echo
		local EZA_OPTS=(-l)
		if [[ -t 1 ]]; then
		    EZA_OPTS+=(--color-scale all --color always)
		fi
		local view
		view="ls -l"
		command -v eza &>/dev/null && view="eza ${EZA_OPTS[*]}"
		for link in "${list[@]}"; do
			${view} /usr/local/bin/"${link}"
		done
	else
		echo "${C_RED} /!\ Problème : aucun binaire détecté dans ${GOBIN} /!\ ${C_RESET}"
		exit 1
	fi
	echo
	[[ "${LOG}" = "/dev/null" ]] || echo "Log : ${LOG}"
	date
}

###############################################################################################################
GO_UPDATE() {
	local current latest arch os gofile urlGO
	echo -n "${C_YELLOW}"
    { trap STOP-SPINNER EXIT && START-SPINNER "Vérification de la version de la toolchain GO"; }
		urlGO="https://go.dev/dl/?mode=json"
		current=$(go version 2>/dev/null | awk '{print $3}') || true
	    latest=$(curl -fsSL "${urlGO}" | jq -r '.[0].version') || true
	    arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') || true
	    os=$(uname | tr '[:upper:]' '[:lower:]') || true
	    gofile="${latest}.${os}-${arch}.tar.gz"
	{ STOP-SPINNER && [[ -t 1 ]] && echo "${C_GREEN}terminée.${C_RESET}"; }   	

    if [[ "${current}" = "${latest}" ]]; then
        echo "${C_GREEN}La toolchain GO est à jour (${latest})${C_RESET}"
        echo "La toolchain GO est à jour (${latest})" >>"${LOG}" 
        echo | tee -a "${LOG}"
    else
    	echo -n "${C_YELLOW}" 
    	echo ">>> Installation de la toolchain GO" >>"${LOG}"
    	{ trap STOP-SPINNER EXIT && START-SPINNER "Téléchargement de la toolchain GO"; }
        	curl -LO "https://go.dev/dl/${gofile}" &>>"${LOG}"
    	{ STOP-SPINNER && [[ -t 1 ]] && echo "${C_GREEN}terminé.${C_RESET}"; }   	
    	echo >>"${LOG}"
        local dest
        dest=$(dirname "${GOROOT}")
        if [[ -f "${gofile}" ]]; then
            tar -C "${dest}" -xvzf "${gofile}" &>>"${LOG}" 
            { rm -vf -- "${gofile}" ; echo ; } >>"${LOG}"
            echo
        else
            echo "${C_RED}Échec du Téléchargement de la toolchain GO${C_RESET}"
            echo "Échec du Téléchargement de la toolchain GO" >>"${LOG}"
            exit 1
        fi
    fi
}

################################################################################################################
INIT(){
	local suffix logdir
	 
	export GOROOT="${HOME}/go"
	export GOPATH="${HOME}/go/workspace"
	export GOBIN="${HOME}/go/workspace/bin"
	mkdir -p "${GOBIN}" 

	if [[ -t 1 ]]; then
		suffix=$(date +%d_%m_%Y-%H.%M.%S)
		logdir="${HOME}/.local/log" 
		mkdir -p "${logdir}"
		LOG="${logdir}/go-${suffix}.log"
		: > "${LOG}"
		clear
	else
		LOG="/dev/null"
	fi	
	
	_ENABLE_COLORS
	date
	echo
	echo "${C_MAGENTA}>>>>>>>>>>  Script d'installation et de mise à jour des paquets GO (version ${version})  <<<<<<<<<<< ${C_RESET}"
	echo	
}

################################################################################################################
INIT
GO_UPDATE
MAIN
