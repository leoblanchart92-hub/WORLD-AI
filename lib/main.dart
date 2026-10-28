import 'package:flutter/material.dart';

import 'update/app_version.dart';
import 'update/update_service.dart';
import 'update/update_ui.dart';

void main() {
  runApp(const WorldAiApp());
}

class WorldAiApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WORLD-AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: HomePage(
        updateService: updateService,
        checkUpdatesOnStart: checkUpdatesOnStart,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.title = 'WORLD-AI',
    this.updateService,
    this.checkUpdatesOnStart = true,
  });

  final String title;
  final GithubUpdateService? updateService;
  final bool checkUpdatesOnStart;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final GithubUpdateService _updates =
      widget.updateService ?? GithubUpdateService();
  late final bool _ownsUpdateService = widget.updateService == null;
  late final Future<AppVersion> _version = _updates.currentVersion();

  int _counter = 0;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (widget.checkUpdatesOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        checkForUpdates(context, _updates, silent: true);
      });
    }
  }

  @override
  void dispose() {
    if (_ownsUpdateService) _updates.dispose();
    super.dispose();
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await checkForUpdates(context, _updates);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _checking ? null : _checkNow,
            tooltip: 'Vérifier les mises à jour',
            icon: _checking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 32),
            FutureBuilder<AppVersion>(
              future: _version,
              builder: (context, snapshot) {
                final label = snapshot.hasData
                    ? 'WORLD-AI v${snapshot.data}'
                    : 'WORLD-AI v…';
                return Text(label, style: theme.textTheme.bodySmall);
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
