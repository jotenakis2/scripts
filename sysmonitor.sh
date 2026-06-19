#!/usr/bin/env bash
set -euo pipefail

#-----------------------------------------------------------------------------
# GPU
GPUpath="/sys/class/drm/card1/device/gpu_busy_percent"
# filtre de la commande sensors, pour affichage d une température
FiltreSensor="Tctl:"
# filtre pour chercher le device de la batterie
FiltreBatt="batt"
# mise en forme
spaceafter=" "
padd="%4s"
padd2="%3s"
seuilcpu=90    # %
seuilgpu=90    # %
seuilmem=90    # %
seuilswap=80   # %
seuilload=50  # %
seuilnet=1024  # ko/s
seuilsensor=70 #°C
seuilbatt=10   # %
#-----------------------------------------------------------------------------




########################################################################################################
# Fonctions                                                                                            #
########################################################################################################


#-------------------------------------------------------
# shellcheck disable=SC2034
define_default_colors(){
	Noir="\033[0;30m"
	Rouge="\033[0;31m"
	Vert="\033[0;32m"
	Jaune="\033[0;33m"
	Bleu="\033[0;34m"
	Violet="\033[0;35m"
	Cyan="\033[0;36m"
	Blanc="\033[0;37m"
	Gris="\033[0;38m"
	Reset="\033[0m"
	#
	#iconcolor="${Bleu}"
	return 0
}

#-------------------------------------------------------
define_icons(){
	cpu_icon="󰻠"
	gpu_icon=""
	load_icon="󱇯"
	mem_icon="󰑭"
	swap_icon="󰓡"
	sensors_icon=""
	tx_icon=""
	rx_icon=""
	icon100="󰁹"
	icon090="󰂂"
	icon080="󰂁"
	icon070="󰂀"
	icon060="󰁿"
	icon050="󰁾"
	icon040="󰁽"
	icon030="󰁼"
	icon020="󰁻"
	icon010="󰁺"
	icon000="󰂃"
	return 0
}

#-------------------------------------------------------
# shellcheck disable=SC2059
sensor(){
    local colorsensor
    colorsensor="${Bleu}"
    declare -g sensors_str=""
    if [[ -n "${sensor}" ]]; then # le sensor a été trouvé
		[[ "${sensor}" -ge "${seuilsensor}" ]] && colorsensor="${Rouge}"
       	sensor=$(printf "${padd2}" "${sensor}")
		sensors_str="${colorsensor}${sensors_icon}${Reset}${sensor}°C${spaceafter}"
	fi
	return 0
}


#-------------------------------------------------------
# shellcheck disable=SC2059
battery(){
	local batt_icon
	local colorbatt
	colorbatt="${Bleu}"
	declare -g batt_str=""
	
   	if [[ -n "${batt}" ]]; then # si la batterie a été trouvée
		if [[ "${batt}" -eq 100 ]]; then
		    batt_icon=${icon100}
		elif [[ "${batt}" -ge 90 ]]; then
		    batt_icon=${icon090}
		elif [[ "${batt}" -ge 80 ]]; then
		    batt_icon=${icon080}
		elif [[ "${batt}" -ge 70 ]]; then
		    batt_icon=${icon070}
		elif [[ "${batt}" -ge 60 ]]; then
		    batt_icon=${icon060}
		elif [[ "${batt}" -ge 50 ]]; then
		    batt_icon=${icon050}
		elif [[ "${batt}" -ge 40 ]]; then
		    batt_icon=${icon040}
		elif [[ "${batt}" -ge 30 ]]; then
		    batt_icon=${icon030}
		elif [[ "${batt}" -ge 20 ]]; then
		    batt_icon=${icon020}
		elif [[ "${batt}" -ge 10 ]]; then
		    batt_icon=${icon010}
		else
		    batt_icon=${icon000}
		fi
		[[ "${batt}" -le "${seuilbatt}" ]] && colorbatt="${Rouge}"
		if [[ "${state}" = "charging" ]]; then
			colorbatt="${Gris}"
			batt_icon="󰂄"
		fi
		batt=$(printf "${padd2}" "${batt}")
		batt_str="${colorbatt}${batt_icon}${Reset}${batt}%${spaceafter}"
	fi
	return 0
}

