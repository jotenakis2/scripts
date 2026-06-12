#!/usr/bin/env bash
linux=$(find /boot/vmlinuz*cachy* 2>/dev/null | sort -V | tail -1) || true
if [[ -n "${linux}" ]]; then
	echo "Noyau cachyos : ${linux}"
	if command -v grubby &>/dev/null; then
		sudo grubby --set-default="${linux}"
	else
		echo "grubby not found"
		exit 1
	fi
else
	echo "aucun noyau cachyos détecté"
fi
