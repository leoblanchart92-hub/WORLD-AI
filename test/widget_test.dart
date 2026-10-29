import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:world_ai/main.dart';
import 'package:world_ai/settings_store.dart';
import 'package:world_ai/update/app_version.dart';
import 'package:world_ai/update/update_service.dart';

/// Service hors ligne : aucun appel réseau, résultats fixés par le test.
class _FakeService extends GithubUpdateService {
  _FakeService({this.status = UpdateStatus.upToDate, this.update});

  final UpdateStatus status;
  final AppUpdate? update;

  static const AppVersion installed = AppVersion(1, 3, 0);

  @override
  Future<AppVersion> currentVersion() async => installed;

  @override
  Future<UpdateCheckResult> check() async => UpdateCheckResult(
        status,
        installed,
        update: status == UpdateStatus.updateAvailable ? update : null,
      );
}

/// Préférences en mémoire : les tests n'ont pas de stockage sur disque.
class _MemorySettings extends SettingsStore {
  bool checkOnLaunch = true;

  @override
  Future<bool> loadCheckOnLaunch({bool fallback = true}) async => checkOnLaunch;

  @override
  Future<void> saveCheckOnLaunch(bool value) async => checkOnLaunch = value;
}

AppUpdate _pendingUpdate() => AppUpdate(
      currentVersion: _FakeService.installed,
      latestVersion: const AppVersion(1, 4, 0),
      releaseNotes: '- Nouvelle interface\n- Tiroir latéral',
      downloadUrl: Uri.parse('https://example.com/world_ai-1.4.0.apk'),
      fileName: 'world_ai-1.4.0.apk',
      sizeInBytes: 47425761,
    );

void main() {
  testWidgets('ouvre sur la discussion et sa barre de saisie', (tester) async {
    await tester.pumpWidget(
      WorldAiApp(updateService: _FakeService(), checkUpdatesOnStart: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Discussion'), findsOneWidget);
    expect(find.text('WORLD-AI v1.3.0'), findsOneWidget);
    expect(find.text('Commence la discussion'), findsOneWidget);
    expect(find.text('Écris un message…'), findsOneWidget);
    // La mise à jour n'est plus dans la barre supérieure.
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
  });

  testWidgets('ouvre les nouveautés depuis le bouton de la discussion', (
    tester,
  ) async {
    await tester.pumpWidget(
      WorldAiApp(updateService: _FakeService(), checkUpdatesOnStart: false),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nouveauté'));
    await tester.pumpAndSettle();

    expect(
      find.text('Retrouve ici les principales améliorations de l’application.'),
      findsOneWidget,
    );
    expect(find.text('Version 1.6.2'), findsOneWidget);
  });

  testWidgets('ouvre les nouveautés depuis les paramètres', (tester) async {
    await tester.pumpWidget(
      WorldAiApp(updateService: _FakeService(), checkUpdatesOnStart: false),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Nouveauté'));
    await tester.pumpAndSettle();

    expect(
      find.text('Retrouve ici les principales améliorations de l’application.'),
      findsOneWidget,
    );
    expect(find.text('Version 1.6.2'), findsOneWidget);
  });

  testWidgets('envoie un message depuis la barre', (tester) async {
    await tester.pumpWidget(
      WorldAiApp(updateService: _FakeService(), checkUpdatesOnStart: false),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Bonjour WORLD-AI');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Bonjour WORLD-AI'), findsOneWidget);
    expect(find.text('Commence la discussion'), findsNothing);
  });

  testWidgets('garde mise à jour et paramètres en bas du menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      WorldAiApp(updateService: _FakeService(), checkUpdatesOnStart: false),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final drawer = find.byType(Drawer);
    expect(drawer, findsOneWidget);
    expect(
      find.descendant(of: drawer, matching: find.text('Mise à jour')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Paramètres')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Discussion')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Mises à jour')),
      findsNothing,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('À propos')),
      findsNothing,
    );

    await tester.tap(
      find.descendant(of: drawer, matching: find.text('Mise à jour')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vérifier les mises à jour'), findsOneWidget);
    expect(find.text('Signature stable'), findsOneWidget);
  });

  testWidgets('propose la mise à jour disponible au démarrage', (tester) async {
    await tester.pumpWidget(
      WorldAiApp(
        updateService: _FakeService(
          status: UpdateStatus.updateAvailable,
          update: _pendingUpdate(),
        ),
        settingsStore: _MemorySettings(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text('Mise à jour disponible'), findsOneWidget);
    expect(find.textContaining('Télécharger et installer'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
  });
}