#-------------------------------------------------------
format_net_value(){
	local value=$1
	if [[ "${value}" -ge 1024 ]]; then
		awk "BEGIN {printf \"%5.1fMo/s\", ${value} / 1024}"
	else
		printf "%5dko/s" "${value}"
	fi
}

#-------------------------------------------------------
# shellcheck disable=SC2059
display(){
	local cpu_str="" mem_str="" load_str="" tx_str="" rx_str="" gpu_str="" swap_str=""
	local colorcpu colorgpu colormem colorload colortx colorrx tx_formatted rx_formatted
	colorgpu="${Bleu}"
	colorload="${Bleu}"
	colormem="${Bleu}"
	colortx="${Bleu}"
	colorrx="${Bleu}"
	colorcpu="${Bleu}"
	colorswap="${Bleu}"

	# Formatage adaptatif du CPU
	if awk "BEGIN {exit !(${cpu} < 10)}"; then
	    cpu=$(awk "BEGIN {printf \"%4.1f\", ${cpu}}")  # < 10% : 1 décimale
	else
	    cpu=$(awk "BEGIN {printf \"%4.0f\", ${cpu}}")  # >= 10% : 0 décimale
	fi
	awk "BEGIN {exit !(${cpu} >= ${seuilcpu})}" && colorcpu="${Rouge}"

	# Formatage adaptatif du GPU
	if awk "BEGIN {exit !(${gpu} < 10)}"; then
	    gpu=$(awk "BEGIN {printf \"%4.1f\", ${gpu}}")  # < 10% : 1 décimale
	else
	    gpu=$(awk "BEGIN {printf \"%4.0f\", ${gpu}}")  # >= 10% : 0 décimale
	fi
	awk "BEGIN {exit !(${gpu} >= ${seuilgpu})}" && colorgpu="${Rouge}"

	# Formatage adaptatif LOAD
	if awk "BEGIN {exit !(${load_pct} < 10)}"; then
	   load_pct=$(awk "BEGIN {printf \"%4.1f\", ${load_pct}}")  # < 10% : 1 décimale
	else
	   load_pct=$(awk "BEGIN {printf \"%4.0f\", ${load_pct}}")  # >= 10% : 0 décimale
	fi

	# Formatage adaptatif RAM
	if awk "BEGIN {exit !(${mem_pct} < 10)}"; then
	   mem_pct=$(awk "BEGIN {printf \"%4.1f\", ${mem_pct}}")  # < 10% : 1 décimale
	else
	   mem_pct=$(awk "BEGIN {printf \"%4.0f\", ${mem_pct}}")  # >= 10% : 0 décimale
	fi

	
	[[ "${load_pct}" -ge "${seuilload}" ]] && colorload="${Rouge}" 
	[[ "${mem_pct}" -ge "${seuilmem}" ]] && colormem="${Rouge}"
	[[ "${tx}" -ge "${seuilnet}" ]] && colortx="${Rouge}"
	[[ "${rx}" -ge "${seuilnet}" ]] && colorrx="${Rouge}"


	# SWAP peut ne pas exister
	if [[ "${swap_pct}" != "na" ]]; then # pas de swap => j'ai défini swap_pct à "na"
		[[ "${swap_pct}" -ge "${seuilswap}" ]] && colorswap="${Rouge}"
		[[ -n "${swap_pct}" ]] && swap_pct=$(printf "${padd}" "${swap_pct}")
		swap_str="${colorswap}${swap_icon}${Reset}${swap_pct}%${spaceafter}"
	fi

	# Padde les valeurs à une largeur fixe
	[[ -n "${cpu}" ]] && cpu=$(printf "${padd}" "${cpu}")
	[[ -n "${gpu}" ]] && gpu=$(printf "${padd}" "${gpu}")	
	[[ -n "${load_pct}" ]] && load_pct=$(printf "${padd}" "${load_pct}")
	[[ -n "${mem_pct}" ]] && mem_pct=$(printf "${padd}" "${mem_pct}")
		
	# Formatage adaptatif réseau
	[[ -n "${tx}" ]] && tx_formatted=$(format_net_value "${tx}")
	[[ -n "${rx}" ]] && rx_formatted=$(format_net_value "${rx}")

    # création des chaines colorées et mise en page à afficher
	cpu_str="${colorcpu}${cpu_icon}${Reset}${cpu}%${spaceafter}"
	gpu_str="${colorgpu}${gpu_icon}${Reset}${gpu}%${spaceafter}"
	load_str="${colorload}${load_icon}${Reset}${load_pct}%${spaceafter}"
	mem_str="${colormem}${mem_icon}${Reset}${mem_pct}%${spaceafter}"
	tx_str="${colortx}${tx_icon}${Reset}${tx_formatted}${spaceafter}"
	rx_str="${colorrx}${rx_icon}${Reset}${rx_formatted}${spaceafter}"

	# affichage
	battery
	sensor
	echo -e "${cpu_str}${gpu_str}${load_str}${mem_str}${swap_str}${sensors_str}${batt_str}${tx_str}${rx_str}"
	return 0
}
#-------------------------------------------------------


