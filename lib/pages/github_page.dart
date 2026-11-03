import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_client.dart';
import '../github/github_client.dart';
import '../theme/app_theme.dart';

/// Connexion du compte GitHub personnel.
///
/// L'IA agit ensuite sur les dépôts de cette personne, avec les droits de son
/// jeton. Le jeton reste sur le relais ; l'application ne voit que le nom du
/// compte connecté.
class GithubPage extends StatefulWidget {
  const GithubPage({
    super.key,
    required this.github,
    required this.session,
    this.onOpenAccount,
  });

  final GithubService github;
  final StoredSession? session;
  final VoidCallback? onOpenAccount;

  @override
  State<GithubPage> createState() => _GithubPageState();
}

class _GithubPageState extends State<GithubPage> {
  GithubStatus? _status;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final _tokenController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  String? get _token => widget.session?.token;

  Future<void> _refresh() async {
    final token = _token;
    if (token == null) {
      setState(() {
        _loading = false;
        _status = const GithubStatus(
          signedIn: false,
          deviceFlow: false,
          connected: false,
        );
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.github.status(token);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is GithubFailure ? error.message : 'Chargement impossible.';
        _loading = false;
      });
    }
  }

  Future<void> _startConnection() async {
    final token = _token;
    if (token == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final device = await widget.github.start(token);
      if (!mounted) return;
      setState(() => _busy = false);
      await _showDeviceSheet(device);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is GithubFailure ? error.message : 'Connexion impossible.';
      });
    }
  }

  /// Affiche le code à recopier et interroge le relais jusqu'à validation.
  Future<void> _showDeviceSheet(GithubDevice device) async {
    final token = _token;
    if (token == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _DeviceSheet(
        device: device,
        poll: () => widget.github.poll(token, device.id),
        onConnected: (login) {
          Navigator.of(sheetContext).pop();
          _refresh();
        },
      ),
    );
  }

  Future<void> _usePersonalToken() async {
    final token = _token;
    final pat = _tokenController.text.trim();
    if (token == null || _busy) return;
    if (pat.length < 20) {
      setState(() => _error = 'Ce jeton est trop court pour être valide.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final login = await widget.github.connectToken(token, pat);
      _tokenController.clear();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GitHub connecté : $login')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is GithubFailure ? error.message : 'Jeton refusé.';
      });
    }
  }

  Future<void> _pickRepo() async {
    final token = _token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final repos = await widget.github.repos(token);
      if (!mounted) return;
      setState(() => _busy = false);
      final choice = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppTheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => _RepoSheet(
          repos: repos,
          selected: _status?.defaultRepo ?? '',
        ),
      );
      if (choice == null || !mounted) return;
      await widget.github.setRepo(token, choice);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is GithubFailure ? error.message : 'Liste indisponible.';
      });
    }
  }

  Future<void> _disconnect() async {
    final token = _token;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceHigh,
        title: const Text('Déconnecter GitHub ?'),
        content: const Text(
          'L’IA ne pourra plus lire ni modifier tes dépôts. Tu pourras '
          'reconnecter ton compte à tout moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.github.disconnect(token);
      if (!mounted) return;
      setState(() => _busy = false);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is GithubFailure ? error.message : 'Déconnexion impossible.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (status == null)
            _Message(
              icon: Icons.cloud_off_rounded,
              title: 'État indisponible',
              body: _error ?? 'Réessaie dans un instant.',
              action: TextButton(onPressed: _refresh, child: const Text('Réessayer')),
            )
          else ...[
            if (_error != null) ...[
              _ErrorBanner(_error!),
              const SizedBox(height: 16),
            ],
            if (!status.signedIn) _signedOutCard() else if (status.connected)
              _connectedCard(status)
            else
              _connectCard(status),
            const SizedBox(height: 22),
            const _SectionTitle('Ce que l’IA peut faire'),
            const _Bullet('Lire le code, les issues, les pull requests et les Actions.'),
            const _Bullet('Écrire des fichiers et pousser un commit sur une branche.'),
            const _Bullet('Ouvrir, commenter et fermer une issue.'),
            const _Bullet('Créer, lire et fusionner une pull request.'),
            const _Bullet('Déclencher un workflow GitHub Actions.'),
            const SizedBox(height: 18),
            const Text(
              'Chaque action est affichée sous la réponse de l’IA. Le jeton '
              'reste sur le relais : il n’est jamais renvoyé à l’application.',
              style: TextStyle(fontSize: 12, height: 1.5, color: AppTheme.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _signedOutCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
            icon: Icons.person_outline_rounded,
            title: 'Compte WORLD-AI requis',
          ),
          const SizedBox(height: 10),
          const Text(
            'Le compte GitHub se rattache au compte WORLD-AI : ouvre ton compte '
            'd’abord, puis reviens ici pour lier GitHub.',
            style: TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textSoft),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: widget.onOpenAccount,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
            child: const Text('Ouvrir mon compte'),
          ),
        ],
      ),
    );
  }

  Widget _connectCard(GithubStatus status) {
    return Column(
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardHeader(
                icon: Icons.hub_outlined,
                title: 'Connecter mon GitHub',
              ),
              const SizedBox(height: 10),
              Text(
                status.deviceFlow
                    ? 'GitHub affiche un code à recopier. L’application attend '
                        'la validation, puis le compte est prêt.'
                    : 'La connexion par bouton n’est pas encore installée sur le '
                        'relais : utilise un jeton d’accès personnel ci-dessous.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppTheme.textSoft,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: status.deviceFlow && !_busy ? _startConnection : null,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Connecter avec GitHub'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardHeader(
                icon: Icons.key_rounded,
                title: 'Ou coller un jeton',
              ),
              const SizedBox(height: 10),
              const Text(
                'Crée un jeton fine-grained limité à tes dépôts (Contents, '
                'Issues, Pull requests et Actions en lecture/écriture), puis '
                'colle-le ici. Il n’est jamais réaffiché.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tokenController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 13, color: AppTheme.text),
                decoration: InputDecoration(
                  hintText: 'github_pat_…',
                  hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.outline),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _usePersonalToken,
                child: const Text('Utiliser ce jeton'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _connectedCard(GithubStatus status) {
    final login = status.login ?? 'compte GitHub';
    return Column(
      children: [
        _Card(
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.seed.withAlpha(60),
                child: Text(
                  login.isEmpty ? 'G' : login.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      login,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Connecté · l’IA agit avec tes droits',
                      style: TextStyle(fontSize: 12, color: AppTheme.success),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Material(
          color: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.folder_outlined, color: AppTheme.accent),
            title: const Text(
              'Dépôt courant',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.text,
              ),
            ),
            subtitle: Text(
              status.defaultRepo.isEmpty
                  ? 'Aucun : l’IA demande le dépôt à chaque fois'
                  : status.defaultRepo,
              style: const TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
            trailing: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded, color: AppTheme.muted),
            onTap: _busy ? null : _pickRepo,
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _busy ? null : _disconnect,
          icon: const Icon(Icons.link_off_rounded, size: 18),
          label: const Text('Déconnecter GitHub'),
          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.muted),
        ),
      ],
    );
  }
}

/* ------------------------------------------------------------------ pièces */

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.outline),
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.accent),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.text,
          ),
        ),
      ],
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
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: AppTheme.muted,
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5, right: 8),
            child: Icon(Icons.circle, size: 5, color: AppTheme.accent),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppTheme.textSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1C24),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFF6A7B7)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFFF6A7B7)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 40),
        Icon(icon, size: 34, color: AppTheme.muted),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, height: 1.5, color: AppTheme.muted),
        ),
        if (action != null) ...[const SizedBox(height: 10), action!],
      ],
    );
  }
}

