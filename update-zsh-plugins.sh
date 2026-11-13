#!/usr/bin/env bash
# shellcheck enable=all
#
# update-zsh-plugins.sh — clone and update the zsh plugins declared in
# plugins.toml (sheldon), then invalidate the init cache so the next shell
# reloads them.
#
# zsh no longer calls sheldon at startup: .zshrc sources the checkouts directly
# (zsh-defer, completions) and only falls back to `sheldon source` when they are
# missing. Updating plugins is therefore a maintenance step, run from here.

set -euo pipefail

readonly PROG="${0##*/}"
readonly DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/zsh"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/zsh/sheldon"
readonly CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/zsh/initcache"

export SHELDON_DATA_DIR="${DATA_DIR}"
export SHELDON_CONFIG_DIR="${CONFIG_DIR}"
export SHELDON_CONFIG_FILE="${CONFIG_DIR}/plugins.toml"

die() {
  printf 'Erreur : %s\n' "$*" >&2
  exit 1
}

command -v sheldon >/dev/null 2>&1 || die "sheldon introuvable dans le PATH"
[[ -f ${SHELDON_CONFIG_FILE} ]] || die "plugins.toml introuvable : ${SHELDON_CONFIG_FILE}"

printf 'plugins   : %s\n' "${SHELDON_CONFIG_FILE}"
printf 'checkouts : %s\n' "${SHELDON_DATA_DIR}/repos"

if (($#)); then
  case "$1" in
    -h | --help)
      printf 'Usage : %s\n\nClone/actualise les plugins déclarés dans plugins.toml,\n' "${PROG}"
      printf "puis invalide le cache d'init de zsh.\n"
      exit 0
      ;;
    *)
      die "option inconnue : $1 (voir --help)"
      ;;
  esac
fi

sheldon lock --update

# The cached `sheldon source` output and the completion dump no longer match the
# checkouts: drop them, the next shell rebuilds both.
rm -f "${CACHE_DIR}/sheldon.zsh" "${CACHE_DIR}/sheldon.zsh.zwc"
printf 'cache     : invalidé (%s/sheldon.zsh)\n' "${CACHE_DIR}"
printf '\nTerminé. Ouvre un nouveau shell zsh pour charger les plugins à jour.\n'
