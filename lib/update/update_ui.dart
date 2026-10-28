import 'package:flutter/material.dart';

import 'apk_installer.dart';
import 'update_service.dart';

/// Vérifie les mises à jour et propose l'installation si nécessaire.
///
/// [silent] réserve les messages à l'utilisateur : utilisé au démarrage, où
/// l'absence de réseau ou de release publiée ne doit rien afficher.
Future<void> checkForUpdates(
  BuildContext context,
  GithubUpdateService service, {
  bool silent = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  try {
    final result = await service.check();
    if (!context.mounted) return;

    switch (result.status) {
      case UpdateStatus.updateAvailable:
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              UpdateDialog(service: service, update: result.update!),
        );
      case UpdateStatus.upToDate:
        if (!silent) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('WORLD-AI est à jour (v${result.currentVersion}).'),
            ),
          );
        }
      case UpdateStatus.noReleasePublished:
        if (!silent) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Aucune version n\'est publiée.')),
          );
        }
    }
  } on UpdateException catch (error) {
    if (!silent) {
      messenger.showSnackBar(
        SnackBar(content: Text('Vérification impossible : ${error.message}')),
      );
    }
  } catch (error) {
    if (!silent) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Vérification impossible pour le moment.'),
        ),
      );
    }
  }
}

/// Dialogue de mise à jour : téléchargement avec progression puis installation.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.service, required this.update});

  final GithubUpdateService service;
  final AppUpdate update;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _busy = false;
  double? _progress;
  String? _error;

  Future<void> _downloadAndInstall() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
    });

    try {
      final apk = await widget.service.downloadApk(
        widget.update,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
          });
        },
      );

      await installApk(apk);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on UpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Installation impossible : $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    final theme = Theme.of(context);
    final progress = _progress;

    return AlertDialog(
      title: Text('Mise à jour ${update.latestVersion}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Version installée : ${update.currentVersion}'),
            const SizedBox(height: 4),
            Text(
              'Nouvelle version : ${update.latestVersion} '
              '(${update.readableSize})',
            ),
            if (update.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Nouveautés', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(_shorten(update.releaseNotes)),
            ],
            const SizedBox(height: 16),
            if (_busy) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                progress == null
                    ? 'Téléchargement…'
                    : 'Téléchargement ${(progress * 100).round()} %',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            Text(
              'Android demande l\'autorisation d\'installer des applications '
              'inconnues pour WORLD-AI si elle n\'est pas encore accordée.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: _busy ? null : _downloadAndInstall,
          child: Text(_busy ? 'Installation…' : 'Télécharger et installer'),
        ),
      ],
    );
  }

  static String _shorten(String notes, {int maxLength = 600}) {
    final compact = notes.trim();
    if (compact.length <= maxLength) return compact;
    return '${compact.substring(0, maxLength).trimRight()}…';
  }
}
