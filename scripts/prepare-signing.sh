#!/usr/bin/env bash
# Prépare la signature de release pour .github/workflows/build-apk.yml.
#
# Deux modes, le premier ayant la priorité :
#
# 1. ANDROID_SIGNING_PASSPHRASE — une phrase secrète choisie par le
#    propriétaire du dépôt. La clé de signature (EC P-256) en est dérivée de
#    façon déterministe : la même phrase redonne toujours exactement la même
#    clé, sans qu'aucun fichier n'ait à être transféré ou encodé.
#
# 2. ANDROID_KEYSTORE_BASE64 — un keystore (.jks/.p12) fourni en base64, avec
#    ANDROID_KEYSTORE_PASSWORD et, si besoin, ANDROID_KEY_ALIAS /
#    ANDROID_KEY_PASSWORD.
#
# Dans les deux cas le script écrit android/key.properties, que Gradle utilise
# pour signer l'APK release, et échoue avec un message explicite plutôt que de
# produire un APK signé en debug.
set -eu

ALIAS=${KEY_ALIAS:-worldai}
[ -n "${RUNNER_TEMP:-}" ] || RUNNER_TEMP=$(mktemp -d)
PROPS=android/key.properties
# Certificat public versionné : Android compare le certificat entier pour
# autoriser une mise à jour, il doit donc être strictement identique d'un
# build à l'autre. Il est créé au premier build puis réutilisé.
CERT_FILE=certs/release-signing-cert.pem

fail() {
  echo "::error::$1"
  exit 1
}

write_props() {
  {
    printf 'storeFile=%s\n' "$1"
    printf 'storePassword=%s\n' "$2"
    printf 'keyAlias=%s\n' "$3"
    printf 'keyPassword=%s\n' "$4"
  } > "$PROPS"
  echo "Signature de release configurée."
}

