#!/usr/bin/env bash
# shellcheck disable=SC2312
apikey='eb53c884836b49bdb81db609d425319f' # compte api.ipgeolocation.io
max_age=900 # cache refresh every 15 min to limit api call

emoji=''
wan_ip=''
kernel=''
ipv4_regex='^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'

# curl & jq are required
if ! command -v curl >/dev/null || ! command -v jq >/dev/null; then
	echo "$0 : You need to install curl and jq commands" | tee /tmp/error
	exit 1
fi

# retrieve IP WAN - 3 methods
command -v dig >/dev/null && wan_ip=$(dig -4 +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -1)
if [[ -z "${wan_ip}" ]] || [[ ! ${wan_ip} =~ ${ipv4_regex} ]]; then
	wan_ip="$(curl -4 ifconfig.co 2>/dev/null | head -1)"
	[[ -n "${wan_ip}" ]] && echo "${wan_ip} (ifconfig.co)" >> /tmp/method
fi
if [[ -z "${wan_ip}" ]] || [[ ! ${wan_ip} =~ ${ipv4_regex} ]]; then
	wan_ip="$(curl -4 ifconfig.me 2>/dev/null | head -1)"
	[[ -n "${wan_ip}" ]] && echo "${wan_ip} (ifconfig.me)" >> /tmp/method
fi

# geoloc
if [[ ${wan_ip} =~ ${ipv4_regex} ]]; then
    file="/tmp/${wan_ip}.json"
    
    if [[ ! -e "${file}" ]] || [[ $(($(date +%s) - $(stat -c %Y "${file}"))) -gt ${max_age} ]]; then
    	rm -f "${file}"
        curl -sS "https://api.ipgeolocation.io/v3/ipgeo?apiKey=${apikey}" > "${file}" 2>/dev/null
    fi
    
    # JSON is valid
    if [[ -s "${file}" ]] && jq -e . < "${file}" >/dev/null 2>&1; then
        emoji=$(jq -r '.location.country_emoji // empty' < "${file}")
        
        # Fallback country_code2
        if [[ -z "${emoji}" ]]; then
            emoji=$(jq -r '.location.country_code2 // empty' < "${file}")
        fi
        
        # Fallback country_code3
        if [[ -z "${emoji}" ]]; then
            emoji=$(jq -r '.location.country_code3 // empty' < "${file}")
        fi
    else
        emoji="❓"  
    fi

else
    wan_ip=''
    emoji=''
fi

# kernel
kernel=$(uname -r | awk -F ".fc" '{print $1}' || true)

# display
echo -e " ${kernel:-?} 󰩟 ${wan_ip:-?}${emoji:-?}"
