#!/usr/bin/env bash
# shellcheck disable=SC2312
# Cle API ipgeolocation.io : jamais dans le depot.
# Priorite : variable d'environnement WANIP_APIKEY, puis ~/.config/wanip/apikey
apikey="${WANIP_APIKEY:-}"
if [[ -z "${apikey}" ]]; then
    keyfile="${XDG_CONFIG_HOME:-${HOME}/.config}/wanip/apikey"
    if [[ -r "${keyfile}" ]]; then
        apikey=$(head -1 "${keyfile}" | tr -d '[:space:]')
    fi
fi
cachedir="${XDG_CACHE_HOME:-${HOME}/.cache}/wanip"
mkdir -p -- "${cachedir}"
max_age=900 # cache refresh every 15 min to limit api call
timeout=1 # 1s timeout max for curl to retrieve data

emoji=''
wan_ip=''
kernel=''
Bleu="\033[0;34m"
Reset="\033[0m"
spaceafter="   "
Rouge="\033[0;31m"

ipv4_regex='^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'

# curl & jq are required
if ! command -v curl >/dev/null || ! command -v jq >/dev/null; then
	printf '%s : curl et jq sont requis\n' "$0" >&2
	exit 1
fi

# retrieve IP WAN - 3 methods
command -v dig >/dev/null && wan_ip=$(dig -4 +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -1)
if [[ -z "${wan_ip}" ]] || [[ ! ${wan_ip} =~ ${ipv4_regex} ]]; then
	wan_ip=$(curl --connect-timeout "${timeout}" -4 ifconfig.co 2>/dev/null | head -1)
fi
if [[ -z "${wan_ip}" ]] || [[ ! ${wan_ip} =~ ${ipv4_regex} ]]; then
	wan_ip=$(curl --connect-timeout "${timeout}" -4 ifconfig.me 2>/dev/null | head -1)
fi

# geoloc (uniquement si une cle est disponible)
if [[ ${wan_ip} =~ ${ipv4_regex} ]]; then
    file="${cachedir}/${wan_ip}.json"

    if [[ -z "${apikey}" ]]; then
        emoji=''
    else
        if [[ ! -e "${file}" ]] || [[ $(($(date +%s) - $(stat -c %Y "${file}" 2>/dev/null || echo 0))) -gt ${max_age} ]]; then
            rm -f "${file}"
            curl --connect-timeout "${timeout}" -sS "https://api.ipgeolocation.io/v3/ipgeo?apiKey=${apikey}" > "${file}" 2>/dev/null
        fi

        if [[ -s "${file}" ]] && jq -e . < "${file}" >/dev/null 2>&1; then
            emoji=$(jq -r '.location.country_emoji // empty' < "${file}")
            if [[ -z "${emoji}" ]]; then
                emoji=$(jq -r '.location.country_code2 // empty' < "${file}")
            fi
            if [[ -z "${emoji}" ]]; then
                emoji=$(jq -r '.location.country_code3 // empty' < "${file}")
            fi
        else
            emoji="❓"
        fi
    fi
else
    wan_ip=''
    emoji=''
fi

strkernel=''
if [[ "${1:-}" = "-k" ]]; then
	# kernel
	kernel=$(uname -r | awk -F ".fc" '{print $1}' || true)
	if [[ "${kernel}" = *cachyos* ]]; then
		strkernel="${Bleu}${Reset} ${kernel}${spaceafter}"
	else
		strkernel="${Rouge}${Reset} ${kernel:-?}${spaceafter}"
	fi
fi

# ip
strIP=''
if [[ -z "${wan_ip}" ]]; then
	strIP="${Rouge}󰩟${Reset} ?"
else
	strIP="${Bleu}󰩟${Reset} ${wan_ip:-?} ${emoji:-}"
fi

# display
echo -e "${strkernel}${strIP}"
