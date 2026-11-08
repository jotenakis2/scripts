#!/usr/bin/env bash
# shellcheck enable=all
# =============================================================================
# private-data_backup-tui.sh — interface texte (gum) pour private-data_backup.sh
#
# Périmètre : sauvegarder, restaurer, consulter l'état.
# Toute la logique (config, vérification, instantanés, verrou, erreurs) reste
# dans private-data_backup.sh ; cette interface ne fait que présenter.
#
# Dépendances : gum (paquet « gum ») et le script principal à côté.
# =============================================================================

set -uo pipefail
umask 077

readonly TUI_VER="1.0"
_self="${BASH_SOURCE[0]:-$0}"
_self="$(readlink -f -- "${_self}")" || _self="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${_self}")" && pwd)" || exit 1
readonly CLI="${SCRIPT_DIR}/private-data_backup.sh"

# Profils chargés depuis `show --porcelain`.
declare -a P_NAME=() P_SRC=() P_CMD=() P_ARCH=() P_DATE=() P_SIZE=()

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

# =============================================================================
# DONNÉES (une seule source de vérité : le script principal)
# =============================================================================

_load() {
	local out="" line a b c d e f
	local -a lines=()

	if ! out="$("${CLI}" show --porcelain 2>/dev/null)"; then
		return 1
	fi

	P_NAME=(); P_SRC=(); P_CMD=(); P_ARCH=(); P_DATE=(); P_SIZE=()
	mapfile -t lines <<<"${out}"
	for line in "${lines[@]}"; do
		[[ -n ${line} ]] || continue
		a=""; b=""; c=""; d=""; e=""; f=""
		IFS=$'\t' read -r a b c d e f <<<"${line}"
		# Les champs vides sont émis « - » par le CLI.
		[[ ${c} == "-" ]] && c=""
		[[ ${d} == "-" ]] && d=""
		[[ ${e} == "-" ]] && e=""
		P_NAME+=("${a}")
		P_SRC+=("${b}")
		P_CMD+=("${c}")
		P_ARCH+=("${d}")
		P_DATE+=("${e}")
		P_SIZE+=("${f}")
	done
	return 0
}

_error_text() {
	local err=""
	err="$("${CLI}" show --porcelain 2>&1 >/dev/null)" || true
	printf '%s' "${err}"
}

# =============================================================================
# ÉCRANS
# =============================================================================

_screen_backup() {
	local -a labels=() args=()
	local i pick line

	for i in "${!P_NAME[@]}"; do
		labels+=("$(_label "${i}")")
	done
	if ((${#labels[@]} == 0)); then
		gum style --border rounded --padding "0 2" --foreground 3 "📭  Aucun profil configuré."
		return 0
	fi

	pick="$(gum choose --no-limit --header "💾  Sauvegarder — espace pour cocher, entrée pour valider" \
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
	local -a idx=() labels=()
	local i j pos=-1 pick profile mode
	local -a opts=()

	for i in "${!P_NAME[@]}"; do
		[[ -n ${P_ARCH[${i}]} ]] || continue
		idx+=("${i}")
		labels+=("$(_label "${i}")")
	done
	if ((${#labels[@]} == 0)); then
		gum style --border rounded --padding "0 2" --foreground 3 \
			"📭  Aucune archive disponible : lance d'abord une sauvegarde."
		return 0
	fi

	pick="$(gum choose --header "♻️  Restaurer — choisir un profil" --cursor "❯ " "${labels[@]}")" || return 0
	for j in "${!labels[@]}"; do
		if [[ ${labels[${j}]} == "${pick}" ]]; then
			pos="${j}"
			break
		fi
	done
	((pos < 0)) && return 0
	i="${idx[${pos}]}"
	profile="${P_NAME[${i}]}"

	local when="" size=""
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

	mode="$(gum choose --header "📸  Instantané de l'état actuel avant écrasement" \
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

_screen_list() {
	printf '\n'
	"${CLI}" list 2>&1 | gum pager
	return 0
}

_screen_state() {
	printf '\n'
	"${CLI}" show 2>&1 | gum pager
	return 0
}

_menu() {
	local choice
	choice="$(gum choose --header "🗄  private-data_backup ${TUI_VER} — $(basename -- "${CLI}")" \
		--cursor "❯ " \
		"💾  Sauvegarder" \
		"♻️  Restaurer" \
		"📋  Archives" \
		"📊  État" \
		"🚪  Quitter")" || return 1
	# Correspondance par mot-clé : les icônes peuvent changer sans casser le menu.
	case "${choice}" in
	*Sauvegarder*) _screen_backup ;;
	*Restaurer*) _screen_restore ;;
	*Archives*) _screen_list ;;
	*État*) _screen_state ;;
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

Sauvegarder, restaurer, consulter l'état. Toute la logique et les sécurités
(vérification, instantané, confirmation, verrou) restent dans le script CLI.

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
			gum style --border rounded --padding "1 2" --foreground 1 --title "⚠️  Erreur" \
				"Impossible de lire la configuration ou le NAS." "${err}"
			return 1
		fi
		_menu || break
	done
	return 0
}

main "${@}"
