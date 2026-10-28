/// Dépôt GitHub d'où l'application télécharge ses mises à jour.
///
/// Le workflow `.github/workflows/build-apk.yml` publie une release `v<version>`
/// avec l'APK en pièce jointe ; l'application lit `releases/latest`.
/// Si le dépôt est renommé ou déplacé, seules ces deux constantes changent.
class UpdateConfig {
  const UpdateConfig._();

  static const String owner = 'leoblanchart92-hub';
  static const String repository = 'WORLD-AI';

  /// Page des releases, utile pour un lien « voir toutes les versions ».
  static Uri get releasesPage =>
      Uri.parse('https://github.com/$owner/$repository/releases');
}
