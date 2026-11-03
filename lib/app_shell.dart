import 'package:flutter/material.dart';

import 'ai/ai_client.dart';
import 'auth/auth_client.dart';
import 'chat/chat_models.dart';
import 'chat/conversation_store.dart';
import 'github/github_client.dart';
import 'pages/account_page.dart';
import 'pages/chat_page.dart';
import 'pages/github_page.dart';
import 'pages/settings_page.dart';
import 'pages/sites_page.dart';
import 'pages/updates_page.dart';
import 'pages/whats_new_page.dart';
import 'settings_store.dart';
import 'sites/sites_client.dart';
import 'theme/app_theme.dart';
import 'update/update_controller.dart';
import 'update/update_ui.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    this.checkUpdatesOnStart = true,
    this.settingsStore,
    this.loadAppIcon,
    this.onAppIconChanged,
    this.aiService,
    this.authService,
    this.githubService,
    this.sitesService,
  });

  final UpdateController controller;
  final bool checkUpdatesOnStart;

  final AiService? aiService;
  final AuthService? authService;
  final GithubService? githubService;
  final SitesService? sitesService;
  final SettingsStore? settingsStore;
  final Future<String> Function()? loadAppIcon;
  final Future<void> Function(String)? onAppIconChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<String> _titles = ['Discussion', 'Mises à jour'];

  static const Duration _preferenceTimeout = Duration(milliseconds: 800);

  late final SettingsStore _settings = widget.settingsStore ?? SettingsStore();

  String _aiModel = defaultAiModel;
  AiService? _aiClient;

  late final AuthService _auth = widget.authService ?? AuthClient();
  late final GithubService _github = widget.githubService ?? GithubClient();
  late final SitesService _sites = widget.sitesService ?? SitesClient();

  StoredSession? _session;

  AiService get _ai =>
      widget.aiService ??
      (_aiClient ??= AiClient(
        deviceId: _settings.deviceId,
        model: _aiModel,
        token: _session?.token,
      ));

  int _index = 0;
  bool _checkOnLaunch = true;

  late final ConversationStore _conversationStore = ConversationStore(token: _session?.token);
  List<Conversation> _conversations = [];
  String? _activeConversationId;

  Conversation get _activeConversation {
    if (_conversations.isEmpty) {
      final c = _createNewConversation();
      _conversations = [c];
      _activeConversationId = c.id;
      return c;
    }
    return _conversations.firstWhere(
      (c) => c.id == _activeConversationId,
      orElse: () => _conversations.first,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.controller.loadInstalledVersion();
    _checkOnLaunch = widget.checkUpdatesOnStart;
    _loadAiModel();
    _loadSession();
    _loadConversations();
    if (widget.checkUpdatesOnStart) _loadPreferences();
  }

  Future<void> _loadAiModel() async {
    final stored = await _settings.loadAiModel(fallback: defaultAiModel);
    final model = aiModelFor(stored);
    if (!mounted || model.id == _aiModel) return;
    setState(() {
      _aiModel = model.id;
      _aiClient = null;
    });
  }

  Future<void> _loadSession() async {
    final session = await _settings.loadSession();
    if (!mounted) return;
    setState(() {
      _session = session;
      _aiClient = null;
      _conversationStore.token = session?.token;
    });
    _loadConversations();
  }

  void _onSessionChanged(StoredSession? session) {
    if (!mounted) return;
    setState(() {
      _session = session;
      _aiClient = null;
      _conversationStore.token = session?.token;
    });
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final local = await _conversationStore.load();
    if (!mounted) return;
    if (_session != null) {
      try {
        final remote = await _conversationStore.fetchRemote(_ai as AiClient);
        if (remote.isNotEmpty) {
          final list = <Conversation>[];
          for (final r in remote) {
            list.add(Conversation(
              id: r['id'] as String,
              title: r['title'] as String? ?? 'Nouvelle discussion',
              createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
              messages: [],
              remote: true,
            ));
          }
          setState(() {
            _conversations = list;
            _activeConversationId ??= list.first.id;
          });
          await _conversationStore.save(_conversations);
          return;
        }
      } catch (_) {}
    }
    if (local.isNotEmpty) {
      setState(() {
        _conversations = local;
        _activeConversationId ??= local.first.id;
      });
    } else {
      final c = _createNewConversation();
      setState(() {
        _conversations = [c];
        _activeConversationId = c.id;
      });
      await _conversationStore.save(_conversations);
    }
  }

  Conversation _createNewConversation() {
    final now = DateTime.now();
    return Conversation(
      id: '${now.microsecondsSinceEpoch}-${now.hashCode.abs()}',
      title: 'Nouvelle discussion',
      createdAt: now,
      updatedAt: now,
      messages: [],
      remote: _session != null,
    );
  }

  Future<void> _newConversation() async {
    var c = _createNewConversation();
    if (_session != null) {
      try {
        final res = await _conversationStore.createRemote(_ai as AiClient, c.title);
        if (res != null && res['id'] != null) {
          c = Conversation(
            id: res['id'] as String,
            title: res['title'] as String? ?? c.title,
            createdAt: DateTime.fromMillisecondsSinceEpoch(res['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(res['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
            messages: [],
            remote: true,
          );
        }
      } catch (_) {}
    }
    setState(() {
      _conversations.insert(0, c);
      _activeConversationId = c.id;
      _index = 0;
    });
    await _conversationStore.save(_conversations);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _clearConversation() async {
    final conv = _activeConversation;
    setState(() {
      conv.messages.clear();
      conv.updatedAt = DateTime.now();
    });
    await _conversationStore.save(_conversations);
  }

  Future<void> _deleteConversation(String id) async {
    if (_session != null) {
      try {
        await _conversationStore.deleteRemote(_ai as AiClient, id);
      } catch (_) {}
    }
    setState(() {
      _conversations.removeWhere((c) => c.id == id);
      if (_conversations.isEmpty) {
        final c = _createNewConversation();
        _conversations = [c];
        _activeConversationId = c.id;
      } else if (_activeConversationId == id) {
        _activeConversationId = _conversations.first.id;
      }
    });
    await _conversationStore.save(_conversations);
    if (mounted) Navigator.of(context).maybePop();
  }

  void _selectConversation(String id) {
    setState(() => _activeConversationId = id);
    if (mounted) Navigator.of(context).maybePop();
    if (_index != 0) _select(0);
  }

  Future<void> _openAccount() async {
    final navigator = Navigator.of(context);
    await navigator.maybePop();
    if (!mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => AccountPage(
          auth: _auth,
          settings: _settings,
          session: _session,
          onSessionChanged: _onSessionChanged,
        ),
      ),
    );
  }

  Future<void> _openGithub() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GithubPage(
          github: _github,
          session: _session,
          onOpenAccount: _openAccount,
        ),
      ),
    );
  }

  Future<void> _openSites() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SitesPage(sites: _sites, session: _session),
      ),
    );
  }

  Future<void> _changeAiModel(String id) async {
    final model = aiModelFor(id);
    if (model.id == _aiModel) return;
    setState(() {
      _aiModel = model.id;
      _aiClient = null;
    });
    await _settings.saveAiModel(model.id);
  }

  Future<void> _loadPreferences() async {
    final stored = await _settings
        .loadCheckOnLaunch(fallback: true)
        .timeout(_preferenceTimeout, onTimeout: () => _checkOnLaunch);
    if (!mounted) return;
    if (stored != _checkOnLaunch) setState(() => _checkOnLaunch = stored);
    if (!stored) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startupCheck();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _startupCheck() async {
    await widget.controller.check(silent: true);
    if (!mounted) return;
    if (widget.controller.phase == UpdatePhase.available) {
      await showUpdateSheet(context, widget.controller);
    }
  }

  void _select(int index) => setState(() => _index = index);

  void _selectFromDrawer(int index) {
    Navigator.of(context).maybePop();
    _select(index);
  }

  Future<void> _updateFromDrawer() async {
    Navigator.of(context).maybePop();
    if (widget.controller.phase == UpdatePhase.available) {
      await showUpdateSheet(context, widget.controller);
      return;
    }
    _select(1);
    await widget.controller.check();
  }

  void _openWhatsNew() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const WhatsNewPage()));
  }

  Future<void> _saveAppIcon(String icon) async {
    await _settings.saveAppIcon(icon);
  }

  Future<void> _openSettings() async {
    final navigator = Navigator.of(context);
    await navigator.maybePop();
    if (!mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          controller: widget.controller,
          store: _settings,
          checkOnLaunch: _checkOnLaunch,
          onCheckOnLaunchChanged: (value) =>
              setState(() => _checkOnLaunch = value),
          loadAppIcon: widget.loadAppIcon ?? _settings.loadAppIcon,
          onAppIconChanged: widget.onAppIconChanged ?? _saveAppIcon,
          onOpenGithub: _openGithub,
          onOpenSites: _openSites,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Scaffold(
      appBar: AppBar(
        title: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_titles[_index]),
              const SizedBox(height: 2),
              Text(
                'WORLD-AI ${controller.installedLabel}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
        ),
        actions: _index == 0
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    onPressed: _openWhatsNew,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                    label: const Text('Nouveauté'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 38),
                    ),
                  ),
                ),
              ]
            : null,
      ),
      drawer: _AppDrawer(
        index: _index,
        controller: controller,
        session: _session,
        conversations: _conversations,
        activeId: _activeConversationId,
        onSelected: _selectFromDrawer,
        onUpdate: _updateFromDrawer,
        onSettings: _openSettings,
        onAccount: _openAccount,
        onNewConversation: _newConversation,
        onSelectConversation: _selectConversation,
        onDeleteConversation: _deleteConversation,
      ),
      body: IndexedStack(
        index: _index,
        children: [
          ChatPage(
            ai: _ai,
            conversation: _activeConversation,
            onConversationChanged: (c) {
              setState(() {});
              _conversationStore.save(_conversations);
              if (_session != null) {
                _conversationStore.syncMessages(_ai as AiClient, c.id, c.messages);
              }
            },
            onNewConversation: _newConversation,
            onClearConversation: _clearConversation,
            onDeleteConversation: _deleteConversation,
            session: _session,
            model: _aiModel,
            onModelChanged: _changeAiModel,
          ),
          UpdatesPage(controller: controller),
        ],
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.index,
    required this.controller,
    required this.session,
    required this.conversations,
    required this.activeId,
    required this.onSelected,
    required this.onUpdate,
    required this.onSettings,
    required this.onAccount,
    required this.onNewConversation,
    required this.onSelectConversation,
    required this.onDeleteConversation,
  });

  final int index;
  final UpdateController controller;
  final StoredSession? session;
  final List<Conversation> conversations;
  final String? activeId;
  final ValueChanged<int> onSelected;
  final VoidCallback onUpdate;
  final VoidCallback onSettings;
  final VoidCallback onAccount;
  final VoidCallback onNewConversation;
  final ValueChanged<String> onSelectConversation;
  final ValueChanged<String> onDeleteConversation;

  String get _updateSubtitle {
    switch (controller.phase) {
      case UpdatePhase.available:
        return 'Version ${controller.update?.latestVersion} prête';
      case UpdatePhase.downloading:
        return 'Téléchargement ${((controller.progress ?? 0) * 100).round()} %';
      case UpdatePhase.installing:
        return 'Installation en cours';
      case UpdatePhase.checking:
        return 'Vérification…';
      case UpdatePhase.upToDate:
        return 'À jour';
      case UpdatePhase.noRelease:
        return 'Aucune version publiée';
      case UpdatePhase.error:
        return 'Vérification impossible';
      case UpdatePhase.idle:
        return 'Toucher pour vérifier';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Drawer(
          backgroundColor: const Color(0xFF0F0C1B),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: AppTheme.heroGradient,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.seed.withAlpha(70),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'WORLD-AI',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: AppTheme.text,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${controller.installedLabel} · Android',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(indent: 24, endIndent: 24),
                const SizedBox(height: 10),
                _AccountTile(session: session, onTap: onAccount),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ListTile(
                    leading: const Icon(Icons.add_rounded, color: AppTheme.accent),
                    title: const Text('Nouvelle discussion',
                        style: TextStyle(color: AppTheme.textSoft, fontWeight: FontWeight.w600)),
                    onTap: onNewConversation,
                  ),
                ),
                const SizedBox(height: 6),
                const Divider(indent: 24, endIndent: 24),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Historique',
                        style: TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final c = conversations[index];
                      final active = c.id == activeId;
                      return ListTile(
                        dense: true,
                        selected: active,
                        selectedTileColor: AppTheme.seed.withAlpha(36),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        leading: Icon(Icons.chat_bubble_outline_rounded,
                            color: active ? AppTheme.accent : AppTheme.muted, size: 18),
                        title: Text(c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: active ? AppTheme.text : AppTheme.textSoft, fontSize: 13)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.muted),
                          onPressed: () => onDeleteConversation(c.id),
                        ),
                        onTap: () => onSelectConversation(c.id),
                      );
                    },
                  ),
                ),
                const Divider(indent: 24, endIndent: 24),
                _FooterTile(
                  icon: Icons.download_rounded,
                  label: 'Mise à jour',
                  subtitle: _updateSubtitle,
                  highlighted: controller.phase == UpdatePhase.available,
                  onTap: onUpdate,
                ),
                _FooterTile(
                  icon: Icons.settings_outlined,
                  label: 'Paramètres',
                  subtitle: 'Préférences de l\'application',
                  onTap: onSettings,
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: Text(
                    'Mises à jour signées, publiées depuis GitHub Releases.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.45,
                      color: AppTheme.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.session, required this.onTap});

  final StoredSession? session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final signedIn = session != null;
    final initial = signedIn && session!.email.isNotEmpty
        ? session!.email.substring(0, 1).toUpperCase()
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: signedIn ? AppTheme.seed.withAlpha(28) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: signedIn ? AppTheme.heroGradient : null,
                    color: signedIn ? null : AppTheme.surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: initial != null
                      ? Text(
                          initial,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.person_outline_rounded,
                          size: 18,
                          color: AppTheme.muted,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session?.email ?? 'Se connecter',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: signedIn ? AppTheme.text : AppTheme.textSoft,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        signedIn
                            ? 'Compte WORLD-AI'
                            : 'Créer un compte ou se connecter',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppTheme.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterTile extends StatelessWidget {
  const _FooterTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final tint = highlighted ? AppTheme.accent : AppTheme.muted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Material(
        color: highlighted ? AppTheme.accent.withAlpha(24) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: highlighted ? AppTheme.accent.withAlpha(80) : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tint.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 18, color: tint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: tint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
