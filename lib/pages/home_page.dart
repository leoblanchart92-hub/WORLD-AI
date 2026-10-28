import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/app_theme.dart';
import '../update/update_controller.dart';
import '../update/update_ui.dart';

/// Page d'accueil : identité de l'app, état des mises à jour, raccourcis.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.onNavigate,
  });

  final UpdateController controller;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _HeroCard(controller: controller),
          const SizedBox(height: 24),
          const _SectionTitle('Mises à jour'),
          const SizedBox(height: 10),
          _UpdateCard(controller: controller, onOpen: () => _open(context)),
          const SizedBox(height: 24),
          const _SectionTitle('Accès rapide'),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _QuickTile(
                    icon: Icons.tune_rounded,
                    title: 'Centre de mises à jour',
                    subtitle: 'Détails et installation',
                    onTap: () => onNavigate(1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickTile(
                    icon: Icons.shield_rounded,
                    title: 'À propos',
                    subtitle: 'Signature et source',
                    onTap: () => onNavigate(2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const Text(
            'Une mise à jour remplace l\'application sans désinstallation : '
            'les données restent sur le téléphone.',
            style: TextStyle(fontSize: 12, height: 1.5, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    if (controller.phase == UpdatePhase.available) {
      await showUpdateSheet(context, controller);
    } else {
      onNavigate(1);
    }
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: Stack(
          children: [
            Positioned(
              right: -46,
              top: -56,
              child: _Glow(size: 180, color: Colors.white.withAlpha(20)),
            ),
            Positioned(
              right: 24,
              bottom: -66,
              child: _Glow(size: 140, color: AppTheme.accent.withAlpha(38)),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'APPLICATION ANDROID',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2.4,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFCFC2FF),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'WORLD-AI',
                    style: TextStyle(
                      fontSize: 32,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Interface modernisée, mises à jour signées et installées '
                    'depuis GitHub.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Colors.white.withAlpha(215),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _HeroChip(
                        icon: Icons.android_rounded,
                        label: controller.installedLabel,
                      ),
                      const SizedBox(width: 8),
                      const _HeroChip(
                        icon: Icons.bolt_rounded,
                        label: 'Mises à jour auto',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.controller, required this.onOpen});

  final UpdateController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color tint, String title, String subtitle) = switch (
        controller.phase) {
      UpdatePhase.checking => (
          Icons.hourglass_top_rounded,
          AppTheme.seed,
          'Vérification en cours',
          'Lecture de la dernière version sur GitHub.',
        ),
      UpdatePhase.available => (
          Icons.arrow_circle_up_rounded,
          AppTheme.accent,
          'Version ${controller.update?.latestVersion} prête',
          '${controller.update?.readableSize ?? ''} · Touche pour installer.',
        ),
      UpdatePhase.downloading || UpdatePhase.installing => (
          Icons.downloading_rounded,
          AppTheme.accent,
          'Mise à jour en cours',
          '${((controller.progress ?? 0) * 100).round()} % · '
              '${formatBytes(controller.receivedBytes)} sur '
              '${formatBytes(controller.totalBytes)}',
        ),
      UpdatePhase.upToDate => (
          Icons.verified_rounded,
          AppTheme.success,
          'À jour',
          'Tu utilises la dernière version publiée.',
        ),
      UpdatePhase.noRelease => (
          Icons.inbox_rounded,
          AppTheme.muted,
          'Aucune version publiée',
          'Les releases apparaîtront après le premier build.',
        ),
      UpdatePhase.error => (
          Icons.error_outline_rounded,
          const Color(0xFFFF6B81),
          'Vérification impossible',
          controller.error ?? 'Réessaie depuis le centre de mises à jour.',
        ),
      UpdatePhase.idle => (
          Icons.system_update_alt_rounded,
          AppTheme.seed,
          'Vérifier les mises à jour',
          'Ouvre le centre de mises à jour.',
        ),
    };

    final showProgress = controller.isDownloading;

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.outline),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tint.withAlpha(36),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: tint.withAlpha(90)),
                ),
                child: Icon(icon, color: tint, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppTheme.muted,
                      ),
                    ),
                    if (showProgress) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: controller.progress,
                          minHeight: 6,
                          backgroundColor: AppTheme.surfaceHigh,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: AppTheme.accent),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
        color: AppTheme.muted,
      ),
    );
  }
}
