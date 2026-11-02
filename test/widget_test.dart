import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:world_ai/ai/ai_client.dart';
import 'package:world_ai/auth/auth_client.dart';
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

/// IA hors ligne : répond immédiatement, sans relais ni réseau.
class _FakeAi implements AiService {
  _FakeAi({this.failure});

  final AiFailure? failure;
  final List<List<AiMessage>> calls = [];

  @override
  Future<AiReply> send(List<AiMessage> messages) async {
    calls.add(messages);
    if (failure != null) throw failure!;
    return const AiReply(text: 'Réponse de test', remaining: 59);
  }
}

/// Comptes hors ligne : aucune requête, résultat fixé par le test.
class _FakeAuth implements AuthService {
  _FakeAuth({this.session});

  StoredSession? session;
  int logouts = 0;
  String? error;

  StoredSession _reply(String email) => StoredSession(
    token: 'jeton-de-test-0123456789abcdefghijklmnopqrstuvwxyz',
    accountId: 'compte-1',
    email: email.trim().toLowerCase(),
  );

  @override
  Future<StoredSession> register(String email, String password) async {
    if (error != null) throw AuthFailure(error!);
    return session = _reply(email);
  }

  @override
  Future<StoredSession> login(String email, String password) async {
    if (error != null) throw AuthFailure(error!);
    return session = _reply(email);
  }

  @override
  Future<Account?> me(String token) async => null;

  @override
  Future<void> logout(String token) async {
    logouts += 1;
    session = null;
  }
}

/// Préférences en mémoire : les tests n'ont pas de stockage sur disque.
class _MemorySettings extends SettingsStore {
  _MemorySettings({this.session});

  bool checkOnLaunch = true;
  String appIcon = 'default';
  String aiModel = defaultAiModel;
  StoredSession? session;

  @override
  Future<StoredSession?> loadSession() async => session;

  @override
  Future<void> saveSession(StoredSession value) async => session = value;

  @override
  Future<void> clearSession() async => session = null;

  @override
  Future<bool> loadCheckOnLaunch({bool fallback = true}) async => checkOnLaunch;

  @override
  Future<void> saveCheckOnLaunch(bool value) async => checkOnLaunch = value;

  @override
  Future<String> loadAppIcon({String fallback = 'default'}) async => appIcon;

  @override
  Future<void> saveAppIcon(String value) async => appIcon = value;

  @override
  Future<String> loadAiModel({String fallback = 'default'}) async => aiModel;

