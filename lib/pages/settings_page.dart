import 'package:flutter/material.dart';

import '../settings_store.dart';
import '../theme/app_theme.dart';
import '../update/update_config.dart';
import '../update/update_controller.dart';
import 'whats_new_page.dart';

/// Paramètres de l'application, ouverts depuis le bas du menu latéral.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.store,
    required this.checkOnLaunch,
    required this.onCheckOnLaunchChanged,
    required this.loadAppIcon,
    required this.onAppIconChanged,
  });

  final UpdateController controller;
  final SettingsStore store;
  final bool checkOnLaunch;
  final ValueChanged<bool> onCheckOnLaunchChanged;
  final Future<String> Function() loadAppIcon;
  final Future<void> Function(String) onAppIconChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// Visuel proposé pour l’icône de l’application.
class _IconOption {
  const _IconOption(this.id, this.label, this.asset);

  final String id;
  final String label;
  final String asset;
}

const List<_IconOption> _appIcons = [
  _IconOption('default', 'Icône 1', 'assets/icons/app_icon_default.png'),
  _IconOption('image2', 'Icône 2', 'assets/icons/app_icon_image2.png'),
  _IconOption('image3', 'Icône 3', 'assets/icons/app_icon_image3.png'),
  _IconOption('image4', 'Icône 4', 'assets/icons/app_icon_image4.png'),
  _IconOption('image5', 'Icône 5', 'assets/icons/app_icon_image5.png'),
  _IconOption('image6', 'Icône 6', 'assets/icons/app_icon_image6.png'),
];

_IconOption _iconFor(String id) {
  for (final icon in _appIcons) {
    if (icon.id == id) return icon;
  }
  return _appIcons.first;
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _checkOnLaunch = widget.checkOnLaunch;
  late Future<String> _appIcon = widget.loadAppIcon();

  Future<void> _setAppIcon(String value) async {
    setState(() {
      _appIcon = Future.value(value);
    });
    await widget.onAppIconChanged(value);
  }

  /// Petite fenêtre de choix de l’icône, appliquée dès qu’une vignette est
  /// touchée.
  Future<void> _pickAppIcon(String current) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => _IconDialog(selected: current),
    );
    if (choice == null || choice == current) return;
    await _setAppIcon(choice);
  }

  Future<void> _setCheckOnLaunch(bool value) async {
    setState(() => _checkOnLaunch = value);
    widget.onCheckOnLaunchChanged(value);
    await widget.store.saveCheckOnLaunch(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const _SectionTitle('Application'),
            Material(
              color: AppTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppTheme.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppTheme.accent,
                ),
                title: const Text(
                  'Nouveauté',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text,
                  ),
                ),
                subtitle: const Text(
                  'Voir toutes les améliorations de l’application',
                  style: TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.muted,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const WhatsNewPage()),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const _SectionTitle('Icône de l’application'),
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Choisis l’icône affichée sur l’écran d’accueil Android.',
                style: TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
            ),
            FutureBuilder<String>(
              future: _appIcon,
              builder: (context, snapshot) {
                final selected = snapshot.data ?? 'default';
                final icon = _iconFor(selected);
                return Material(
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: AppTheme.outline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        icon.asset,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        cacheWidth: 144,
                      ),
                    ),
                    title: const Text(
                      'Icône de l’application',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text,
                      ),
                    ),
                    subtitle: Text(
                      icon.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.muted,
                      ),
                    ),
                    trailing: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Choisir',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accent,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.muted,
                        ),
                      ],
                    ),
                    onTap: snapshot.connectionState == ConnectionState.waiting
                        ? null
                        : () => _pickAppIcon(selected),
                  ),
                );
              },
            ),
            const SizedBox(height: 22),
            const _SectionTitle('Mises à jour'),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.outline),
              ),
              child: Column(
                children: [
                  _SwitchRow(
                    icon: Icons.bolt_rounded,
                    title: 'Vérifier au lancement',
                    subtitle:
                        'Recherche une nouvelle version à chaque '
                        'ouverture de l\'application.',
                    value: _checkOnLaunch,
                    onChanged: _setCheckOnLaunch,
                  ),
                  const Divider(height: 1),
                  _InfoRow(
                    icon: Icons.android_rounded,
                    title: 'Version installée',
                    value: widget.controller.installedLabel,
                  ),
                  const Divider(height: 1),
                  _InfoRow(
                    icon: Icons.link_rounded,
                    title: 'Dépôt des releases',
                    value: '${UpdateConfig.owner}/${UpdateConfig.repository}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'La vérification manuelle reste disponible depuis le bouton '
              'Mise à jour du bas du menu latéral, à tout moment.',
              style: TextStyle(
                fontSize: 12,
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

/// Petite fenêtre de sélection : six vignettes, un toucher applique l’icône
/// et referme la fenêtre.
class _IconDialog extends StatelessWidget {
  const _IconDialog({required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      surfaceTintColor: Colors.transparent,
      scrollable: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppTheme.outline),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      title: const Text(
        'Icône de l’application',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppTheme.text,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < _appIcons.length; index += 2) ...[
              if (index > 0) const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _IconChoice(
                        icon: _appIcons[index],
                        selected: _appIcons[index].id == selected,
                        onTap: () =>
                            Navigator.of(context).pop(_appIcons[index].id),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: index + 1 < _appIcons.length
                        ? AspectRatio(
                            aspectRatio: 1,
                            child: _IconChoice(
                              icon: _appIcons[index + 1],
                              selected: _appIcons[index + 1].id == selected,
                              onTap: () =>
                                  Navigator.of(context)
                                      .pop(_appIcons[index + 1].id),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final _IconOption icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.outline,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(icon.asset, fit: BoxFit.cover, cacheWidth: 360),
                    if (selected)
                      Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: Color(0xFF04231F),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
                child: Text(
                  icon.label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppTheme.seed,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, color: AppTheme.text),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w700,
          color: AppTheme.muted,
        ),
      ),
    );
  }
}
