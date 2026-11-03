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
| `2.4.0` | L’IA crée des sites de test (pages HTML publiées à une adresse publique), écran *Sites de test*, et la connexion GitHub passe dans les paramètres. |
| `2.3.0` | Connexion du compte GitHub personnel (OAuth device flow) et actions de l’IA sur les dépôts ; pièces jointes dans les messages. |
| `2.2.0` | Historique des discussions, copier un message, régénérer, modifier et relancer, arrêt de génération, heure discrète, effacer la conversation, synchronisation des discussions sur le relais. |
| `2.1.0` | Icône à côté des messages utilisateur quand connecté. |
| `2.0.0` | Comptes WORLD-AI : inscription, connexion, profil et déconnexion depuis le menu. |
| `1.9.1` | Choix entre les trois IA Groq francophones : GPT-OSS 120B, GPT-OSS 20B et Qwen3 27B. |
| `1.9.0` | Discussion connectée à l’IA Groq via un relais hébergé : la clé reste côté serveur. |
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
| `lib/update/update_ui.dart` | Feuille de mise à jour : détails, progression, reprise et installation. |
| `lib/update/apk_installer.dart` | Lance l'installeur Android sur l'APK téléchargé. |

Comportement :

- **Vérification au démarrage**, silencieuse : pas de réseau, pas de release ou
  déjà à jour ⇒ aucun message. Une version plus récente ⇒ dialogue.
- **Vérification manuelle** via l'action « Mise à jour » du bas du menu
  latéral (les entrées « Mises à jour » et « À propos » ne figurent pas dans la
  navigation principale) : les erreurs réseau sont alors affichées.
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

## L’IA et la clé Groq

La discussion interroge un **relais** ([`relay/worker.js`](relay/worker.js)),
un Worker hébergé qui détient la clé Groq et relaie les appels. L’APK ne
contient **aucune clé** : un `.env` ou un `--dart-define` embarqué serait
lisible par n’importe qui, et le dépôt est public.

| Élément | Rôle |
| --- | --- |
| `relay/worker.js` | Relais : reçoit l’historique, ajoute la clé, appelle Groq. |
| `relay/wrangler.toml` | Test local uniquement (`wrangler dev`, D1 locale). |
| `relay/deploy.json` | Manifeste utilisé pour l’hébergement. |
| `relay/local-check.mjs` | Vérifications hors ligne du relais (`node relay/local-check.mjs`). |
| `lib/ai/ai_client.dart` | Client de l’application, sans aucune clé. |
| `lib/github/github_client.dart` | Connexion GitHub par compte (`/github*`). |
| `lib/pages/github_page.dart` | Écran *GitHub* : connexion, dépôt courant, déconnexion. |
| `lib/sites/sites_client.dart` | Client des sites de test publiés par l’IA (`/sites`). |
| `lib/pages/sites_page.dart` | Écran *Sites de test* : ouvrir, supprimer. |