  @override
  Future<void> saveAiModel(String value) async => aiModel = value;
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
    expect(find.text('Groq · GPT-OSS 120B'), findsOneWidget);
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
    expect(find.text('Version 2.1.0'), findsOneWidget);
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
    expect(find.text('Version 2.1.0'), findsOneWidget);
  });

  testWidgets('change et mémorise l’icône depuis les paramètres', (
    tester,
  ) async {
    final settings = _MemorySettings();
    await tester.pumpWidget(
      WorldAiApp(
        updateService: _FakeService(),
        checkUpdatesOnStart: false,
        settingsStore: settings,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();

    expect(find.text('Icône 1'), findsOneWidget);
    await tester.tap(find.text('Choisir'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    for (var number = 1; number <= 6; number++) {
      expect(
        find.descendant(of: dialog, matching: find.text('Icône $number')),
        findsOneWidget,
      );
    }

    final choice = find.descendant(of: dialog, matching: find.text('Icône 6'));
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle();

    expect(settings.appIcon, 'image6');
    expect(find.text('Icône 6'), findsOneWidget);
  });

  testWidgets('envoie un message et affiche la réponse de l’IA', (
    tester,
  ) async {
    final ai = _FakeAi();
    await tester.pumpWidget(
      WorldAiApp(
        updateService: _FakeService(),
        checkUpdatesOnStart: false,
        settingsStore: _MemorySettings(),
        aiService: ai,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Bonjour WORLD-AI');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Bonjour WORLD-AI'), findsOneWidget);
    expect(find.text('Réponse de test'), findsOneWidget);
    expect(find.text('Commence la discussion'), findsNothing);
    expect(ai.calls.single.last.content, 'Bonjour WORLD-AI');
  });

  testWidgets('crée un compte depuis le menu et le garde en mémoire', (
    tester,
  ) async {
    final settings = _MemorySettings();
    final auth = _FakeAuth();
    await tester.pumpWidget(
      WorldAiApp(
        updateService: _FakeService(),
        checkUpdatesOnStart: false,
        settingsStore: settings,
        aiService: _FakeAi(),
        authService: auth,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Créer un compte ou se connecter'), findsOneWidget);

    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('account-email')),
      ' Lea@Exemple.FR ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password')),
      'motdepasse123',
    );
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();

    expect(settings.session?.email, 'lea@exemple.fr');
    expect(auth.session?.email, 'lea@exemple.fr');
    expect(find.text('Mon compte'), findsOneWidget);
    expect(find.text('lea@exemple.fr'), findsOneWidget);
  });

  testWidgets('refuse une adresse invalide avant tout appel', (tester) async {
    final settings = _MemorySettings();
    final auth = _FakeAuth();
    await tester.pumpWidget(
      WorldAiApp(
        updateService: _FakeService(),
        checkUpdatesOnStart: false,
        settingsStore: settings,
        aiService: _FakeAi(),
        authService: auth,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('account-email')),
      'pas-une-adresse',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password')),
      'motdepasse123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Écris une adresse e-mail valide.'), findsOneWidget);
    expect(settings.session, isNull);
    expect(auth.session, isNull);
  });

  testWidgets('se déconnecte et oublie la session', (tester) async {
    final settings = _MemorySettings(
      session: const StoredSession(
        token: 'jeton-de-test-0123456789abcdefghijklmnopqrstuvwxyz',
        accountId: 'compte-1',
        email: 'lea@exemple.fr',
      ),
    );
    final auth = _FakeAuth(session: settings.session);
    await tester.pumpWidget(
      WorldAiApp(
        updateService: _FakeService(),
        checkUpdatesOnStart: false,
        settingsStore: settings,
        aiService: _FakeAi(),
        authService: auth,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('lea@exemple.fr'));
    await tester.pumpAndSettle();

    expect(find.text('Mon compte'), findsOneWidget);
    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();

    expect(auth.logouts, 1);
    expect(settings.session, isNull);
    expect(find.text('Créer un compte'), findsOneWidget);
    expect(find.text('Tu es déconnecté.'), findsOneWidget);
  });

  testWidgets('choisit une autre IA et la mémorise', (tester) async {
    final settings = _MemorySettings();
    await tester.pumpWidget(
      WorldAiApp(
        updateService: _FakeService(),
        checkUpdatesOnStart: false,
        settingsStore: settings,
        aiService: _FakeAi(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Groq · GPT-OSS 120B'), findsOneWidget);

    await tester.tap(find.text('Groq · GPT-OSS 120B'));
    await tester.pumpAndSettle();
    expect(find.text('Choisir l’IA'), findsOneWidget);
    // Les versions restent derrière le fournisseur « Groq ».
    expect(find.text('Qwen3 27B'), findsNothing);

    await tester.tap(find.text('Groq'));
    await tester.pumpAndSettle();
    expect(find.text('Choisis la version'), findsOneWidget);
    expect(find.text('Qwen3 27B'), findsOneWidget);

    await tester.ensureVisible(find.text('Qwen3 27B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Qwen3 27B'));
    await tester.pumpAndSettle();

    expect(settings.aiModel, 'qwen/qwen3.8-27b');
    expect(find.text('Groq · Qwen3 27B'), findsOneWidget);
  });

  testWidgets('affiche l’erreur du relais et permet de réessayer', (
    tester,
  ) async {
    final ai = _FakeAi(
      failure: const AiFailure('Limite quotidienne atteinte.', canRetry: false),
    );
    await tester.pumpWidget(
      WorldAiApp(
        updateService: _FakeService(),
        checkUpdatesOnStart: false,
        settingsStore: _MemorySettings(),
        aiService: ai,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Bonjour');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Limite quotidienne atteinte.'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('garde mise à jour et paramètres en bas du menu', (tester) async {
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
