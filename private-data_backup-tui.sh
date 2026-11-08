#!/usr/bin/env bash
# shellcheck enable=all
# =============================================================================
# private-data_backup-tui.sh — interface texte (gum) pour private-data_backup.sh
#
# Périmètre : sauvegarder, restaurer (archive ou instantané), agir sur les
# archives (vérifier, supprimer, rétention, purge des orphelins) et gérer les
# profils (ajout/modification/suppression dans le fichier de configuration).
#
# Toute la logique (config, vérification, instantanés, verrou, confirmations,
# codes de retour) reste dans private-data_backup.sh ; cette interface ne fait
# que présenter et transmettre.
#
# Dépendances : gum (paquet « gum ») et le script principal à côté.
# =============================================================================

set -uo pipefail
umask 077

readonly TUI_VER="1.1"
_self="${BASH_SOURCE[0]:-$0}"
_self="$(readlink -f -- "${_self}")" || _self="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${_self}")" && pwd)" || exit 1
readonly CLI="${SCRIPT_DIR}/private-data_backup.sh"

# Glyphes Nerd Font (police Nerd Font requise dans le terminal).
readonly ICON_DB=$'\uf1c0'
readonly ICON_SAVE=$'\uf0c7'
readonly ICON_RESTORE=$'\uf0e2'
readonly ICON_ARCHIVE=$'\uf187'
readonly ICON_USERS=$'\uf0c0'
readonly ICON_QUIT=$'\uf011'
readonly ICON_SNAP=$'\uf0c5'
readonly ICON_EMPTY=$'\uf114'
readonly ICON_WARN=$'\uf071'
readonly ICON_PLUS=$'\uf067'
readonly ICON_EDIT=$'\uf044'
readonly ICON_TRASH=$'\uf1f8'

# Profils (`show --porcelain`).
declare -a P_NAME=() P_SRC=() P_CMD=() P_ARCH=() P_DATE=() P_SIZE=() P_EXCL=()

# Archives (`list --porcelain`).
declare -a A_GROUP=() A_DATE=() A_SIZE=() A_PATH=()

# Sélections courantes.
PICK_FILE=""
PICK_GROUP=""
PF_NAME=""
PF_SRC=""
PF_CMD=""
PF_EXCL=""

# =============================================================================
# UTILITAIRES
# =============================================================================

_die() {
	printf ' ✗ %s\n' "${*}" >&2
	exit 1
}

_human() {
	local bytes="${1:-0}"
	LC_ALL=C awk -v b="${bytes}" 'BEGIN {
		split("o Ko Mo Go To", u, " ")
		i = 1; s = b + 0
		while (s >= 1024 && i < 5) { s /= 1024; i++ }
		if (i == 1) printf "%d %s", s, u[i]
		else printf "%.1f %s", s, u[i]
	}'
	return 0
}

