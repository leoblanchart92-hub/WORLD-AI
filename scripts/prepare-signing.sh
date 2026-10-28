#!/usr/bin/env bash
# Décode le keystore des secrets CI et écrit android/key.properties.
#
# Utilisé par .github/workflows/build-apk.yml (secret ANDROID_KEYSTORE_BASE64)
# et utilisable à la main pour diagnostiquer :
#
#   ANDROID_KEYSTORE_BASE64="$(base64 -w0 release.jks)" \
#   ANDROID_KEYSTORE_PASSWORD=… ANDROID_KEY_ALIAS=… ANDROID_KEY_PASSWORD=… \
#   bash scripts/prepare-signing.sh
#
# Le décodage tolère les façons habituelles de coller un base64 dans un secret
# GitHub : retours à la ligne (base64 -w76), guillemets autour de la valeur,
# et variante « url-safe » (- et _ au lieu de + et /).
#
# Il vérifie ensuite que le contenu décodé est bien un keystore avant de lancer
# Gradle : une valeur inutilisable doit produire un message précis, pas une
# release non signée ou un échec obscur plus loin.
set -eu

fail() {
  echo "::error::$1"
  exit 1
}

[ -n "${KEYSTORE_BASE64:-}" ] || fail \
  "Secret ANDROID_KEYSTORE_BASE64 absent : la release serait signée avec la clé debug, donc impossible à mettre à jour. Ajoute les 4 secrets décrits dans README.md."
[ -n "${KEYSTORE_PASSWORD:-}" ] || fail "Secret ANDROID_KEYSTORE_PASSWORD absent."
[ -n "${KEY_ALIAS:-}" ] || fail "Secret ANDROID_KEY_ALIAS absent (par exemple : worldai)."
[ -n "${KEY_PASSWORD:-}" ] || fail "Secret ANDROID_KEY_PASSWORD absent."
[ -n "${RUNNER_TEMP:-}" ] || RUNNER_TEMP=$(mktemp -d)

# Nettoyage : espaces, tabulations, retours à la ligne, guillemets, url-safe.
CLEAN=$(printf '%s' "$KEYSTORE_BASE64" | tr -d ' \t\r\n"' | tr '_-' '/+')
[ -n "$CLEAN" ] || fail "ANDROID_KEYSTORE_BASE64 est vide."

# Complète le remplissage "=" : certains collages le perdent.
while [ $(( ${#CLEAN} % 4 )) -ne 0 ]; do CLEAN="${CLEAN}="; done

if printf '%s' "$CLEAN" | grep -q '[^A-Za-z0-9+/=]'; then
  fail "ANDROID_KEYSTORE_BASE64 n'est pas du base64 (caractères inattendus). Colle la sortie de : base64 -w0 release.jks — une seule ligne, sans en-tête ni préfixe data:."
fi

KS="$RUNNER_TEMP/release.jks"
if ! printf '%s' "$CLEAN" | base64 -d > "$KS" 2>/dev/null || [ ! -s "$KS" ]; then
  fail "Décodage base64 du keystore impossible. Régénère la valeur avec : base64 -w0 release.jks."
fi

SIZE=$(wc -c < "$KS" | tr -d ' ')
echo "Keystore décodé : $SIZE octets."

# Un .jks/.keystore réel pèse quelques kilo-octets et commence par la signature
# JKS (feedfeed) ou ASN.1/PKCS12 (3082). Une valeur de quelques octets est
# presque toujours l'encodage d'un nom de fichier au lieu du fichier lui-même.
MAGIC=$(od -An -tx1 -N4 "$KS" | tr -d ' \n')
case "$MAGIC" in
  feedfeed|3082*)
    ;;
  *)
    fail "ANDROID_KEYSTORE_BASE64 ne contient pas un keystore ($SIZE octets décodés, en-tête « $MAGIC »). Il faut la sortie de « base64 -w0 release.jks » — le fichier binaire encodé, pas son nom ni un mot de passe. Un keystore pèse ~2 000 à 3 000 octets, soit ~3 000 à 4 000 caractères en base64."
    ;;
esac

# Mot de passe faux et alias absent sont deux erreurs distinctes : on les sépare
# pour indiquer lequel des secrets corriger.
if ! ERR=$(keytool -list -keystore "$KS" -storepass "$KEYSTORE_PASSWORD" 2>&1 >/dev/null); then
  fail "Mot de passe du keystore refusé : ANDROID_KEYSTORE_PASSWORD ne correspond pas à ce fichier (keytool : $ERR)."
fi

if ! ERR=$(keytool -list -keystore "$KS" -storepass "$KEYSTORE_PASSWORD" \
      -alias "$KEY_ALIAS" 2>&1 >/dev/null); then
  ALIASES=$(keytool -list -keystore "$KS" -storepass "$KEYSTORE_PASSWORD" 2>/dev/null \
    | grep -E 'PrivateKeyEntry' | cut -d, -f1 | tr -d ' ' | paste -sd ', ' - || true)
  fail "Alias « $KEY_ALIAS » absent du keystore : ANDROID_KEY_ALIAS doit reprendre l'alias exact du certificat. Alias présents : ${ALIASES:-aucun}."
fi
echo "Keystore et alias vérifiés."

{
  printf 'storeFile=%s\n' "$KS"
  printf 'storePassword=%s\n' "$KEYSTORE_PASSWORD"
  printf 'keyAlias=%s\n' "$KEY_ALIAS"
  printf 'keyPassword=%s\n' "$KEY_PASSWORD"
} > android/key.properties

echo "Signature de release configurée."