**Poser la clé** : tableau de bord d’hébergement → projet *WORLD-AI relay* →
*Secrets* → nom `GROQ_API_KEY`, valeur créée sur
[console.groq.com/keys](https://console.groq.com/keys). La valeur n’est jamais
écrite dans le dépôt ni dans l’application. `/health` renvoie alors
`{"configured":true}`.

Garde-fous du relais : appels de navigateur refusés (en-tête `Origin`), modèles
limités à ceux que la clé peut joindre et qui répondent en français —
`openai/gpt-oss-120b`, `openai/gpt-oss-20b` et `qwen/qwen3.8-27b` (les Llama 3.x
et les modèles « Enterprise » exigent un contrat Groq), **aucune limite de
messages** (`DEVICE_DAILY_LIMIT` et `GLOBAL_DAILY_LIMIT` à `0` ; une valeur > 0
réactive le plafond), 1 024 jetons maximum par réponse. L’usage reste compté
anonymement dans D1, sans jamais bloquer une requête.

Pour viser un autre relais : `--dart-define=AI_RELAY_URL=https://…`.

## Les actions GitHub de l’IA

Chaque personne **connecte son propre compte GitHub** depuis l’application
(*Paramètres* → *GitHub*). L’IA agit alors avec ses droits, sur ses dépôts :
lire le code, ouvrir et commenter des issues, créer une branche, écrire des
fichiers (un commit), ouvrir et fusionner une pull request, déclencher un
workflow Actions. Chaque action est affichée sous la réponse, avec une coche ou
une croix.

| Élément | Rôle |
| --- | --- |
| `GITHUB_CLIENT_ID` | Identifiant de l’application OAuth du relais. |
| `GITHUB_CLIENT_SECRET` | Secret de cette application OAuth. |
| `GITHUB_TOKEN` | Facultatif : jeton utilisé pour les invités (sans compte). |
| `GITHUB_REPO` | Facultatif : dépôt courant par défaut. |

### Installer la connexion GitHub (une fois)

1. GitHub → *Settings* → *Developer settings* → **OAuth Apps** →
   **New OAuth App**. Nom `WORLD-AI`, *Homepage URL* = l’adresse du relais,
   *Authorization callback URL* = la même adresse (le device flow ne s’en sert
   pas, mais GitHub l’exige).
2. Sur la page de l’application, cocher **Enable Device Flow**.
3. Copier le **Client ID**, générer un **Client Secret**.
4. Tableau de bord d’hébergement → projet *WORLD-AI relay* → *Secrets* :
   `GITHUB_CLIENT_ID` et `GITHUB_CLIENT_SECRET`. Puis redéployer.

Chaque personne ouvre ensuite *Paramètres* → *GitHub*, touche
**Connecter avec GitHub**, recopie le code affiché sur
[github.com/login/device](https://github.com/login/device) et valide. Aucun
jeton ne transite par l’application : le relais garde le jeton du compte dans sa
base D1 et ne renvoie que le nom du compte et l’état des actions. Un jeton
d’accès personnel peut aussi être collé dans cet écran si l’OAuth n’est pas
installée.

Comportement : au plus six étapes d’outils par message (lecture puis écriture),
puis l’IA résume ce qu’elle a fait. Le dépôt courant se choisit dans l’écran
GitHub ; l’IA peut aussi le préciser elle-même (« repo ») et lister les dépôts
du compte. Un échec remonte avec l’erreur réelle de GitHub, jamais inventée.

Pour retirer l’accès d’une personne : *Déconnecter GitHub* dans l’application
(le jeton est supprimé de la base) ou révocation depuis GitHub.

## Les sites de test créés par l’IA

Demande à l’IA une page web — « crée-moi une page de test pour ma boutique » —
et elle publie une page HTML autonome, puis te donne son adresse. Les sites
appartiennent au compte WORLD-AI : un invité peut discuter, mais pas publier.

| Route | Rôle |
| --- | --- |
| `GET /s/<slug>` | Sert la page publiée (publique, sans session). |
| `GET /sites` | Liste les sites du compte connecté. |
| `POST /sites` | Publie une page (`title`, `html`). |
| `PATCH /sites/<slug>` | Remplace le contenu, l’adresse ne change pas. |
| `DELETE /sites/<slug>` | Supprime le site ; son adresse cesse de répondre. |

Outils exposés à l’IA : `site_create`, `site_update`, `site_list` et
`site_delete`. Chaque site est **une seule page** (styles et scripts dans le
fichier), plafonnée à 300 000 caractères, et un compte peut en avoir 50. Le
`slug` est aléatoire (`/s/9f0c1a…`) : l’adresse est publique mais difficile à
deviner. Un seul propriétaire peut modifier ou supprimer un site.

Les pages sont servies avec `Content-Security-Policy: sandbox` : leurs scripts
fonctionnent, mais dans une origine isolée, sans accès aux sessions ni aux
données du relais. Dans l’application, *Paramètres* → *Sites de test* permet de
les ouvrir dans le navigateur ou de les supprimer.

## Les comptes

Les comptes vivent dans la base D1 du relais : aucune dépendance à un service
d’authentification tiers, et la discussion reste utilisable sans compte.

| Route | Rôle |
| --- | --- |
| `POST /auth/register` | Crée le compte, renvoie un jeton de session. |
| `POST /auth/login` | Vérifie le mot de passe, ouvre une session. |
| `GET /auth/me` | Retourne le compte du jeton fourni. |
| `POST /auth/logout` | Ferme la session côté serveur. |

Règles de sécurité :

- mot de passe haché en **PBKDF2-SHA256** (100 000 itérations, sel aléatoire par
  compte) ; le clair n’est jamais écrit en base, ni journalisé ;
- jeton de session de 32 octets, stocké seulement sous forme de condensat
  SHA-256, valable 90 jours ; une déconnexion le supprime ;
- même message et même coût pour une adresse inconnue et un mauvais mot de
  passe, afin de ne pas révéler quelles adresses sont inscrites ;
- huit échecs par adresse et par IP bloquent les tentatives pendant quinze
  minutes ;
- adresse normalisée en minuscules, mot de passe de 8 à 200 caractères ;
- `/auth/*` refuse aussi les requêtes portant un en-tête `Origin`.

Côté application, `lib/auth/auth_client.dart` appelle ces routes et
`lib/pages/account_page.dart` porte les formulaires. Le jeton et l’adresse sont
enregistrés dans les préférences locales (`SettingsStore`) pour éviter un
aller-retour réseau au lancement ; le mot de passe, lui, n’est jamais conservé.
Le jeton est joint aux messages de la discussion (`Authorization: Bearer …`),
mais l’IA répond aussi sans compte.

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
lib/ai/                    client du relais IA (aucune clé embarquée)
lib/auth/                  client des comptes (connexion, session)
lib/pages/account_page.dart  formulaires de compte et profil
lib/update/                système de mise à jour (voir tableau ci-dessus)
relay/                     relais Groq hébergé (voir « L’IA et la clé Groq »)
android/                   projet Android, permissions réseau et installation
test/                      tests widgets + tests de comparaison de versions
.github/workflows/         compilation CI et publication des releases
```

Permissions Android déclarées : `INTERNET` (API GitHub) et
`REQUEST_INSTALL_PACKAGES` (lancement de l'installeur d'APK).
