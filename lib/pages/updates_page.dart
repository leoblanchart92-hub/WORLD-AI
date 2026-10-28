import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/app_theme.dart';
import '../update/update_controller.dart';
import '../update/update_ui.dart';

/// Centre de mises à jour : version installée, version publiée, progression.
class UpdatesPage extends StatelessWidget {
  const UpdatesPage({super.key, required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _VersionOverview(controller: controller),
          const SizedBox(height: 16),
          ..._sections(context),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: controller.isBusy ? null : () => controller.check(),
              icon: controller.phase == UpdatePhase.checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 20),
              label: Text(
                controller.phase == UpdatePhase.checking
                    ? 'Vérification…'
                    : 'Vérifier les mises à jour',
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _InfoCard(
            icon: Icons.shield_rounded,
            title: 'Signature stable',
            message: 'Chaque APK est signé avec la même clé de release : '
                'Android accepte la mise à jour par-dessus l\'application '
                'existante, sans perdre les données.',
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    switch (controller.phase) {
      case UpdatePhase.available:
        final update = controller.update;
        if (update == null) break;
        return [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppTheme.seed.withAlpha(80)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nouveautés',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  update.releaseNotes.isEmpty
                      ? 'Aucune note de version.'
                      : update.releaseNotes,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppTheme.textSoft,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => showUpdateSheet(context, controller),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: Text('Installer la version ${update.latestVersion}'),
                  ),
                ),
              ],
            ),
          ),
        ];
      case UpdatePhase.downloading:
      case UpdatePhase.installing:
        final progress = controller.progress;
        return [
          _InfoCard(
            icon: controller.phase == UpdatePhase.installing
                ? Icons.settings_rounded
                : Icons.downloading_rounded,
            color: AppTheme.accent,
            title: controller.phase == UpdatePhase.installing
                ? 'Ouverture de l\'installeur…'
                : 'Téléchargement en cours',
            message:
                '${((progress ?? 0) * 100).round()} % · '
                '${formatBytes(controller.receivedBytes)} sur '
                '${formatBytes(controller.totalBytes)}',
            progress: progress,
          ),
        ];
      case UpdatePhase.error:
        return [
          _InfoCard(
            icon: Icons.error_outline_rounded,
            color: const Color(0xFFFF6B81),
            title: 'Vérification impossible',
            message: controller.error ?? 'Une erreur est survenue.',
          ),
        ];
      case UpdatePhase.upToDate:
        return const [
          _InfoCard(
            icon: Icons.verified_rounded,
            color: AppTheme.success,
            title: 'Tout est à jour',
            message: 'La version installée est la dernière publiée sur GitHub.',
          ),
        ];
      case UpdatePhase.noRelease:
        return const [
          _InfoCard(
            icon: Icons.inbox_rounded,
            iconColor: AppTheme.muted,
            title: 'Aucune version publiée',
            message: 'Dès que la CI publie une release, elle apparaîtra ici.',
          ),
        ];
      case UpdatePhase.idle:
      case UpdatePhase.checking:
        break;
    }
    return const [];
  }
}

class _VersionOverview extends StatelessWidget {
  const _VersionOverview({required this.controller});

  final UpdateController controller;

  String get _publishedLabel {
    final update = controller.update;
    if (update != null) return update.latestVersion.toString();
    if (controller.phase == UpdatePhase.upToDate) {
      return controller.currentVersion?.toString() ?? '—';
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Installée',
                  value: controller.installedLabel,
                ),
              ),
              Container(width: 1, height: 44, color: AppTheme.outline),
              const SizedBox(width: 16),
              Expanded(
                child: _Stat(
                  label: 'Publiée',
                  value: _publishedLabel,
                  highlighted: controller.phase == UpdatePhase.available,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _StatusPill(controller: controller),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
            color: AppTheme.muted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: highlighted ? AppTheme.accent : AppTheme.text,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    final (Color color, String label) = switch (controller.phase) {
      UpdatePhase.checking => (AppTheme.seed, 'Vérification en cours'),
      UpdatePhase.available => (
          AppTheme.accent,
          'Mise à jour ${controller.update?.latestVersion} disponible',
        ),
      UpdatePhase.downloading => (
          AppTheme.accent,
          'Téléchargement ${((controller.progress ?? 0) * 100).round()} %',
        ),
      UpdatePhase.installing => (AppTheme.accent, 'Installation en cours'),
      UpdatePhase.upToDate => (AppTheme.success, 'À jour'),
      UpdatePhase.noRelease => (AppTheme.muted, 'Aucune release publiée'),
      UpdatePhase.error => (const Color(0xFFFF6B81), 'Erreur de vérification'),
      UpdatePhase.idle => (AppTheme.muted, 'Pas encore vérifié'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
    this.color = AppTheme.seed,
    this.iconColor,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final Color? iconColor;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final tint = iconColor ?? color;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint.withAlpha(32),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: tint.withAlpha(80)),
                ),
                child: Icon(icon, size: 19, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppTheme.muted,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: AppTheme.surfaceHigh,
                color: AppTheme.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
