import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:world_ai/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const WorldAiApp(checkUpdatesOnStart: false),
    );

    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('expose le bouton de vérification des mises à jour', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const WorldAiApp(checkUpdatesOnStart: false),
    );

    expect(find.byIcon(Icons.system_update), findsOneWidget);
    expect(find.text('WORLD-AI'), findsOneWidget);
  });
}
