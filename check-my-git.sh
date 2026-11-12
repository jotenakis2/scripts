#!/usr/bin/env bash
# shellcheck enable=all
#
# État de synchronisation des dépôts Git dans ~/Projects.
# Statuts : À_JOUR, EN_AVANCE, EN_RETARD, DIVERGÉ, MODIFIÉ, PAS_DE_DISTANT.

set -euo pipefail

PROJECTS_DIR="${HOME}/Projects"

if [[ ! -d "${PROJECTS_DIR}" ]]; then
    printf 'Erreur: le répertoire %s n'\''existe pas\n' "${PROJECTS_DIR}" >&2
    exit 1
fi

# Couleurs uniquement sur un terminal.
if [[ -t 1 ]]; then
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_RESET=$'\033[0m'
else
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_BLUE=''
    C_RESET=''
fi

# Les greffons tiers (zsh, node_modules…) ne sont pas des dépôts du projet :
# on élague ces répertoires pour ne pas polluer le tableau.
repos=()
while IFS= read -r -d '' gitdir; do
    repos+=("$(dirname "${gitdir}")")
done < <(find "${PROJECTS_DIR}" \
    \( -name '.local' -o -name 'node_modules' -o -name 'vendor' -o -name '.cache' \) -prune -o \
    -type d -name '.git' -print0 2>/dev/null || true)

if [[ ${#repos[@]} -eq 0 ]]; then
    printf 'Aucun dépôt Git trouvé dans %s\n' "${PROJECTS_DIR}"
    exit 0
fi

printf '%-47s %-18s %-12s %s\n' 'DÉPÔT' 'BRANCHE' 'STATUT' 'ÉTAT'
printf '%-47s %-18s %-12s %s\n' \
    '-----------------------------------------------' \
    '------------------' '------------' '-----------------------'

total=0
clean=0
dirty=0
behind=0
diverged=0

for repo in "${repos[@]}"; do
    total=$((total + 1))

    branch="$(git -C "${repo}" branch --show-current 2>/dev/null || true)"
    if [[ -z "${branch}" ]]; then
        printf '%-47s %-18s %-12s %s\n' "${repo}" '?' '?' 'SANS_BRANCHE'
        continue
    fi

    # Rafraîchir les refs distantes, avec un délai borné si possible.
    if git -C "${repo}" remote get-url origin >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 15 git -C "${repo}" fetch --quiet origin 2>/dev/null || true
        else
            git -C "${repo}" fetch --quiet origin 2>/dev/null || true
        fi
    fi

    if [[ -n "$(git -C "${repo}" status --porcelain 2>/dev/null || true)" ]]; then
        printf '%-47s %-18s %-12s %s\n' \
            "${repo}" "${branch}" "${C_YELLOW}MODIFIÉ${C_RESET}" 'AVEC_MODIFICATIONS_LOCAL'
        dirty=$((dirty + 1))
        continue
    fi

    upstream="$(git -C "${repo}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    if [[ -z "${upstream}" ]]; then
        printf '%-47s %-18s %-12s %s\n' \
            "${repo}" "${branch}" "${C_YELLOW}?${C_RESET}" 'PAS_DE_DISTANT'
        continue
    fi

    counts="$(git -C "${repo}" rev-list --left-right --count "HEAD...${upstream}" 2>/dev/null || true)"
    if [[ -z "${counts}" ]]; then
        printf '%-47s %-18s %-12s %s\n' \
            "${repo}" "${branch}" "${C_RED}?${C_RESET}" 'ERREUR_COMPARAISON'
        continue
    fi

    read -r ahead behind_count <<<"${counts}"

    if (( ahead == 0 && behind_count == 0 )); then
        printf '%-47s %-18s %-12s %s\n' \
            "${repo}" "${branch}" "${C_GREEN}=${C_RESET}" 'À_JOUR'
        clean=$((clean + 1))
    elif (( ahead > 0 && behind_count == 0 )); then
        printf '%-47s %-18s %-12s %s\n' \
            "${repo}" "${branch}" "${C_BLUE}↑${C_RESET}" "EN_AVANCE (+${ahead})"
    elif (( ahead == 0 && behind_count > 0 )); then
        printf '%-47s %-18s %-12s %s\n' \
            "${repo}" "${branch}" "${C_RED}↓${C_RESET}" "EN_RETARD (-${behind_count})"
        behind=$((behind + 1))
    else
        printf '%-47s %-18s %-12s %s\n' \
            "${repo}" "${branch}" "${C_RED}↕${C_RESET}" "DIVERGÉ (+${ahead}/-${behind_count})"
        diverged=$((diverged + 1))
    fi
done

printf '\n%d dépôt(s) : %d à jour, %d modifié(s), %d en retard, %d divergé(s)\n' \
    "${total}" "${clean}" "${dirty}" "${behind}" "${diverged}"
