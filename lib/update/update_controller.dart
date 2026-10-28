import 'package:flutter/foundation.dart';

import 'apk_installer.dart';
import 'app_version.dart';
import 'update_service.dart';

/// Étape courante du cycle « vérifier → télécharger → installer ».
enum UpdatePhase {
  /// Rien n'a encore été vérifié dans cette session.
  idle,
  checking,
  upToDate,
  noRelease,
  available,
  downloading,
  installing,
  error,
}

/// État partagé des mises à jour : une seule vérification, affichée à la fois
/// sur l'accueil, dans la page « Mises à jour » et dans la feuille modale.
///
/// Étendre [ChangeNotifier] permet à plusieurs écrans d'observer le même
/// téléchargement : la progression reste visible même si l'utilisateur change
/// de page pendant le transfert.
class UpdateController extends ChangeNotifier {
  UpdateController({GithubUpdateService? service})
      : _service = service ?? GithubUpdateService(),
        _ownsService = service == null;

  final GithubUpdateService _service;
  final bool _ownsService;

  UpdatePhase _phase = UpdatePhase.idle;
  AppVersion? _currentVersion;
  AppUpdate? _update;
  String? _error;
  double? _progress;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  bool _disposed = false;

  UpdatePhase get phase => _phase;
  AppVersion? get currentVersion => _currentVersion;
  AppUpdate? get update => _update;
  String? get error => _error;
  double? get progress => _progress;
  int get receivedBytes => _receivedBytes;
  int get totalBytes => _totalBytes;

  bool get isBusy =>
      _phase == UpdatePhase.checking ||
      _phase == UpdatePhase.downloading ||
      _phase == UpdatePhase.installing;

  bool get isDownloading =>
      _phase == UpdatePhase.downloading || _phase == UpdatePhase.installing;

  /// Version installée prête à afficher, même avant la première vérification.
  String get installedLabel =>
      _currentVersion == null ? 'v…' : 'v$_currentVersion';

  /// Lit `versionName` depuis le manifeste Android, une seule fois.
  Future<void> loadInstalledVersion() async {
    if (_currentVersion != null) return;
    try {
      final version = await _service.currentVersion();
      if (_disposed) return;
      _currentVersion = version;
      _notify();
    } catch (_) {
      // Version illisible : l'interface garde « v… » plutôt que d'échouer.
    }
  }

  /// Compare la version installée à la dernière release publiée.
  ///
  /// [silent] est utilisé au lancement : une erreur réseau ne doit alors rien
  /// afficher et ne pas transformer l'accueil en écran d'erreur.
  Future<void> check({bool silent = false}) async {
    if (isBusy) return;
    _phase = UpdatePhase.checking;
    _error = null;
    _notify();

    try {
      final result = await _service.check();
      if (_disposed) return;
      _currentVersion = result.currentVersion;
      switch (result.status) {
        case UpdateStatus.updateAvailable:
          _update = result.update;
          _phase = UpdatePhase.available;
        case UpdateStatus.upToDate:
          _update = null;
          _phase = UpdatePhase.upToDate;
        case UpdateStatus.noReleasePublished:
          _update = null;
          _phase = UpdatePhase.noRelease;
      }
    } on UpdateException catch (error) {
      _fail(error.message, silent: silent);
    } catch (_) {
      _fail('Vérification impossible pour le moment.', silent: silent);
    }
    _notify();
  }

  /// Télécharge l'APK puis ouvre l'installeur Android.
  ///
  /// Renvoie `false` si une erreur est survenue ; le message est alors dans
  /// [error] et l'interface propose de réessayer.
  Future<bool> downloadAndInstall() async {
    final update = _update;
    if (update == null || isBusy) return false;

    _phase = UpdatePhase.downloading;
    _error = null;
    _progress = 0;
    _receivedBytes = 0;
    _totalBytes = update.sizeInBytes;
    _notify();

    try {
      final apk = await _service.downloadApk(
        update,
        onProgress: (received, total) {
          if (_disposed) return;
          _receivedBytes = received;
          _totalBytes = total;
          _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
          _notify();
        },
      );

      if (_disposed) return false;
      _phase = UpdatePhase.installing;
      _progress = 1;
      _notify();

      await installApk(apk);

      if (_disposed) return true;
      _phase = UpdatePhase.available;
      _notify();
      return true;
    } on UpdateException catch (error) {
      _fail(error.message);
      _notify();
      return false;
    } catch (error) {
      _fail('Installation impossible : $error');
      _notify();
      return false;
    }
  }

  void _fail(String message, {bool silent = false}) {
    if (_disposed) return;
    if (silent) {
      // Retour discret à l'état précédent, sans message d'erreur.
      _phase = _update == null ? UpdatePhase.idle : UpdatePhase.available;
      _error = null;
    } else {
      _phase = UpdatePhase.error;
      _error = message;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsService) _service.dispose();
    super.dispose();
  }
}
