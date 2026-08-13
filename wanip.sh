#!/usr/bin/env bash
wan_ip="$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -1)" || true
file="/tmp/${wan_ip}"
str=""

# pays
if [[ -e "${file}" ]]; then
	loc=$(/usr/bin/cat "${file}" 2>/dev/null) || true
else
	if command -v whois &>/dev/null; then
		loc=$(whois "${wan_ip}" | rg "country:" | awk -F: '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}') || true
		[[ -n "${loc}" ]] && echo "${loc}" > "${file}"
	fi
fi

# drapeau
country="${loc:-}"
if [[ "${country,,}" = "fr" ]]; then
	country="🇫🇷"
	str=" ${country}"
elif [[ -n "${country}" ]]; then
	str=" (${country})"
fi

# affichage
echo -e "󰩟 ${wan_ip:-inconnue}${str}"
