#!/bin/bash
# Script : état de synchronisation des dépôts Git dans ~/Projects
# Statuts : À_JOUR, EN_AVANCE, EN_RETARD, AVEC_MODIFICATIONS_LOCAL

set -euo pipefail

PROJECTS_DIR="${HOME}/Projects"

if [[ ! -d "${PROJECTS_DIR}" ]]; then
    echo "Erreur: le répertoire ${PROJECTS_DIR} n'existe pas" >&2
    exit 1
fi

# Trouver tous les dépôts Git
repos=()
while IFS= read -r -d '' gitdir; do
    repos+=("$(dirname "${gitdir}")")
done < <(find "${PROJECTS_DIR}" -type d -name ".git" -print0 2>/dev/null)

if [[ ${#repos[@]} -eq 0 ]]; then
    echo "Aucun dépôt Git trouvé dans ${PROJECTS_DIR}"
    exit 0
fi

printf "%-47s %-15s %-10s %s\n" "DÉPÔT" "BRANCHE" "STATUT" "ÉTAT"
printf "%-45s %-15s %-10s %s\n" "---------------------------------------------" "---------------" "----------" "----"

for repo in "${repos[@]}"; do
    # Obtenir la branche courante
    branch=$(git -C "${repo}" branch --show-current)
    
    if [[ -z "${branch}" ]]; then
        printf "%-45s %-15s %-10s %s\n" "${repo}" "?" "?" "SANS_BRANCHE"
        continue
    fi
    
    # Rafraîchir les refs distantes
    git -C "${repo}" fetch --quiet origin 2>/dev/null || true
    
    # Vérifier s'il y a des modifications locales non commitées
    if [[ -n "$(git -C "${repo}" status --porcelain)" ]]; then
        printf "%-45s %-15s %-11s %s\n" "${repo}" "${branch}" "MODIFIÉ" "AVEC_MODIFICATIONS_LOCAL"
        continue
    fi
    
    # Obtenir les commits
    remote_commit=""
    remote_commit=$(git -C "${repo}" rev-parse "origin/${branch}" 2>/dev/null) || remote_commit=""
    
    if [[ -z "${remote_commit}" ]]; then
        printf "%-45s %-15s %-10s %s\n" "${repo}" "${branch}" "?" "PAS_DE_DISTANT"
        continue
    fi
    
    local_head=$(git -C "${repo}" rev-parse "${branch}")
    
    if [[ "${local_head}" == "${remote_commit}" ]]; then
        printf "%-45s %-15s %-10s %s\n" "${repo}" "${branch}" "=" "À_JOUR"
    elif git -C "${repo}" merge-base --always "${local_head}" "${remote_commit}" | grep -q "${local_head}"; then
        printf "%-45s %-15s %-10s %s\n" "${repo}" "${branch}" "↑" "EN_AVANCE"
    else
        printf "%-45s %-15s %-10s %s\n" "${repo}" "${branch}" "↓" "EN_RETARD"
    fi
done
