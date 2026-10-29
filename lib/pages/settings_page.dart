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

class _SettingsPageState extends State<SettingsPage> {
  static const Map<String, String> _iconAssets = {
    'default': 'assets/icons/app_icon_default.png',
    'image2': 'assets/icons/app_icon_image2.png',
    'image3': 'assets/icons/app_icon_image3.png',
  };

  late bool _checkOnLaunch = widget.checkOnLaunch;
  late Future<String> _appIcon = widget.loadAppIcon();

  Future<void> _setAppIcon(String value) async {
    setState(() {
      _appIcon = Future.value(value);
    });
    await widget.onAppIconChanged(value);
  }

  Future<void> _setCheckOnLaunch(bool value) async {
    setState(() => _checkOnLaunch = value);
    widget.onCheckOnLaunchChanged(value);
    await widget.store.saveCheckOnLaunch(value);
  }

  String _iconLabel(String value) {
    switch (value) {
      case 'image2':
        return 'Icône 2';
      case 'image3':
        return 'Icône 3';
      default:
        return 'Icône 1';
    }
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
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.outline),
                  ),
                  child: Material(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    child: RadioGroup<String>(
                      groupValue: selected,
                      onChanged: (value) {
                        if (value != null &&
                            snapshot.connectionState !=
                                ConnectionState.waiting) {
                          _setAppIcon(value);
                        }
                      },
                      child: Column(
                        children: [
                          for (final entry in _iconAssets.entries)
                            RadioListTile<String>(
                              value: entry.key,
                              enabled:
                                  snapshot.connectionState !=
                                  ConnectionState.waiting,
                              activeColor: AppTheme.accent,
                              title: Text(_iconLabel(entry.key)),
                              secondary: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.asset(
                                  entry.value,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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
