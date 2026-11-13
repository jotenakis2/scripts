#!/usr/bin/env bash
# shellcheck enable=all
#
# zsh-history-clean.sh — cleans a zsh history file (EXTENDED_HISTORY format,
# `: timestamp:duration;command`).
#
# Four passes, in this order:
#   1. multi-line entries dropped. With SHARE_HISTORY + INC_APPEND_HISTORY,
#      each line of a multi-line command / heredoc becomes a separate entry:
#      the first line alone, then fragments (`}`, `fi`, `EOF`, `\`…).
#      Fragments are thrown away, and so is the first line since it is incomplete.
#   2. leading and trailing spaces trimmed from every command; entries that
#      became empty are dropped.
#   3. entries starting with `\` dropped: that is the alias escape used
#      now and then (`\ps`, `\gdu`), which is not the command actually
#      typed day to day. Can be disabled with --keep-escaped.
#   4. dedupe on the cleaned command, keeping the LAST occurrence
#      (same semantics as HIST_IGNORE_ALL_DUPS), chronological order preserved.
#
# WARNING: an open zsh shell keeps its history list in memory and may
# rewrite the file on exit (SHARE_HISTORY). Close your zsh terminals
# before a real cleanup, otherwise part of the work is lost.

set -euo pipefail

readonly PROG="${0##*/}"
readonly DEFAULT_HISTFILE="${HOME}/.local/share/zsh/zsh_history"
readonly DEFAULT_BACKUP_DIR="${HOME}/.local/share/zsh-backups"

HISTFILE_PATH="${HISTFILE:-${DEFAULT_HISTFILE}}"
BACKUP_DIR="${DEFAULT_BACKUP_DIR}"
KEEP=0
DRY_RUN=0
DO_BACKUP=1
DROP_ESCAPED=1

usage() {
  cat <<EOF
Usage : ${PROG} [options]

Nettoie l'historique zsh : entrées multi-lignes, espaces superflus, entrées
échappées (commande préfixée par un antislash), doublons, et éventuellement
plafonne le nombre d'entrées.

Options :
  -n, --dry-run         affiche ce qui serait fait, n'écrit rien
  -k, --keep N          ne conserve que les N dernières entrées (après nettoyage)
  -e, --keep-escaped    conserve les entrées commençant par un antislash
                        (elles sont supprimées par défaut)
  -f, --file FICHIER    historique à traiter
                        (défaut : \$HISTFILE ou ${DEFAULT_HISTFILE})
  -d, --backup-dir DIR  dossier des sauvegardes (défaut : ${DEFAULT_BACKUP_DIR})
  -B, --no-backup       ne pas sauvegarder avant d'écrire (déconseillé)
  -h, --help            cette aide

Exemples :
  ${PROG} --dry-run            # mesurer le gain sans toucher au fichier
  ${PROG}                      # nettoyage + sauvegarde
  ${PROG} --keep 5000          # nettoyage puis plafond à 5000 entrées
EOF
}

die() {
  printf 'Erreur: %s\n' "$*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    -n | --dry-run) DRY_RUN=1 ;;
    -k | --keep)
      [[ ${2:-} =~ ^[0-9]+$ ]] || die "--keep attend un nombre"
      KEEP="$2"
      shift
      ;;
    -f | --file)
      [[ -n ${2:-} ]] || die "--file attend un chemin"
      HISTFILE_PATH="$2"
      shift
      ;;
    -d | --backup-dir)
      [[ -n ${2:-} ]] || die "--backup-dir attend un chemin"
      BACKUP_DIR="$2"
      shift
      ;;
    -B | --no-backup) DO_BACKUP=0 ;;
    -e | --keep-escaped) DROP_ESCAPED=0 ;;
    -h | --help) usage; exit 0 ;;
    *)
      printf 'Option inconnue : %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

[[ -f ${HISTFILE_PATH} ]] || die "fichier introuvable : ${HISTFILE_PATH}"
[[ -r ${HISTFILE_PATH} ]] || die "fichier illisible : ${HISTFILE_PATH}"
readonly SRC="${HISTFILE_PATH}"

# Without the EXTENDED_HISTORY prefix the file is not in the expected format:
# we refuse rather than risk wiping a history in another format.
head -n 1 "${SRC}" | grep -q '^: ' ||
  die "format inattendu : pas de préfixe ': horodatage:;' en première ligne"

SIZE_BEFORE=$(wc -c <"${SRC}")
LINES_BEFORE=$(wc -l <"${SRC}")
readonly SIZE_BEFORE LINES_BEFORE

