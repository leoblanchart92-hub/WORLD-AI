import 'dart:convert';

/// Une action exécutée par l’IA (outil GitHub) pendant sa réponse.
class ChatAction {
  const ChatAction({required this.tool, required this.summary, this.ok = true});

  final String tool;
  final String summary;
  final bool ok;

  Map<String, dynamic> toJson() => {'tool': tool, 'summary': summary, 'ok': ok};

  factory ChatAction.fromJson(Map<String, dynamic> json) => ChatAction(
        tool: json['tool'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        ok: json['ok'] as bool? ?? true,
      );
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.actions = const [],
  });

  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime createdAt;
  final List<ChatAction> actions;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (actions.isNotEmpty)
          'actions': [for (final a in actions) a.toJson()],
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      actions: (json['actions'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatAction.fromJson)
          .toList(),
    );
  }

  static String encodeList(List<ChatMessage> messages) =>
      jsonEncode(messages.map((m) => m.toJson()).toList());

  static List<ChatMessage> decodeList(String raw) {
    if (raw.trim().isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.remote = false,
  });

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<ChatMessage> messages;
  bool remote;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'remote': remote,
      };

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Nouvelle discussion',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      messages: (json['messages'] as List? ?? [])
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      remote: json['remote'] as bool? ?? false,
    );
  }

  static String encodeList(List<Conversation> conversations) =>
      jsonEncode(conversations.map((c) => c.toJson()).toList());

  static List<Conversation> decodeList(String raw) {
    if (raw.trim().isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
