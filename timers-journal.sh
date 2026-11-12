#!/usr/bin/env bash
# shellcheck enable=all
#
# timers-journal.sh — liste les timers systemd de l'utilisateur courant et
# affiche, pour chaque service déclenché, le journal du boot en cours.
#
# Usage : timers-journal.sh [-a] [-n LIGNES] [-h]

set -euo pipefail

readonly PROG="${0##*/}"

usage() {
  cat <<EOF
Usage : ${PROG} [-a] [-n LIGNES] [-t] [-h]

Liste les timers systemd --user et affiche le journal (boot en cours) du
service associé à chacun.

Options :
  -a          inclure les timers inactifs (équivalent de list-timers --all)
  -n LIGNES   ne montrer que les N dernières lignes de journal par service
  -t          inclure les timers transitoires (podman healthcheck, systemd-run…)
  -h          afficher cette aide
EOF
}

# --- Couleurs ---------------------------------------------------------------

if command -v tput >/dev/null 2>&1 && [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  BOLD="$(tput bold)"
  DIM="$(tput dim)"
  RED="$(tput setaf 1)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"
  RESET="$(tput sgr0)"
else
  BOLD='' DIM='' RED='' GREEN='' YELLOW='' BLUE='' RESET=''
fi

# --- Options ----------------------------------------------------------------

opt_all=0
opt_lines=0
opt_transient=0

while getopts ':ahn:t' opt; do
  case "${opt}" in
    a) opt_all=1 ;;
    n)
      if [[ ! "${OPTARG}" =~ ^[0-9]+$ ]]; then
        printf '%s: -n attend un entier positif (reçu : %s)\n' "${PROG}" "${OPTARG}" >&2
        exit 2
      fi
      opt_lines="${OPTARG}"
      ;;
    t) opt_transient=1 ;;
    h)
      usage
      exit 0
      ;;
    :)
      printf "%s: l'option -%s attend un argument\n" "${PROG}" "${OPTARG}" >&2
      usage >&2
      exit 2
      ;;
    \?)
      printf '%s: option inconnue -%s\n' "${PROG}" "${OPTARG}" >&2
      usage >&2
      exit 2
      ;;
    *)
      printf '%s: option inattendue -%s\n' "${PROG}" "${opt}" >&2
      usage >&2
      exit 2
      ;;
  esac
done
shift $((OPTIND - 1))

# --- Timers -----------------------------------------------------------------

lt_args=(--user list-timers --no-legend --no-pager --output=json)
if [[ "${opt_all}" -eq 1 ]]; then
  lt_args+=(--all)
fi

if ! listing="$(systemctl "${lt_args[@]}")"; then
  printf '%s: impossible de lister les timers systemd --user\n' "${PROG}" >&2
  exit 1
fi

if [[ -z "${listing}" || "${listing}" == '[]' ]]; then
  printf '%sAucun timer systemd --user trouvé.%s\n' "${YELLOW}" "${RESET}"
  exit 0
fi

if ! rows="$(jq -r '.[] | [.unit, .activates, (.next // 0), (.last // 0)] | @tsv' <<<"${listing}")"; then
  printf '%s: sortie JSON de list-timers illisible\n' "${PROG}" >&2
  exit 1
fi

if [[ -z "${rows}" ]]; then
  printf '%sAucun timer systemd --user trouvé.%s\n' "${YELLOW}" "${RESET}"
  exit 0
fi

# Convertit un horodatage en µs depuis l'époque en date lisible.
format_usec() {
  local usec="${1}"
  local secs=$((usec / 1000000))
  date -d "@${secs}" '+%a %Y-%m-%d %H:%M:%S %Z'
}

# --- Affichage --------------------------------------------------------------

while IFS=$'\t' read -r timer service next_us last_us; do
  [[ -n "${timer}" ]] || continue
  [[ -n "${service}" ]] || service="${timer%.timer}.service"

  raw="$(systemctl --user show "${timer}" -p ActiveState -p SubState -p Transient)"
  state=''
  substate=''
  transient='no'
  while IFS='=' read -r key value; do
    case "${key}" in
      ActiveState) state="${value}" ;;
      SubState) substate="${value}" ;;
      Transient) transient="${value}" ;;
      *) ;;
    esac
  done <<<"${raw}"
  [[ -n "${state}" ]] || state='unknown'

  # Les timers transitoires (podman healthcheck, systemd-run --user…) sont
  # écartés par défaut : ils sont recréés à chaque exécution.
  if [[ "${transient}" == 'yes' ]] && [[ "${opt_transient}" -eq 0 ]]; then
    continue
  fi

  description="$(systemctl --user show --value -p Description "${service}")"
  if [[ "${#description}" -gt 100 ]]; then
    description="${description:0:97}…"
  fi

  if [[ "${next_us}" =~ ^[0-9]+$ ]] && [[ "${next_us}" != '0' ]]; then
    next="$(format_usec "${next_us}")"
  else
    next='—'
  fi
  if [[ "${last_us}" =~ ^[0-9]+$ ]] && [[ "${last_us}" != '0' ]]; then
    last="$(format_usec "${last_us}")"
  else
    last='—'
  fi

  color="${GREEN}"
  if [[ "${state}" != 'active' ]]; then
    color="${RED}"
  fi

  printf '\n%s════════════════════════════════════════════════════════════════════%s\n' \
    "${BOLD}${BLUE}" "${RESET}"
  printf '%s%s%s\n' "${BOLD}${BLUE}" "${timer}" "${RESET}"
  printf '  %s→%s %s%s%s (%s%s%s)\n' \
    "${DIM}" "${RESET}" "${BOLD}" "${service}" "${RESET}" \
    "${color}" "${state}${substate:+ / ${substate}}" "${RESET}"
  if [[ -n "${description}" ]]; then
    printf '  %s%s%s\n' "${DIM}" "${description}" "${RESET}"
  fi
  printf '  %sprochain :%s %s\n' "${DIM}" "${RESET}" "${next}"
  printf '  %sdernier  :%s %s\n' "${DIM}" "${RESET}" "${last}"
  printf '  %sjournal (boot courant) :%s\n' "${DIM}${color}" "${RESET}"

  jargs=(--user --boot=0 --no-pager --quiet --unit="${service}")
  if [[ "${opt_lines}" -gt 0 ]]; then
    jargs+=(--lines="${opt_lines}")
  fi

  if ! output="$(journalctl "${jargs[@]}")"; then
    printf '  %sERREUR%s : journalctl a échoué pour %s\n' "${RED}" "${RESET}" "${service}"
    continue
  fi

  if [[ -z "${output}" ]]; then
    printf '  %s(aucune entrée pour ce boot)%s\n' "${DIM}" "${RESET}"
  else
    printf '%s\n' "${output}" | sed 's/^/  /'
  fi
done <<<"${rows}"

printf '\n'
