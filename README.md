# WORLD-AI

Application Android **Flutter** livrée en APK, avec **mises à jour automatiques
depuis GitHub** : au lancement, l'application compare sa version à la dernière
release publiée et propose d'installer l'APK téléchargé.

## Activer les mises à jour (une seule fois)

Tant que cette partie n'est pas faite, la CI signe les APK avec la clé debug :
ils s'installent, mais aucune mise à jour ne pourra s'installer par-dessus.

### 1. Un seul secret : une phrase secrète de ton choix

Dans le dépôt : **Settings** → **Secrets and variables** → **Actions** →
**New repository secret** :

| Nom | Valeur |
| --- | --- |
| `ANDROID_SIGNING_PASSPHRASE` | une phrase de ton choix, **au moins 12 caractères**, idéalement 4 mots sans rapport (exemple de forme : `cheval-bleu-42-tempete`) |

Rien à télécharger, aucun fichier à encoder : la clé de signature est
**dérivée** de cette phrase par
[`scripts/prepare-signing.sh`](scripts/prepare-signing.sh) (courbe EC P-256,
dérivation déterministe). La même phrase redonne toujours exactement la même
clé et le même certificat, donc la même identité de signature pour Android.

> **Ne change jamais cette phrase.** Une phrase différente produit une clé
> différente : Android refuserait alors la mise à jour
> (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`) et il faudrait désinstaller puis
> réinstaller l'application. Note-la dans ton gestionnaire de mots de passe :
> la solidité de la clé dépend de sa longueur et de son imprévisibilité.

Le **certificat public**, lui, est versionné dans
[`certs/release-signing-cert.pem`](certs/release-signing-cert.pem) : la
première compilation le crée et l'enregistre automatiquement dans le dépôt,
les suivantes le réutilisent. C'est indispensable — Android compare le
certificat entier, pas seulement la clé : sans ce fichier, chaque build serait
considéré comme signé par une entité différente.

Si la phrase secrète est définie, elle est utilisée **en priorité** : les
anciens secrets `ANDROID_KEYSTORE_*` peuvent être supprimés. Un keystore
personnel reste pris en charge avec `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` et `ANDROID_KEY_PASSWORD`
(voir « Signature de release » plus bas).

### 2. Relancer la compilation

Onglet **Actions** → *Build APK* → **Re-run all jobs**. L'étape *Préparer la
signature de release* doit afficher :

```
Clé dérivée de la phrase secrète (EC P-256, alias worldai).
Nouveau certificat créé : certs/release-signing-cert.pem (à versionner).
Certificat : AA:BB:…  (empreinte SHA-256)
Signature de release configurée.
```

Au premier passage, l'étape suivante (*Enregistrer le certificat de signature*)
commite ce fichier. Les builds suivants affichent `Certificat versionné
réutilisé` : c'est normal et c'est ce qui garantit des mises à jour
acceptées.

### 3. Installer l'APK

Onglet **Releases** → `v1.2.0` → télécharger `world_ai-1.2.0.apk`.
**Désinstaller l'application déjà installée avant de l'installer** : l'ancienne
version est signée par la clé debug, et Android refuse une mise à jour entre
deux clés différentes. Cette réinstallation manuelle n'a lieu qu'une seule fois.

### 4. Vérifier ensuite la mise à jour automatique

Incrémenter `version:` dans [`pubspec.yaml`](pubspec.yaml) et pousser : l'app
installée détecte la nouvelle release au lancement et propose de l'installer.

### 5. Conserver la phrase secrète

C'est la seule chose à sauvegarder : sans elle, la clé est irrécupérable et
aucune mise à jour ne pourra plus être publiée pour les installations existantes.

## Récupérer l'APK

À chaque push sur `main`, le workflow
[`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml) :

1. analyse le code (`flutter analyze`) et lance les tests (`flutter test`) ;
2. compile l'APK release ;
3. l'expose en **artifact** du run (onglet *Actions*, conservation 90 jours) ;
4. crée ou met à jour la **release** `v<version>` avec l'APK et son `sha256`.

Deux façons de l'installer sur un téléphone :

- **Release** : onglet *Releases* du dépôt → télécharger `world_ai-<version>.apk` ;
- **Artifact** : run GitHub Actions le plus récent → section *Artifacts*.

Il faut autoriser « Installer des applications inconnues » pour le navigateur ou
le gestionnaire de fichiers utilisé, puis ouvrir le fichier téléchargé.

## Dépôt public obligatoire

L'application interroge `https://api.github.com/repos/leoblanchart92-hub/WORLD-AI/releases/...`
**sans authentification**. GitHub répond `404` à une requête anonyme sur un
dépôt **privé** : l'application conclurait « aucune version n'est publiée » et
ne proposerait jamais de mise à jour.

Le dépôt doit donc rester **public** (*Settings → General → Danger zone → Change
visibility*). Le mettre en privé casserait la mise à jour des installations
existantes ; il faudrait alors distribuer les APK à la main.

## Publier une version (et donc une mise à jour)

1. Incrémenter la version dans [`pubspec.yaml`](pubspec.yaml) :
   `version: 1.1.0+2` → `version: 1.2.0+3` (`versionName` + `versionCode`).
   Le `versionCode` doit **toujours** augmenter.
