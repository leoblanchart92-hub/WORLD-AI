import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_client.dart';
import '../sites/sites_client.dart';
import '../theme/app_theme.dart';

/// Sites de test publiés par l'IA pour ce compte.
///
/// Chaque site est une page HTML autonome servie par le relais à une adresse
/// publique : l'écran sert à les retrouver, les ouvrir et les supprimer.
class SitesPage extends StatefulWidget {
  const SitesPage({super.key, required this.sites, required this.session});

  final SitesService sites;
  final StoredSession? session;

  @override
  State<SitesPage> createState() => _SitesPageState();
}

class _SitesPageState extends State<SitesPage> {
  List<PublishedSite> _sites = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final token = widget.session?.token;
    if (token == null) {
      setState(() {
        _loading = false;
        _sites = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sites = await widget.sites.list(token);
      if (!mounted) return;
      setState(() {
        _sites = sites;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is SiteFailure ? error.message : 'Chargement impossible.';
        _loading = false;
      });
    }
  }

  Future<void> _open(PublishedSite site) async {
    final uri = Uri.tryParse(site.url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’ouvrir ${site.url}')),
      );
    }
  }

  Future<void> _delete(PublishedSite site) async {
    final token = widget.session?.token;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppTheme.outline),
        ),
        title: const Text(
          'Supprimer ce site ?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.text),
        ),
        content: Text(
          '« ${site.label} » disparaît et son adresse cesse de fonctionner.',
          style: const TextStyle(fontSize: 13, height: 1.5, color: AppTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.sites.remove(token, site.slug);
      if (!mounted) return;
      setState(() => _sites = _sites.where((s) => s.slug != site.slug).toList());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is SiteFailure ? error.message : 'Suppression impossible.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sites de test'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text(
              'Quand tu demandes à l’IA de créer un site, elle publie ici une page '
              'HTML autonome et te donne son adresse. Tu peux la rouvrir, la '
              'partager ou la supprimer à tout moment.',
              style: TextStyle(fontSize: 12.5, height: 1.55, color: AppTheme.muted),
            ),
            const SizedBox(height: 20),
            if (widget.session == null)
              _Notice(
                icon: Icons.lock_outline_rounded,
                message:
                    'Connecte-toi à un compte WORLD-AI pour publier et retrouver '
                    'des sites : ils sont rattachés à ton compte.',
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _Notice(icon: Icons.error_outline_rounded, message: _error!)
            else if (_sites.isEmpty)
              const _Notice(
                icon: Icons.travel_explore_rounded,
                message:
                    'Aucun site pour le moment. Demande par exemple : '
                    '« crée-moi une page de test pour ma boutique ».',
              )
            else
              for (final site in _sites) ...[
                _SiteTile(
                  site: site,
                  onOpen: () => _open(site),
                  onDelete: () => _delete(site),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _SiteTile extends StatelessWidget {
  const _SiteTile({
    required this.site,
    required this.onOpen,
    required this.onDelete,
  });

  final PublishedSite site;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppTheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: const Icon(Icons.public_rounded, color: AppTheme.accent),
        title: Text(
          site.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.text,
          ),
        ),
        subtitle: Text(
          site.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Ouvrir',
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded, size: 20, color: AppTheme.accent),
            ),
            IconButton(
              tooltip: 'Supprimer',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppTheme.muted),
            ),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, height: 1.5, color: AppTheme.muted),
            ),
          ),
        ],
      ),
    );
  }
}
