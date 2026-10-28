import 'package:flutter_test/flutter_test.dart';

import 'package:world_ai/update/app_version.dart';
import 'package:world_ai/update/update_controller.dart';
import 'package:world_ai/update/update_service.dart';

class _StubService extends GithubUpdateService {
  _StubService(this._check);

  final Future<UpdateCheckResult> Function() _check;

  @override
  Future<AppVersion> currentVersion() async => const AppVersion(1, 3, 0);

  @override
  Future<UpdateCheckResult> check() => _check();
}

void main() {
  const installed = AppVersion(1, 3, 0);

  test('passe en « à jour » quand la release est identique', () async {
    final controller = UpdateController(
      service: _StubService(
        () async => const UpdateCheckResult(UpdateStatus.upToDate, installed),
      ),
    );
    addTearDown(controller.dispose);

    await controller.check();

    expect(controller.phase, UpdatePhase.upToDate);
    expect(controller.update, isNull);
    expect(controller.installedLabel, 'v1.3.0');
  });

  test('expose la mise à jour disponible', () async {
    final update = AppUpdate(
      currentVersion: installed,
      latestVersion: const AppVersion(1, 4, 0),
      releaseNotes: 'Notes',
      downloadUrl: Uri.parse('https://example.com/a.apk'),
      fileName: 'a.apk',
      sizeInBytes: 1024,
    );
    final controller = UpdateController(
      service: _StubService(
        () async => UpdateCheckResult(
          UpdateStatus.updateAvailable,
          installed,
          update: update,
        ),
      ),
    );
    addTearDown(controller.dispose);

    await controller.check();

    expect(controller.phase, UpdatePhase.available);
    expect(controller.update?.latestVersion.toString(), '1.4.0');
  });

  test('signale l\'erreur, sauf en mode silencieux', () async {
    final visible = UpdateController(
      service: _StubService(
        () async => throw UpdateException('Pas de connexion internet.'),
      ),
    );
    addTearDown(visible.dispose);

    await visible.check();
    expect(visible.phase, UpdatePhase.error);
    expect(visible.error, 'Pas de connexion internet.');

    final silent = UpdateController(
      service: _StubService(
        () async => throw UpdateException('Pas de connexion internet.'),
      ),
    );
    addTearDown(silent.dispose);

    await silent.check(silent: true);
    expect(silent.phase, UpdatePhase.idle);
    expect(silent.error, isNull);
  });
}
