import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/app_theme.dart';
import 'update_controller.dart';
import 'update_service.dart';

/// Ouvre la feuille de mise à jour : détails, téléchargement, installation.
Future<void> showUpdateSheet(
  BuildContext context,
  UpdateController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xD905040A),
    builder: (_) => UpdateSheet(controller: controller),
  );
}

/// Contenu modal du téléchargement, piloté par l'état partagé [UpdateController].
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({super.key, required this.controller});

  final UpdateController controller;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  Future<void> _download() async {
    final launched = await widget.controller.downloadAndInstall();
    if (!mounted) return;
    if (launched) Navigator.of(context).maybePop();
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;

        return PopScope(
          // Pendant le téléchargement, fermer la feuille perdrait la progression.
          canPop: !controller.isDownloading,
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: AppTheme.outline)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SheetHandle(),
                      const SizedBox(height: 16),
                      _buildBody(controller),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(UpdateController controller) {
    switch (controller.phase) {
      case UpdatePhase.downloading:
      case UpdatePhase.installing:
        return _DownloadingBody(controller: controller);
      case UpdatePhase.error:
        return _ErrorBody(
          message: controller.error ?? 'Une erreur est survenue.',
          onRetry: _download,
          onClose: _close,
        );
      case UpdatePhase.checking:
        return const _SimpleBody(
          icon: Icons.hourglass_top_rounded,
          title: 'Vérification…',
          message: 'Lecture de la dernière version publiée sur GitHub.',
          busy: true,
        );
      case UpdatePhase.available:
        final update = controller.update;
        if (update == null) break;
        return _AvailableBody(
          update: update,
          onDownload: _download,
          onClose: _close,
        );
      case UpdatePhase.idle:
      case UpdatePhase.upToDate:
      case UpdatePhase.noRelease:
        break;
    }

    return _SimpleBody(
      icon: Icons.verified_rounded,
      iconColor: AppTheme.success,
      title: 'Aucune mise à jour',
      message: 'WORLD-AI ${controller.installedLabel} est la dernière version '
          'publiée.',
      onClose: _close,
    );
  }
}

// ---------------------------------------------------------------------------
// Corps de la feuille
// ---------------------------------------------------------------------------

class _AvailableBody extends StatelessWidget {
  const _AvailableBody({
    required this.update,
    required this.onDownload,
    required this.onClose,
  });

  final AppUpdate update;
  final VoidCallback onDownload;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const _IconTile(icon: Icons.rocket_launch_rounded),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mise à jour disponible',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'WORLD-AI ${update.latestVersion}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _VersionBox(
                label: 'Installée',
                value: update.currentVersion.toString(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AppTheme.muted,
              ),
            ),
            Expanded(
              child: _VersionBox(
                label: 'Nouvelle',
                value: update.latestVersion.toString(),
                highlighted: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(icon: Icons.sd_storage_rounded, label: update.readableSize),
            const _Pill(icon: Icons.android_rounded, label: 'APK Android'),
            const _Pill(icon: Icons.verified_rounded, label: 'Signé'),
          ],
        ),
        if (update.releaseNotes.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _SectionLabel('Nouveautés'),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 168),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.outline),
            ),
            child: SingleChildScrollView(
              child: Text(
                update.releaseNotes,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppTheme.textSoft,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        const _Hint(
          text: 'Android demandera l\'autorisation d\'installer des '
              'applications inconnues pour WORLD-AI. Les données de '
              'l\'application sont conservées.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onDownload,
          icon: const Icon(Icons.download_rounded, size: 20),
          label: Text('Télécharger et installer (${update.readableSize})'),
        ),
        const SizedBox(height: 4),
        TextButton(onPressed: onClose, child: const Text('Plus tard')),
      ],
    );
  }
}

class _DownloadingBody extends StatelessWidget {
  const _DownloadingBody({required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    final progress = controller.progress;
    final percent = progress == null ? null : (progress * 100).round();
    final installing = controller.phase == UpdatePhase.installing;
    final total = controller.totalBytes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        Center(
          child: SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 7,
                    backgroundColor: AppTheme.surfaceHigh,
                    color: AppTheme.accent,
                  ),
                ),
                Text(
                  percent == null ? '…' : '$percent %',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            installing
                ? 'Ouverture de l\'installeur…'
                : 'Téléchargement en cours',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.text,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Center(
          child: Text(
            installing
                ? 'Valide l\'installation dans Android.'
                : '${formatBytes(controller.receivedBytes)} sur '
                    '${formatBytes(total)}',
            style: const TextStyle(fontSize: 13, color: AppTheme.muted),
          ),
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: AppTheme.surfaceHigh,
            color: AppTheme.accent,
          ),
        ),
        const SizedBox(height: 18),
        const _Hint(
          text: 'Garde l\'application ouverte jusqu\'à l\'ouverture de '
              'l\'installeur Android.',
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const _IconTile(
              icon: Icons.error_outline_rounded,
              color: Color(0xFFFF6B81),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Téléchargement impossible',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: const TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppTheme.textSoft,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 20),
          label: const Text('Réessayer'),
        ),
        const SizedBox(height: 4),
        TextButton(onPressed: onClose, child: const Text('Fermer')),
      ],
    );
  }
}

class _SimpleBody extends StatelessWidget {
  const _SimpleBody({
    required this.icon,
    required this.title,
    required this.message,
    this.iconColor = AppTheme.seed,
    this.busy = false,
    this.onClose,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color iconColor;
  final bool busy;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _IconTile(icon: icon, color: iconColor, busy: busy),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: const TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppTheme.textSoft,
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(onPressed: onClose, child: const Text('Fermer')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Éléments réutilisables (feuille et pages)
// ---------------------------------------------------------------------------

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFF3A3157),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    this.color = AppTheme.seed,
    this.busy = false,
  });

  final IconData icon;
  final Color color;
  final bool busy;

  static const double _size = 50;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: busy
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: color,
              ),
            )
          : Icon(icon, color: color, size: _size * 0.46),
    );
  }
}

class _VersionBox extends StatelessWidget {
  const _VersionBox({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: highlighted
            ? AppTheme.seed.withAlpha(38)
            : AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? AppTheme.seed.withAlpha(110) : AppTheme.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: AppTheme.muted,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: highlighted ? AppTheme.text : AppTheme.textSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSoft),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

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

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppTheme.muted,
            ),
          ),
        ),
      ],
    );
  }
}
