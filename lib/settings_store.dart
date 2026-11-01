import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Préférences locales, stockées dans un unique fichier JSON du dossier de
/// support de l'application.
///
/// Toute erreur (plugin absent, disque en lecture seule) retombe sur la valeur
/// par défaut : une préférence d'affichage ne doit jamais empêcher l'app de
/// démarrer.
class SettingsStore {
  static const String _fileName = 'settings.json';
  static const String _checkOnLaunchKey = 'checkOnLaunch';
  static const String _appIconKey = 'appIcon';

  Future<File?> _file() async {
    try {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      return File('${directory.path}/$_fileName');
    } catch (error) {
      debugPrint('Dossier de préférences indisponible : $error');
      return null;
    }
  }

  Future<bool> loadCheckOnLaunch({bool fallback = true}) async {
    final file = await _file();
    if (file == null) return fallback;
    try {
      if (!await file.exists()) return fallback;
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data[_checkOnLaunchKey] is bool) {
        return data[_checkOnLaunchKey] as bool;
      }
    } catch (error) {
      debugPrint('Préférences illisibles : $error');
    }
    return fallback;
  }

  Future<String> loadAppIcon({String fallback = 'default'}) async {
    final file = await _file();
    if (file == null) return fallback;
    try {
      if (!await file.exists()) return fallback;
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data[_appIconKey] is String) {
        return data[_appIconKey] as String;
      }
    } catch (error) {
      debugPrint('Préférences illisibles : $error');
    }
    return fallback;
  }

  Future<void> saveCheckOnLaunch(bool value) async {
    await _updateValue(_checkOnLaunchKey, value);
  }

  Future<void> saveAppIcon(String value) async {
    await _updateValue(_appIconKey, value);
  }

  Future<void> _updateValue(String key, Object value) async {
    final file = await _file();
    if (file == null) return;
    try {
      final Map<String, dynamic> data;
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } else {
        data = <String, dynamic>{};
      }
      data[key] = value;
      await file.writeAsString(jsonEncode(data));
    } catch (error) {
      debugPrint('Préférences non enregistrées : $error');
    }
  }
}
