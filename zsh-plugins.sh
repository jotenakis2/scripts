#!/usr/bin/env bash
# shellcheck enable=all
#
# zsh-plugins.sh — clone and update the zsh plugins used by ~/.config/zsh.
#
# There is no plugin manager: .zshrc sources these git checkouts directly
# (zsh-defer) and adds the completions directory to fpath. This script is the
# only place that touches the network.
#
# Usage:
#   zsh-plugins.sh install   clone what is missing (fresh machine)
#   zsh-plugins.sh update    pull every checkout (default)
#   zsh-plugins.sh status    show each checkout's version and state

set -euo pipefail

readonly PROG="${0##*/}"
readonly DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/zsh"
readonly REPO_DIR="${DATA_DIR}/repos/github.com"

# owner/repo — zsh-defer and the completions are loaded at startup, the other
# two are loaded from the deferred bundle
readonly PLUGINS=(
  "romkatv/zsh-defer"
  "zsh-users/zsh-completions"
  "Aloxaf/fzf-tab"
  "zsh-users/zsh-autosuggestions"
)

die() {
  printf 'Erreur : %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage : %s [install|update|status]\n\n' "${PROG}"
  printf '  install  clone les plugins manquants\n'
  printf '  update   met à jour les dépôts (défaut)\n'
  printf '  status   affiche l état de chaque dépôt\n'
}

command -v git >/dev/null 2>&1 || die "git introuvable dans le PATH"

action="${1:-update}"
case "${action}" in
  -h | --help | help) usage; exit 0 ;;
  install | update | status) ;;
  *) die "action inconnue : ${action} (voir --help)" ;;
esac

mkdir -p "${REPO_DIR}"

clone_or_pull() {
  local slug="$1" path="${REPO_DIR}/$1" url="https://github.com/$1"
  if [[ -d ${path}/.git ]]; then
    if [[ ${action} == install ]]; then
      printf '  %-28s déjà présent\n' "${slug}"
      return 0
    fi
    if [[ ${action} == status ]]; then
      local head date
      head=$(git -C "${path}" rev-parse --short HEAD)
      date=$(git -C "${path}" log -1 --format=%cs)
      printf '  %-28s %s (%s)\n' "${slug}" "${head}" "${date}"
      return 0
    fi
    if git -C "${path}" pull --ff-only --quiet; then
      local head
      head=$(git -C "${path}" rev-parse --short HEAD)
      printf '  %-28s à jour (%s)\n' "${slug}" "${head}"
    else
      printf '  %-28s ÉCHEC du pull (dépôt modifié ?)\n' "${slug}" >&2
      return 1
    fi
  elif [[ ${action} == status ]]; then
    printf '  %-28s absent\n' "${slug}"
  else
    printf '  %-28s clone…\n' "${slug}"
    git clone --depth 1 --quiet "${url}" "${path}"
    printf '  %-28s cloné\n' "${slug}"
  fi
}

printf 'dépôts : %s\n\n' "${REPO_DIR}"
for plugin in "${PLUGINS[@]}"; do
  clone_or_pull "${plugin}"
done

if [[ ${action} != status ]]; then
  # the completion dump was built from the previous checkout state: drop it so
  # the next shell rebuilds it (compinit TTL would otherwise keep it for 2 days)
  zdotdir="${ZDOTDIR:-${HOME}/.config/zsh}"
  rm -f "${zdotdir}/zcompdump" "${zdotdir}/zcompdump.zwc"
  printf '\nCache de complétions invalidé. Ouvre un nouveau shell zsh.\n'
fi
