import 'package:flutter/material.dart';

import 'pages/chat_page.dart';
import 'pages/settings_page.dart';
import 'pages/updates_page.dart';
import 'pages/whats_new_page.dart';
import 'settings_store.dart';
import 'theme/app_theme.dart';
import 'update/update_controller.dart';
import 'update/update_ui.dart';

/// Coquille de l'application : barre supérieure, menu latéral et pages.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    this.checkUpdatesOnStart = true,
    this.settingsStore,
    this.loadAppIcon,
    this.onAppIconChanged,
  });

  final UpdateController controller;
  final bool checkUpdatesOnStart;

  /// Injecté par les tests ; sinon les préférences viennent du disque.
  final SettingsStore? settingsStore;
  final Future<String> Function()? loadAppIcon;
  final Future<void> Function(String)? onAppIconChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<String> _titles = ['Discussion', 'Mises à jour'];

  /// Au-delà de ce délai, la préférence est considérée comme activée : un
  /// stockage lent ne doit pas désactiver silencieusement les mises à jour.
  static const Duration _preferenceTimeout = Duration(milliseconds: 800);

  late final SettingsStore _settings = widget.settingsStore ?? SettingsStore();

  int _index = 0;
  bool _checkOnLaunch = true;

  @override
  void initState() {
    super.initState();
    widget.controller.loadInstalledVersion();
    _checkOnLaunch = widget.checkUpdatesOnStart;
    if (widget.checkUpdatesOnStart) _loadPreferences();
  }

  /// Les préférences décident si la vérification automatique a lieu ; elles
  /// sont lues avant la première requête réseau.
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

  /// Vérification silencieuse : elle n'ouvre la feuille que s'il y a
  /// réellement quelque chose à installer.
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

  /// Bouton « Mise à jour » du bas du menu : installe si une version attend,
  /// sinon ouvre le centre de mises à jour et lance la vérification.
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WhatsNewPage()),
    );
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
        onSelected: _selectFromDrawer,
        onUpdate: _updateFromDrawer,
        onSettings: _openSettings,
      ),
      body: IndexedStack(
        index: _index,
        children: [
          const ChatPage(),
          UpdatesPage(controller: controller),
        ],
      ),
    );
  }
}

/// Menu latéral : identité de l'app, navigation, puis mise à jour et
/// paramètres ancrés en bas.
class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.index,
    required this.controller,
    required this.onSelected,
    required this.onUpdate,
    required this.onSettings,
  });

  final int index;
  final UpdateController controller;
  final ValueChanged<int> onSelected;
  final VoidCallback onUpdate;
  final VoidCallback onSettings;

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
                _NavTile(
                  icon: Icons.forum_outlined,
                  selectedIcon: Icons.forum_rounded,
                  label: 'Discussion',
                  selected: index == 0,
                  onTap: () => onSelected(0),
                ),
                const Spacer(),
                const Divider(indent: 24, endIndent: 24),
                const SizedBox(height: 10),
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

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? AppTheme.seed.withAlpha(48) : Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Icon(selected ? selectedIcon : icon, color: AppTheme.textSoft),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppTheme.text : AppTheme.textSoft,
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
                color: highlighted
                    ? AppTheme.accent.withAlpha(80)
                    : Colors.transparent,
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
