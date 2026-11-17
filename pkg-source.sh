#!/usr/bin/env bash
# shellcheck enable=all
# shellcheck shell=bash
#
# pkg-source.sh — d'où vient chaque paquet installé sur cette machine ?
#
# pacman ne stocke pas le dépôt d'origine d'un paquet installé : `expac %r`
# répond « local » pour tout. La seule façon fiable est de confronter la liste
# des installés aux bases de synchronisation : présent dans core/extra/multilib
# = officiel (et l'on sait lequel), absent de toutes = étranger (AUR, paquet
# construit à la main, dépôt tiers).
#
# Usage :
#   pkg-source.sh                 résumé par source
#   pkg-source.sh --list          chaque paquet et sa source
#   pkg-source.sh --aur           seulement les paquets étrangers
#   pkg-source.sh --repo extra    seulement un dépôt
#   pkg-source.sh --explicit      seulement les paquets installés exprès
#   pkg-source.sh --json          sortie JSON
#
# Codes de sortie : 0 ok, 2 usage.

set -Eeuo pipefail

FORMAT=summary
FILTER_REPO=''
EXPLICIT_ONLY=0

usage() {
    sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
}

while (($# > 0)); do
    case $1 in
    --list)
        FORMAT=list
        shift
        ;;
    --aur | --foreign)
        FORMAT=list
        FILTER_REPO=local
        shift
        ;;
    --repo)
        FORMAT=list
        FILTER_REPO=${2:-}
        [[ -n $FILTER_REPO ]] || {
            printf '--repo attend un nom de dépôt\n' >&2
            exit 2
        }
        shift 2
        ;;
    --explicit)
        EXPLICIT_ONLY=1
        shift
        ;;
    --json)
        FORMAT=json
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        printf 'option inconnue : %s\n' "$1" >&2
        exit 2
        ;;
    esac
done

command -v pacman >/dev/null 2>&1 || {
    printf 'pacman est absent : machine non Arch ?\n' >&2
    exit 2
}

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

# 1. base installée : nom → (explicite|dépendance)
if ((EXPLICIT_ONLY)); then
    pacman -Qeq | sort >"$tmp/installed"
else
    pacman -Qq | sort >"$tmp/installed"
fi
pacman -Qeq | sort >"$tmp/explicit"

# 2. dépôt de chaque nom, d'après les bases de synchronisation. `pacman -Sl`
#    imprime « dépôt nom version » ; plusieurs dépôts peuvent proposer le même
#    nom, on garde le premier vu dans l'ordre de priorité de pacman.
pacman -Sl 2>/dev/null | awk '{ if (!seen[$2]++) print $2, $1 }' | sort >"$tmp/repos"

# 3. jointure : installé + dépôt, « local » si absent de toutes les bases
awk 'NR == FNR { repo[$1] = $2; next }
     { print $1, (($1 in repo) ? repo[$1] : "local") }' \
    "$tmp/repos" "$tmp/installed" >"$tmp/pairs"

# 4. marque les paquets installés explicitement
awk 'NR == FNR { ex[$1] = 1; next }
     { print $1, $2, (($1 in ex) ? "1" : "0") }' "$tmp/explicit" "$tmp/pairs" >"$tmp/final"
sort -k2,2 -k1,1 "$tmp/final" -o "$tmp/final"

filter() {
    if [[ -n ${FILTER_REPO} ]]; then
        awk -v r="${FILTER_REPO}" '$2 == r' "$tmp/final"
    else
        cat "$tmp/final"
    fi
}

case ${FORMAT} in
summary)
    printf '%-14s %8s %10s\n' "SOURCE" "PAQUETS" "EXPLICITES"
    printf '%-14s %8s %10s\n' "──────────────" "────────" "──────────"
    filter | awk '{ n[$2]++; if ($3 == 1) e[$2]++ }
        END { for (r in n) printf "%-14s %8d %10d\n", r, n[r], e[r] + 0 }' |
        sort -k2,2nr
    printf '\n'
    filter | awk '{ n[$2]++ } END { t = 0; for (r in n) t += n[r]; printf "total : %d paquet(s)\n", t }'
    ;;
list)
    filter | awk '{ printf "%-42s %s\n", $1, $2 }'
    ;;
json)
    filter | awk '{ printf "{\"name\": \"%s\", \"source\": \"%s\", \"explicit\": %s}\n", $1, $2, ($3 == 1 ? "true" : "false") }' |
        awk 'BEGIN { printf "[\n" } { if (NR > 1) printf ",\n"; printf "%s", $0 } END { printf "\n]\n" }'
    ;;
*)
    printf 'format inconnu : %s\n' "${FORMAT}" >&2
    exit 2
    ;;
esac
