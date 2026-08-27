#!/usr/bin/env bash
# shellcheck disable=SC2312
ipv4_regex='^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'

# --- IP LAN (interface non-loopback) ---
lan_addr="$(hostname -I)"

# --- IP WAN (publique) ---
wan_ip="$(dig -4 +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -1)"
if [[ -z "${wan_ip}" ]] || [[ ! ${wan_ip} =~ ${ipv4_regex} ]]; then
	wan_ip="$(curl -4 ifconfig.co 2>/dev/null | head -1)"
fi
if [[ -z "${wan_ip}" ]] || [[ ! ${wan_ip} =~ ${ipv4_regex} ]]; then
	wan_ip="$(curl -4 ifconfig.me 2>/dev/null | head -1)"
fi
if [[ ! ${wan_ip} =~ ${ipv4_regex} ]]; then
	wan_ip=''
fi

# --- GATEWAY ---
gateway="$(ip -4 route | awk '/^default/ {print $3}' | head -1)"
if [[ -z "${gateway}" ]] || [[ ! ${gateway} =~ ${ipv4_regex} ]]; then
	gateway=''
fi

# --- DNS (de /etc/resolv.conf) ---
dns="$(resolvectl status | awk '/^  Current DNS Server:/ {print $4; exit}' | sed 's/#.*//')"
if [[ -z "${dns}" ]] || [[ ! ${dns} =~ ${ipv4_regex} ]]; then
	dns=''
fi


# --- Affichage aligné 
printf "%-5s %23s\n" "WAN :" "${wan_ip:-N/A}"
printf "%-5s %24s\n" "LAN :" "${lan_addr:-N/A}"
printf "%-5s %23s\n" "GATE:" "${gateway:-N/A}"
printf "%-5s %23s\n" "DNS :" "${dns:-N/A}"
