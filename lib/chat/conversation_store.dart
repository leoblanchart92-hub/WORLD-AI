import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_client.dart';
import 'chat_models.dart';

class ConversationStore {
  ConversationStore({this.token});

  String? token;

  static const _key = 'world_ai_conversations_v1';

  Future<List<Conversation>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key) ?? '';
      return Conversation.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Conversation> conversations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, Conversation.encodeList(conversations));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> fetchRemote(AiClient client) async {
    if (token == null || token!.isEmpty) return [];
    final res = await client.client.get(
      Uri.parse('${AiClient.relayUrl}/conversations'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );
    if (res.statusCode != 200) return [];
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['conversations'] as List? ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> createRemote(AiClient client, String title) async {
    if (token == null || token!.isEmpty) return null;
    final res = await client.client.post(
      Uri.parse('${AiClient.relayUrl}/conversations'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'title': title}),
    );
    if (res.statusCode != 201) return null;
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['conversation'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<void> syncMessages(AiClient client, String conversationId,
      List<ChatMessage> messages) async {
    if (token == null || token!.isEmpty) return;
    if (messages.isEmpty) return;
    final items = messages
        .map((m) => {
              'role': m.role,
              'content': m.content,
              'created_at': m.createdAt.millisecondsSinceEpoch,
            })
        .toList();
    await client.client.post(
      Uri.parse('${AiClient.relayUrl}/conversations/$conversationId/messages'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'messages': items}),
    );
  }

  Future<void> deleteRemote(AiClient client, String conversationId) async {
    if (token == null || token!.isEmpty) return;
    await client.client.delete(
      Uri.parse('${AiClient.relayUrl}/conversations/$conversationId'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );
  }
}
