import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../update/update_config.dart';
import '../update/update_controller.dart';

/// Page « À propos » : identité de l'app, provenance et signature des APK.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(35),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withAlpha(60)),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'WORLD-AI',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version installée ${controller.installedLabel}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withAlpha(210),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Application Android livrée en APK, mise à jour directement '
                    'depuis les releases GitHub.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: Colors.white.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const _InfoRow(
            icon: Icons.link_rounded,
            label: 'Dépôt des releases',
            value: '${UpdateConfig.owner}/${UpdateConfig.repository}',
          ),
          const _InfoRow(
            icon: Icons.key_rounded,
            label: 'Signature',
            value: 'Clé de release stable (EC P-256), certificat versionné',
          ),
          const _InfoRow(
            icon: Icons.install_desktop_rounded,
            label: 'Installation',
            value: 'APK signé, remplace la version précédente sans perte de '
                'données',
          ),
          const _InfoRow(
            icon: Icons.palette_rounded,
            label: 'Interface',
            value: 'Material 3, thème sombre, tiroir latéral',
          ),
          const SizedBox(height: 22),
          const Text(
            'Les mises à jour sont vérifiées au lancement, puis à la demande '
            'depuis le bouton ↻ de la barre supérieure ou la page Mises à jour.',
            style: TextStyle(fontSize: 12, height: 1.5, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