_fmt_dt() {
	local d="${1:-}"
	if [[ ${#d} -ne 14 ]]; then
		printf '%s' "—"
		return 0
	fi
	printf '%s-%s-%s %s:%s' "${d:0:4}" "${d:4:2}" "${d:6:2}" "${d:8:2}" "${d:10:2}"
}

_pause() {
	printf '\n'
	read -r -s -n 1 -p "  Entrée pour revenir au menu…" || true
	printf '\n'
}

_group_display() {
	if [[ ${1} == "pre-restore/"* ]]; then
		printf '%s (instantané)' "${1#pre-restore/}"
	else
		printf '%s' "${1}"
	fi
}

_profile_index() {
	# $1 = nom de profil → index dans P_*
	local want="${1}" i
	for i in "${!P_NAME[@]}"; do
		if [[ ${P_NAME[${i}]} == "${want}" ]]; then
			printf '%s' "${i}"
			return 0
		fi
	done
	return 1
}

# =============================================================================
# DONNÉES (une seule source de vérité : le script principal)
# =============================================================================

_load() {
	local out="" line a b c d e f g
	local -a lines=()

	if ! out="$("${CLI}" show --porcelain 2>/dev/null)"; then
		return 1
	fi

	P_NAME=(); P_SRC=(); P_CMD=(); P_ARCH=(); P_DATE=(); P_SIZE=(); P_EXCL=()
	mapfile -t lines <<<"${out}"
	for line in "${lines[@]}"; do
		[[ -n ${line} ]] || continue
		a=""; b=""; c=""; d=""; e=""; f=""; g=""
		IFS=$'\t' read -r a b c d e f g <<<"${line}"
		[[ ${c} == "-" ]] && c=""
		[[ ${d} == "-" ]] && d=""
		[[ ${e} == "-" ]] && e=""
		[[ ${g} == "-" ]] && g=""
		P_NAME+=("${a}")
		P_SRC+=("${b}")
		P_CMD+=("${c}")
		P_ARCH+=("${d}")
		P_DATE+=("${e}")
		P_SIZE+=("${f}")
		P_EXCL+=("${g}")
	done
	return 0
}

_load_archives() {
	local out="" line g d s p
	local -a lines=()

	A_GROUP=(); A_DATE=(); A_SIZE=(); A_PATH=()
	if ! out="$("${CLI}" list --porcelain 2>/dev/null)"; then
		return 1
	fi
	mapfile -t lines <<<"${out}"
	for line in "${lines[@]}"; do
		[[ -n ${line} ]] || continue
		g=""; d=""; s=""; p=""
		IFS=$'\t' read -r g d s p <<<"${line}"
		A_GROUP+=("${g}")
		A_DATE+=("${d}")
		A_SIZE+=("${s}")
		A_PATH+=("${p}")
	done
	return 0
}

_error_text() {
	local err=""
	err="$("${CLI}" show --porcelain 2>&1 >/dev/null)" || true
	printf '%s' "${err}"
}

# =============================================================================
# LIBELLÉS
# =============================================================================

_label() {
	local i="${1}" line="" when="" size=""
	if [[ -n ${P_ARCH[${i}]} ]]; then
		when="$(_fmt_dt "${P_DATE[${i}]}")"
		size="$(_human "${P_SIZE[${i}]}")"
		line="$(printf '%-14s %-32s  %s  (%s)' \
			"${P_NAME[${i}]}" "${P_SRC[${i}]}" "${when}" "${size}")"
	else
		line="$(printf '%-14s %-32s  %s' \
			"${P_NAME[${i}]}" "${P_SRC[${i}]}" "aucune archive")"
	fi
	printf '%s' "${line}"
}

_archive_label() {
	local i="${1}" group="" when="" size="" base=""
	group="$(_group_display "${A_GROUP[${i}]}")"
	when="$(_fmt_dt "${A_DATE[${i}]}")"
	size="$(_human "${A_SIZE[${i}]}")"
	base="${A_PATH[${i}]##*/}"
	printf '%-24s %s  %9s  %s' "${group}" "${when}" "${size}" "${base}"
}

# Sélectionne une archive ; renseigne PICK_FILE / PICK_GROUP.
_pick_archive() {
	local -a labels=()
	local i pick pos=-1

	if ! _load_archives; then
		gum style --border rounded --padding "0 2" --foreground 1 "${ICON_WARN}  Liste indisponible (NAS monté ?)"
		return 1
	fi
	if ((${#A_PATH[@]} == 0)); then
		gum style --border rounded --padding "0 2" --foreground 3 "${ICON_EMPTY}  Aucune archive."
		return 1
	fi
	for i in "${!A_PATH[@]}"; do
		labels+=("$(_archive_label "${i}")")
	done
	pick="$(gum choose --header "${ICON_ARCHIVE}  Choisir une archive" --cursor "❯ " \
		--height 15 "${labels[@]}")" || return 1
	for i in "${!labels[@]}"; do
		if [[ ${labels[${i}]} == "${pick}" ]]; then
			pos="${i}"
			break
		fi
	done
	((pos < 0)) && return 1
	PICK_FILE="${A_PATH[${pos}]}"
	PICK_GROUP="${A_GROUP[${pos}]}"
	return 0
}

# =============================================================================
# ÉCRANS : SAUVEGARDER / RESTAURER
# =============================================================================

_screen_backup() {
	local -a labels=() args=()
	local i pick line

	for i in "${!P_NAME[@]}"; do
		labels+=("$(_label "${i}")")
	done
	if ((${#labels[@]} == 0)); then
		gum style --border rounded --padding "0 2" --foreground 3 "${ICON_EMPTY}  Aucun profil configuré."
		return 0
	fi

	pick="$(gum choose --no-limit --height 15 \
		--header "${ICON_SAVE}  Sauvegarder — espace pour cocher, entrée pour valider" \
		--cursor "❯ " "${labels[@]}")" || return 0
	[[ -z ${pick} ]] && return 0

	while IFS= read -r line; do
		[[ -n ${line} ]] || continue
		args+=("${line%% *}")
	done <<<"${pick}"
	((${#args[@]} == 0)) && return 0

	gum confirm --affirmative "Sauvegarder" --negative "Annuler" \
		"Sauvegarder : ${args[*]} ?" || return 0

	printf '\n'
	"${CLI}" backup "${args[@]}"
	_pause
	return 0
}

_screen_restore() {
	local -a idx=() labels=() opts=()
	local i j pos=-1 pick profile mode when size

	for i in "${!P_NAME[@]}"; do
		[[ -n ${P_ARCH[${i}]} ]] || continue
		idx+=("${i}")
		labels+=("$(_label "${i}")")
	done
	if ((${#labels[@]} == 0)); then
		gum style --border rounded --padding "0 2" --foreground 3 \
			"${ICON_EMPTY}  Aucune archive disponible : lance d'abord une sauvegarde."
		return 0
	fi

	pick="$(gum choose --header "${ICON_RESTORE}  Restaurer — choisir un profil" \
		--cursor "❯ " "${labels[@]}")" || return 0
	for j in "${!labels[@]}"; do
		if [[ ${labels[${j}]} == "${pick}" ]]; then
			pos="${j}"
			break
		fi
	done
	((pos < 0)) && return 0
	i="${idx[${pos}]}"
	profile="${P_NAME[${i}]}"
	when="$(_fmt_dt "${P_DATE[${i}]}")"
	size="$(_human "${P_SIZE[${i}]}")"

	gum style --border rounded --padding "0 2" --title "Restauration ${profile}" \
		"archive : ${P_ARCH[${i}]}" \
		"date    : ${when}" \
		"taille  : ${size}" \
		"cible   : ~/${P_SRC[${i}]}" \
		"" \
		"L'archive sera vérifiée avant extraction ; les fichiers écrasés" \
		"sont conservés en *.pre-restore-<date>."

	mode="$(gum choose --header "${ICON_SNAP}  Instantané de l'état actuel avant écrasement" \
		"auto (si ≤ 512 Mo)" "oui (forcer)" "non (aucun)")" || return 0

	opts=(restore "${profile}" --yes)
	case "${mode}" in
	oui*) opts+=(--snapshot) ;;
	non*) opts+=(--no-snapshot) ;;
	*) ;;
	esac

	gum confirm --default=false --affirmative "Restaurer" --negative "Annuler" \
		"Écraser ~/${P_SRC[${i}]} avec ${P_ARCH[${i}]} ?" || return 0

	printf '\n'
	"${CLI}" "${opts[@]}"
	_pause
	return 0
}

# =============================================================================
# ÉCRAN : ARCHIVES
# =============================================================================

_archives_restore() {
	local profile="" src="" pindex=""
	_pick_archive || return 0
	profile="${PICK_GROUP#pre-restore/}"
	profile="${profile^^}"
	if pindex="$(_profile_index "${profile}")"; then
		src="${P_SRC[${pindex}]}"
	else
		src="(profil inconnu)"
	fi
	gum style --border rounded --padding "0 2" --title "Restaurer une version" \
		"archive : ${PICK_FILE##*/}" \
		"profil  : ${profile}" \
		"cible   : ~/${src}"
	if ! gum confirm --default=false --affirmative "Restaurer" --negative "Annuler" \
		"Écraser ~/${src} avec cette archive ?"; then
		return 0
	fi
	printf '\n'
	"${CLI}" restore --archive "${PICK_FILE}" --yes
	_pause
	return 0
}

_archives_verify() {
	_pick_archive || return 0
	printf '\n'
	"${CLI}" verify "${PICK_FILE}"
	_pause
	return 0
}

_archives_delete() {
	_pick_archive || return 0
	if ! gum confirm --default=false --affirmative "Supprimer" --negative "Annuler" \
		"Supprimer définitivement ${PICK_FILE##*/} ?"; then
		return 0
	fi
	printf '\n'
	"${CLI}" delete-archive "${PICK_FILE}" --yes
	_pause
	return 0
}

_archives_retention() {
	printf '\n'
	"${CLI}" delete_old --dry-run
	if ! gum confirm --default=false --affirmative "Appliquer" --negative "Annuler" \
		"Appliquer cette rétention (suppressions définitives) ?"; then
		return 0
	fi
	printf '\n'
	"${CLI}" delete_old --yes
	_pause
	return 0
}

_archives_purge() {
	printf '\n'
	"${CLI}" delete_old --purge-orphans --dry-run --no-verify
	if ! gum confirm --default=false --affirmative "Purger" --negative "Annuler" \
		"Supprimer tous les profils hors configuration (définitif) ?"; then
		return 0
	fi
	printf '\n'
	"${CLI}" delete_old --purge-orphans --yes --no-verify
	_pause
	return 0
}

_screen_archives() {
	printf '\n'
	"${CLI}" list 2>&1 | gum pager

	local action
	action="$(gum choose --header "${ICON_ARCHIVE}  Archives — que faire ?" --cursor "❯ " \
		"Restaurer une version…" \
		"Vérifier une archive…" \
		"Supprimer une archive…" \
		"Rétention (delete_old)…" \
		"Purger les profils orphelins…" \
		"Retour")" || return 0
	case "${action}" in
	Restaurer*) _archives_restore ;;
	Vérifier*) _archives_verify ;;
	Supprimer*) _archives_delete ;;
	Rétention*) _archives_retention ;;
	Purger*) _archives_purge ;;
	*) ;;
	esac
	return 0
}

# =============================================================================
# ÉCRAN : PROFILS
# =============================================================================

_profile_pick() {
	local -a labels=()
	local i pick pos=-1

	if ((${#P_NAME[@]} == 0)); then
		gum style --border rounded --padding "0 2" --foreground 3 "${ICON_EMPTY}  Aucun profil."
		return 1
	fi
	for i in "${!P_NAME[@]}"; do
		labels+=("$(_label "${i}")")
	done
	pick="$(gum choose --header "${ICON_USERS}  Choisir un profil" --cursor "❯ " "${labels[@]}")" || return 1
	for i in "${!labels[@]}"; do
		if [[ ${labels[${i}]} == "${pick}" ]]; then
			pos="${i}"
			break
		fi
	done
	((pos < 0)) && return 1
	printf '%s' "${pos}"
	return 0
}

_profile_inputs() {
	local mode="${1}" i="${2:-}" picked="" where=""

	PF_NAME=""; PF_SRC=""; PF_CMD=""; PF_EXCL=""
	if [[ ${mode} == "edit" ]]; then
		PF_NAME="${P_NAME[${i}]}"
		PF_SRC="${P_SRC[${i}]}"
		PF_CMD="${P_CMD[${i}]}"
		PF_EXCL="${P_EXCL[${i}]}"
	fi

	PF_NAME="$(gum input --header "Nom du profil (A-Z, 0-9, _)" \
		--value "${PF_NAME}" --placeholder "MUSIQUE")" || return 1
	[[ -n ${PF_NAME} ]] || return 1

	where="$(gum choose --header "Dossier à sauvegarder" \
		"Choisir dans ${HOME}…" "Saisir un chemin relatif…")" || return 1
	if [[ ${where} == "Choisir"* ]]; then
		picked="$(gum file --directory --all --height 18 \
			--header "Dossier (${HOME})" "${HOME}")" || return 1
		if [[ ${picked} == "${HOME}/"* ]]; then
			PF_SRC="${picked#"${HOME}/"}"
		else
			gum style --border rounded --padding "0 2" --foreground 1 \
				"${ICON_WARN}  Hors de ${HOME} : ${picked}"
			return 1
		fi
	else
		PF_SRC="$(gum input --header "Dossier relatif à \$HOME" \
			--value "${PF_SRC}" --placeholder "Documents")" || return 1
	fi
	[[ -n ${PF_SRC} ]] || return 1

	PF_CMD="$(gum input --header "Binaire à surveiller (optionnel)" \
		--value "${PF_CMD}" --placeholder "brave")" || return 1
	PF_EXCL="$(gum input --header "Exclusions tar séparées par | (optionnel)" \
		--value "${PF_EXCL}" --placeholder "Cache|GPUCache")" || return 1
	return 0
}

_profile_save() {
	local action="${1}" rc=0
	gum style --border rounded --padding "0 2" --title "${action} un profil" \
		"nom     : ${PF_NAME}" \
		"dossier : ~/${PF_SRC}" \
		"binaire : ${PF_CMD:-(aucun)}" \
		"exclure : ${PF_EXCL:-(aucune)}"
	gum confirm --default=false --affirmative "Enregistrer" --negative "Annuler" \
		"Écrire dans le fichier de configuration ?" || return 0
	printf '\n'
	"${CLI}" profile-add "${PF_NAME}" "${PF_SRC}" "${PF_CMD}" "${PF_EXCL}"
	rc=$?
	_pause
	return "${rc}"
}

_profile_add() {
	_profile_inputs add || return 0
	_profile_save "Ajouter"
	return 0
}

_profile_edit() {
	local pos="" old="" rc=0
	pos="$(_profile_pick)" || return 0
	old="${P_NAME[${pos}]}"
	_profile_inputs edit "${pos}" || return 0
	_profile_save "Modifier"
	rc=$?
	# Renommage : l'ancien nom est retiré seulement si l'écriture a réussi.
	if ((rc == 0)) && [[ ${PF_NAME^^} != "${old}" ]]; then
		printf '\n'
		"${CLI}" profile-remove "${old}"
		_pause
	fi
	return 0
}

_profile_remove() {
	local pos=""
	pos="$(_profile_pick)" || return 0
	if ! gum confirm --default=false --affirmative "Retirer" --negative "Annuler" \
		"Retirer ${P_NAME[${pos}]} de la configuration ? (ses archives resteront sur le NAS)"; then
		return 0
	fi
	printf '\n'
	"${CLI}" profile-remove "${P_NAME[${pos}]}"
	_pause
	return 0
}

_screen_profiles() {
	local -a labels=()
	local i action

	for i in "${!P_NAME[@]}"; do
		labels+=("$(_label "${i}")")
	done
	if ((${#labels[@]} == 0)); then
		gum style --border rounded --padding "0 2" --foreground 3 "${ICON_EMPTY}  Aucun profil."
		return 0
	fi
	gum style --border rounded --padding "0 2" --title "Profils configurés" "${labels[@]}"

	action="$(gum choose --header "${ICON_USERS}  Profils — que faire ?" --cursor "❯ " \
		"${ICON_PLUS}  Ajouter un profil" \
		"${ICON_EDIT}  Modifier un profil" \
		"${ICON_TRASH}  Retirer un profil" \
		"Retour")" || return 0
	case "${action}" in
	*Ajouter*) _profile_add ;;
	*Modifier*) _profile_edit ;;
	*Retirer*) _profile_remove ;;
	*) ;;
	esac
	return 0
}

# =============================================================================
# MENU
# =============================================================================

_menu() {
	local choice
	choice="$(gum choose --header "${ICON_DB}  private-data_backup ${TUI_VER} — $(basename -- "${CLI}")" \
		--cursor "❯ " \
		"${ICON_SAVE}  Sauvegarder" \
		"${ICON_RESTORE}  Restaurer" \
		"${ICON_ARCHIVE}  Archives / État" \
		"${ICON_USERS}  Profils" \
		"${ICON_QUIT}  Quitter")" || return 1
	# Correspondance par mot-clé : les icônes peuvent changer sans casser le menu.
	case "${choice}" in
	*Sauvegarder*) _screen_backup ;;
	*Restaurer*) _screen_restore ;;
	*Archives*) _screen_archives ;;
	*Profils*) _screen_profiles ;;
	*) return 1 ;;
	esac
	return 0
}

# =============================================================================
# POINT D'ENTRÉE
# =============================================================================

main() {
	case "${1:-}" in
	-h|--help)
		cat <<EOF
${0} — interface texte de private-data_backup.sh

Sauvegarder, restaurer (archive ou instantané), agir sur les archives
(vérifier, supprimer, rétention, purge des orphelins) et gérer les profils
(ajout, modification, retrait dans le fichier de configuration).

Toute la logique et les sécurités (vérification, instantané, confirmation,
verrou) restent dans le script CLI.

Dépendances : gum, ${CLI}
EOF
		return 0
		;;
	--version)
		printf 'private-data_backup-tui %s\n' "${TUI_VER}"
		return 0
		;;
	*) ;;
	esac

	[[ -t 0 ]] && [[ -t 1 ]] || _die "cette interface nécessite un terminal interactif"
	command -v gum >/dev/null 2>&1 || _die "gum est requis (pacman -S gum)"
	[[ -x ${CLI} ]] || _die "script principal introuvable : ${CLI}"

	local err=""
	while true; do
		if ! _load; then
			err="$(_error_text)"
			gum style --border rounded --padding "1 2" --foreground 1 --title "${ICON_WARN}  Erreur" \
				"Impossible de lire la configuration ou le NAS." "${err}"
			return 1
		fi
		_menu || break
	done
	return 0
}

main "${@}"
