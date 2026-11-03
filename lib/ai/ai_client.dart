import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AiAttachment {
  const AiAttachment({
    required this.name,
    required this.mime,
    required this.data,
  });

  final String name;
  final String mime;
  final String data;

  Map<String, dynamic> toJson() => {
        'name': name,
        'mime': mime,
        'data': data,
      };
}

class AiMessage {
  const AiMessage(this.role, this.content, {this.attachments = const []});

  const AiMessage.user(this.content, {this.attachments = const []})
      : role = 'user';
  const AiMessage.assistant(this.content) : role = 'assistant', attachments = const [];

  final String role;
  final String content;
  final List<AiAttachment> attachments;

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (attachments.isNotEmpty)
          'attachments': [for (final a in attachments) a.toJson()],
      };
}

class AiFailure implements Exception {
  const AiFailure(this.message, {this.canRetry = true});

  final String message;
  final bool canRetry;

  @override
  String toString() => message;
}

class AiAction {
  const AiAction({required this.tool, required this.summary, this.ok = true});

  final String tool;
  final String summary;
  final bool ok;
}

class AiReply {
  const AiReply({required this.text, this.remaining, this.actions = const []});

  final String text;
  final int? remaining;
  final List<AiAction> actions;
}

class AiModel {
  const AiModel(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;
}

const List<AiModel> aiModels = [
  AiModel('openai/gpt-oss-120b', 'GPT-OSS 120B', 'Le plus complet'),
  AiModel('openai/gpt-oss-20b', 'GPT-OSS 20B', 'Très rapide'),
  AiModel('qwen/qwen3.8-27b', 'Qwen3 27B', 'Multilingue'),
];

const String defaultAiModel = 'openai/gpt-oss-120b';

AiModel aiModelFor(String? id) {
  for (final model in aiModels) {
    if (model.id == id) return model;
  }
  return aiModels.first;
}

abstract class AiService {
  Future<AiReply> send(List<AiMessage> messages, {http.Client? client});
}

class AiClient implements AiService {
  AiClient({
    required this.deviceId,
    this.model = defaultAiModel,
    this.token,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static const String relayUrl = String.fromEnvironment(
    'AI_RELAY_URL',
    defaultValue: 'https://site-39ed8b11e00442268b206ab8cea42e5f.freebuff.page',
  );

  static const Duration timeout = Duration(seconds: 45);

  final Future<String> Function() deviceId;
  final String model;
  final String? token;
  final http.Client _httpClient;

  http.Client get client => _httpClient;

  @override
  Future<AiReply> send(List<AiMessage> messages, {http.Client? client}) async {
    final device = await deviceId();
    final httpClientToUse = client ?? _httpClient;
    final http.Response response;
    try {
      response = await httpClientToUse
          .post(
            Uri.parse('$relayUrl/v1/chat'),
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json',
              'x-device-id': device,
              if (token != null) 'authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'model': model,
              'messages': [for (final message in messages) message.toJson()],
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AiFailure('L’IA met trop de temps à répondre. Réessaie.');
    } on http.ClientException {
      throw const AiFailure(
        'Connexion impossible. Vérifie ta connexion internet.',
      );
    } catch (_) {
      throw const AiFailure(
        'Connexion impossible. Vérifie ta connexion internet.',
      );
    }

    final body = _decode(response.body);

    if (response.statusCode != 200) {
      final error = body?['error'];
      final message = error is Map ? error['message'] : null;
      final code = error is Map ? error['code'] : null;
      throw AiFailure(
        message is String && message.isNotEmpty
            ? message
            : 'L’IA n’a pas pu répondre (${response.statusCode}).',
        canRetry: code != 'device_limit' && code != 'global_limit',
      );
    }

    final reply = body?['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw const AiFailure('Réponse vide de l’IA. Réessaie.');
    }
    final remaining = body?['remaining'];
    final rawActions = body?['actions'];
    final actions = <AiAction>[
      if (rawActions is List)
        for (final item in rawActions)
          if (item is Map)
            AiAction(
              tool: item['tool'] as String? ?? '',
              summary: item['summary'] as String? ?? '',
              ok: item['ok'] as bool? ?? true,
            ),
    ];
    return AiReply(
      text: reply.trim(),
      remaining: remaining is int ? remaining : null,
      actions: actions,
    );
  }

  Map<String, dynamic>? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
