#!/bin/bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail

MOK_KEY_NICKNAME='CachyOS Secure Boot'
CERT_DIR="/etc/mok-cachyos"
CERT_FILE="${CERT_DIR}/cert.der"
KEY_P12_FILE="${CERT_DIR}/key.p12"
PESIGN_CERT_DB='/etc/pki/pesign'

logger -t kernel-postinst "script appelé : $0 args: $*"

if [[ "$#" -ne 2 ]]; then
    logger -t kernel-postinst "problèmes d'arguments"
    exit 1
fi

KERNEL_IMAGE="$2"

case "$KERNEL_IMAGE" in
    *cachyos*)
        logger -t kernel-postinst "Noyau cachyos à signer"
        ;;
    *)
        logger -t kernel-postinst "Pas de noyau cachyos à signer"
        exit 0
        ;;
esac

if ! command -v pesign >/dev/null 2>&1; then
    logger -t kernel-postinst "pesign non détecté"
    exit 1
fi

if [[ ! -w "$KERNEL_IMAGE" ]]; then
    logger -t kernel-postinst "kernel image non modifiable donc non signable: $KERNEL_IMAGE"
    exit 1
fi

# Fonction: vérifier si le certificat est dans la base NSS
certificate_in_db() {
    local nickname="$1"
    local db_path="$2"
    certutil -d "$db_path" -L | grep -q "$nickname"
}

# Fonction: importer le certificat s'il n'est pas dans la DB
import_certificate_if_missing() {
    local nickname="$1"
    local cert_dir="$2"
    local cert_file="$3"
    local key_p12_file="$4"
    local db_path="$5"

    if certificate_in_db "$nickname" "$db_path"; then
        logger -t kernel-postinst "Certificat '$nickname' déjà dans la base NSS"
        return 0
    fi

    if [[ ! -f "$cert_file" ]]; then
        logger -t kernel-postinst "Fichier certificat introuvable: $cert_file"
        exit 1
    fi

    if [[ ! -f "$key_p12_file" ]]; then
        logger -t kernel-postinst "Fichier key.p12 introuvable: $key_p12_file"
        exit 1
    fi

    logger -t kernel-postinst "Importation du certificat '$nickname' dans $db_path"
    
    certutil -A -i "$cert_file" -n "$nickname" -d "$db_path" -t "Pu,Pu,Pu"
    pk12util -i "$key_p12_file" -d "$db_path"

    logger -t kernel-postinst "Certificat '$nickname' importé avec succès"
}

# Importer le certificat si manquant
import_certificate_if_missing "$MOK_KEY_NICKNAME" "$CERT_DIR" "$CERT_FILE" "$KEY_P12_FILE" "$PESIGN_CERT_DB"

logger -t kernel-postinst "Signature noyau $KERNEL_IMAGE..."
pesign --verbose --certificate "$MOK_KEY_NICKNAME" --in "$KERNEL_IMAGE" --sign --out "$KERNEL_IMAGE.signed"

if [[ ! -f "$KERNEL_IMAGE.signed" ]]; then
    logger -t kernel-postinst "Erreur: fichier signé non créé"
    exit 1
fi

mv -f -- "$KERNEL_IMAGE.signed" "$KERNEL_IMAGE"

logger -t kernel-postinst "Signature réussie: $KERNEL_IMAGE"