TMP=$(mktemp "${SRC}.XXXXXX")
STATS="${TMP}.stats"
# shellcheck disable=SC2064  # expansion wanted now
trap "rm -f '${TMP}' '${STATS}'" EXIT

# Single awk pass: split entries, clean, dedupe.
awk -v keep="${KEEP}" -v drop_escaped="${DROP_ESCAPED}" -v stats="${STATS}" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

function flush(   i, prefix, cmd) {
  if (pending == "") return
  i = index(pending, ";")
  if (i == 0) { pending = ""; return }              # unexpected line, ignored
  prefix = substr(pending, 1, i)                    # ": timestamp:duration;"
  cmd = trim(substr(pending, i + 1))
  if (cmd == "")            { empty++;  pending = ""; return }
  if (cmd ~ /\\$/)          { orphan++; pending = ""; return }  # continuation on its own
  if (drop_escaped && substr(cmd, 1, 1) == "\\") { escaped++; pending = ""; return }
  n++
  entry[n] = prefix cmd
  key[n] = cmd
  last[key[n]] = n
  pending = ""
}

/^: / { flush(); pending = $0; next }
{ continuation++; pending = "" }                    # fragment of a multi-line entry

END {
  flush()
  for (i = 1; i <= n; i++) {
    if (last[key[i]] != i) { dup++; continue }       # keep the last occurrence
    kept[++k] = entry[i]
  }
  start = (keep > 0 && k > keep) ? k - keep + 1 : 1
  for (i = start; i <= k; i++) print kept[i]
  printf "candidates=%d\ndup=%d\ncontinuation=%d\norphan=%d\nempty=%d\nescaped=%d\nkept=%d\n", \
         n, dup, continuation, orphan, empty, escaped, k - start + 1 > stats
}' "${SRC}" >"${TMP}"

while IFS='=' read -r k v; do
  case "${k}" in
    candidates) N_CAND="${v}" ;;
    dup) N_DUP="${v}" ;;
    continuation) N_CONT="${v}" ;;
    orphan) N_ORPH="${v}" ;;
    empty) N_EMPTY="${v}" ;;
    escaped) N_ESC="${v}" ;;
    kept) N_KEPT="${v}" ;;
    *) die "statistique inattendue : ${k}" ;;
  esac
done <"${STATS}"
readonly N_CAND N_DUP N_CONT N_ORPH N_EMPTY N_ESC N_KEPT

SIZE_AFTER=$(wc -c <"${TMP}")
LINES_AFTER=$(wc -l <"${TMP}")
readonly SIZE_AFTER LINES_AFTER

N_LOST=$((N_CAND - N_KEPT))

printf 'fichier        : %s\n' "${SRC}"
printf 'entrées        : %d candidates → %d conservées\n' "${N_CAND}" "${N_KEPT}"
printf '  multi-lignes : %d lignes de continuation + %d entrées incomplètes\n' \
  "${N_CONT}" "${N_ORPH}"
printf '  vides        : %d\n' "${N_EMPTY}"
printf '  échappées    : %d entrées commençant par \\ (--keep-escaped pour les garder)\n' "${N_ESC}"
printf '  doublons     : %d\n' "${N_DUP}"
if ((KEEP > 0)); then
  printf '  plafond      : --keep %d (entrées anciennes écartées : %d)\n' \
    "${KEEP}" "$((N_LOST - N_DUP))"
fi
printf 'lignes         : %d → %d\n' "${LINES_BEFORE}" "${LINES_AFTER}"
printf 'octets         : %d → %d  (%d Ko libérés)\n' \
  "${SIZE_BEFORE}" "${SIZE_AFTER}" "$(((SIZE_BEFORE - SIZE_AFTER) / 1024))"

if ((DRY_RUN)); then
  printf '\nmode dry-run : aucun fichier modifié.\n'
  exit 0
fi

if ((DO_BACKUP)); then
  mkdir -p "${BACKUP_DIR}"
  BACKUP_FILE="${BACKUP_DIR}/zsh_history-$(date +%Y%m%d-%H%M%S).bak"
  cp -p "${SRC}" "${BACKUP_FILE}"
  printf 'sauvegarde     : %s\n' "${BACKUP_FILE}"
else
  printf 'sauvegarde     : désactivée (--no-backup)\n'
fi

chmod --reference="${SRC}" "${TMP}" 2>/dev/null || true
mv -f "${TMP}" "${SRC}"
trap - EXIT
rm -f "${STATS}"

printf 'réécrit        : %s\n' "${SRC}"
printf 'rappel : ferme les shells zsh ouverts, ils réécrivent ce fichier en sortant.\n'