2. Commit + push sur `main`.
3. Le workflow publie la release `v1.2.0` avec l'APK.
4. Les installations existantes voient la mise à jour à leur prochain lancement.

Sans incrément de version, le workflow remplace l'APK de la release existante
mais aucune mise à jour n'est proposée : c'est volontaire.

## Versions publiées

| Version | Contenu |
| --- | --- |
| `1.3.0` | Publication de test : valide la mise à jour automatique depuis une 1.2.0 installée. |
| `1.2.0` | Première version signée avec la clé de release : les mises à jour suivantes s'installent par-dessus sans réinstallation. |
| `1.1.0` | Système de mise à jour (vérification au lancement, téléchargement avec progression, installeur Android) et CI de compilation. |
| `1.0.0` | Version initiale. |

## Fonctionnement du système de mise à jour

| Fichier | Rôle |
| --- | --- |
| `lib/update/update_config.dart` | Dépôt GitHub interrogé (`owner` / `repository`). |
| `lib/update/app_version.dart` | Lecture et comparaison de versions (`1.10.0 > 1.9.9`). |
| `lib/update/update_service.dart` | Appel `GET /repos/{owner}/{repo}/releases/latest`, sélection de l'asset `.apk`, téléchargement avec progression. |
| `lib/update/update_ui.dart` | Dialogue « Plus tard / Télécharger et installer », messages d'erreur. |
| `lib/update/apk_installer.dart` | Lance l'installeur Android sur l'APK téléchargé. |

Comportement :

- **Vérification au démarrage**, silencieuse : pas de réseau, pas de release ou
  déjà à jour ⇒ aucun message. Une version plus récente ⇒ dialogue.
- **Vérification manuelle** via le bouton ↻ de la barre d'application : les
  erreurs réseau sont alors affichées.
- **Téléchargement** dans le cache de l'application, avec pourcentage ; un
  fichier déjà complet est réutilisé, une taille incohérente le fait supprimer.
- **Installation** : Android demande une fois l'autorisation d'installer des
  applications inconnues pour WORLD-AI ; ensuite l'APK remplace l'ancienne
  version et les données de l'application sont conservées.
- **Échec de vérification** : jamais bloquant, l'application reste utilisable.

Pour signer sans passer par GitHub, créer `android/key.properties` :

```properties
storeFile=/chemin/vers/release.jks
storePassword=…
keyAlias=worldai
keyPassword=…
```

Ce fichier et les `.jks` sont exclus du dépôt.

## Signature de release : indispensable pour les mises à jour

Sans configuration, la compilation utilise la **clé debug**. Or chaque run de CI
génère une clé debug différente : Android refuserait alors d'installer la
nouvelle version par-dessus l'ancienne (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
Pour un flux de mise à jour fonctionnel, configurer une clé stable :

```bash
keytool -genkeypair -v -keystore release.jks -alias worldai \
  -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=WORLD-AI, O=WORLD-AI, C=FR"
base64 -w0 release.jks > release.jks.b64
```

Puis, dans *Settings → Secrets and variables → Actions*, ajouter :

| Secret | Contenu |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | contenu de `release.jks.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | mot de passe du keystore |
| `ANDROID_KEY_ALIAS` | alias (`worldai`) |
| `ANDROID_KEY_PASSWORD` | mot de passe de la clé |

Le workflow s'en sert automatiquement ; sans ces secrets il continue de produire
un APK signé en debug, installable mais non compatible avec les mises à jour
successives.

### Si la CI échoue sur la signature

L'étape *Préparer la signature de release* lance
[`scripts/prepare-signing.sh`](scripts/prepare-signing.sh), qui :

- tolère un base64 collé sur plusieurs lignes, entouré de guillemets, ou en
  variante « url-safe » (`-` et `_` au lieu de `+` et `/`) ;
- signale explicitement si la valeur n'est pas du base64, si le mot de passe du
  keystore est faux ou si l'alias est incorrect ;
- **échoue** plutôt que de produire un APK signé en debug, qui casserait les
  mises à jour sans prévenir.

Le secret `ANDROID_KEYSTORE_BASE64` doit contenir **une seule ligne** : la sortie
de `base64 -w0 release.jks`. Ni `data:application/…;base64,`, ni chemin de
fichier, ni contenu binaire. Pour tester la configuration hors CI :

```bash
ANDROID_KEYSTORE_BASE64="$(base64 -w0 release.jks)" \
ANDROID_KEYSTORE_PASSWORD=… ANDROID_KEY_ALIAS=worldai ANDROID_KEY_PASSWORD=… \
bash scripts/prepare-signing.sh
```

Conserver `release.jks` en lieu sûr : perdre cette clé impose une réinstallation
manuelle de l'application sur les appareils concernés.

## Développement local

Prérequis : Flutter stable (Dart ≥ 3.13) et un JDK 17.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
```

Raccourci pour installer la version compilée :

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Structure

```
lib/main.dart              écran d'accueil + bouton de mise à jour
lib/update/                système de mise à jour (voir tableau ci-dessus)
android/                   projet Android, permissions réseau et installation
test/                      tests widgets + tests de comparaison de versions
.github/workflows/         compilation CI et publication des releases
```

Permissions Android déclarées : `INTERNET` (API GitHub) et
`REQUEST_INSTALL_PACKAGES` (lancement de l'installeur d'APK).
