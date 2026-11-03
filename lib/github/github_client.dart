import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/ai_client.dart';

/// État de la connexion GitHub du compte WORLD-AI.
class GithubStatus {
  const GithubStatus({
    required this.signedIn,
    required this.deviceFlow,
    required this.connected,
    this.login,
    this.defaultRepo = '',
  });

  /// Un compte WORLD-AI est-il ouvert sur cet appareil ?
  final bool signedIn;

  /// La connexion OAuth est-elle installée sur le relais ?
  final bool deviceFlow;

  /// Un compte GitHub est-il lié ?
  final bool connected;

  final String? login;

  /// Dépôt utilisé quand la demande ne précise pas de dépôt.
  final String defaultRepo;
}

/// Code à recopier sur GitHub pour autoriser l'application.
class GithubDevice {
  const GithubDevice({
    required this.id,
    required this.userCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresIn,
  });

  final String id;
  final String userCode;
  final String verificationUri;
  final int interval;
  final int expiresIn;
}

/// Réponse du relais pendant l'attente de validation.
class GithubPoll {
  const GithubPoll(this.state, {this.login});

  /// `pending`, `slow_down`, `connected`, `expired` ou `denied`.
  final String state;
  final String? login;
}

/// Dépôt accessible avec le compte connecté.
class GithubRepo {
  const GithubRepo({
    required this.fullName,
    required this.private,
    required this.defaultBranch,
    required this.canPush,
  });

  final String fullName;
  final bool private;
  final String defaultBranch;
  final bool canPush;
}

/// Erreur déjà formulée pour l'utilisateur.
class GithubFailure implements Exception {
  const GithubFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Contrat de connexion GitHub, injectable pour les tests.
abstract class GithubService {
  Future<GithubStatus> status(String token);
  Future<GithubDevice> start(String token);
  Future<GithubPoll> poll(String token, String deviceId);
  Future<String> connectToken(String token, String personalAccessToken);
  Future<GithubStatus> setRepo(String token, String repo);
  Future<void> disconnect(String token);
  Future<List<GithubRepo>> repos(String token);
}

/// Client des routes `/github*` du relais.
///
/// Le jeton GitHub n'est jamais renvoyé par le relais : l'application ne
/// manipule que l'identifiant du compte connecté.
class GithubClient implements GithubService {
  GithubClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const String relayUrl = AiClient.relayUrl;
  static const Duration timeout = Duration(seconds: 25);

  final http.Client _http;

  @override
  Future<GithubStatus> status(String token) async {
    final body = await _send('GET', '/github', token);
    return GithubStatus(
      signedIn: body['signedIn'] == true,
      deviceFlow: body['deviceFlow'] == true,
      connected: body['connected'] == true,
      login: body['login'] is String ? body['login'] as String : null,
      defaultRepo: body['defaultRepo'] is String ? body['defaultRepo'] as String : '',
    );
  }

  @override
  Future<GithubDevice> start(String token) async {
    final body = await _send('POST', '/github/device', token);
    final id = body['id'];
    final code = body['userCode'];
    if (id is! String || code is! String) {
      throw const GithubFailure('GitHub n’a pas renvoyé de code. Réessaie.');
    }
    return GithubDevice(
      id: id,
      userCode: code,
      verificationUri: body['verificationUri'] is String
          ? body['verificationUri'] as String
          : 'https://github.com/login/device',
      interval: body['interval'] is int ? body['interval'] as int : 5,
      expiresIn: body['expiresIn'] is int ? body['expiresIn'] as int : 900,
    );
  }

  @override
  Future<GithubPoll> poll(String token, String deviceId) async {
    final body = await _send(
      'POST',
      '/github/device/poll',
      token,
      payload: {'id': deviceId},
    );
    final state = body['status'];
    return GithubPoll(
      state is String ? state : 'pending',
      login: body['login'] is String ? body['login'] as String : null,
    );
  }

  @override
  Future<String> connectToken(String token, String personalAccessToken) async {
    final body = await _send(
      'POST',
      '/github/token',
      token,
      payload: {'token': personalAccessToken.trim()},
    );
    final login = body['login'];
    return login is String ? login : '';
  }

  @override
  Future<GithubStatus> setRepo(String token, String repo) async {
    await _send('PATCH', '/github', token, payload: {'repo': repo});
    return status(token);
  }

  @override
  Future<void> disconnect(String token) async {
    await _send('DELETE', '/github', token);
  }

  @override
  Future<List<GithubRepo>> repos(String token) async {
    final body = await _send('GET', '/github/repos', token);
    final raw = body['repos'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map && item['full_name'] is String)
          GithubRepo(
            fullName: item['full_name'] as String,
            private: item['private'] == true,
            defaultBranch: item['default_branch'] is String
                ? item['default_branch'] as String
                : 'main',
            canPush: item['can_push'] == true,
          ),
    ];
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
      throw const GithubFailure('Le serveur met trop de temps à répondre.');
    } catch (_) {
      throw const GithubFailure(
        'Connexion impossible. Vérifie ta connexion internet.',
      );
    }

    final body = _decode(response.body);
    if (response.statusCode != 200) {
      final error = body?['error'];
      final message = error is Map ? error['message'] : null;
      throw GithubFailure(
        message is String && message.isNotEmpty
            ? message
            : 'GitHub n’a pas répondu correctement (${response.statusCode}).',
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
