import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_version.dart';
import 'update_config.dart';

/// Erreur dont le message est directement affichable à l'utilisateur.
class UpdateException implements Exception {
  UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum UpdateStatus {
  /// Une version plus récente est publiée avec un APK téléchargeable.
  updateAvailable,

  /// L'application est déjà à la dernière version publiée.
  upToDate,

  /// Aucune release n'a encore été publiée sur le dépôt.
  noReleasePublished,
}

/// Mise à jour disponible, avec les informations nécessaires à l'installation.
class AppUpdate {
  const AppUpdate({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileName,
    required this.sizeInBytes,
  });

  final AppVersion currentVersion;
  final AppVersion latestVersion;
  final String releaseNotes;
  final Uri downloadUrl;
  final String fileName;
  final int sizeInBytes;

  /// Taille lisible, par exemple « 42,1 Mo ».
  String get readableSize {
    if (sizeInBytes <= 0) return 'taille inconnue';
    final megabytes = sizeInBytes / (1024 * 1024);
    return '${megabytes.toStringAsFixed(1).replaceAll('.', ',')} Mo';
  }
}

class UpdateCheckResult {
  const UpdateCheckResult(this.status, this.currentVersion, {this.update});

  final UpdateStatus status;
  final AppVersion currentVersion;
  final AppUpdate? update;
}

typedef DownloadProgressCallback = void Function(int received, int total);

/// Interroge l'API GitHub Releases et télécharge l'APK de la dernière version.
class GithubUpdateService {
  GithubUpdateService({
    this.owner = UpdateConfig.owner,
    this.repository = UpdateConfig.repository,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String owner;
  final String repository;
  final http.Client _client;

  static const String _apiHost = 'https://api.github.com';
  static const Duration _requestTimeout = Duration(seconds: 25);

  Uri get _latestReleaseUri =>
      Uri.parse('$_apiHost/repos/$owner/$repository/releases/latest');

  Map<String, String> get _headers => const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// Version installée, lue depuis le manifeste Android (`versionName`).
  Future<AppVersion> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersion.parse(info.version);
  }

  /// Compare la version installée à la dernière release publiée.
  ///
  /// Renvoie un [UpdateCheckResult] ; lève une [UpdateException] si le dépôt
  /// répond autre chose que 200/404.
  Future<UpdateCheckResult> check() async {
    final current = await currentVersion();

    final http.Response response;
    try {
      response = await _client.get(_latestReleaseUri, headers: _headers).timeout(
            _requestTimeout,
          );
    } on TimeoutException {
      throw UpdateException('GitHub ne répond pas, réessaie plus tard.');
    } on SocketException {
      throw UpdateException('Pas de connexion internet.');
    }

    if (response.statusCode == 404) {
      return UpdateCheckResult(UpdateStatus.noReleasePublished, current);
    }
    if (response.statusCode != 200) {
      throw UpdateException('GitHub a répondu ${response.statusCode}.');
    }

    final Map<String, dynamic> release;
    try {
      release = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw UpdateException('Réponse de GitHub illisible.');
    }

    final latest = AppVersion.parse(release['tag_name'] as String? ?? '');
    if (latest <= current) {
      return UpdateCheckResult(UpdateStatus.upToDate, current);
    }

    final asset = _findApkAsset(release['assets']);
    if (asset == null) {
      throw UpdateException(
        'La version $latest est publiée sans APK téléchargeable.',
      );
    }

    final downloadUrl = Uri.tryParse(asset['browser_download_url'] as String? ?? '');
    if (downloadUrl == null) {
      throw UpdateException('Lien de téléchargement invalide.');
    }

    return UpdateCheckResult(
      UpdateStatus.updateAvailable,
      current,
      update: AppUpdate(
        currentVersion: current,
        latestVersion: latest,
        releaseNotes: (release['body'] as String? ?? '').trim(),
        downloadUrl: downloadUrl,
        fileName: _sanitizeFileName(
          asset['name'] as String? ?? 'world_ai-$latest.apk',
        ),
        sizeInBytes: (asset['size'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Télécharge l'APK dans le cache de l'application et renvoie le fichier.
  ///
  /// Un fichier déjà présent avec la bonne taille est réutilisé, ce qui rend
  /// une nouvelle tentative instantanée après une installation interrompue.
  Future<File> downloadApk(
    AppUpdate update, {
    DownloadProgressCallback? onProgress,
  }) async {
    final directory = await getTemporaryDirectory();
    await directory.create(recursive: true);
    final file = File('${directory.path}/${update.fileName}');

    if (update.sizeInBytes > 0 &&
        await file.exists() &&
        await file.length() == update.sizeInBytes) {
      onProgress?.call(update.sizeInBytes, update.sizeInBytes);
      return file;
    }

    final http.StreamedResponse response;
    try {
      response = await _client
          .send(http.Request('GET', update.downloadUrl))
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw UpdateException('Le téléchargement n\'a pas démarré à temps.');
    } on SocketException {
      throw UpdateException('Pas de connexion internet.');
    }

    if (response.statusCode != 200) {
      throw UpdateException(
        'Téléchargement refusé par GitHub (${response.statusCode}).',
      );
    }

    final total = response.contentLength ?? update.sizeInBytes;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (error) {
      await sink.close();
      if (await file.exists()) {
        await file.delete();
      }
      throw UpdateException('Téléchargement interrompu : $error');
    }

    if (total > 0 && received != total) {
      await file.delete();
      throw UpdateException(
        'Fichier incomplet ($received octets sur $total).',
      );
    }

    return file;
  }

  void dispose() => _client.close();

  static Map<String, dynamic>? _findApkAsset(Object? assets) {
    if (assets is! List) return null;
    for (final entry in assets) {
      if (entry is! Map<String, dynamic>) continue;
      final name = (entry['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) return entry;
    }
    return null;
  }

  /// Les noms d'assets GitHub sont sûrs, mais on évite tout séparateur de
  /// chemin avant d'écrire sur le disque.
  static String _sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