########################################################################################################
# Corps du script                                                                                      #
########################################################################################################

#--- début GPU
gpu=''
[[ -f "${GPUpath}" ]] && gpu=$(cat "${GPUpath}")

#--- début Cpu
# méthode basée sur calcul kernel /proc/stat à 2 instants
read -r _ u n s i w ir si st _ _ _ < /proc/stat
pt=$((u+n+s+i+w+ir+si+st)); pi=$((i+w))


#---Charge
load=$(awk '{print $1}' /proc/loadavg) # charge 1 min
load_pct=$(awk "BEGIN {printf \"%.0f\", (${load} / $(nproc)) * 100}") || true # charge 1min / nb de processeurs * 100

#---Memory & swap
read -r mem_total mem_avail swap_total swap_avail < <(
    awk '/MemTotal/ {mem_total=$2}
         /MemAvailable/ {mem_avail=$2}
         /SwapTotal/ {swap_total=$2}
         /SwapFree/ {swap_avail=$2}
         END {print mem_total, mem_avail, swap_total, swap_avail}' /proc/meminfo
) || true
mem_pct=$(( (mem_total - mem_avail) * 100 / mem_total ))
swap_pct="na"
[[ ${swap_total} -gt 0 ]] && swap_pct=$(( (swap_total - swap_avail) * 100 / swap_total ))

#---Temperature
sensor=$(sensors 2>/dev/null | grep "${FiltreSensor}" || true)
sensor=$(echo "${sensor}" | grep -oP '\+\K[0-9]+' || true) # on filtre la sortie de sensors pour récupérer une température

#---Réseau
lan="$(ip route | awk '/^default/ {print $5}')" # on récupère l'interface de la route par défaut (wlan0, eth0, ...)
if [[ -n "${lan}" ]]; then
    net_rx1=$(cat "/sys/class/net/${lan}/statistics/rx_bytes" || true)
    net_tx1=$(cat "/sys/class/net/${lan}/statistics/tx_bytes" || true)
    sleep 0.5
    net_rx2=$(cat "/sys/class/net/${lan}/statistics/rx_bytes" || true)
    net_tx2=$(cat "/sys/class/net/${lan}/statistics/tx_bytes" || true)
    rx=$(( (net_rx2 - net_rx1) * 2 / 1024 ))
    tx=$(( (net_tx2 - net_tx1) * 2 / 1024 ))
else
	sleep 0.5
    rx=0
    tx=0
fi

#--- fin Cpu (on profite de la demi-seconde du réseau)
read -r _ u n s i w ir si st _ _ _ < /proc/stat
t=$((u+n+s+i+w+ir+si+st)); it=$((i+w))
if ((t-pt>0)); then
    cpu=$(awk "BEGIN {printf \"%.1f\", 100*(${t}-${pt}-${it}+${pi})/(${t}-${pt})}")
else
    cpu="0.0"
fi

#---Batt
dev_batt="$(upower -e | grep -i "${FiltreBatt}" || true)" # on récupère le device de la batterie
batt=""
if [[ -n "${dev_batt}" ]]; then  # on récupère la valeur de batterie restante sinon chaine vide.
	batt="$(upower -i "${dev_batt}" | grep percentage | grep -o "[0-9]*")"
	state="$(upower -i "${dev_batt}" | grep "state" | awk '{print $2}')"
fi

#----------------
define_default_colors
define_icons
display
#----------------
