#!/usr/bin/env bash
set -euo pipefail
args=${1:-}
read -r one five fifteen _ < /proc/loadavg

if [[ "${args}" = "" ]]; then
	awk -v one="${one}" -v five="${five}" -v fifteen="${fifteen}" \
	  'BEGIN {
	    oo1 = one / 12
	    oo5 = five / 12
	    oo15 = fifteen / 12
	    printf "   1min: %4.1f (%3.0f%%)    5min: %4.1f (%3.0f%%)    15min: %4.1f (%3.0f%%)\n", one, oo1*100, five, oo5*100, fifteen, oo15*100
	  }'
else
	awk -v one="${one}" -v five="${five}" -v fifteen="${fifteen}" \
	  'BEGIN {
	  	oo1 = one / 12
	    oo5 = five / 12
	    printf "󱇯  1min: %4.1f(%2.0f%%) 5min: %4.1f(%2.0f%%)\n", one, oo1*100, five, oo5*100
	  }'
fi
