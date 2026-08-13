#!/usr/bin/env bash

# --- IP LAN (interface non-loopback) ---
lan_ip="$(ip -4 route | awk '/default/ {print $5}' | head -1)"
lan_addr="$(ip -4 addr show "$lan_ip" +brd 0.0.0.0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)"
if [[ -z "${lan_addrs}" ]]; then
  lan_addr="$(hostname -I | awk '{print $1}')"
fi

# --- IP WAN (publique) ---
wan_ip="$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -1)"
if [[ -z "$wan_ip" ]]; then
  wan_ip="$(curl -s --max-time 2 ipinfo.io/ip 2>/dev/null | head -1)"
fi
if [[ -z "$wan_ip" ]]; then
  wan_ip="$(curl -s --max-time 2 ipecho.net/plain 2>/dev/null | head -1)"
fi

# --- GATEWAY ---
gateway="$(ip -4 route | awk '/default/ {print $3}' | head -1)"

# --- DNS (de /etc/resolv.conf) ---
dns="$(resolvectl status | awk '/^  Current DNS Server:/ {print $4; exit}' | sed 's/#.*//')"

# --- Affichage aligné (champ fixe 15 chars) ---
printf "%-10s %15s\n" "WAN :" "${wan_ip:-N/A}"
printf "%-10s %15s\n" "LAN :" "${lan_addr:-N/A}"
printf "%-10s %15s\n" "GATE:" "${gateway:-N/A}"
printf "%-10s %15s\n" "DNS :" "${dns:-N/A}"
