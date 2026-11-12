#!/usr/bin/env bash
# shellcheck enable=all
#
# Tableau des principales cryptomonnaies via l'API CoinGecko.
# Dépendances : gum, curl, jq, awk.

set -euo pipefail
export LC_NUMERIC=C

for cmd in gum curl jq awk; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf 'Dépendance manquante : %s\n' "${cmd}" >&2
    exit 1
  fi
done

API_BASE='https://api.coingecko.com/api/v3'

# Couleurs gum
NoirGum=0
VertGum=2
JauneGum=3
BleuGum=4
BlancGum=7

export GUM_CONFIRM_SELECTED_BACKGROUND="${VertGum}"
export GUM_CONFIRM_SELECTED_FOREGROUND="${NoirGum}"
export GUM_CONFIRM_UNSELECTED_BACKGROUND="${NoirGum}"
export GUM_CONFIRM_UNSELECTED_FOREGROUND="${BlancGum}"
export GUM_CONFIRM_SHOW_HELP=false
export GUM_CHOOSE_SHOW_HELP=false
export GUM_INPUT_SHOW_HELP=false

# Demander le nombre de cryptos à afficher.
gum style --border rounded --padding '0 1' --border-foreground "${BleuGum}" 'Combien de cryptos afficher ?'
NB_CRYPTOS="$(gum choose --cursor.foreground="${BleuGum}" --header.foreground="${BleuGum}" --show-help=false --header 'Choix ?' '10' '20' '30' '40' '50' '100' '200' || true)"

if [[ -z "${NB_CRYPTOS}" ]]; then
  printf 'Annulé\n'
  exit 0
fi

if [[ ! "${NB_CRYPTOS}" =~ ^[0-9]+$ ]]; then
  printf 'Choix invalide : %s\n' "${NB_CRYPTOS}" >&2
  exit 1
fi

clear 2>/dev/null || true
gum style --border double --padding '1 2' --border-foreground "${VertGum}" --foreground "${JauneGum}" --align center " 󰠓 Top ${NB_CRYPTOS} Cryptos - Market Data 󰡪 "

# Récupération des données.
DATA="$(curl --fail --silent --show-error --max-time 20 \
  "${API_BASE}/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=250&page=1&sparkline=false&price_change_percentage=1h,24h,7d,14d,30d,200d,1y")" || {
  printf 'Erreur : impossible de récupérer les données CoinGecko.\n' >&2
  exit 1
}

if ! jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"${DATA}"; then
  printf 'Erreur : réponse CoinGecko invalide.\n' >&2
  exit 1
fi

# En-tête du tableau avec séparateurs.
printf '\n'
printf "\033[36m\033[1m%-5s\033[90m│\033[36m%-9s\033[90m│\033[36m%12s\033[90m│\033[36m%11s\033[90m│\033[36m%11s\033[90m│\033[36m%11s\033[90m│\033[36m%11s\033[90m│\033[36m%11s\033[90m│\033[36m%11s\033[90m│\033[36m%11s\033[90m│\033[36m%11s\033[90m│\033[36m%-9s\033[90m│\033[36m%-6s\033[0m\n" \
  'Rank' 'Crypto' 'Prix USD' 'MCap (B)' '1h %' '24h %' '7d %' '14d %' '30d %' '200d %' '1y %' 'Crypto' 'Link'
printf '\033[90m%s\033[0m\n' '─────┼─────────┼────────────┼───────────┼───────────┼───────────┼───────────┼───────────┼───────────┼───────────┼───────────┼─────────┼──────'

color_pct() {
  local val="${1}"
  if [[ "${val}" == 'null' || -z "${val}" ]]; then
    printf '%11s' 'N/A'
    return 0
  fi

  local formatted
  formatted="$(awk -v v="${val}" 'BEGIN { printf "%9.1f%%", v }')"

  if awk -v v="${val}" 'BEGIN { exit !(v >= 0) }'; then
    printf '\033[32m%11s\033[0m' "${formatted}"
  else
    printf '\033[31m%11s\033[0m' "${formatted}"
  fi
}

color_price() {
  local price="${1}"
  local pct24h="${2}"

  if [[ "${pct24h}" == 'null' || -z "${pct24h}" ]]; then
    printf '%12s' "${price}"
  elif awk -v v="${pct24h}" 'BEGIN { exit !(v > 0) }'; then
    printf '\033[32m%12s\033[0m' "${price}"
  elif awk -v v="${pct24h}" 'BEGIN { exit !(v < 0) }'; then
    printf '\033[31m%12s\033[0m' "${price}"
  else
    printf '%12s' "${price}"
  fi
}

