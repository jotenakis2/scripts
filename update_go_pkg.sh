#!/usr/bin/env bash
terminal="${TERM}"
export GOROOT=/opt/go
export GOPATH=/opt/go/workspace
export GOBIN=/opt/go/workspace/bin

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
    if [[ "${terminal}" != "dumb" ]]; then
        set +m
        tput civis || true # Hide cursor, ignore errors if unsupported
        echo -ne "Mise à jour en cours...  ${C_RED})"
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
    if [[ "${terminal}" != "dumb" ]]; then
        { kill -9 "${spinner_pid}" && wait "${spinner_pid}"; } 2>/dev/null || true # Kill spinner safely
        set -m
        echo -en "\b\b"
        tput cvvis || true # Show cursor, ignore errors if unsupported
        echo -ne "${C_RESET}"
        return 0
    fi
}
###############################################################################################################

_ENABLE_COLORS
echo
# shellcheck disable=SC2154
echo "${C_GREEN}Paquets GO installés dans ${C_BLUE}${GOBIN}${C_RESET} :"
echo ""
ls "${GOBIN}"

echo "${C_RED}"
{ trap STOP-SPINNER EXIT && START-SPINNER; }
	go install github.com/zi0p4tch0/radiogogo@latest
	go install github.com/ashish0kumar/stormy@latest
	go install github.com/programmersd21/zap/cmd/zap@latest
	go install github.com/xdagiz/xytz@latest
	go install github.com/renatoworks/oh-my-reddit@latest
	go install github.com/showwin/speedtest-go@latest
	go install github.com/Foxemsx/riptide/cmd/riptide@latest
	go install github.com/nolight132/nls/cmd/nls@latest
	go install github.com/0xjuanma/golazo@latest
	go install github.com/mr-karan/doggo/cmd/doggo@latest
	go install github.com/heymaikol/network-doctor@latest
{ STOP-SPINNER && echo "${C_GREEN}terminée.${C_RESET}"; }
echo ""

if [[ -t 1 ]]; then
	eza -l --header --group-directories-first --color-scale all --color always --group -b "${GOBIN}"
else
	ls -lh "${GOBIN}"
fi
