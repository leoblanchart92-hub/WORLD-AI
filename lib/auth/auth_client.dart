import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/ai_client.dart';

/// Compte WORLD-AI, tel que le relais le décrit.
class Account {
  const Account({required this.id, required this.email});

  final String id;
  final String email;
}

/// Session enregistrée sur l'appareil : jeton d'accès et compte associé.
class StoredSession {
  const StoredSession({
    required this.token,
    required this.accountId,
    required this.email,
  });

  final String token;
  final String accountId;
  final String email;
}

/// Erreur d'authentification, déjà formulée pour l'utilisateur.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Contrat d'authentification, injectable pour les tests.
abstract class AuthService {
  Future<StoredSession> register(String email, String password);
  Future<StoredSession> login(String email, String password);
  Future<Account?> me(String token);
  Future<void> logout(String token);
}

/// Client des routes `/auth/*` du relais WORLD-AI.
///
/// Le mot de passe traverse la connexion chiffrée une seule fois ; le relais
/// n'en garde qu'un condensat. Le jeton de session reste sur l'appareil.
class AuthClient implements AuthService {
  AuthClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const String relayUrl = AiClient.relayUrl;
  static const Duration timeout = Duration(seconds: 25);

  /// Doit rester aligné avec la validation du relais.
  static final RegExp emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[a-zA-Z]{2,}$');
  static const int minPasswordLength = 8;

  final http.Client _http;

  @override
  Future<StoredSession> register(String email, String password) {
    return _signIn('/auth/register', email, password);
  }

  @override
  Future<StoredSession> login(String email, String password) {
    return _signIn('/auth/login', email, password);
  }

  Future<StoredSession> _signIn(
    String path,
    String email,
    String password,
  ) async {
    final response = await _post(path, {
      'email': email.trim().toLowerCase(),
      'password': password,
    });
    final body = _decode(response.body);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw AuthFailure(
        _message(body) ?? 'Connexion impossible (${response.statusCode}).',
      );
    }
    final token = body?['token'];
    final user = body?['user'];
    if (token is! String || token.isEmpty || user is! Map) {
      throw const AuthFailure('Réponse inattendue du serveur. Réessaie.');
    }
    final id = user['id'];
    final mail = user['email'];
    if (id is! String || mail is! String) {
      throw const AuthFailure('Réponse inattendue du serveur. Réessaie.');
    }
    return StoredSession(token: token, accountId: id, email: mail);
  }

  @override
  Future<Account?> me(String token) async {
    final http.Response response;
    try {
      response = await _http
          .get(
            Uri.parse('$relayUrl/auth/me'),
            headers: {
              'accept': 'application/json',
              'authorization': 'Bearer $token',
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AuthFailure('Le serveur met trop de temps à répondre.');
    } catch (_) {
      throw const AuthFailure(
        'Connexion impossible. Vérifie ta connexion internet.',
      );
    }

    if (response.statusCode == 401) return null;
    final body = _decode(response.body);
    if (response.statusCode != 200) {
      throw AuthFailure(_message(body) ?? 'Vérification impossible.');
    }
    final user = body?['user'];
    if (user is! Map) return null;
    final id = user['id'];
    final email = user['email'];
    if (id is! String || email is! String) return null;
    return Account(id: id, email: email);
  }

  @override
  Future<void> logout(String token) async {
    try {
      await _http
          .post(
            Uri.parse('$relayUrl/auth/logout'),
            headers: {
              'accept': 'application/json',
              'authorization': 'Bearer $token',
            },
          )
          .timeout(timeout);
    } catch (_) {
      // La déconnexion locale reste valable même hors ligne.
    }
  }

  Future<http.Response> _post(String path, Map<String, Object?> body) async {
    try {
      return await _http
          .post(
            Uri.parse('$relayUrl$path'),
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AuthFailure('Le serveur met trop de temps à répondre.');
    } catch (_) {
      throw const AuthFailure(
        'Connexion impossible. Vérifie ta connexion internet.',
      );
    }
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final data = jsonDecode(body);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  static String? _message(Map<String, dynamic>? body) {
    final error = body?['error'];
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return null;
  }
}