make_link() {
  local url="${1}"
  local text="${2}"
  # shellcheck disable=SC1003 # la séquence ESC \ est volontaire (OSC 8)
  printf '\033]8;;%s\033\\%s\033]8;;\033\\' "${url}" "${text}"
}

format_price() {
  local price="${1}"
  if [[ "${price}" == 'null' || -z "${price}" ]]; then
    printf 'N/A'
  elif awk -v p="${price}" 'BEGIN { exit !(p < 1) }'; then
    awk -v p="${price}" 'BEGIN { printf "%.6f", p }'
  elif awk -v p="${price}" 'BEGIN { exit !(p < 100) }'; then
    awk -v p="${price}" 'BEGIN { printf "%.2f", p }'
  else
    awk -v p="${price}" 'BEGIN { printf "%.0f", p }'
  fi
}

# Filtrage : stablecoins USD, wrapped, staking, bridged, RWA tokens.
FILTER='usdt|gho|jtrsy|eurcv|nusd|pc0000023|pc0000031|fdit|reusd|ustbl|apxusd|frxusd|币安人生|avusd|usd0|cash|pusd|usdc|usde|usd1|usdf|usdg|busd|dai|usdd|tusd|usdp|gusd|usds|pyusd|fdusd|frax|buidl|bnsol|rlusd|bfusd|^w[a-z]|^st[a-z]|^cb[a-z]|^r[a-z]eth|weeth|wbeth|^wbt|bsc-usd|^e[a-z]eth|^sa[a-z]|^aeth|figr|heloc|_usd|^susd|jitosol|^m$'

count=0
declare -A seen_symbols=()

while IFS=$'\t' read -r rank coin_id symbol price mcap pct1h pct24h pct7d pct14d pct30d pct200d pct1y; do
  if grep -qiE -- "${FILTER}" <<<"${symbol}"; then
    continue
  fi

  symbol_upper="${symbol^^}"
  if [[ -n "${seen_symbols[${symbol_upper}]:-}" ]]; then
    continue
  fi
  seen_symbols["${symbol_upper}"]=1

  count=$((count + 1))
  if (( count > NB_CRYPTOS )); then
    break
  fi

  mcap_b="$(awk -v m="${mcap}" 'BEGIN { printf "%.2f", m / 1000000000 }')"
  price_fmt="$(format_price "${price}")"
  coingecko_url="https://www.coingecko.com/en/coins/${coin_id}"
  link="$(make_link "${coingecko_url}" '🔗')"

  printf '%-5s\033[90m│\033[33m%-9s\033[90m│\033[0m' "${rank}" "${symbol_upper}"
  color_price "\$${price_fmt}" "${pct24h}"
  printf '\033[90m│\033[0m%11s\033[90m│\033[0m' "\$${mcap_b}"

  color_pct "${pct1h}"
  printf '\033[90m│\033[0m'
  color_pct "${pct24h}"
  printf '\033[90m│\033[0m'
  color_pct "${pct7d}"
  printf '\033[90m│\033[0m'
  color_pct "${pct14d}"
  printf '\033[90m│\033[0m'
  color_pct "${pct30d}"
  printf '\033[90m│\033[0m'
  color_pct "${pct200d}"
  printf '\033[90m│\033[0m'
  color_pct "${pct1y}"
  printf '\033[90m│\033[33m%-9s\033[90m│\033[34m%s\033[0m\n' "${symbol_upper}" "${link}"
done < <(jq -r '.[] | [
    .market_cap_rank,
    .id,
    .symbol,
    .current_price,
    .market_cap,
    .price_change_percentage_1h_in_currency,
    .price_change_percentage_24h_in_currency,
    .price_change_percentage_7d_in_currency,
    .price_change_percentage_14d_in_currency,
    .price_change_percentage_30d_in_currency,
    .price_change_percentage_200d_in_currency,
    .price_change_percentage_1y_in_currency
] | @tsv' <<<"${DATA}" || true)

printf '\n'
now="$(date '+%Y-%m-%d %H:%M:%S')"
printf '\033[90mDernière mise à jour: %s\033[0m\n' "${now}"
printf '\n'
