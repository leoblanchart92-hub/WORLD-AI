import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/ai_client.dart';

/// Site de test publié par l'IA pour un compte WORLD-AI.
class PublishedSite {
  const PublishedSite({
    required this.slug,
    required this.title,
    required this.url,
    this.updatedAt,
  });

  final String slug;
  final String title;

  /// Adresse publique, ouvrable dans un navigateur.
  final String url;
  final DateTime? updatedAt;

  /// Nom affiché : le titre choisi, sinon l'identifiant du site.
  String get label => title.trim().isEmpty ? slug : title.trim();
}

/// Erreur déjà formulée pour l'utilisateur.
class SiteFailure implements Exception {
  const SiteFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Contrat des sites publiés, injectable pour les tests.
abstract class SitesService {
  Future<List<PublishedSite>> list(String token);
  Future<void> remove(String token, String slug);
}

/// Client des routes `/sites` du relais.
class SitesClient implements SitesService {
  SitesClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const String relayUrl = AiClient.relayUrl;
  static const Duration timeout = Duration(seconds: 25);

  final http.Client _http;

  @override
  Future<List<PublishedSite>> list(String token) async {
    final body = await _send('GET', '/sites', token);
    final raw = body['sites'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map && item['url'] is String && item['slug'] is String)
          PublishedSite(
            slug: item['slug'] as String,
            title: item['title'] is String ? item['title'] as String : '',
            url: item['url'] as String,
            updatedAt: item['updatedAt'] is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (item['updatedAt'] as num).toInt(),
                  )
                : null,
          ),
    ];
  }

  @override
  Future<void> remove(String token, String slug) async {
    await _send('DELETE', '/sites/$slug', token);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    String token, {
    Map<String, Object?>? payload,
  }) async {
    final uri = Uri.parse('$relayUrl$path');
    final headers = {
      'accept': 'application/json',
      'authorization': 'Bearer $token',
      if (payload != null) 'content-type': 'application/json',
    };
    final http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (payload != null) request.body = jsonEncode(payload);
      final streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const SiteFailure('Le serveur met trop de temps à répondre.');
    } catch (_) {
      throw const SiteFailure(
        'Connexion impossible. Vérifie ta connexion internet.',
      );
    }

    final body = _decode(response.body);
    if (response.statusCode != 200) {
      final error = body?['error'];
      final message = error is Map ? error['message'] : null;
      throw SiteFailure(
        message is String && message.isNotEmpty
            ? message
            : 'Le relais n’a pas répondu correctement (${response.statusCode}).',
      );
    }
    return body ?? const <String, dynamic>{};
  }

  static Map<String, dynamic>? _decode(String raw) {
    try {
      final data = jsonDecode(raw);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }
}
