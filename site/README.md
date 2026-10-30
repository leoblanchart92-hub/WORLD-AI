# Site vitrine WORLD-AI

Page vitrine statique en français, prête à être publiée sur **Render Static Site**. Elle présente l’application Android, explique honnêtement les fonctionnalités disponibles et mène au téléchargement de l’APK officiel. Les deux visuels fournis sont copiés dans `assets/` pour que le site soit autonome.

## Publier sur Render

Dans Render, crée un service **New → Static Site** et connecte le dépôt `leoblanchart92-hub/WORLD-AI`. Indique :

| Réglage Render | Valeur |
| --- | --- |
| Branch | `main` |
| Root Directory | `site` |
| Build Command | laisser vide |
| Publish Directory | `.` |

Render publiera le contenu statique du dossier et déploiera ensuite les nouveaux changements de ce dossier à chaque push sur `main`. Aucun backend, npm ou secret n’est nécessaire.

## Téléchargement de l’application

Les boutons de téléchargement récupèrent l’APK directement depuis la dernière GitHub Release publique. Le lien de secours actuel pointe vers la 1.7.0 ; au chargement, `app.js` interroge l’API publique GitHub afin de mettre à jour le lien et la version affichée quand une release plus récente est disponible.

WORLD-AI affiche pour le moment une interface de discussion, mais n’envoie pas encore les messages à une IA. Le site le précise dans la présentation et la FAQ.
