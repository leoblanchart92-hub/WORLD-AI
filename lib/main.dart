import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'theme/app_theme.dart';
import 'update/update_controller.dart';
import 'update/update_service.dart';

void main() {
  runApp(const WorldAiApp());
}

class WorldAiApp extends StatefulWidget {
  const WorldAiApp({
    super.key,
    this.updateService,
    this.checkUpdatesOnStart = true,
  });

  /// Injecté par les tests pour rester hors ligne.
  final GithubUpdateService? updateService;

  /// Vérification silencieuse de mise à jour au lancement.
  final bool checkUpdatesOnStart;

  @override
  State<WorldAiApp> createState() => _WorldAiAppState();
}

class _WorldAiAppState extends State<WorldAiApp> {
  late final UpdateController _controller =
      UpdateController(service: widget.updateService);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WORLD-AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: AppShell(
        controller: _controller,
        checkUpdatesOnStart: widget.checkUpdatesOnStart,
      ),
    );
  }
}
