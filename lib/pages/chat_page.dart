import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import '../ai/ai_client.dart';
import '../auth/auth_client.dart';
import '../chat/chat_models.dart';
import '../chat/conversation_store.dart';
import '../theme/app_theme.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.ai,
    required this.conversation,
    required this.onConversationChanged,
    required this.onNewConversation,
    required this.onClearConversation,
    required this.onDeleteConversation,
    this.session,
    this.model = defaultAiModel,
    this.onModelChanged,
  });

  final AiService ai;
  final Conversation conversation;
  final ValueChanged<Conversation> onConversationChanged;
  final VoidCallback onNewConversation;
  final VoidCallback onClearConversation;
  final ValueChanged<String> onDeleteConversation;
  final StoredSession? session;
  final String model;
  final ValueChanged<String>? onModelChanged;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatAttachment {
  const _ChatAttachment({
    required this.name,
    required this.mime,
    required this.bytes,
  });

  final String name;
  final String mime;
  final Uint8List bytes;

  String get dataUrl => 'data:$mime;base64,${base64Encode(bytes)}';
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  AiFailure? _failure;
  bool _sending = false;
  bool _canSend = false;
  http.Client? _abortClient;
  ConversationStore? _store;
  final List<_ChatAttachment> _attachments = [];

  @override
  void initState() {
    super.initState();
    _input.addListener(_handleInputChanged);
    _store = ConversationStore(token: widget.session?.token);
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session?.token != widget.session?.token) {
      _store = ConversationStore(token: widget.session?.token);
    }
  }

  @override
  void dispose() {
    _input.removeListener(_handleInputChanged);
    _input.dispose();
    _scroll.dispose();
    _abortClient?.close();
    super.dispose();
  }

  void _handleInputChanged() {
    final canSend = (_input.text.trim().isNotEmpty || _attachments.isNotEmpty) && !_sending;
    if (canSend != _canSend) setState(() => _canSend = canSend);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _newId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return '$now-${now.hashCode.abs()}';
  }

  void _updateConversation(List<ChatMessage> messages) {
    final conv = widget.conversation;
    conv.messages.clear();
    conv.messages.addAll(messages);
    conv.updatedAt = DateTime.now();
    if (conv.title == 'Nouvelle discussion' || conv.title.isEmpty) {
      final firstUser = messages.firstWhere((m) => m.role == 'user', orElse: () => messages.first);
      final t = firstUser.content.replaceAll('\n', ' ').trim();
      conv.      title = t.isEmpty ? 'Nouvelle discussion' : (t.length > 40 ? '${t.substring(0, 40)}…' : t);
    }
    widget.onConversationChanged(conv);
    _store?.save([conv, ...[]]);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _attachments.isEmpty) || _sending) return;
    final now = DateTime.now();
    final userMsg = ChatMessage(id: _newId(), role: 'user', content: text.isEmpty ? '(pièce jointe)' : text, createdAt: now);
    final messages = List<ChatMessage>.from(widget.conversation.messages)..add(userMsg);
    final attachments = List<_ChatAttachment>.from(_attachments);
    setState(() {
      _input.clear();
      _attachments.clear();
      _canSend = false;
      _failure = null;
      _sending = true;
    });
    _updateConversation(messages);
    _scrollToEnd();
    await _request(messages, attachments: attachments);
  }

  Future<void> _request(List<ChatMessage> messages, {List<_ChatAttachment> attachments = const []}) async {
    _abortClient?.close();
    final client = http.Client();
    _abortClient = client;
    try {
      final history = <AiMessage>[];
      for (var i = 0; i < messages.length; i++) {
        final m = messages[i];
        if (m.role == 'user') {
          if (i == messages.length - 1 && attachments.isNotEmpty) {
            history.add(AiMessage.user(
              m.content,
              attachments: [
                for (final a in attachments)
                  AiAttachment(name: a.name, mime: a.mime, data: a.dataUrl),
              ],
            ));
          } else {
            history.add(AiMessage.user(m.content));
          }
        }
        if (m.role == 'assistant') history.add(AiMessage.assistant(m.content));
      }
      final reply = await (widget.ai as AiClient).send(
        history,
        client: client,
      );
      if (!mounted) return;
      if (client == _abortClient) _abortClient = null;
      final assistantMsg = ChatMessage(
        id: _newId(),
        role: 'assistant',
        content: reply.text,
        createdAt: DateTime.now(),
        actions: [
          for (final a in reply.actions)
            ChatAction(tool: a.tool, summary: a.summary, ok: a.ok),
        ],
      );
      final updated = List<ChatMessage>.from(messages)..add(assistantMsg);
      setState(() {
        _sending = false;
        _failure = null;
      });
      _updateConversation(updated);
      _scrollToEnd();
      if (widget.session != null && _store != null) {
        unawaited(_store!.syncMessages(widget.ai as AiClient, widget.conversation.id, updated));
      }
    } on AiFailure catch (failure) {
      if (!mounted) return;
      if (client == _abortClient) _abortClient = null;
      setState(() {
        _sending = false;
        _failure = failure;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      if (client == _abortClient) _abortClient = null;
      if (e is http.ClientException) {
        setState(() {
          _sending = false;
          _failure = const AiFailure('Génération arrêtée.');
        });
        _scrollToEnd();
        return;
      }
      setState(() {
        _sending = false;
        _failure = const AiFailure('L’IA n’a pas pu répondre. Réessaie.');
      });
      _scrollToEnd();
    }
  }

  void _stop() {
    _abortClient?.close();
    _abortClient = null;
    if (!mounted) return;
    setState(() => _sending = false);
  }

  Future<void> _retry() async {
    if (_sending || widget.conversation.messages.isEmpty) return;
    setState(() {
      _failure = null;
      _sending = true;
    });
    await _request(List<ChatMessage>.from(widget.conversation.messages));
  }

  Future<void> _regenerate() async {
    if (_sending || widget.conversation.messages.isEmpty) return;
    final msgs = List<ChatMessage>.from(widget.conversation.messages);
    while (msgs.isNotEmpty && msgs.last.role == 'assistant') {
      msgs.removeLast();
    }
    if (msgs.isEmpty) return;
    setState(() {
      _failure = null;
      _sending = true;
    });
    _updateConversation(msgs);
    _scrollToEnd();
    await _request(msgs);
  }

  Future<void> _editAndResend(ChatMessage message) async {
    if (_sending) return;
    final controller = TextEditingController(text: message.content);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Modifier et relancer', style: TextStyle(color: AppTheme.text)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(color: AppTheme.text),
          decoration: const InputDecoration(
            hintText: 'Modifie ton message…',
            hintStyle: TextStyle(color: AppTheme.muted),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Relancer')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;
    final msgs = List<ChatMessage>.from(widget.conversation.messages);
    final idx = msgs.indexWhere((m) => m.id == message.id);
    if (idx < 0) return;
    msgs.removeRange(idx, msgs.length);
    final now = DateTime.now();
    msgs.add(ChatMessage(id: _newId(), role: 'user', content: result, createdAt: now));
    setState(() {
      _failure = null;
      _sending = true;
    });
    _updateConversation(msgs);
    _scrollToEnd();
    await _request(msgs);
  }

  Future<void> _copy(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copié'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _pickModel() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ModelPicker(current: aiModelFor(widget.model)),
    );
    if (chosen != null) widget.onModelChanged?.call(chosen);
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: source, imageQuality: 85, maxWidth: 2048);
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      final mime = lookupMimeType(xfile.name, headerBytes: bytes) ?? 'image/jpeg';
      setState(() {
        _attachments.add(_ChatAttachment(name: xfile.name, mime: mime, bytes: bytes));
        _handleInputChanged();
      });
    } catch (_) {}
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'json', 'csv', 'xml', 'html', 'pdf', 'js', 'ts', 'py', 'dart', 'log'],
        withData: true,
      );
      if (result == null) return;
      for (final f in result.files) {
        if (f.bytes == null) continue;
        if (f.bytes!.length > 5 * 1024 * 1024) continue;
        final mime = lookupMimeType(f.name, headerBytes: f.bytes) ?? 'text/plain';
        setState(() {
          _attachments.add(_ChatAttachment(name: f.name, mime: mime, bytes: f.bytes!));
        });
      }
      _handleInputChanged();
    } catch (_) {}
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppTheme.accent),
              title: const Text('Galerie'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: AppTheme.accent),
              title: const Text('Appareil photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_rounded, color: AppTheme.accent),
              title: const Text('Fichiers'),
              onTap: () {
                Navigator.pop(context);
                _pickFiles();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
      _handleInputChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.conversation.messages;
    final showEmpty = messages.isEmpty && !_sending;

    return Column(
      children: [
        Expanded(
          child: showEmpty
              ? const _EmptyChat()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: messages.length + (_sending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= messages.length) return const _Thinking();
                    final msg = messages[index];
                    final isLastAssistant =
                        msg.role == 'assistant' && index == messages.length - 1 && !_sending;
                    return _MessageRow(
                      message: msg,
                      session: widget.session,
                      time: _formatTime(msg.createdAt),
                      canEdit: msg.role == 'user' && !_sending,
                      canRegenerate: isLastAssistant && !_sending,
                      onCopy: () => _copy(msg),
                      onEdit: () => _editAndResend(msg),
                      onRegenerate: _regenerate,
                    );
                  },
                ),
        ),
        if (_failure != null) _FailureCard(failure: _failure!, onRetry: _retry),
        _Composer(
          controller: _input,
          canSend: _canSend,
          sending: _sending,
          onSend: _send,
          onStop: _stop,
          model: aiModelFor(widget.model),
          onPickModel: widget.onModelChanged == null ? null : _pickModel,
          onNewConversation: widget.onNewConversation,
          onClearConversation: widget.onClearConversation,
          onAttach: _showAttachSheet,
          attachments: _attachments,
          onRemoveAttachment: _removeAttachment,
        ),
      ],
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.session,
    required this.time,
    required this.canEdit,
    required this.canRegenerate,
    required this.onCopy,
    required this.onEdit,
    required this.onRegenerate,
  });

  final ChatMessage message;
  final StoredSession? session;
  final String time;
  final bool canEdit;
  final bool canRegenerate;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final fromUser = message.role == 'user';
    final signedIn = fromUser && session != null;
    final initial = signedIn && session!.email.isNotEmpty
        ? session!.email.substring(0, 1).toUpperCase()
        : null;

    final bubble = GestureDetector(
      onLongPress: () async {
        final action = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: AppTheme.surface,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copier'),
                  onTap: () => Navigator.pop(context, 'copy'),
                ),
                if (canEdit)
                  ListTile(
                    leading: const Icon(Icons.edit_rounded),
                    title: const Text('Modifier et relancer'),
                    onTap: () => Navigator.pop(context, 'edit'),
                  ),
                if (canRegenerate)
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('Régénérer'),
                    onTap: () => Navigator.pop(context, 'regen'),
                  ),
              ],
            ),
          ),
        );
        if (action == 'copy') onCopy();
        if (action == 'edit') onEdit();
        if (action == 'regen') onRegenerate();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78 - (signedIn ? 38 : 0),
        ),
        decoration: BoxDecoration(
          gradient: fromUser ? AppTheme.heroGradient : null,
          color: fromUser ? null : AppTheme.surface,
          border: fromUser ? null : Border.all(color: AppTheme.outline),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(fromUser ? 18 : 6),
            bottomRight: Radius.circular(fromUser ? 6 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: fromUser ? Colors.white : AppTheme.textSoft,
              ),
            ),
            if (message.actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final action in message.actions)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        action.ok
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        size: 13,
                        color: action.ok ? AppTheme.accent : const Color(0xFFF3A5B4),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          action.summary,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: AppTheme.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );

    final timeRow = Padding(
      padding: EdgeInsets.only(bottom: 10, left: fromUser ? 0 : 4, right: fromUser ? (signedIn ? 38 : 0) : 4),
      child: Text(
        time,
        style: const TextStyle(fontSize: 10, color: AppTheme.muted),
      ),
    );

    if (!fromUser) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [bubble, timeRow],
        ),
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(child: bubble),
              if (signedIn)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppTheme.heroGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: initial != null
                        ? Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.person_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                  ),
                ),
            ],
          ),
          timeRow,
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.forum_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Commence la discussion',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Appui long sur un message pour copier, modifier ou régénérer.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.current});

  final AiModel current;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  bool _showVersions = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _showVersions ? _versions(context) : _providers(context),
        ),
      ),
    );
  }

  List<Widget> _providers(BuildContext context) {
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: Text(
          'Choisir l’IA',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.text,
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Text(
          'Choisis le fournisseur, puis sa version.',
          style: TextStyle(fontSize: 12, color: AppTheme.muted),
        ),
      ),
      ListTile(
        key: const ValueKey('provider-groq'),
        onTap: () => setState(() => _showVersions = true),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: AppTheme.heroGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            size: 18,
            color: Colors.white,
          ),
        ),
        title: const Text(
          'Groq',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSoft,
          ),
        ),
        subtitle: Text(
          '${aiModels.length} versions · réponses en français',
          style: const TextStyle(fontSize: 12, color: AppTheme.muted),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppTheme.muted,
        ),
      ),
      const SizedBox(height: 8),
    ];
  }

  List<Widget> _versions(BuildContext context) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 20, 4),
        child: Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _showVersions = false),
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              color: AppTheme.textSoft,
              tooltip: 'Fournisseurs',
            ),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Groq',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text,
                  ),
                ),
                Text(
                  'Choisis la version',
                  style: TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
            ),
          ],
        ),
      ),
      for (final model in aiModels)
        ListTile(
          onTap: () => Navigator.of(context).pop(model.id),
          leading: Icon(
            model.id == widget.current.id
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: model.id == widget.current.id ? AppTheme.accent : AppTheme.muted,
          ),
          title: Text(
            model.label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSoft,
            ),
          ),
          subtitle: Text(
            model.description,
            style: const TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
        ),
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Text(
          'Toutes répondent en français. Le choix est mémorisé.',
          style: TextStyle(fontSize: 11.5, color: AppTheme.muted),
        ),
      ),
    ];
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 15,
              color: AppTheme.accent,
            ),
            const SizedBox(width: 8),
            Text(
              'WORLD-AI rédige…',
              style: TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.failure, required this.onRetry});

  final AiFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF5A3140)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: Color(0xFFF3A5B4),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              failure.message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Color(0xFFF6C9D3),
              ),
            ),
          ),
          if (failure.canRetry)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accent,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Réessayer'),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.canSend,
    required this.sending,
    required this.onSend,
    required this.onStop,
    required this.model,
    required this.onPickModel,
    required this.onNewConversation,
    required this.onClearConversation,
    required this.onAttach,
    required this.attachments,
    required this.onRemoveAttachment,
  });

  final TextEditingController controller;
  final bool canSend;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final AiModel model;
  final VoidCallback? onPickModel;
  final VoidCallback onNewConversation;
  final VoidCallback onClearConversation;
  final VoidCallback onAttach;
  final List<_ChatAttachment> attachments;
  final void Function(int) onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(26),
      borderSide: BorderSide.none,
    );

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: AppTheme.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AiBadge(model: model, onTap: onPickModel),
              const SizedBox(height: 10),
              if (attachments.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < attachments.length; i++)
                          Padding(
                            padding: EdgeInsets.only(right: i == attachments.length - 1 ? 0 : 8),
                            child: _AttachmentChip(
                              attachment: attachments[i],
                              onRemove: () => onRemoveAttachment(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  IconButton(
                    onPressed: onAttach,
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'Joindre',
                    color: AppTheme.muted,
                  ),
                  IconButton(
                    onPressed: onNewConversation,
                    icon: const Icon(Icons.edit_note_rounded),
                    tooltip: 'Nouvelle discussion',
                    color: AppTheme.muted,
                  ),
                  IconButton(
                    onPressed: onClearConversation,
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: 'Effacer la conversation',
                    color: AppTheme.muted,
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      cursorColor: AppTheme.accent,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => canSend ? onSend() : null,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.text,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Écris un message…',
                        hintStyle: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.muted,
                        ),
                        filled: true,
                        fillColor: AppTheme.surfaceHigh,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        border: border,
                        enabledBorder: border,
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide(
                            color: AppTheme.seed.withAlpha(170),
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  sending
                      ? _StopButton(onTap: onStop)
                      : _SendButton(enabled: canSend, onTap: onSend),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onRemove});

  final _ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.mime.startsWith('image/');
    return Container(
      height: 64,
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Stack(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(11)),
                child: isImage
                    ? Image.memory(
                        attachment.bytes,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 64,
                        height: 64,
                        color: AppTheme.surface,
                        child: const Icon(Icons.insert_drive_file_rounded, color: AppTheme.muted),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Text(
                    attachment.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.text),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: AppTheme.background,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, size: 14, color: AppTheme.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiBadge extends StatelessWidget {
  const _AiBadge({required this.model, this.onTap});

  final AiModel model;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 18,
            color: AppTheme.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Groq · ${model.label}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSoft,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Relais WORLD-AI · sans limite de messages',
                  style: TextStyle(fontSize: 11, color: AppTheme.muted),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.swap_horiz_rounded,
              size: 18,
              color: AppTheme.muted,
            ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: content,
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: enabled ? AppTheme.accentGradient : null,
        color: enabled ? null : AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled ? Colors.transparent : AppTheme.outline,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 22,
            color: enabled ? const Color(0xFF04231F) : AppTheme.muted,
          ),
        ),
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: const Icon(
            Icons.stop_rounded,
            size: 22,
            color: AppTheme.textSoft,
          ),
        ),
      ),
    );
  }
}
