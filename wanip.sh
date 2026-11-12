#!/usr/bin/env bash
# shellcheck enable=all
#
# Affiche l'IP WAN publique et, si une clé API est configurée, sa géolocalisation.
#
# Clé API (optionnelle) :
#   export WANIP_API_KEY='...'
# ou fichier ~/.config/wanip/apikey (chmod 600).

set -euo pipefail

readonly max_age=900   # cache : 15 min
readonly timeout=3     # timeout réseau : 3 s

Bleu=$'\033[0;34m'
Rouge=$'\033[0;31m'
Reset=$'\033[0m'
spaceafter='   '

ipv4_regex='^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'

if ! command -v curl >/dev/null 2>&1; then
    printf '%s : curl est requis.\n' "$0" >&2
    exit 1
fi

# Clé API : environnement prioritaire, puis fichier local.
api_key="${WANIP_API_KEY:-}"
if [[ -z "${api_key}" && -r "${HOME}/.config/wanip/apikey" ]]; then
    api_key="$(<"${HOME}/.config/wanip/apikey")"
fi
api_key="${api_key//[$'\r\n\t ']/}"

if [[ -n "${api_key}" ]] && ! command -v jq >/dev/null 2>&1; then
    printf 'jq est requis pour la géolocalisation ; géolocalisation désactivée.\n' >&2
    api_key=''
fi

wan_ip=''
if command -v dig >/dev/null 2>&1; then
    wan_ip="$(dig -4 +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -1 || true)"
fi
if [[ -z "${wan_ip}" ]] || [[ ! "${wan_ip}" =~ ${ipv4_regex} ]]; then
    wan_ip="$(curl --connect-timeout "${timeout}" --max-time "${timeout}" -fsS -4 https://ifconfig.co 2>/dev/null | head -1 || true)"
fi
if [[ -z "${wan_ip}" ]] || [[ ! "${wan_ip}" =~ ${ipv4_regex} ]]; then
    wan_ip="$(curl --connect-timeout "${timeout}" --max-time "${timeout}" -fsS -4 https://ifconfig.me 2>/dev/null | head -1 || true)"
fi
if [[ ! "${wan_ip}" =~ ${ipv4_regex} ]]; then
    wan_ip=''
fi

emoji=''
if [[ -n "${wan_ip}" && -n "${api_key}" ]]; then
    cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/wanip"
    mkdir -p "${cache_dir}"
    chmod 700 "${cache_dir}" 2>/dev/null || true
    cache_file="${cache_dir}/${wan_ip}.json"

    now="$(date +%s)"
    mtime="$(stat -c %Y "${cache_file}" 2>/dev/null || printf '0')"

    if [[ ! -s "${cache_file}" ]] || (( now - mtime > max_age )); then
        tmp_file="$(mktemp "${cache_dir}/.geo.XXXXXX")"
        trap 'rm -f "${tmp_file}"' EXIT
        if curl --connect-timeout "${timeout}" --max-time 10 -fsS \
            "https://api.ipgeolocation.io/v3/ipgeo?apiKey=${api_key}&ip=${wan_ip}" \
            -o "${tmp_file}" 2>/dev/null; then
            chmod 600 "${tmp_file}" 2>/dev/null || true
            mv -f "${tmp_file}" "${cache_file}"
        else
            rm -f "${tmp_file}"
        fi
        trap - EXIT
    fi

    if [[ -s "${cache_file}" ]] && jq -e . >/dev/null 2>&1 <"${cache_file}"; then
        emoji="$(jq -r '.location.country_emoji // empty' <"${cache_file}")"
        [[ -n "${emoji}" ]] || emoji="$(jq -r '.location.country_code2 // empty' <"${cache_file}")"
        [[ -n "${emoji}" ]] || emoji="$(jq -r '.location.country_code3 // empty' <"${cache_file}")"
    else
        emoji='❓'
    fi
fi

strkernel=''
if [[ "${1:-}" == '-k' ]]; then
    kernel="$(uname -r)"
    if [[ "${kernel}" == *cachyos* ]]; then
        strkernel="${Bleu} ${Reset} ${kernel}${spaceafter}"
    else
        strkernel="${Rouge} ${Reset} ${kernel:-?}${spaceafter}"
    fi
fi

if [[ -z "${wan_ip}" ]]; then
    strIP="${Rouge}󰩟${Reset} ?"
else
    strIP="${Bleu}󰩟${Reset} ${wan_ip} ${emoji:-}"
fi

printf '%b%b\n' "${strkernel}" "${strIP}"
