#!/bin/bash
command -v tput &>/dev/null && [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] || tput() { true; }
clear 
BOLD=$(tput bold)
DIM=$(tput dim)
UNDERLINE=$(tput smul)
RESET=$(tput sgr0)

echo "NORMAL"
for i in $(seq 0 255); do
	COLOR=$(tput setaf "${i}")
    printf "${COLOR}%3d${RESET} " "${i}"
    (( (i+1) % 16 == 0 )) && echo
done
echo
echo "${BOLD}GRAS${RESET}"
for i in $(seq 0 255); do
	COLOR=$(tput setaf "${i}")
    printf "${BOLD}${COLOR}%3d${RESET} " "${i}"
    (( (i+1) % 16 == 0 )) && echo
done
echo
echo "${DIM}ATTÉNUÉ${RESET}"
for i in $(seq 0 255); do
	COLOR=$(tput setaf "${i}")
    printf "${DIM}${COLOR}%3d${RESET} " "${i}"
    (( (i+1) % 16 == 0 )) && echo
done
echo
echo "${UNDERLINE}SOULIGNÉ${RESET}"
for i in $(seq 0 255); do
	COLOR=$(tput setaf "${i}")
    printf "${UNDERLINE}${COLOR}%3d${RESET} " "${i}"
    (( (i+1) % 16 == 0 )) && echo
done
