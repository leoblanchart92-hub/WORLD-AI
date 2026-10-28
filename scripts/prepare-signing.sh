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
echo "Keystore décodé : $(wc -c < "$KS") octets."

# Contrôle avant Gradle : mauvais mot de passe ou mauvais alias donnent ici un
# message explicite au lieu d'un échec de signature plus loin.
if ! keytool -list -keystore "$KS" -storepass "$KEYSTORE_PASSWORD" \
    -alias "$KEY_ALIAS" >/dev/null 2>&1; then
  fail "Keystore illisible : vérifie ANDROID_KEYSTORE_PASSWORD et ANDROID_KEY_ALIAS (l'alias exact du certificat)."
fi
echo "Keystore et alias vérifiés."

{
  printf 'storeFile=%s\n' "$KS"
  printf 'storePassword=%s\n' "$KEYSTORE_PASSWORD"
  printf 'keyAlias=%s\n' "$KEY_ALIAS"
  printf 'keyPassword=%s\n' "$KEY_PASSWORD"
} > android/key.properties

echo "Signature de release configurée."
