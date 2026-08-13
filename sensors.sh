#!/usr/bin/env bash
Rouge=$'\033[0;31m'
Noir=$'\033[0;30m'
Vert=$'\033[0;32m'
Jaune=$'\033[0;33m'
Bleu=$'\033[0;34m'
Magenta=$'\033[0;35m'
Cyan=$'\033[0;36m'
Reset=$'\033[0m'
GPU='amdgpu-pci-0500' BAT='BAT0-acpi-0' WIFI='ath11k_hwmon-pci-0200'
CPU='k10temp-pci-00c3' NVME='nvme-pci-0400'
dir="${HOME}/.cache/sensors"
GPUfile="${dir}/gpu" BATfile="${dir}/bat" WIFIfile="${dir}/wifi"
CPUfile="${dir}/cpu" NVMEfile="${dir}/nvme" 
readonly Rouge Noir Vert Jaune Bleu Magenta Cyan Reset 
readonly GPU CPU BAT WIFI NVME dir
readonly GPUfile CPUfile BATfile WIFIfile NVMEfile

#-------------------------------------------------------------------------------------------------------------------------------------------------
CLEANUP() {
    printf '\033[?25h\033[?1049l\033[H\033[2J'
    echo -e "\n 󱠢  Au revoir..."
    exit 0
}
#-------------------------------------------------------------------------------------------------------------------------------------------------
get_status() {
    local val num icon color
    val=$(echo "$1" | sed 's/^+//;s/°C/°C/' | sed 's/\ //g' || true)
	num="${val//[^0-9.]/}"
    icon="" 
    color="\033[92m"
    if awk "BEGIN {exit !(${num} > 60)}"; then readonly icon=""; color="\033[91m\033[1m"
    elif awk "BEGIN {exit !(${num} > 55)}"; then readonly icon=""; color="\033[93m"; fi
    printf "${color}%-8s${icon} %s\033[0m\n" "$2" "${val}"
    return 0
}
#-------------------------------------------------------------------------------------------------------------------------------------------------

echo -en "${Rouge} ${Vert} ${Noir} ${Jaune} ${Bleu} ${Magenta} ${Cyan} ${Reset}"
mkdir -p "${dir}"
printf '\033[?25l\033[?1049h\033[H\033[2J'

trap CLEANUP INT TERM
while true; do
	sensors "${GPU}" > "${GPUfile}"
	sensors "${BAT}" > "${BATfile}"
	sensors "${WIFI}" > "${WIFIfile}"
	sensors "${CPU}" > "${CPUfile}"
	sensors "${NVME}" > "${NVMEfile}" 

	echo -en "${Jaune}"
	echo "╔════════════════════════════════╗"
	echo "║ 📊 Sensors HP EliteBook 645 G9 ║"
	echo "╚════════════════════════════════╝"
	echo -en "${Reset}"

	cpu_temp=$(grep -i tctl "${CPUfile}" | awk '{print $2}' || true) 
	get_status "${cpu_temp}" " C"
	gpu_temp=$(grep edge "${GPUfile}" | awk '{print $2}' || true)
	get_status "${gpu_temp}" " G"
	nvme_temp=$(grep 'Sensor 2' "${NVMEfile}" | head -1 | awk '{print $3}' || true)
	get_status "${nvme_temp}" "  "
	wifi_temp=$(grep temp "${WIFIfile}" | awk '{print $2}' || true)
	get_status "${wifi_temp}" "  "
	sleep 1
	printf '\033[H' #\033[2J'
done

#-------------------------------------------------------------------------------------------------------------------------------------------------

