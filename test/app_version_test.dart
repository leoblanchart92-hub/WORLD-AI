import 'package:flutter_test/flutter_test.dart';

import 'package:world_ai/update/app_version.dart';

void main() {
  group('AppVersion.parse', () {
    test('lit les formats publiés par GitHub', () {
      expect(AppVersion.parse('1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.parse('v1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.parse('1.2.3+45'), const AppVersion(1, 2, 3));
      expect(AppVersion.parse('1.2.3-rc.1'), const AppVersion(1, 2, 3));
      expect(AppVersion.parse('2.0'), const AppVersion(2, 0, 0));
    });

    test('rejette une version illisible', () {
      expect(() => AppVersion.parse(''), throwsFormatException);
      expect(() => AppVersion.parse('abc'), throwsFormatException);
    });
  });

  group('comparaison', () {
    test('ordonne les versions numériquement, pas alphabétiquement', () {
      expect(AppVersion.parse('1.10.0') > AppVersion.parse('1.9.9'), isTrue);
      expect(AppVersion.parse('2.0.0') > AppVersion.parse('1.99.99'), isTrue);
      expect(AppVersion.parse('1.0.1') < AppVersion.parse('1.1.0'), isTrue);
    });

    test('détecte l\'égalité y compris avec préfixe v', () {
      expect(AppVersion.parse('v1.1.0'), AppVersion.parse('1.1.0'));
      expect(AppVersion.parse('1.1.0') >= AppVersion.parse('1.1.0'), isTrue);
      expect(AppVersion.parse('1.1.0') > AppVersion.parse('1.1.0'), isFalse);
    });
  });
}
