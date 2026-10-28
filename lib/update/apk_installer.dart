import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';

import 'update_service.dart';

/// Lance l'installeur d'APK d'Android sur [apk].
///
/// Android affiche lui-même la demande d'autorisation « Installer des
/// applications inconnues » si elle n'a pas encore été accordée pour WORLD-AI.
Future<void> installApk(File apk) async {
  if (!Platform.isAndroid) {
    throw UpdateException(
      'L\'installation automatique n\'est disponible que sur Android.',
    );
  }

  final result = await OpenFilex.open(
    apk.path,
    type: 'application/vnd.android.package-archive',
  );

  if (result.type != ResultType.done) {
    throw UpdateException(
      result.message.isEmpty
          ? 'Android n\'a pas pu ouvrir l\'installeur.'
          : 'Android n\'a pas pu ouvrir l\'installeur : ${result.message}',
    );
  }

  debugPrint('Installeur APK ouvert sur ${apk.path}');
}
