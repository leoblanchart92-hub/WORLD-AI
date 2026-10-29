import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_shell.dart';
import 'settings_store.dart';
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
    this.settingsStore,
  });

  /// Injecté par les tests pour rester hors ligne.
  final GithubUpdateService? updateService;

  /// Vérification silencieuse de mise à jour au lancement.
  final bool checkUpdatesOnStart;

  /// Injecté par les tests ; sinon les préférences viennent du disque.
  final SettingsStore? settingsStore;

  @override
  State<WorldAiApp> createState() => _WorldAiAppState();
}

class _WorldAiAppState extends State<WorldAiApp> {
  static const MethodChannel _iconChannel = MethodChannel(
    'com.worldai.world_ai/app_icon',
  );

  late final UpdateController _controller = UpdateController(
    service: widget.updateService,
  );
  late final SettingsStore _settings = widget.settingsStore ?? SettingsStore();

  @override
  void initState() {
    super.initState();
    _loadAppIcon();
  }

  Future<void> _loadAppIcon() async {
    final icon = await _settings.loadAppIcon();
    await _applyAppIcon(icon);
  }

  Future<void> _applyAppIcon(String icon) async {
    try {
      await _iconChannel.invokeMethod<void>('setIcon', icon);
    } on MissingPluginException {
      // iOS et les tests gardent l’icône système par défaut.
    } on PlatformException catch (error) {
      debugPrint('Icône de l’application non modifiée : ${error.message}');
    }
  }

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
        settingsStore: _settings,
        loadAppIcon: _settings.loadAppIcon,
        onAppIconChanged: (icon) async {
          await _settings.saveAppIcon(icon);
          await _applyAppIcon(icon);
        },
      ),
    );
  }
}
