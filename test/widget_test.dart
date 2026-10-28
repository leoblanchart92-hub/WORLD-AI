import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:world_ai/main.dart';
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

AppUpdate _pendingUpdate() => AppUpdate(
      currentVersion: _FakeService.installed,
      latestVersion: const AppVersion(1, 4, 0),
      releaseNotes: '- Nouvelle interface\n- Tiroir latéral',
      downloadUrl: Uri.parse('https://example.com/world_ai-1.4.0.apk'),
      fileName: 'world_ai-1.4.0.apk',
      sizeInBytes: 47425761,
    );

void main() {
  testWidgets('affiche l\'accueil et la version installée', (tester) async {
    await tester.pumpWidget(
      WorldAiApp(updateService: _FakeService(), checkUpdatesOnStart: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('WORLD-AI v1.3.0'), findsOneWidget);
    expect(find.text('Centre de mises à jour'), findsOneWidget);
  });

  testWidgets('le tiroir latéral mène au centre de mises à jour', (
    tester,
  ) async {
    await tester.pumpWidget(
      WorldAiApp(updateService: _FakeService(), checkUpdatesOnStart: false),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final drawer = find.byType(NavigationDrawer);
    expect(drawer, findsOneWidget);
    expect(
      find.descendant(of: drawer, matching: find.text('À propos')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: drawer, matching: find.text('Mises à jour')),
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mise à jour disponible'), findsOneWidget);
    expect(find.textContaining('Télécharger et installer'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
  });
}
