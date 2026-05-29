#!/usr/bin/env bash
set -Eeuo pipefail
# script de maj de bypass-paywall magnolia1234 pour Helium (version zip extraite et installée dans INSTALL_DIR)

readonly REPO_URL='https://gitflic.ru/project/magnolia1234/bpc_uploads.git'
readonly TMP_DIR='/tmp'
readonly CLONE_DIR="${HOME}/.local/share/bpc-src"
readonly INSTALL_DIR="${HOME}/.local/share/bpc"
readonly HASH_FILE='release-hashes.txt'
readonly PREFERRED_ZIP='bypass-paywalls-chrome-clean-master.zip'
readonly VER=1.0

# -------------------------------------------------------------------------------------------------------------------------
echo "Script ${0##*/} - version ${VER}."
main() {
  local source_zip archive_path

  trap cleanup EXIT

  need_cmd git
  need_cmd rm
  need_cmd install
  need_cmd unzip
  need_cmd find
  need_cmd dirname
  need_cmd sed
  need_cmd head
  need_cmd mktemp
  need_cmd cp
  need_cmd sort
  need_cmd awk
  need_cmd sha256sum

  update_or_clone_repo

  # shellcheck disable=SC2310
  source_zip="$(select_zip)" || die 'aucune archive zip Chrome trouvée dans le dépôt'
  verify_sha256_if_available "${source_zip}"

  archive_path="$(copy_zip_to_tmp "${source_zip}")"
  install_extension "${archive_path}"

  rm -f -- "${archive_path}"
}



# -------------------------------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------------------------------

log() {
  printf '[%(%F %T)T] %s\n' -1 "${*}" >&2
}

# -------------------------------------------------------------------------------------------------------------------------

die() {
  printf 'Erreur: %s\n' "${*}" >&2
  exit 1
}

# -------------------------------------------------------------------------------------------------------------------------

need_cmd() {
  command -v "${1}" >/dev/null 2>&1 || die "commande introuvable: ${1}"
}


# -------------------------------------------------------------------------------------------------------------------------

cleanup() {
  if [[ -n "${staging_dir:-}" && -d "${staging_dir:-}" ]]; then
    rm -rf -- "${staging_dir}"
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

extract_version() {
  local manifest_file="${1}"

  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]\+\)".*/\1/p' "${manifest_file}" | head -n 1
}

# -------------------------------------------------------------------------------------------------------------------------

find_manifest_root() {
  local base_dir="${1}"
  local manifest

  if [[ -f "${base_dir}/manifest.json" ]]; then
    printf '%s\n' "${base_dir}"
    return 0
  fi

  manifest="$(
    find "${base_dir}" \
      -mindepth 2 \
      -maxdepth 5 \
      -type f \
      -name 'manifest.json' \
      | head -n 1
  )"

  [[ -n "${manifest}" ]] || return 1
  dirname -- "${manifest}"
}

# -------------------------------------------------------------------------------------------------------------------------

update_or_clone_repo() {
  if [[ -d "${CLONE_DIR}/.git" ]]; then
    log "Mise à jour du dépôt local ${CLONE_DIR}"
    git -C "${CLONE_DIR}" fetch --depth 1 origin
    git -C "${CLONE_DIR}" reset --hard origin/HEAD
    git -C "${CLONE_DIR}" clean -fdx
  else
    log "Clonage du dépôt dans ${CLONE_DIR}"
    rm -rf -- "${CLONE_DIR}"
    git clone --depth 1 "${REPO_URL}" "${CLONE_DIR}"
  fi

  git -C "${CLONE_DIR}" rev-parse --verify HEAD >/dev/null 2>&1 || die "impossible de vérifier HEAD dans ${CLONE_DIR}"
}

# -------------------------------------------------------------------------------------------------------------------------

select_zip() {
  local candidate

  if [[ -f "${CLONE_DIR}/${PREFERRED_ZIP}" ]]; then
    printf '%s\n' "${CLONE_DIR}/${PREFERRED_ZIP}"
    return 0
  fi

  # shellcheck disable=SC2312
  while IFS= read -r candidate; do
    case "$(basename "${candidate}")" in
      bypass-paywalls-chrome-clean-android-*.zip) continue ;;
      bypass-paywalls-firefox-*.zip) continue ;;
      *firefox*.zip) continue ;;
      *android*.zip) continue ;;
      *chrome*.zip)
        printf '%s\n' "${candidate}"
        return 0
        ;;
        *) continue ;;
    esac
  done < <(find "${CLONE_DIR}" -maxdepth 1 -type f -name '*.zip' | sort)

  return 1
}