/// Feuille du device flow : code, copie, et attente de la validation.
class _DeviceSheet extends StatefulWidget {
  const _DeviceSheet({
    required this.device,
    required this.poll,
    required this.onConnected,
  });

  final GithubDevice device;
  final Future<GithubPoll> Function() poll;
  final ValueChanged<String> onConnected;

  @override
  State<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<_DeviceSheet> {
  Timer? _timer;
  String? _message;
  bool _done = false;
  int _interval = 5;

  @override
  void initState() {
    super.initState();
    _interval = widget.device.interval.clamp(3, 30);
    _start();
  }

  void _start() {
    _timer = Timer.periodic(Duration(seconds: _interval), (_) => _check());
    _check();
  }

  Future<void> _check() async {
    if (_done) return;
    try {
      final result = await widget.poll();
      if (!mounted || _done) return;
      switch (result.state) {
        case 'connected':
          _done = true;
          _timer?.cancel();
          widget.onConnected(result.login ?? '');
        case 'slow_down':
          _interval = (_interval + 5).clamp(3, 60);
          _timer?.cancel();
          _timer = Timer.periodic(Duration(seconds: _interval), (_) => _check());
        case 'expired':
          _done = true;
          _timer?.cancel();
          setState(() => _message = 'Le code a expiré. Relance la connexion.');
        case 'denied':
          _done = true;
          _timer?.cancel();
          setState(() => _message = 'Autorisation refusée sur GitHub.');
        default:
          break;
      }
    } catch (error) {
      if (!mounted || _done) return;
      setState(
        () => _message = error is GithubFailure
            ? error.message
            : 'Vérification impossible pour le moment.',
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _openGithub() async {
    final uri = Uri.parse(widget.device.verificationUri);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) await Clipboard.setData(ClipboardData(text: uri.toString()));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Autoriser WORLD-AI',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ouvre github.com/login/device et recopie ce code :',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: AppTheme.muted),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.outline),
              ),
              child: Text(
                widget.device.userCode,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.device.userCode));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copier'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _openGithub,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Ouvrir GitHub'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (_message == null)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _message ?? 'En attente de la validation sur GitHub…',
                    style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Choix du dépôt courant parmi ceux du compte.
class _RepoSheet extends StatelessWidget {
  const _RepoSheet({required this.repos, required this.selected});

  final List<GithubRepo> repos;
  final String selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 22, 24, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Dépôt courant',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                ),
              ),
            ),
          ),
          if (repos.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Text(
                'Aucun dépôt accessible avec ce compte.',
                style: TextStyle(fontSize: 12.5, color: AppTheme.muted),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: repos.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      leading: const Icon(Icons.block_rounded, color: AppTheme.muted),
                      title: const Text(
                        'Aucun dépôt par défaut',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSoft),
                      ),
                      onTap: () => Navigator.of(context).pop(''),
                    );
                  }
                  final repo = repos[index - 1];
                  return ListTile(
                    selected: repo.fullName == selected,
                    leading: Icon(
                      repo.private ? Icons.lock_outline_rounded : Icons.folder_outlined,
                      color: repo.canPush ? AppTheme.accent : AppTheme.muted,
                    ),
                    title: Text(
                      repo.fullName,
                      style: const TextStyle(fontSize: 13, color: AppTheme.text),
                    ),
                    subtitle: Text(
                      repo.canPush ? 'Écriture autorisée' : 'Lecture seule',
                      style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
                    ),
                    onTap: () => Navigator.of(context).pop(repo.fullName),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