# ---------------------------------------------------------------------------
# Mode 1 : clé dérivée d'une phrase secrète
# ---------------------------------------------------------------------------
from_passphrase() {
  local pass=$1
  [ "${#pass}" -ge 12 ] || fail \
    "ANDROID_SIGNING_PASSPHRASE trop courte (${#pass} caractères) : il en faut au moins 12, idéalement 4 mots sans rapport."
  command -v python3 >/dev/null 2>&1 || fail \
    "python3 est requis pour dériver la clé (présent sur ubuntu-latest)."
  command -v openssl >/dev/null 2>&1 || fail "openssl est requis pour créer le certificat."
  command -v keytool >/dev/null 2>&1 || fail "keytool est requis (fourni par le JDK configuré)."

  # Dérivation déterministe : sha256(domaine ‖ phrase) réduit modulo l'ordre du
  # groupe de la courbe P-256. Aucun aléa, donc la clé est reproductible à
  # l'identique à chaque compilation.
  if ! python3 - "$pass" "$RUNNER_TEMP" <<'PY'
import hashlib
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

passphrase, outdir = sys.argv[1], sys.argv[2]

# Ordre du groupe de la courbe secp256r1 (P-256).
ORDER = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551

seed = hashlib.sha256(
    b"world-ai/release-signing-key/v1\x00" + passphrase.encode("utf-8")
).digest()
scalar = int.from_bytes(seed, "big") % (ORDER - 1) + 1

key = ec.derive_private_key(scalar, ec.SECP256R1())
with open(f"{outdir}/release-key.pem", "wb") as handle:
    handle.write(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
PY
  then
    fail "Dérivation de la clé impossible : le module Python « cryptography » est introuvable (pip install cryptography)."
  fi

  local pem="$RUNNER_TEMP/release-key.pem"
  local crt="$RUNNER_TEMP/release-cert.pem"
  local p12="$RUNNER_TEMP/release.p12"
  local jks="$RUNNER_TEMP/release.jks"

  if [ -f "$CERT_FILE" ]; then
    openssl x509 -in "$CERT_FILE" -noout -pubkey > "$RUNNER_TEMP/cert-pub.pem" 2>/dev/null \
      || fail "$CERT_FILE est illisible : le certificat versionné n'est pas du PEM."
    openssl pkey -in "$pem" -pubout > "$RUNNER_TEMP/key-pub.pem" 2>/dev/null \
      || fail "Lecture de la clé dérivée impossible (openssl)."
    if ! cmp -s "$RUNNER_TEMP/cert-pub.pem" "$RUNNER_TEMP/key-pub.pem"; then
      fail "La phrase secrète ne correspond plus au certificat versionné dans $CERT_FILE : Android refuserait la mise à jour. Rétablis la phrase d'origine, ou supprime ce certificat si tu acceptes une nouvelle identité (les installations existantes devront alors être réinstallées)."
    fi
    cp "$CERT_FILE" "$crt"
    echo "Certificat versionné réutilisé ($CERT_FILE)."
  else
    mkdir -p "$(dirname "$CERT_FILE")"
    openssl req -x509 -new -key "$pem" -sha256 -days 10000 \
      -subj "/CN=WORLD-AI/O=WORLD-AI/C=FR" -out "$crt" >/dev/null 2>&1 \
      || fail "Création du certificat impossible (openssl)."
    cp "$crt" "$CERT_FILE"
    echo "Nouveau certificat créé : $CERT_FILE (à versionner)."
  fi

  openssl pkcs12 -export -inkey "$pem" -in "$crt" -name "$ALIAS" \
    -passout "pass:$pass" -out "$p12" >/dev/null 2>&1 \
    || fail "Création du magasin PKCS#12 impossible (openssl)."

  # Conversion en JKS : format historique mais le mieux toléré par le plugin
  # Android Gradle, quel que soit le type de magasin par défaut du JDK.
  keytool -importkeystore -noprompt \
    -srckeystore "$p12" -srcstoretype PKCS12 -srcstorepass "$pass" \
    -destkeystore "$jks" -deststoretype JKS -deststorepass "$pass" \
    -destkeypass "$pass" >/dev/null 2>&1 \
    || fail "Conversion du keystore en JKS impossible (keytool)."

  keytool -list -keystore "$jks" -storepass "$pass" -alias "$ALIAS" >/dev/null 2>&1 \
    || fail "Le keystore dérivé est illisible : la phrase secrète n'a pas produit de clé exploitable."

  local fingerprint
  fingerprint=$(keytool -list -v -keystore "$jks" -storepass "$pass" -alias "$ALIAS" 2>/dev/null \
    | sed -n 's/.*SHA256: //p' | head -n1)

  echo "Clé dérivée de la phrase secrète (EC P-256, alias $ALIAS)."
  echo "Certificat : ${fingerprint:-empreinte indisponible}"

  write_props "$jks" "$pass" "$ALIAS" "$pass"
}

# ---------------------------------------------------------------------------
# Mode 2 : keystore fourni en base64
# ---------------------------------------------------------------------------
from_base64() {
  local encoded=$1
  local storepass=${KEYSTORE_PASSWORD:-}
  local keypass=${KEY_PASSWORD:-$storepass}

  [ -n "$storepass" ] || fail \
    "ANDROID_KEYSTORE_PASSWORD est absent : ajoute le mot de passe du keystore."

  # Tolère les collages multi-lignes, entre guillemets, ou en base64 url-safe.
  local clean
  clean=$(printf '%s' "$encoded" | tr -d ' \t\r\n"' | tr '_-' '/+')
  [ -n "$clean" ] || fail "ANDROID_KEYSTORE_BASE64 est vide."

  while [ $(( ${#clean} % 4 )) -ne 0 ]; do clean="${clean}="; done

  if printf '%s' "$clean" | grep -q '[^A-Za-z0-9+/=]'; then
    fail "ANDROID_KEYSTORE_BASE64 n'est pas du base64 (caractères inattendus). Colle la sortie de : base64 -w0 release.jks."
  fi

  local ks="$RUNNER_TEMP/release-uploaded.jks"
  if ! printf '%s' "$clean" | base64 -d > "$ks" 2>/dev/null || [ ! -s "$ks" ]; then
    fail "Décodage base64 du keystore impossible. Régénère la valeur avec : base64 -w0 release.jks."
  fi

  local size magic
  size=$(wc -c < "$ks" | tr -d ' ')
  echo "Keystore décodé : $size octets."

  magic=$(od -An -tx1 -N4 "$ks" | tr -d ' \n')
  case "$magic" in
    feedfeed|3082*) ;;
    *)
      fail "ANDROID_KEYSTORE_BASE64 ne contient pas un keystore ($size octets décodés, en-tête « $magic ») : il faut le fichier .jks encodé, pas son nom. Alternative sans fichier : définis le secret ANDROID_SIGNING_PASSPHRASE."
      ;;
  esac

  if ! keytool -list -keystore "$ks" -storepass "$storepass" >/dev/null 2>&1; then
    fail "Mot de passe du keystore refusé : ANDROID_KEYSTORE_PASSWORD ne correspond pas à ce fichier."
  fi

  if ! keytool -list -keystore "$ks" -storepass "$storepass" -alias "$ALIAS" >/dev/null 2>&1; then
    local aliases
    aliases=$(keytool -list -keystore "$ks" -storepass "$storepass" 2>/dev/null \
      | grep -E 'PrivateKeyEntry' | cut -d, -f1 | tr -d ' ' | paste -sd ', ' - || true)
    fail "Alias « $ALIAS » absent du keystore : ANDROID_KEY_ALIAS doit reprendre l'alias exact du certificat. Alias présents : ${aliases:-aucun}."
  fi
  echo "Keystore et alias vérifiés."

  write_props "$ks" "$storepass" "$ALIAS" "$keypass"
}

# ---------------------------------------------------------------------------
if [ -n "${SIGNING_PASSPHRASE:-}" ]; then
  from_passphrase "$SIGNING_PASSPHRASE"
elif [ -n "${KEYSTORE_BASE64:-}" ]; then
  from_base64 "$KEYSTORE_BASE64"
else
  fail "Aucune clé de signature : définis le secret ANDROID_SIGNING_PASSPHRASE (une phrase de ton choix, au moins 12 caractères). Voir « Activer les mises à jour » dans README.md."
fi