# -------------------------------------------------------------------------------------------------------------------------

verify_sha256_if_available() {
  local source_zip="${1}"
  local hash_path expected_hash actual_hash target_file

  hash_path="${CLONE_DIR}/${HASH_FILE}"
  [[ -f "${hash_path}" ]] || {
    log "Pas de ${HASH_FILE}, vérification SHA256 ignorée"
    return 0
  }

  target_file="$(basename "${source_zip}")"

  expected_hash="$(
    awk -v file="${target_file}" '
      $0 == "SHA256 hash of " file ":" {
        if (getline > 0) {
          print $0
          exit
        }
      }
    ' "${hash_path}"
  )"

  if [[ -z "${expected_hash}" ]]; then
    log "Aucun hash trouvé pour ${target_file} dans ${HASH_FILE}, vérification ignorée"
    return 0
  fi

  [[ "${expected_hash}" =~ ^[0-9a-fA-F]{64}$ ]] || die "hash SHA256 invalide dans ${HASH_FILE} pour ${target_file}: ${expected_hash}"

  actual_hash="$(sha256sum -- "${source_zip}" | awk '{print $1}')"

  [[ "${actual_hash}" == "${expected_hash}" ]] || die "SHA256 invalide pour ${target_file}: attendu ${expected_hash}, obtenu ${actual_hash}"

  log "SHA256 vérifié pour ${target_file} (${actual_hash} vs ${expected_hash})"
}

# -------------------------------------------------------------------------------------------------------------------------

copy_zip_to_tmp() {
  local source_zip="${1}"
  local archive_path
  archive_path="${TMP_DIR}/$(basename "${source_zip}")"

  log "Copie de $(basename "${source_zip}") vers ${archive_path}"
  install -Dm644 -- "${source_zip}" "${archive_path}"

  [[ -s "${archive_path}" ]] || die "archive zip absente ou vide: ${archive_path}"
  printf '%s\n' "${archive_path}"
}

# -------------------------------------------------------------------------------------------------------------------------

install_extension() {
  local archive_path="${1}"
  local extension_root version old_version

  staging_dir="$(mktemp -d "${TMP_DIR}/bpc-unpack.XXXXXXXXXX")"

  if [[ -f "${INSTALL_DIR}/manifest.json" ]]; then
    old_version="$(extract_version "${INSTALL_DIR}/manifest.json")"
  fi

  log "Décompression de ${archive_path} dans ${staging_dir}"
  unzip -q -- "${archive_path}" -d "${staging_dir}"

  # shellcheck disable=SC2310
  extension_root="$(find_manifest_root "${staging_dir}")" || die "manifest.json introuvable dans l'archive ${archive_path}"
  [[ -f "${extension_root}/manifest.json" ]] || die "manifest.json absent dans ${extension_root}"

  version="$(extract_version "${extension_root}/manifest.json")"
  [[ -n "${version}" ]] || die "version introuvable dans manifest.json"

  if [[ -n "${old_version:-}" && "${old_version}" == "${version}" ]]; then
    log "La version ${version} est déjà installée, aucune mise à jour nécessaire"
    printf 'Dépôt local           : %s\n' "${CLONE_DIR}"
    printf 'Archive zip           : %s\n' "${archive_path}"
    printf 'Extension installée   : %s\n' "${INSTALL_DIR}"
    printf 'Version déjà présente : %s\n' "${version}"
    return 0
  fi

  if [[ -n "${old_version:-}" ]]; then
    log "Mise à jour de la version ${old_version} vers ${version}"
  else
    log "Installation de la version ${version}"
  fi

  log "Réinstallation dans ${INSTALL_DIR}"
  rm -rf -- "${INSTALL_DIR}"
  install -d -- "${INSTALL_DIR}"
  cp -a -- "${extension_root}/." "${INSTALL_DIR}/"

  [[ -f "${INSTALL_DIR}/manifest.json" ]] \
    || die "installation incomplète: manifest.json absent après copie"

  log "Extension installée: ${INSTALL_DIR}"
  log "Version détectée: ${version}"
  printf 'Dépôt local           : %s\n' "${CLONE_DIR}"
  printf 'Extension installée   : %s\n' "${INSTALL_DIR}"
  printf 'Version détectée      : %s\n' "${version}"
  [[ -n "${old_version:-}" && "${old_version}" != "${version}" ]] && printf 'Ancienne version      : %s\n' "${old_version}"
}

# -------------------------------------------------------------------------------------------------------------------------

main "${@}"
