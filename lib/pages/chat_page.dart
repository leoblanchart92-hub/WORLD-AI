import 'package:flutter/material.dart';

import '../ai/ai_client.dart';
import '../theme/app_theme.dart';

/// Écran principal : fil de discussion et barre de saisie en bas.
///
/// Les messages partent vers le relais WORLD-AI, qui les transmet à Groq avec
/// sa propre clé : l'application n'en contient aucune.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.ai,
    this.model = defaultAiModel,
    this.onModelChanged,
  });

  final AiService ai;

  /// Identifiant de l'IA choisie (voir [aiModels]).
  final String model;

  /// Appelé quand l'utilisateur choisit une autre IA.
  final ValueChanged<String>? onModelChanged;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<AiMessage> _history = [];
  AiFailure? _failure;
  bool _sending = false;
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(_handleInputChanged);
  }

  @override
  void dispose() {
    _input.removeListener(_handleInputChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _handleInputChanged() {
    final canSend = _input.text.trim().isNotEmpty && !_sending;
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _history.add(AiMessage.user(text));
      _input.clear();
      _canSend = false;
      _failure = null;
      _sending = true;
    });
    _scrollToEnd();
    await _request();
  }

  /// Envoie tout l'historique : le relais est sans état, il reçoit le contexte.
  Future<void> _request() async {
    try {
      final reply = await widget.ai.send(List<AiMessage>.of(_history));
      if (!mounted) return;
      setState(() {
        _history.add(AiMessage.assistant(reply.text));
        _sending = false;
        _failure = null;
      });
      _scrollToEnd();
    } on AiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failure = failure;
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failure = const AiFailure('L’IA n’a pas pu répondre. Réessaie.');
      });
      _scrollToEnd();
    }
  }

  /// Choix de l'IA : toutes celles proposées répondent en français.
  Future<void> _pickModel() async {
    final current = aiModelFor(widget.model);
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  'Toutes répondent en français. Le choix est mémorisé.',
                  style: TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ),
              for (final model in aiModels)
                ListTile(
                  onTap: () => Navigator.of(context).pop(model.id),
                  leading: Icon(
                    model.id == current.id
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: model.id == current.id
                        ? AppTheme.accent
                        : AppTheme.muted,
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
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) widget.onModelChanged?.call(chosen);
  }

  Future<void> _retry() async {
    if (_sending || _history.isEmpty) return;
    setState(() {
      _failure = null;
      _sending = true;
    });
    await _request();
  }

  @override
  Widget build(BuildContext context) {
    final showEmpty = _history.isEmpty && !_sending;

    return Column(
      children: [
        Expanded(
          child: showEmpty
              ? const _EmptyChat()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: _history.length + (_sending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _history.length) return const _Thinking();
                    return _Bubble(message: _history[index]);
                  },
                ),
        ),
        if (_failure != null) _FailureCard(failure: _failure!, onRetry: _retry),
        _Composer(
          controller: _input,
          canSend: _canSend,
          onSend: _send,
          model: aiModelFor(widget.model),
          onPickModel: widget.onModelChanged == null ? null : _pickModel,
        ),
      ],
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
              'Écris ton premier message. Tes échanges passent par le relais '
              'WORLD-AI, qui les transmet à l’IA Groq.',
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final fromUser = message.role == 'user';

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
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
        child: Text(
          message.content,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: fromUser ? Colors.white : AppTheme.textSoft,
          ),
        ),
      ),
    );
  }
}

/// Bulle d'attente, volontairement statique : aucune animation continue.
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
    required this.onSend,
    required this.model,
    required this.onPickModel,
  });

  final TextEditingController controller;
  final bool canSend;
  final VoidCallback onSend;
  final AiModel model;
  final VoidCallback? onPickModel;

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
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      cursorColor: AppTheme.accent,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
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
                  _SendButton(enabled: canSend, onTap: onSend),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// IA active : Groq, par l'intermédiaire du relais WORLD-AI.
///
/// La pastille ouvre le choix de l'IA ; sans gestionnaire, elle reste
/// simplement informative.
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
