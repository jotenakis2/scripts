#!/usr/bin/env bash
# shellcheck enable=all
#
# Test de fuite DNS via bash.ws.

set -euo pipefail

RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'
api_domain='bash.ws'

echo_bold() {
    printf '%b%s%b\n' "${BOLD}" "${1}" "${NC}"
}

echo_error() {
    printf '%b%s%b\n' "${RED}" "${1}" "${NC}" >&2
}

require_cmd() {
    if ! command -v "${1}" >/dev/null 2>&1; then
        echo_error "Please, install \"${1}\""
        exit 1
    fi
}

check_internet_connection() {
    if ! curl --silent --head --fail --max-time 10 "https://${api_domain}" >/dev/null; then
        echo_error 'No internet connection.'
        exit 1
    fi
}

print_servers() {
    local type="${1}"
    jq --monochrome-output --raw-output --arg type "${type}" '
        .[] | select(.type == $type) |
        "\(.ip)\(if .country_name != "" and .country_name != false then " [\(.country_name)\(if .asn != "" and .asn != false then " \(.asn)" else "" end)]" else "" end)"
    ' <<<"${result_json}"
}

# MAIN
require_cmd curl
require_cmd shuf
require_cmd jq
require_cmd ping
check_internet_connection

id="$(shuf -i 1000000-9999999 -n 1)"

for i in $(seq 1 10); do
    ping -c 1 "${i}.${id}.${api_domain}" >/dev/null 2>&1 || true
done

result_json="$(curl --silent --fail --show-error --max-time 20 "https://${api_domain}/dnsleak/test/${id}?json")" || {
    echo_error 'Impossible de récupérer le résultat du test DNS.'
    exit 1
}

if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"${result_json}"; then
    echo_error 'Réponse JSON invalide.'
    exit 1
fi

dns_count="$(jq '[.[] | select(.type == "dns")] | length' <<<"${result_json}")"

if [[ "${dns_count}" -eq 0 ]]; then
    echo_bold 'No DNS servers found'
else
    echo_bold 'DNS servers used'
    print_servers 'dns'
fi

exit 0
