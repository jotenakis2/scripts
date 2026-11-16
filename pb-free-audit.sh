#!/usr/bin/env bash
# shellcheck enable=all
# shellcheck shell=bash
# shellcheck disable=SC2310 # les fonctions d'assertion sont appelées dans des conditions
#
# pb-free-audit.sh — réaudite le paquet AUR protonmail-bridge-free après une
# montée de version.
#
# Ce paquet n'est pas un arbre forké : c'est le dépôt officiel Proton au tag
# annoncé, plus une poignée de patches. Tout le risque tient donc dans ces
# patches. Ce script les rejoue sur une copie propre de la source et refuse
# tout ce qui sort du périmètre attendu.
#
# Usage :
#   pb-free-audit.sh                 # paquet AUR au tag de son PKGBUILD
#   pb-free-audit.sh --tag v3.27.2   # forcer un tag
#   pb-free-audit.sh --dir /chemin   # PKGBUILD déjà téléchargé
#   pb-free-audit.sh --verbose
#
# Sortie : 0 = périmètre respecté, 1 = quelque chose est sorti du cadre.
# Dépendances : git, curl, patch, sha256sum, awk.

set -Eeuo pipefail

AUR_PKG=${AUR_PKG:-protonmail-bridge-free}
WORK=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/pb-free-audit}
TAG=${TAG:-}
DIR=${DIR:-}
VERBOSE=${VERBOSE:-0}
UPSTREAM=${UPSTREAM:-https://github.com/ProtonMail/proton-bridge}

# Fichiers que les patches du paquet ont le droit de modifier. Tout le reste
# est refusé : c'est le seul endroit où le paquet pourrait glisser du code.
ALLOW=${ALLOW:-'
internal/constants/
internal/frontend/bridge-gui/bridge-gui/main.cpp
internal/frontend/bridge-gui/BridgeSetup.cmake
'}

# Motifs interdits dans les fichiers Go modifiés. Les patches légitimes ne
# touchent que des constantes : ils n'exécutent rien et n'appellent personne.
FORBIDDEN=${FORBIDDEN:-'
os/exec
exec.Command
syscall.Exec
os.StartProcess
net.Dial
http.Post
crypto/tls
WriteFile
'} 

# Hôtes autorisés pour un appel réseau dans les fichiers modifiés.
ALLOWED_HOSTS=${ALLOWED_HOSTS:-'github.com raw.githubusercontent.com proton.me mail.proton.me mail-api.proton.me'}

fail=0
warn=0
note() { printf '%s\n' "$*"; }
ok() { printf '  ok    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; fail=$((fail + 1)); }
soft() { printf '  warn  %s\n' "$*"; warn=$((warn + 1)); }

die() { printf 'erreur : %s\n' "$*" >&2; exit 2; }

while (($# > 0)); do
    case $1 in
    --tag)
        TAG=${2:-}
        shift 2
        ;;
    --dir)
        DIR=${2:-}
        shift 2
        ;;
    --verbose | -v)
        VERBOSE=1
        shift
        ;;
    -h | --help)
        sed -n '3,20p' "$0"
        exit 0
        ;;
    *) die "option inconnue : $1" ;;
    esac
done

need() { command -v "$1" >/dev/null 2>&1 || die "commande absente : $1"; }
need git
need curl
need patch
need sha256sum

mkdir -p -- "$WORK"
cd -- "$WORK"

# ---------------------------------------------------------------- PKGBUILD
if [[ -z ${DIR} ]]; then
    note "récupération du paquet AUR ${AUR_PKG}"
    rm -rf -- "$WORK/aur"
    mkdir -p -- "$WORK/aur"
    curl -sSL -o "$WORK/aur.tar.gz" "https://aur.archlinux.org/cgit/aur.git/snapshot/${AUR_PKG}.tar.gz" ||
        die "téléchargement du paquet impossible"
    tar -xzf "$WORK/aur.tar.gz" -C "$WORK/aur" --strip-components=1 || die "archive illisible"
    DIR=$WORK/aur
fi
[[ -f $DIR/PKGBUILD ]] || die "PKGBUILD absent dans $DIR"
note "paquet : $DIR"

pkgver=$(sed -n 's/^pkgver=//p' "$DIR/PKGBUILD" | head -1)
[[ -n ${TAG} ]] || TAG="v${pkgver}"
note "version annoncée : ${pkgver} / tag ${TAG}"

# ------------------------------------------------------- patches et empreintes
mapfile -t sums < <(awk '/^sha256sums=\(/{f=1;next} f&&/^\)/{f=0} f' "$DIR/PKGBUILD" |
    grep -oE "[0-9a-f]{64}" || true)
note "empreintes déclarées : ${#sums[@]}"

mapfile -t patch_urls < <(grep -oE 'https://[^"'"'"' )]+\.patch' "$DIR/PKGBUILD" || true)
note "patches distants : ${#patch_urls[@]}"

work_patches=$WORK/patches
rm -rf -- "$work_patches"
mkdir -p -- "$work_patches"
ordered=()   # l'ordre du PKGBUILD est significatif : les patches se composent

in_sums() {
    local h=$1 s
    for s in "${sums[@]}"; do
        [[ $s == "$h" ]] && return 0
    done
    return 1
}

for url in "${patch_urls[@]}"; do
    name=$(basename -- "$url")
    curl -sSfL -o "$work_patches/$name" "$url" || {
        bad "téléchargement impossible : $url"
        continue
    }
    h=$(sha256sum "$work_patches/$name" | cut -d' ' -f1)
    if in_sums "$h"; then
        ok "empreinte conforme : $name"
    else
        bad "empreinte absente du PKGBUILD : $name ($h)"
    fi
    ordered+=("$work_patches/$name")
done

# patches locaux livrés avec le paquet
mapfile -t local_patches < <(find "$DIR" -maxdepth 1 -name '*.patch' -type f 2>/dev/null | sort || true)
for f in "${local_patches[@]+"${local_patches[@]}"}"; do
    h=$(sha256sum "$f" | cut -d' ' -f1)
    name=$(basename -- "$f")
    if in_sums "$h"; then
        ok "empreinte conforme (local) : $name"
    else
        bad "empreinte absente du PKGBUILD (local) : $name"
    fi
    cp -f -- "$f" "$work_patches/"
    ordered+=("$work_patches/$name")
done

((${#patch_urls[@]} + ${#local_patches[@]} > 0)) || die "aucun patch trouvé : paquet inattendu"

# ------------------------------------------------------------------- source
base=$WORK/src
pristine=$WORK/pristine
if [[ ! -d $pristine/.git ]]; then
    note "clonage de la source officielle au tag ${TAG}"
    rm -rf -- "$base" "$pristine"
    git clone --quiet --depth 1 --branch "$TAG" "$UPSTREAM" "$base" ||
        die "clonage impossible (tag ${TAG} inexistant ?)"
    cp -a -- "$base" "$pristine"
fi
head_sha=$(git -C "$pristine" rev-parse HEAD)
note "commit amont : ${head_sha}"

rm -rf -- "$base"
cp -a -- "$pristine" "$base"

# ------------------------------------------------------------------ patches
note "application des patches"
applied=0
for f in "${ordered[@]}"; do
    if (cd "$base" && patch -Np1 --quiet <"$f"); then
        applied=$((applied + 1))
    else
        bad "patch non applicable : $(basename -- "$f")"
    fi
done
note "patches appliqués : ${applied}/${#patch_urls[@]}+${#local_patches[@]}"

# -------------------------------------------------------------- périmètre
note "périmètre des modifications"
changed_raw=$(cd "$base" && git status --porcelain 2>/dev/null | awk '{print $2}' | grep -vE '\.(orig|rej)$' | sort || true)
mapfile -t changed <<<"${changed_raw}"
if ((${#changed[@]} == 0)); then
    bad "aucune modification : les patches n'ont rien changé ?"
fi

for f in "${changed[@]+"${changed[@]}"}"; do
    rel=${f#./}
    allowed=0
    while IFS= read -r pattern; do
        [[ -z $pattern ]] && continue
        if [[ $rel == "$pattern"* ]]; then
            allowed=1
            break
        fi
    done <<<"$ALLOW"
    if ((allowed)); then
        ok "dans le périmètre : $rel"
    else
        bad "HORS PÉRIMÈTRE : $rel"
    fi
done

# --------------------------------------------------- motifs interdits (Go)
note "recherche de motifs interdits dans les fichiers modifiés"
for f in "${changed[@]+"${changed[@]}"}"; do
    rel=${f#./}
    [[ $rel == *.go ]] || continue
    while IFS= read -r motif; do
        [[ -z $motif ]] && continue
        if grep -nF -- "$motif" "$base/$rel" >/dev/null 2>&1; then
            if grep -qF -- "$motif" "$pristine/$rel" 2>/dev/null; then
                ((VERBOSE)) && soft "déjà présent en amont : $motif ($rel)"
            else
                bad "motif interdit ajouté : $motif ($rel)"
            fi
        fi
    done <<<"$FORBIDDEN"
done

# ---------------------------------------------- appels réseau vers l'extérieur
note "appels réseau ajoutés"
while IFS= read -r url; do
    host=$(printf '%s' "$url" | sed -E 's#^[a-z]+://([^/]+).*#\1#')
    allowed=0
    for h in $ALLOWED_HOSTS; do
        [[ $host == "$h" ]] && allowed=1
    done
    if ((allowed)); then
        ok "hôte attendu : ${host}"
    else
        bad "hôte inattendu dans un appel réseau : ${host}"
    fi
done < <(diff -ruN "$pristine/internal/constants" "$base/internal/constants" 2>/dev/null |
    grep -E '^\+' | grep -v '^+++' |
    grep -vE '^\+\s*(//|#|\*|/\*)' |
    grep -ohE 'https?://[A-Za-z0-9._-]+[^"'"'"' ]*' || true)

# ------------------------------------------------------------------- verdict
printf '\n'
if ((fail == 0)); then
    note "VERDICT : périmètre respecté (${#changed[@]} fichier(s), ${applied} patch(es), ${warn} avertissement(s))."
    note "Rappel : cela ne blanchit pas l'usurpation d'identité côté Proton."
    exit 0
fi
note "VERDICT : ${fail} problème(s) — à lire avant d'installer."
exit 1
