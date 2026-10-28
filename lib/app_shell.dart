import 'package:flutter/material.dart';

import 'pages/about_page.dart';
import 'pages/home_page.dart';
import 'pages/updates_page.dart';
import 'theme/app_theme.dart';
import 'update/update_controller.dart';
import 'update/update_ui.dart';

/// Coquille de l'application : barre supérieure, tiroir latéral et pages.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    this.checkUpdatesOnStart = true,
  });

  final UpdateController controller;
  final bool checkUpdatesOnStart;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<String> _titles = ['Accueil', 'Mises à jour', 'À propos'];

  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.loadInstalledVersion();
    if (widget.checkUpdatesOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startupCheck());
    }
  }

  /// Vérification silencieuse au lancement : elle n'ouvre la feuille que s'il
  /// y a réellement quelque chose à installer.
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
        actions: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Vérifier les mises à jour',
                onPressed: controller.isBusy ? null : () => controller.check(),
                icon: controller.isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
        ],
      ),
      drawer: _AppDrawer(
        index: _index,
        controller: controller,
        onSelected: _selectFromDrawer,
      ),
      body: IndexedStack(
        index: _index,
        children: [
          HomePage(controller: controller, onNavigate: _select),
          UpdatesPage(controller: controller),
          AboutPage(controller: controller),
        ],
      ),
    );
  }
}

/// Tiroir latéral : identité de l'app, navigation et état des mises à jour.
class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.index,
    required this.controller,
    required this.onSelected,
  });

  final int index;
  final UpdateController controller;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final updateReady = controller.phase == UpdatePhase.available;

        return NavigationDrawer(
          selectedIndex: index,
          onDestinationSelected: onSelected,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Divider(),
            ),
            const SizedBox(height: 10),
            const NavigationDrawerDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: Text('Accueil'),
            ),
            NavigationDrawerDestination(
              icon: _DotIcon(
                icon: Icons.system_update_outlined,
                active: updateReady,
              ),
              selectedIcon: const Icon(Icons.system_update_rounded),
              label: const Text('Mises à jour'),
            ),
            const NavigationDrawerDestination(
              icon: Icon(Icons.info_outline_rounded),
              selectedIcon: Icon(Icons.info_rounded),
              label: Text('À propos'),
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Divider(),
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Mises à jour signées, publiées depuis GitHub Releases.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: AppTheme.muted,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _DotIcon extends StatelessWidget {
  const _DotIcon({required this.icon, required this.active});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (active)
          Positioned(
            right: -2,
            top: -1,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0F0C1B), width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
