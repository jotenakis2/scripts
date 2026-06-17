#!/usr/bin/env bash
wan_ip="$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -1)" || true
str=""

if command -v geoiplookup &>/dev/null; then
	loc=$(geoiplookup "${wan_ip}" | awk -F ": " '{print $2}' | awk -F", " '{print $2}') || true
	country="${loc:-}"
	if [[ "${country,,}" = "france" ]]; then
		country="🇫🇷"
		str=" ${country}"
	elif [[ -n "${country}" ]]; then
		str=" (${country})"
	fi
fi

echo -e "󰩟 ${wan_ip:-inconnue}${str}"
