#!/bin/bash
# Security audit script: chkrootkit + rkhunter
# shellcheck disable=SC2310
set -euo pipefail
[[ "${EUID}" -eq 0 ]] || { echo "script to be used as root."; exit 1; }

# Configuration
terminal="${TERM}"
LOG_DIR="/var/log/rootkit_scanning"
DATEdisplay=$(date +%d/%m/%Y_%H:%M:%S)
DATE=$(date +%d%m%Y_%H%M%S)
HOSTNAME=$(hostname)
EMAIL_ALERT="olivier.lorillu@proton.me"
TMP_REPORT=$(mktemp)
TMP_CHK=$(mktemp)
TMP_RKH=$(mktemp)
ALERT=0
SCAN=0

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
_BANNER() {
    local color=$1
    shift
    local text="$*"
    local fg cols
    cols="${COLUMNS:-}"
    case "${color}" in
        red) fg=31 ;; green) fg=32 ;; yellow) fg=33 ;; blue) fg=34 ;;
        magenta) fg=35 ;; cyan) fg=36 ;; white) fg=37 ;; *) fg=39 ;;
    esac
    local w=$((cols - 2))
    if ((w < 1)); then return 0; fi
    local len=${#text}
    ((len > w)) && text=${text:0:w} && len=w
    local padl=$(((w - len) / 2))
    local padr=$((w - len - padl))

    local TL=$'\xE2\x95\x94' TR=$'\xE2\x95\x97'
    local BL=$'\xE2\x95\x9A' BR=$'\xE2\x95\x9D'
    local H=$'\xE2\x95\x90' V=$'\xE2\x95\x91'
    local hline
    hline=$(printf '%*s' "${w}" '' | sed "s/ /${H}/g")

    printf '\033[%sm%s%s%s\033[0m\n' "${fg}" "${TL}" "${hline}" "${TR}"
    printf '\033[%sm%s%*s%s%*s%s\033[0m\n' "${fg}" "${V}" "${padl}" '' "${text}" "${padr}" '' "${V}"
    printf '\033[%sm%s%s%s\033[0m\n' "${fg}" "${BL}" "${hline}" "${BR}"
    echo "${text}" >>"${LOG_FILE:-/dev/null}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

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

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_EXIST() {
    local cmd
    cmd=$1
    command -v "${cmd}" &>/dev/null && return 0
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_SECTION() {
    local msg="${1^^}"
    local fillertype="${2}"
    local color="${3}"
    [[ $# == 0 ]] && return 1

    declare -i term_cols # Terminal width
    if ! term_cols="${COLUMNS:-}"; then return 1; fi
    echo -e "${color}"
    term_cols=$(( term_cols - 2 ))

    declare -i str_len="${#msg}" # Length of $msg
    if [[ ${str_len} -ge ${term_cols} ]]; then echo "${msg}"; return 0; fi

    declare -i filler_len="$(((term_cols - str_len) / 2))"
    local ch="${fillertype:0:1}"
    local filler=""
    for ((i = 0; i < filler_len; i++)); do
        filler="${filler}${ch}"
    done

    printf "%s%s%s" "${filler}" "${msg}" "${filler}"
    [[ $(((term_cols - str_len) % 2)) -ne 0 ]] && printf "%s" "${ch}"
    printf "\n"
    echo -e "${C_RESET}"
    echo -e "\n>>>>>>>>>> ${msg}" >>"${LOG_FILE:-/dev/null}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────


################################################################################################################
START-SPINNER() {
    if [[ "${terminal}" != "dumb" ]]; then
        set +m
        tput civis || true # Hide cursor, ignore errors if unsupported
        echo -ne "Scan en cours...  ${C_RED})"
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

mkdir -p "${LOG_DIR}"

_cleanup() {
    rm -f "${TMP_REPORT}" "${TMP_CHK}" "${TMP_RKH}"
}
trap _cleanup EXIT

_ENABLE_COLORS
_BANNER "blue" "Rootkit Scan: ${HOSTNAME} - ${DATEdisplay}"

# === CHKROOTKIT ===
_SECTION " chkrootkit " "━" "${C_YELLOW}"
echo "=== chkrootkit: ${HOSTNAME} ===" >> "${TMP_REPORT}"

if _EXIST chkrootkit; then
    { trap STOP-SPINNER EXIT && START-SPINNER; }
    chkrootkit -q 2>/dev/null \
        | grep -Eiv "can't exec|not tested" \
        | grep -Eiv '/usr/lib/systemd/\.abignore|/usr/lib/debug(/usr)?/\.dwz|/usr/lib/\.build-id|/usr/lib/modules/.*/\.vmlinuz\.hmac|/usr/lib/sysimage/rpm/\.rpm\.lock' \
        | grep -Eiv '/usr/lib/python3\.[0-9]+/site-packages/glances/outputs/static/\.(eslintrc|prettierrc)\.js|/usr/lib/python3\.[0-9]+/site-packages/fastapi/\.agents' \
        | grep -Eiv '/usr/lib/node_modules_24/npm/node_modules/node-gyp/\.release-please-manifest\.json|/usr/lib/node_modules_24/npm/node_modules/node-gyp/gyp/\.release-please-manifest\.(json|js)|/usr/lib/node_modules_24/npm/node_modules/qrcode-terminal/\.travis\.yml' \
        | grep -Eiv '/usr/lib/node_modules/bash-language-server/node_modules/\.pnpm|/usr/lib/node_modules/bash-language-server/node_modules/.*/\.yarn' \
        > "${TMP_CHK}" || true
    { STOP-SPINNER && echo "terminé."; }
    SCAN=1
    if [[ -s "${TMP_CHK}" ]]; then
        echo -e "${C_RED}⚠ ALERT: Potential rootkit detected !${C_RESET}"
        cat "${TMP_CHK}" >> "${TMP_REPORT}"
        ALERT=1
    else
        echo -e "${C_GREEN}✓ chkrootkit: OK (no rootkit)${C_RESET}"
        echo "chkrootkit: OK" >> "${TMP_REPORT}"
    fi
else
    echo "${C_RED} Please install chkrootkit!"
fi


# === RKHUNTER ===
_SECTION " rkhunter " "━" "${C_YELLOW}"
echo "=== rkhunter: ${HOSTNAME} ===" >> "${TMP_REPORT}"

if _EXIST rkhunter; then
    echo -n "Préparation... "
    rkhunter --update --nocolors 2>/dev/null >> "${TMP_REPORT}" || true
    rkhunter --propupd 2>/dev/null >> "${TMP_REPORT}" || true
    echo "terminée, OK."

    { trap STOP-SPINNER EXIT && START-SPINNER; }
    rkhunter --check --skip-keypress --report-warnings-only --nocolors 2>/dev/null >> "${TMP_RKH}" || true
    { STOP-SPINNER && echo "terminé."; }
    SCAN=1
    if [[ -s "${TMP_RKH}" ]]; then
        echo -e "${C_RED}⚠ ALERT: rkhunter warnings detected !${C_RESET}"
        cat "${TMP_RKH}" >> "${TMP_REPORT}"
        ALERT=1
    else
        echo -e "${C_GREEN}✓ rkhunter: OK (no warnings)${C_RESET}"
        echo "rkhunter: OK" >> "${TMP_REPORT}"
    fi
else
    echo "${C_RED} Please install rkhunter!"
fi

cp -f "${TMP_REPORT}" "${LOG_DIR}/rootkit-scan-${DATE}.log" 2>/dev/null
cp -f "${TMP_REPORT}" "${LOG_DIR}/rootkit-scan-latest.log" 2>/dev/null
rm -f "${TMP_REPORT}" "${TMP_CHK}" "${TMP_RKH}" 2>/dev/null

# === ALERTS ===
if [[ ${SCAN} -eq 1 ]]; then
    _SECTION " OUTCOMES " "━" "${C_YELLOW}"
    if [[ ${ALERT} -eq 1 ]]; then
        echo -e "${C_RED}✓ Sending alert email...${C_RESET}"
        mail -s "⚠ ROOTKIT ALERT: ${HOSTNAME} - ${DATE}" "${EMAIL_ALERT}" < "${TMP_REPORT}"
        echo -e "${C_RED}✓ Logs saved to: ${LOG_DIR}/rootkit-scan-${DATE}.log${C_RESET}"
        echo -e "${C_RED}✓ Full log rkhunter: /var/log/rkhunter/rkhunter.log"
    else
        echo -e "${C_GREEN}✓ Scan completed successfully (no alerts)${C_RESET}"
        echo -e "${C_GREEN}✓ Logs saved to: ${LOG_DIR}/rootkit-scan-${DATE}.log${C_RESET}"
        echo -e "${C_GREEN}✓ Full log rkhunter: /var/log/rkhunter/rkhunter.log"
    fi
else
    exit 1
fi
